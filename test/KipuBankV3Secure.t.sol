// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {KipuBankV3Secure} from "../src/KipuBankV3Secure.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// Mock contracts for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        _decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return super.decimals();
    }
}

contract MockPriceFeed {
    int256 private _price;
    uint256 private _timestamp;
    uint80 private _roundId;
    
    constructor(int256 initialPrice) {
        _price = initialPrice;
        _timestamp = block.timestamp;
        _roundId = 1;
    }
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _timestamp, _timestamp, _roundId);
    }
    
    function updatePrice(int256 newPrice) external {
        _price = newPrice;
        _timestamp = block.timestamp;
        _roundId++;
    }
    
    function updateTimestamp(uint256 newTimestamp) external {
        _timestamp = newTimestamp;
    }
    
    function decimals() external pure returns (uint8) {
        return 8;
    }
}

contract MockUniswapRouter {
    mapping(address => mapping(address => uint256)) public prices;
    bool public shouldFail = false;
    
    function factory() external pure returns (address) {
        return address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f); // Mainnet factory
    }
    
    function WETH() external pure returns (address) {
        return address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }
    
    function setPrice(address tokenA, address tokenB, uint256 price) external {
        prices[tokenA][tokenB] = price;
    }
    
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }
    
    function getAmountsOut(uint amountIn, address[] calldata path) 
        external 
        view 
        returns (uint[] memory amounts) 
    {
        require(!shouldFail, "MockRouter: getAmountsOut failed");
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        
        for (uint i = 0; i < path.length - 1; i++) {
            uint256 price = prices[path[i]][path[i + 1]];
            amounts[i + 1] = (amounts[i] * price) / 1e18;
        }
    }
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(!shouldFail, "MockRouter: swap failed");
        require(block.timestamp <= deadline, "MockRouter: expired");
        
        amounts = this.getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "MockRouter: insufficient output");
        
        // Transfer tokens (simplified for testing)
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(path[path.length - 1]).mint(to, amounts[amounts.length - 1]);
        
        return amounts;
    }
}

contract MockUniswapFactory {
    mapping(address => mapping(address => address)) public pairs;
    
    function setPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }
    
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }
}

/**
 * @title KipuBankV3Secure Test Suite
 * @notice Comprehensive security testing for the enhanced KipuBank contract
 */
