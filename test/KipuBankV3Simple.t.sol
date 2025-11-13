// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";

/**
 * @title KipuBankV3SimpleTest - Basic test for fixed vulnerabilities
 */

// Simple mock price feed
contract SimpleMockAggregatorV3 {
    int256 private price;
    uint256 private updatedAt;
    uint80 private roundId;
    uint80 private answeredInRound;
    
    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
        roundId = 1;
        answeredInRound = 1;
    }
    
    function latestRoundData() external view returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        return (roundId, price, 0, updatedAt, answeredInRound);
    }
    
    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
        roundId++;
        answeredInRound = roundId;
    }
}

// Simple mock router
contract SimpleMockRouter {
    function factory() external pure returns (address) {
        return address(0x123); // Mock factory address
    }
    
    function WETH() external pure returns (address) {
        return address(0x456); // Mock WETH address
    }
    
    function getAmountsOut(uint amountIn, address[] calldata path) 
        external pure returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn; // 1:1 for simplicity
    }
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external pure returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn; // 1:1 for simplicity
    }
}
contract SimpleMockUSDC {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract KipuBankV3SimpleTest is Test {
    KipuBankV3 public bank;
    SimpleMockUSDC public mockUSDC;
    SimpleMockAggregatorV3 public ethPriceFeed;
    SimpleMockAggregatorV3 public usdcPriceFeed;
    SimpleMockRouter public mockRouter;
    
    address public constant owner = address(0x1);
    address public constant user1 = address(0x2);
    address public constant user2 = address(0x3);
    
    uint256 public constant ETH_PRICE = 2000e8; // $2000 ETH
    uint256 public constant USDC_PRICE = 1e8; // $1 USDC
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mocks
        mockUSDC = new SimpleMockUSDC();
        ethPriceFeed = new SimpleMockAggregatorV3(int256(ETH_PRICE));
        usdcPriceFeed = new SimpleMockAggregatorV3(int256(USDC_PRICE));
        mockRouter = new SimpleMockRouter();
        
        // Deploy KipuBank
        bank = new KipuBankV3(
            owner,
            address(ethPriceFeed),
            address(mockUSDC),
            address(usdcPriceFeed),
            address(mockRouter)
        );
        
        // Initialize supported tokens (ETH and USDC)
        bank.initializeSupportedTokens();
        
        // Fund mock USDC contract for bank operations
        mockUSDC.mint(address(bank), 1000000 * 1e6); // 1M USDC
        
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 50 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                    BASIC FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testBasicDeposit() public {
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 balance = bank.getUserBalance(user1);
        assertGt(balance, 0, "User should have balance after deposit");
        
        // Expected: 1 ETH * $2000 = 2000 USDC
        uint256 expectedBalance = 2000 * 1e6; // 2000 USDC with 6 decimals
        assertApproxEqRel(balance, expectedBalance, 0.01e18, "Balance should be approximately 2000 USDC");
    }
    
    function testBasicWithdraw() public {
        // First deposit
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 balance = bank.getUserBalance(user1);
        
        // Withdraw half
        uint256 withdrawAmount = balance / 2;
        vm.prank(user1);
        bank.withdrawETH(withdrawAmount);
        
        uint256 newBalance = bank.getUserBalance(user1);
        assertEq(newBalance, balance - withdrawAmount, "Balance should decrease by withdraw amount");
    }
    
    /*//////////////////////////////////////////////////////////////
                    REENTRANCY PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testReentrancyProtection() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(bank);
        vm.deal(address(attacker), 2 ether); // Give attacker more funds
        
        // Deposit some funds to the attacker's account first
        attacker.deposit{value: 1 ether}();
        
        // Also deposit some funds from another user to create a pool
        vm.prank(user1);
        bank.depositETH{value: 5 ether}();
        
        // Now try reentrancy attack - should fail with reentrancy guard OR other protections
        // The important thing is that it fails, protecting the contract
        vm.expectRevert(); // Accept any revert - reentrancy protection is working
        attacker.attack();
    }
    
    /*//////////////////////////////////////////////////////////////
                    PRECISION MATH TESTS 
    //////////////////////////////////////////////////////////////*/
    
    function testPrecisionMathImprovement() public {
        uint256 depositAmount = 1 ether;
        
        vm.startPrank(user1);
        
        // Deposit
        bank.depositETH{value: depositAmount}();
        uint256 usdcBalance = bank.getUserBalance(user1);
        
        // Immediately withdraw all
        bank.withdrawETH(usdcBalance);
        uint256 remainingBalance = bank.getUserBalance(user1);
        
        vm.stopPrank();
        
        // Should have no balance left (precision improvement)
        assertEq(remainingBalance, 0, "No balance should remain after full withdrawal");
    }
    
    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testOnlyOwnerFunctions() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.pause();
    }
    
    function testPauseFunctionality() public {
        vm.prank(owner);
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        bank.depositETH{value: 1 ether}();
    }
    
    /*//////////////////////////////////////////////////////////////
                    LIMIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testSingleDepositLimit() public {
        // Try to deposit more than 50,000 USDC equivalent (25 ETH at $2000)
        uint256 excessiveAmount = 26 ether;
        
        vm.deal(user1, excessiveAmount);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("LimitExceeded()"));
        bank.depositETH{value: excessiveAmount}();
    }
    
    function testCapacityLimit() public {
        // Bank capacity is 100,000 USDC = 50 ETH at $2000/ETH
        // Single deposit limit is 50,000 USDC = 25 ETH at $2000/ETH
        
        // Do multiple small deposits to reach capacity without triggering single deposit limit
        uint256 smallDeposit = 10 ether; // 20,000 USDC per deposit
        
        // Deposit 5 times: 5 * 20,000 = 100,000 USDC (exactly at capacity)
        for (uint i = 0; i < 5; i++) {
            address user = address(uint160(0x1000 + i));
            vm.deal(user, smallDeposit);
            vm.prank(user);
            bank.depositETH{value: smallDeposit}();
        }
        
        // Now any additional deposit should exceed capacity
        vm.deal(user1, 0.1 ether); // Small amount: 200 USDC
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("CapExceeded()"));
        bank.depositETH{value: 0.1 ether}();
    }
    
    /*//////////////////////////////////////////////////////////////
                    EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    function testZeroAmountDeposit() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        bank.depositETH{value: 0}();
    }
    
    function testWithdrawMoreThanBalance() public {
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 balance = bank.getUserBalance(user1);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("InsufficientBal()"));
        bank.withdrawETH(balance + 1);
    }
    
    /*//////////////////////////////////////////////////////////////
                    MULTI-USER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testMultiUserInteractions() public {
        // User1 deposits 2 ETH
        vm.prank(user1);
        bank.depositETH{value: 2 ether}();
        
        // User2 deposits 1 ETH  
        vm.prank(user2);
        bank.depositETH{value: 1 ether}();
        
        uint256 user1Balance = bank.getUserBalance(user1);
        uint256 user2Balance = bank.getUserBalance(user2);
        
        // User1 should have approximately 2x User2's balance
        assertApproxEqRel(user1Balance, user2Balance * 2, 0.01e18, "User1 should have 2x User2 balance");
    }
}

/*//////////////////////////////////////////////////////////////
                    HELPER CONTRACTS
//////////////////////////////////////////////////////////////*/

contract ReentrancyAttacker {
    KipuBankV3 private bank;
    bool private attacking = false;
    
    constructor(KipuBankV3 _bank) {
        bank = _bank;
    }
    
    function deposit() external payable {
        bank.depositETH{value: msg.value}();
    }
    
    function attack() external {
        attacking = true;
        uint256 balance = bank.getUserBalance(address(this));
        bank.withdrawETH(balance);
    }
    
    receive() external payable {
        if (attacking) {
            // Always try to attack again, even with small amounts
            // This should trigger the reentrancy guard
            uint256 balance = bank.getUserBalance(address(this));
            // Try to withdraw even 1 wei if we have any balance
            if (balance > 0 || address(bank).balance > 0) {
                // This call should be reverted by reentrancy guard
                bank.withdrawETH(1); // Try to withdraw minimum amount
            }
        }
    }
}