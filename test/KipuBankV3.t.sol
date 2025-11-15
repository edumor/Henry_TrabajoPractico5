// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";

/**
 * @title KipuBankV3Test - Comprehensive Security Test Suite
 * @author Eduardo Moreno - Ethereum Developers ETH_KIPU
 * @notice Test suite following OWASP Smart Contract Top 10 (2025) methodology
 * @dev Tests for vulnerabilities: Access Control, Oracle Manipulation, Logic Errors, 
 *      Input Validation, Reentrancy, External Calls, Integer Overflow, DoS
 */
contract KipuBankV3Test is Test {
    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    KipuBankV3 public bank;
    MockERC20 public mockUSDC;
    MockERC20 public mockToken;
    MockChainlinkFeed public mockETHPriceFeed;
    MockChainlinkFeed public mockUSDCPriceFeed;
    MockChainlinkFeed public mockTokenPriceFeed;
    MockUniswapRouter public mockUniswapRouter;
    MaliciousContract public maliciousContract;
    
    address public owner;
    address public user1;
    address public user2;
    address public attacker;
    
    // Constants for testing
    int256 public constant INITIAL_ETH_PRICE = 2000_00000000; // $2000 (8 decimals)
    int256 public constant INITIAL_USDC_PRICE = 1_00000000;   // $1 (8 decimals)
    int256 public constant INITIAL_TOKEN_PRICE = 10_00000000; // $10 (8 decimals)
    uint256 public constant MAX_CAP_USDC = 100000000000;       // 100,000 USDC (6 decimals)
    
    /*//////////////////////////////////////////////////////////////
                        EVENTS TO TEST
    //////////////////////////////////////////////////////////////*/
    
    event Deposit(address indexed user, uint256 usdcAmount, uint256 tokenAmount, uint256 timestamp);
    event Withdrawal(address indexed user, uint256 amount, uint256 timestamp);
    event TokenSwapped(address indexed user, address indexed token, uint256 amountIn, uint256 amountOut);
    event TokenAdded(address indexed token, uint8 decimals, address priceFeed);
    event TokenRemoved(address indexed token);
    event PauseStateChanged(bool isPaused);

    /*//////////////////////////////////////////////////////////////
                        SETUP FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Set up test accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");
        
        // Deploy mock contracts
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        mockToken = new MockERC20("TestToken", "TT", 18);
        mockETHPriceFeed = new MockChainlinkFeed(INITIAL_ETH_PRICE);
        mockUSDCPriceFeed = new MockChainlinkFeed(INITIAL_USDC_PRICE);
        mockTokenPriceFeed = new MockChainlinkFeed(INITIAL_TOKEN_PRICE);
        mockUniswapRouter = new MockUniswapRouter(address(mockUSDC));
        
        // Deploy KipuBankV3
        vm.prank(owner);
        bank = new KipuBankV3(
            owner,
            address(mockETHPriceFeed),
            address(mockUSDC),
            address(mockUSDCPriceFeed),
            address(mockUniswapRouter)
        );
        
        // Initialize supported tokens
        vm.prank(owner);
        bank.initializeSupportedTokens();
        
        // Add test token support
        vm.prank(owner);
        bank.addSupportedToken(address(mockToken), address(mockTokenPriceFeed), 18);
        
        // Setup initial balances for testing
        deal(user1, 10 ether);
        deal(user2, 5 ether);
        deal(attacker, 1 ether);
        
        mockUSDC.mint(user1, 1000000 * 10**6); // 1M USDC
        mockUSDC.mint(user2, 500000 * 10**6);  // 500K USDC
        mockToken.mint(user1, 1000 * 10**18);  // 1000 tokens
        mockToken.mint(attacker, 100 * 10**18); // 100 tokens for attacks
        
        // Deploy malicious contract for reentrancy tests
        maliciousContract = new MaliciousContract(payable(address(bank)));
        deal(address(maliciousContract), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    SC01:2025 - ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_OnlyOwnerFunctions() public {
        // Test that only owner can call admin functions
        vm.prank(user1);
        vm.expectRevert();
        bank.addSupportedToken(address(mockToken), address(mockTokenPriceFeed), 18);
        
        vm.prank(user1);
        vm.expectRevert();
        bank.removeSupportedToken(address(mockToken));
        
        vm.prank(user1);
        vm.expectRevert();
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        bank.unpause();
        
        vm.prank(user1);
        vm.expectRevert();
        bank.renounceOwnership();
    }
    
    function test_OwnershipTransfer() public {
        // Test ownership transfer
        vm.prank(owner);
        bank.transferOwnership(user1);
        
        assertEq(bank.owner(), user1);
        
        // Old owner should not have access
        vm.prank(owner);
        vm.expectRevert();
        bank.pause();
        
        // New owner should have access
        vm.prank(user1);
        bank.pause();
        assertTrue(bank.isPaused());
    }

    /*//////////////////////////////////////////////////////////////
                SC02:2025 - ORACLE MANIPULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_StaleOraclePrice() public {
        // Set stale timestamp (older than 1 hour)
        mockETHPriceFeed.setUpdatedAt(block.timestamp - 3601);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("StalePrice()"));
        bank.depositETH{value: 1 ether}();
    }
    
    function test_InvalidOraclePrice() public {
        // Set negative price
        mockETHPriceFeed.setPrice(-1);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidPrice()"));
        bank.depositETH{value: 1 ether}();
    }
    
    function test_OraclePriceManipulation() public {
        // Simulate oracle manipulation attack
        int256 originalPrice = INITIAL_ETH_PRICE;
        
        // Deposit with normal price
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        uint256 normalBalance = bank.getUserBalance(user1);
        
        // Manipulate price upward
        mockETHPriceFeed.setPrice(int256(uint256(originalPrice) * 10)); // 10x price
        
        vm.prank(user2);
        bank.depositETH{value: 1 ether}();
        uint256 manipulatedBalance = bank.getUserBalance(user2);
        
        // Attacker should get 10x more USDC equivalent
        assertApproxEqRel(manipulatedBalance, normalBalance * 10, 0.01e18); // 1% tolerance
    }

    /*//////////////////////////////////////////////////////////////
                SC03:2025 - LOGIC ERRORS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_DecimalConversionErrors() public {
        // Test potential decimal conversion errors
        uint256 smallAmount = 1; // 1 wei ETH
        
        vm.prank(user1);
        bank.depositETH{value: smallAmount}();
        
        // Check if balance calculation is correct for very small amounts
        uint256 userBalance = bank.getUserBalance(user1);
        // With ETH at $2000, 1 wei should give 0.000000000000002 USDC
        // Due to rounding, this might be 0
        assertTrue(userBalance == 0 || userBalance == 1);
    }
    
    function test_CapExceededLogic() public {
        // Test bank capacity logic
        uint256 maxDepositETH = (MAX_CAP_USDC * 1e20) / uint256(INITIAL_ETH_PRICE); // Max ETH equivalent
        
        vm.prank(user1);
        bank.depositETH{value: maxDepositETH}();
        
        // Next deposit should fail
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("CapExceeded()"));
        bank.depositETH{value: 0.01 ether}();
    }
    
    function test_BalanceCalculationLogic() public {
        // Test balance calculation consistency
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 expectedUSDC = (1 ether * uint256(INITIAL_ETH_PRICE)) / 1e20;
        uint256 actualBalance = bank.getUserBalance(user1);
        
        assertEq(actualBalance, expectedUSDC);
    }

    /*//////////////////////////////////////////////////////////////
                SC04:2025 - INPUT VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ZeroAmountValidation() public {
        // Test zero amount deposits
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        bank.depositETH{value: 0}();
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        bank.depositERC20(address(mockUSDC), 0);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        bank.withdrawETH(0);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        bank.withdrawUSDC(0);
    }
    
    function test_ZeroAddressValidation() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        bank.addSupportedToken(address(0), address(mockTokenPriceFeed), 18);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        bank.addSupportedToken(address(mockToken), address(0), 18);
    }
    
    function test_UnsupportedTokenValidation() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNS", 18);
        mockUniswapRouter.setHasPair(address(unsupportedToken), false);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotSupported()"));
        bank.depositERC20(address(unsupportedToken), 100);
    }

    /*//////////////////////////////////////////////////////////////
                SC05:2025 - REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ReentrancyAttackWithdrawETH() public {
        // Setup: Malicious contract deposits first
        vm.prank(address(maliciousContract));
        bank.depositETH{value: 0.5 ether}();
        
        uint256 initialBalance = address(bank).balance;
        uint256 attackerInitialBalance = address(maliciousContract).balance;
        
        // Execute reentrancy attack
        vm.prank(address(maliciousContract));
        maliciousContract.attack();
        
        uint256 finalBalance = address(bank).balance;
        uint256 attackerFinalBalance = address(maliciousContract).balance;
        
        // Check if reentrancy was successful (it should be in the vulnerable version)
        console.log("Bank balance before attack:", initialBalance);
        console.log("Bank balance after attack:", finalBalance);
        console.log("Attacker balance before:", attackerInitialBalance);
        console.log("Attacker balance after:", attackerFinalBalance);
        
        // In vulnerable version, attacker should drain more than deposited
        if (attackerFinalBalance > attackerInitialBalance + 0.5 ether) {
            console.log("VULNERABILITY DETECTED: Reentrancy attack successful!");
        }
    }

    /*//////////////////////////////////////////////////////////////
                SC06:2025 - UNCHECKED EXTERNAL CALLS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ETHTransferFailure() public {
        // Create a contract that rejects ETH transfers
        RejectETHContract rejectContract = new RejectETHContract(payable(address(bank)));
        
        // Fund the reject contract
        vm.deal(address(rejectContract), 1 ether);
        
        vm.prank(address(rejectContract));
        bank.depositETH{value: 0.5 ether}();
        
        // Try to withdraw - should fail due to rejected transfer
        vm.prank(address(rejectContract));
        vm.expectRevert(abi.encodeWithSignature("TransferFailed()"));
        rejectContract.attemptWithdraw();
    }

    /*//////////////////////////////////////////////////////////////
                SC08:2025 - INTEGER OVERFLOW TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_OverflowProtection() public {
        // Test with maximum values to check for overflows
        uint256 maxUint256 = type(uint256).max;
        
        // This should revert due to overflow protection in Solidity 0.8.26
        vm.expectRevert();
        unchecked {
            uint256 result = maxUint256 + 1;
        }
    }

    /*//////////////////////////////////////////////////////////////
                SC10:2025 - DOS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_PauseFunctionality() public {
        // Test pause/unpause mechanism
        vm.prank(owner);
        bank.pause();
        
        assertTrue(bank.isPaused());
        
        // All functions should revert when paused
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        bank.depositETH{value: 1 ether}();
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        bank.depositERC20(address(mockUSDC), 100);
        
        vm.prank(owner);
        bank.unpause();
        
        assertFalse(bank.isPaused());
        
        // Functions should work again
        vm.prank(user1);
        bank.depositETH{value: 0.1 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @dev INVARIANT 1: Total user balances ≤ Bank capacity
    function test_invariant_UserBalancesSumLessEqualBankCapacity() public {
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        vm.prank(user2);
        depositUSDCForUser(user2, 100000 * 10**6); // 100,000 USDC
        
        uint256 user1Balance = bank.getUserBalance(user1);
        uint256 user2Balance = bank.getUserBalance(user2);
        uint256 totalUserBalances = user1Balance + user2Balance;
        uint256 bankCapacity = bank.currentCapUSDC();
        
        assertLe(totalUserBalances, bankCapacity, "Total user balances exceed bank capacity");
    }
    
    /// @dev INVARIANT 2: Contract ETH balance ≥ Sum of ETH withdrawable by users
    function test_invariant_ContractETHBalanceConsistency() public {
        uint256 depositAmount = 2 ether;
        
        vm.prank(user1);
        bank.depositETH{value: depositAmount}();
        
        uint256 userUSDCBalance = bank.getUserBalance(user1);
        uint256 contractETHBalance = bank.currentETHBalance();
        
        // Calculate withdrawable ETH equivalent
        uint256 withdrawableETH = (userUSDCBalance * 1e20) / uint256(INITIAL_ETH_PRICE);
        
        assertGe(contractETHBalance, withdrawableETH, "Contract ETH less than withdrawable amount");
    }
    
    /// @dev INVARIANT 3: Bank capacity never exceeds MAX_CAP
    function test_invariant_BankCapacityNeverExceedsMax() public {
        uint256 currentCap = bank.currentCapUSDC();
        uint256 maxCap = MAX_CAP_USDC;
        
        assertLe(currentCap, maxCap, "Bank capacity exceeds maximum");
        
        // Try to deposit beyond capacity
        uint256 maxDepositETH = (maxCap * 1e20) / uint256(INITIAL_ETH_PRICE);
        
        vm.prank(user1);
        bank.depositETH{value: maxDepositETH}();
        
        currentCap = bank.currentCapUSDC();
        assertLe(currentCap, maxCap, "Bank capacity exceeds maximum after max deposit");
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZING TEST FOUNDATIONS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_DepositETH(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(amount <= type(uint128).max); // Prevent overflow
        
        uint256 usdcEquivalent = (amount * uint256(INITIAL_ETH_PRICE)) / 1e20;
        vm.assume(usdcEquivalent <= MAX_CAP_USDC);
        
        uint256 userBalanceBefore = bank.getUserBalance(user1);
        
        vm.prank(user1);
        bank.depositETH{value: amount}();
        
        uint256 userBalanceAfter = bank.getUserBalance(user1);
        
        assertEq(userBalanceAfter - userBalanceBefore, usdcEquivalent);
    }
    
    function testFuzz_WithdrawETH(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= 10 ether);
        vm.assume(withdrawAmount > 0);
        
        uint256 usdcEquivalent = (depositAmount * uint256(INITIAL_ETH_PRICE)) / 1e20;
        vm.assume(withdrawAmount <= usdcEquivalent);
        
        // Deposit first
        vm.prank(user1);
        bank.depositETH{value: depositAmount}();
        
        uint256 userBalanceBefore = bank.getUserBalance(user1);
        uint256 contractETHBefore = bank.currentETHBalance();
        
        // Withdraw
        vm.prank(user1);
        bank.withdrawETH(withdrawAmount);
        
        uint256 userBalanceAfter = bank.getUserBalance(user1);
        uint256 contractETHAfter = bank.currentETHBalance();
        
        assertEq(userBalanceBefore - userBalanceAfter, withdrawAmount);
        
        uint256 expectedETHWithdrawn = (withdrawAmount * 1e20) / uint256(INITIAL_ETH_PRICE);
        assertEq(contractETHBefore - contractETHAfter, expectedETHWithdrawn);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CompleteDepositWithdrawCycle() public {
        uint256 depositAmount = 1 ether;
        
        // Initial state
        uint256 userInitialETH = user1.balance;
        
        // Deposit ETH
        vm.prank(user1);
        bank.depositETH{value: depositAmount}();
        
        uint256 userUSDCBalance = bank.getUserBalance(user1);
        assertTrue(userUSDCBalance > 0, "No USDC balance after deposit");
        
        // Withdraw ETH
        vm.prank(user1);
        bank.withdrawETH(userUSDCBalance);
        
        uint256 userFinalETH = user1.balance;
        uint256 userFinalUSDCBalance = bank.getUserBalance(user1);
        
        assertEq(userFinalUSDCBalance, 0, "USDC balance not zero after full withdrawal");
        
        // Should get back approximately the same ETH (minus gas)
        assertApproxEqRel(userFinalETH + depositAmount, userInitialETH, 0.001e18); // 0.1% tolerance
    }

    function test_MixedTokenDeposits() public {
        // Approve tokens
        vm.prank(user1);
        mockUSDC.approve(address(bank), type(uint256).max);
        
        vm.prank(user1);
        mockToken.approve(address(bank), type(uint256).max);
        
        // Deposit ETH
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 balanceAfterETH = bank.getUserBalance(user1);
        
        // Deposit USDC
        vm.prank(user1);
        bank.depositERC20(address(mockUSDC), 1000 * 10**6);
        
        uint256 balanceAfterUSDC = bank.getUserBalance(user1);
        assertEq(balanceAfterUSDC - balanceAfterETH, 1000 * 10**6);
        
        // Deposit other token (will be swapped)
        vm.prank(user1);
        bank.depositERC20(address(mockToken), 10 * 10**18); // 10 tokens at $10 each = $100
        
        uint256 balanceAfterToken = bank.getUserBalance(user1);
        uint256 tokenDeposit = balanceAfterToken - balanceAfterUSDC;
        
        // Should be approximately 100 USDC (allowing for slippage)
        assertApproxEqRel(tokenDeposit, 100 * 10**6, 0.1e18); // 10% tolerance for swap slippage
    }

    /*//////////////////////////////////////////////////////////////
                        SETUP HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function depositUSDCForUser(address user, uint256 amount) internal {
        vm.prank(user);
        mockUSDC.approve(address(bank), amount);
        
        vm.prank(user);
        bank.depositERC20(address(mockUSDC), amount);
    }
}

/*//////////////////////////////////////////////////////////////
                    MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

contract MockChainlinkFeed {
    int256 private price;
    uint256 private updatedAt;
    uint80 private roundId;
    
    constructor(int256 _initialPrice) {
        price = _initialPrice;
        updatedAt = block.timestamp;
        roundId = 1;
    }
    
    function latestRoundData() external view returns (
        uint80 roundId_,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt_,
        uint80 answeredInRound
    ) {
        return (roundId, price, block.timestamp, updatedAt, roundId);
    }
    
    function setPrice(int256 _newPrice) external {
        price = _newPrice;
        updatedAt = block.timestamp;
        roundId++;
    }
    
    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }
}

contract MockUniswapRouter {
    address public immutable USDC;
    mapping(address => bool) public hasPair;
    
    constructor(address _usdc) {
        USDC = _usdc;
    }
    
    function setHasPair(address token, bool _hasPair) external {
        hasPair[token] = _hasPair;
    }
    
    function factory() external view returns (address) {
        return address(this);
    }
    
    function WETH() external pure returns (address) {
        return address(0);
    }
    
    function getPair(address tokenA, address tokenB) external view returns (address) {
        if (tokenA == USDC || tokenB == USDC) {
            return hasPair[tokenA == USDC ? tokenB : tokenA] ? address(0x1) : address(0);
        }
        return address(0);
    }
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        
        if (path.length == 2 && path[1] == USDC) {
            // Simulate swap: assume 1 token = $10, 1 USDC = $1
            amounts[1] = amountIn * 10 / 1e12; // Convert 18 decimals to 6 decimals with 10:1 ratio
        } else {
            amounts[1] = amountIn; // 1:1 for other cases
        }
    }
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(deadline >= block.timestamp, "Deadline expired");
        require(path.length >= 2, "Invalid path");
        
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        
        if (path[1] == USDC) {
            amounts[1] = amountIn * 10 / 1e12; // 10:1 ratio with decimal conversion
        } else {
            amounts[1] = amountIn;
        }
        
        require(amounts[amounts.length - 1] >= amountOutMin, "Insufficient output");
        
        // Simulate token transfer
        MockERC20(USDC).mint(to, amounts[1]);
        
        return amounts;
    }
}

// Contract to test reentrancy attacks
contract MaliciousContract {
    KipuBankV3 public bank;
    bool public attacking = false;
    
    constructor(address payable _bank) {
        bank = KipuBankV3(_bank);
    }
    
    function attack() external {
        attacking = true;
        uint256 balance = bank.getUserBalance(address(this));
        if (balance > 0) {
            bank.withdrawETH(balance);
        }
    }
    
    // This will be called when receiving ETH
    receive() external payable {
        if (attacking && address(bank).balance >= 0.1 ether) {
            uint256 balance = bank.getUserBalance(address(this));
            if (balance > 0) {
                bank.withdrawETH(balance);
            }
        }
    }
}

// Contract that rejects ETH transfers to test unchecked external calls
contract RejectETHContract {
    KipuBankV3 public bank;
    
    constructor(address payable _bank) {
        bank = KipuBankV3(_bank);
    }
    
    function attemptWithdraw() external {
        uint256 balance = bank.getUserBalance(address(this));
        bank.withdrawETH(balance);
    }
    
    // Reject all ETH transfers
    receive() external payable {
        revert("ETH transfer rejected");
    }
}