contract KipuBankV3SecureTest is Test {
    KipuBankV3Secure public bank;
    MockERC20 public usdc;
    MockERC20 public testToken;
    MockPriceFeed public ethPriceFeed;
    MockPriceFeed public usdcPriceFeed;
    MockPriceFeed public testTokenPriceFeed;
    MockUniswapRouter public uniswapRouter;
    MockUniswapFactory public uniswapFactory;
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");
    
    uint256 constant ETH_PRICE = 2000_00000000; // $2000 with 8 decimals
    uint256 constant USDC_PRICE = 1_00000000;   // $1 with 8 decimals
    uint256 constant TEST_TOKEN_PRICE = 500_00000000; // $500 with 8 decimals
    
    event Deposit(address indexed user, uint256 usdcAmount, uint256 ethAmount, uint256 timestamp);
    event Withdrawal(address indexed user, uint256 amount, uint256 timestamp);
    event TokenSwapped(address indexed user, address indexed token, uint256 amountIn, uint256 amountOut);
    event CircuitBreakerTriggered(address indexed token, uint256 oldPrice, uint256 newPrice, uint256 deviation);

    function setUp() public {
        // Deploy mock contracts
        usdc = new MockERC20("USD Coin", "USDC", 6);
        testToken = new MockERC20("Test Token", "TEST", 18);
        
        ethPriceFeed = new MockPriceFeed(int256(ETH_PRICE));
        usdcPriceFeed = new MockPriceFeed(int256(USDC_PRICE));
        testTokenPriceFeed = new MockPriceFeed(int256(TEST_TOKEN_PRICE));
        
        uniswapRouter = new MockUniswapRouter();
        uniswapFactory = new MockUniswapFactory();
        
        // Set up Uniswap pairs
        address testPair = makeAddr("testPair");
        uniswapFactory.setPair(address(testToken), address(usdc), testPair);
        uniswapRouter.setPrice(address(testToken), address(usdc), 250_000000); // 1 TEST = 250 USDC
        
        // Deploy bank contract
        vm.prank(owner);
        bank = new KipuBankV3Secure(
            owner,
            address(ethPriceFeed),
            address(usdc),
            address(usdcPriceFeed),
            address(uniswapRouter)
        );
        
        // Configure for maximum coverage testing (no rate limiting)
        vm.prank(owner);
        bank.setRateLimit(0);
        
        // Add test token support
        vm.prank(owner);
        bank.addSupportedToken(address(testToken), address(testTokenPriceFeed), 18);
        
        // Setup initial balances
        deal(user1, 10 ether);
        deal(user2, 10 ether);
        deal(attacker, 100 ether);
        
        usdc.mint(user1, 10000_000000); // 10k USDC
        usdc.mint(user2, 10000_000000);
        usdc.mint(attacker, 100000_000000); // 100k USDC
        
        testToken.mint(user1, 100 ether);
        testToken.mint(user2, 100 ether);
        testToken.mint(attacker, 1000 ether);
        testToken.mint(address(uniswapRouter), 1000000 ether); // Liquidity for swaps
        
        // Pre-approve all tokens for seamless testing
        vm.prank(user1);
        usdc.approve(address(bank), type(uint256).max);
        vm.prank(user1);
        testToken.approve(address(bank), type(uint256).max);
        
        vm.prank(user2);
        usdc.approve(address(bank), type(uint256).max);
        vm.prank(user2);
        testToken.approve(address(bank), type(uint256).max);
        
        vm.prank(attacker);
        usdc.approve(address(bank), type(uint256).max);
        vm.prank(attacker);
        testToken.approve(address(bank), type(uint256).max);
        
        // Approve tokens for bank
        vm.prank(user1);
        usdc.approve(address(bank), type(uint256).max);
        vm.prank(user1);
        testToken.approve(address(bank), type(uint256).max);
        
        vm.prank(user2);
        usdc.approve(address(bank), type(uint256).max);
        vm.prank(user2);
        testToken.approve(address(bank), type(uint256).max);
        
        vm.prank(attacker);
        usdc.approve(address(bank), type(uint256).max);
        vm.prank(attacker);
        testToken.approve(address(bank), type(uint256).max);
        
        vm.prank(address(bank));
        testToken.approve(address(uniswapRouter), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            BASIC FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DepositETH_Success() public {
        uint256 depositAmount = 1 ether;
        uint256 expectedUSDC = (depositAmount * ETH_PRICE) / (1e18 * 1e2); // ~2000 USDC
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, expectedUSDC, depositAmount, block.timestamp);
        
        bank.depositETH{value: depositAmount}();
        
        assertEq(bank.getUserBalance(user1), expectedUSDC);
        assertEq(bank.currentUSDCBalance(), expectedUSDC + 1); // +1 from initialization
        assertEq(bank.currentETHBalance(), depositAmount + 1); // +1 from initialization
    }

    function test_DepositUSDC_Success() public {
        uint256 depositAmount = 1000_000000; // 1000 USDC
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, depositAmount, depositAmount, block.timestamp);
        
        bank.depositERC20(address(usdc), depositAmount);
        
        assertEq(bank.getUserBalance(user1), depositAmount);
        assertEq(usdc.balanceOf(address(bank)), depositAmount);
    }

    function test_DepositTokenWithSwap_Success() public {
        uint256 depositAmount = 1 ether; // 1 TEST token
        uint256 expectedUSDC = 250_000000; // Should get ~250 USDC based on mock price
        
        vm.prank(user1);
        bank.depositERC20(address(testToken), depositAmount);
        
        // User should receive USDC equivalent
        assertEq(bank.getUserBalance(user1), expectedUSDC);
    }

    function test_WithdrawETH_Success() public {
        // First deposit
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 userBalance = bank.getUserBalance(user1);
        uint256 withdrawAmount = userBalance / 2; // Withdraw half
        
        uint256 initialETHBalance = user1.balance;
        
        vm.prank(user1);
        bank.withdrawETH(withdrawAmount);
        
        assertEq(bank.getUserBalance(user1), userBalance - withdrawAmount);
        assertGt(user1.balance, initialETHBalance); // User should receive ETH
    }

    function test_WithdrawUSDC_Success() public {
        // First deposit USDC
        uint256 depositAmount = 1000_000000;
        vm.prank(user1);
        bank.depositERC20(address(usdc), depositAmount);
        
        uint256 withdrawAmount = 500_000000; // Withdraw half
        uint256 initialUSDCBalance = usdc.balanceOf(user1);
        
        vm.prank(user1);
        bank.withdrawUSDC(withdrawAmount);
        
        assertEq(bank.getUserBalance(user1), depositAmount - withdrawAmount);
        assertEq(usdc.balanceOf(user1), initialUSDCBalance + withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            SECURITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ReentrancyProtection() public {
        // Deploy malicious contract that attempts reentrancy
        MaliciousReentrant malicious = new MaliciousReentrant(address(bank));
        deal(address(malicious), 10 ether);
        
        // Fund the malicious contract
        vm.prank(address(malicious));
        bank.depositETH{value: 1 ether}();
        
        // Attempt reentrancy attack - should fail
        vm.prank(address(malicious));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        malicious.attack();
    }

    function test_OracleManipulationProtection() public {
        // Set initial price and deposit
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        // Attempt to manipulate price drastically (>15% change should trigger circuit breaker)
        ethPriceFeed.updatePrice(int256(ETH_PRICE * 2)); // 100% increase
        
        // Should revert due to circuit breaker
        vm.prank(user2);
        vm.expectRevert(KipuBankV3Secure.PriceChangeTooLarge.selector);
        bank.depositETH{value: 1 ether}();
    }

    function test_StalePriceProtection() public {
        // Set stale timestamp (> 1 hour old)
        ethPriceFeed.updateTimestamp(block.timestamp - 3601);
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3Secure.StalePrice.selector);
        bank.depositETH{value: 1 ether}();
    }

    function test_RateLimiting() public {
        vm.startPrank(user1);
        
        // First deposit should succeed
        bank.depositETH{value: 0.1 ether}();
        
        // Immediate second deposit should fail (same block)
        vm.expectRevert(KipuBankV3Secure.OperationTooFrequent.selector);
        bank.depositETH{value: 0.1 ether}();
        
        vm.stopPrank();
    }

    function test_CapacityLimit() public {
        // Calculate amount that would exceed capacity
        uint256 maxCapInETH = 100 ether; // MAX_CAP equivalent
        uint256 exceedsCapAmount = 101 ether;
        
        vm.prank(attacker);
        vm.expectRevert(KipuBankV3Secure.CapExceeded.selector);
        bank.depositETH{value: exceedsCapAmount}();
    }

    function test_MaxSingleDepositLimit() public {
        uint256 maxSingleDeposit = 10_000_000; // 10 USDC equivalent (MAX_SINGLE_DEPOSIT)
        uint256 exceedsMaxAmount = 11_000_000; // 11 USDC
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3Secure.AmountExceedsMaximum.selector);
        bank.depositERC20(address(usdc), exceedsMaxAmount);
    }

    function test_PauseProtection() public {
        vm.prank(owner);
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        bank.depositETH{value: 1 ether}();
    }

    function test_UserPauseProtection() public {
        vm.prank(owner);
        bank.pauseUser(user1);
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3Secure.UserPaused.selector);
        bank.depositETH{value: 1 ether}();
    }

    function test_InsufficientBalanceWithdrawal() public {
        uint256 userBalance = bank.getUserBalance(user1); // Should be 0
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3Secure.InsufficientBal.selector);
        bank.withdrawUSDC(1000_000000);
    }

    function test_SwapFailureHandling() public {
        // Set router to fail
        uniswapRouter.setShouldFail(true);
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3Secure.SwapFailed.selector);
        bank.depositERC20(address(testToken), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BalanceConservationInvariant() public {
        // Multiple users deposit different amounts
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        vm.roll(block.number + 2); // Move forward to pass rate limit
        
        vm.prank(user2);
        bank.depositERC20(address(usdc), 1000_000000);
        
        // Check that total user balances equal contract USDC balance
        uint256 user1Balance = bank.getUserBalance(user1);
        uint256 user2Balance = bank.getUserBalance(user2);
        uint256 totalUserBalances = user1Balance + user2Balance;
        
        // Account for initialization offset
        assertEq(bank.currentUSDCBalance(), totalUserBalances + 1);
    }

    function test_SolvencyInvariant() public {
        // Deposit some funds
        vm.prank(user1);
        bank.depositETH{value: 5 ether}();
        
        vm.roll(block.number + 2);
        
        vm.prank(user2);
        bank.depositERC20(address(usdc), 5000_000000);
        
        // Contract should have enough ETH + USDC to cover all user balances
        uint256 totalUserBalances = bank.getUserBalance(user1) + bank.getUserBalance(user2);
        uint256 contractUSDC = usdc.balanceOf(address(bank));
        uint256 contractETHInUSDC = (address(bank).balance * ETH_PRICE) / (1e18 * 1e2);
        
        assertGe(contractUSDC + contractETHInUSDC, totalUserBalances);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OnlyOwnerFunctions() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        bank.addSupportedToken(makeAddr("newToken"), makeAddr("newFeed"), 18);
        
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        bank.pauseUser(user2);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_ZeroAmountDeposit() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3Secure.ZeroAmount.selector);
        bank.depositETH{value: 0}();
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3Secure.ZeroAmount.selector);
        bank.depositERC20(address(usdc), 0);
    }

    function test_UnsupportedTokenDeposit() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18);
        unsupportedToken.mint(user1, 100 ether);
        
        vm.prank(user1);
        unsupportedToken.approve(address(bank), type(uint256).max);
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3Secure.NotSupported.selector);
        bank.depositERC20(address(unsupportedToken), 1 ether);
    }

    function test_ReceiveFunctionDeposit() public {
        uint256 depositAmount = 0.5 ether;
        uint256 expectedUSDC = (depositAmount * ETH_PRICE) / (1e18 * 1e2);
        
        // Send ETH directly to contract via receive()
        vm.prank(user1);
        (bool success, ) = address(bank).call{value: depositAmount}("");
        assertTrue(success);
        
        assertEq(bank.getUserBalance(user1), expectedUSDC);
    }
    
    function test_RateLimitConfiguration() public {
        vm.prank(owner);
        bank.setRateLimit(1);
        
        vm.prank(user1);
        bank.depositETH{value: 0.1 ether}();
        
        vm.roll(block.number + 2);
        vm.prank(user1);
        bank.depositETH{value: 0.1 ether}();
        
        vm.prank(owner);
        bank.setRateLimit(0);
    }
    
    function test_EmergencyWithdrawCoverage() public {
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.prank(owner);
        bank.pause();
        vm.prank(owner);
        bank.emergencyWithdraw(address(0), address(bank).balance);
        
        assertGt(owner.balance, ownerBalanceBefore);
    }
    
    function test_TokenSupportManagement() public {
        MockERC20 newToken = new MockERC20("Test", "TEST", 18);
        MockPriceFeed newFeed = new MockPriceFeed(10_00000000);
        
        vm.prank(owner);
        bank.addSupportedToken(address(newToken), address(newFeed), 18);
        
        vm.prank(owner);
        bank.removeSupportedToken(address(newToken));
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleUsersComplexScenario() public {
        // User1 deposits ETH
        vm.prank(user1);
        bank.depositETH{value: 2 ether}();
        
        vm.roll(block.number + 2);
        
        // User2 deposits USDC
        vm.prank(user2);
        bank.depositERC20(address(usdc), 3000_000000);
        
        vm.roll(block.number + 2);
        
        // User1 deposits test tokens (with swap)
        vm.prank(user1);
        bank.depositERC20(address(testToken), 5 ether);
        
        vm.roll(block.number + 2);
        
        // User2 withdraws some USDC
        uint256 user2Balance = bank.getUserBalance(user2);
        vm.prank(user2);
        bank.withdrawUSDC(user2Balance / 2);
        
        // Verify final state
        assertGt(bank.getUserBalance(user1), 0);
        assertGt(bank.getUserBalance(user2), 0);
        assertEq(bank.getUserBalance(user2), user2Balance / 2);
    }
}

/**
 * @title Malicious Reentrancy Contract
 * @notice Used to test reentrancy protection
 */
contract MaliciousReentrant {
    KipuBankV3Secure public immutable bank;
    bool public attacking = false;
    
    constructor(address _bank) {
        bank = KipuBankV3Secure(payable(_bank));
    }
    
    function attack() external {
        attacking = true;
        uint256 balance = bank.getUserBalance(address(this));
        if (balance > 0) {
            bank.withdrawETH(balance);
        }
    }
    
    receive() external payable {
        if (attacking && msg.sender == address(bank)) {
            uint256 balance = bank.getUserBalance(address(this));
            if (balance > 0) {
                bank.withdrawETH(balance); // This should fail due to reentrancy protection
            }
        }
    }
}

/**
 * @title Property-Based Testing Contract
 * @notice Tests invariants through fuzzing
 */
contract KipuBankV3InvariantTest is Test {
    KipuBankV3Secure public bank;
    MockERC20 public usdc;
    MockPriceFeed public ethPriceFeed;
    MockPriceFeed public usdcPriceFeed;
    MockUniswapRouter public uniswapRouter;
    
    address[] public users;
    
    function setUp() public {
        // Setup similar to main test
        usdc = new MockERC20("USD Coin", "USDC", 6);
        ethPriceFeed = new MockPriceFeed(2000_00000000);
        usdcPriceFeed = new MockPriceFeed(1_00000000);
        uniswapRouter = new MockUniswapRouter();
        
        bank = new KipuBankV3Secure(
            address(this),
            address(ethPriceFeed),
            address(usdc),
            address(usdcPriceFeed),
            address(uniswapRouter)
        );
        
        // Create test users
        for (uint i = 0; i < 10; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users.push(user);
            deal(user, 100 ether);
            usdc.mint(user, 100000_000000);
            
            vm.prank(user);
            usdc.approve(address(bank), type(uint256).max);
        }
    }

    /// @notice Invariant: Total user balances should equal contract USDC balance
    function invariant_balanceConservation() public view {
        uint256 totalUserBalances = 0;
        for (uint256 i = 0; i < users.length; i++) {
            totalUserBalances += bank.getUserBalance(users[i]);
        }
        
        // Account for initialization offset
        assert(bank.currentUSDCBalance() >= totalUserBalances);
        assert(bank.currentUSDCBalance() - totalUserBalances <= 1); // Allow for initialization
    }

    /// @notice Invariant: Bank should never exceed capacity
    function invariant_capacityLimit() public view {
        assert(bank.currentUSDCBalance() <= 100_000_000); // 100 ETH equivalent in USDC
    }

    /// @notice Invariant: Contract should be solvent
    function invariant_solvency() public view {
        uint256 totalUserBalances = 0;
        for (uint256 i = 0; i < users.length; i++) {
            totalUserBalances += bank.getUserBalance(users[i]);
        }
        
        uint256 contractUSDC = usdc.balanceOf(address(bank));
        uint256 contractETHInUSDC = (address(bank).balance * 2000_000000) / (1e18 * 1e2);
        
        assert(contractUSDC + contractETHInUSDC >= totalUserBalances);
    }
}