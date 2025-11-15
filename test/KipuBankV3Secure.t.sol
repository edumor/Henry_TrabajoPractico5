// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";

/**
 * @title KipuBankV3SecureTest - Enhanced security test suite for KipuBankV3
 * @dev Comprehensive testing for vulnerability fixes and edge cases
 */

// Enhanced mock price feed with configurable behavior
contract MockAggregatorV3 {
    int256 private price;
    uint256 private updatedAt;
    uint80 private roundId;
    uint80 private answeredInRound;
    bool private shouldRevert;
    bool private returnStalePrice;
    bool private returnNegativePrice;
    
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
        if (shouldRevert) {
            revert("Oracle error");
        }
        
        if (returnNegativePrice) {
            return (roundId, -1, 0, updatedAt, answeredInRound);
        }
        
        if (returnStalePrice) {
            return (roundId, price, 0, block.timestamp - 3601, answeredInRound); // Stale by 1 hour + 1 second
        }
        
        return (roundId, price, 0, updatedAt, answeredInRound);
    }
    
    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
        roundId++;
        answeredInRound = roundId;
    }
    
    function setStalePrice(bool _stale) external {
        returnStalePrice = _stale;
    }
    
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
    
    function setNegativePrice(bool _negative) external {
        returnNegativePrice = _negative;
    }
}

// Mock USDC token for testing  
contract MockUSDCToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string public name = "USDC Mock";
    string public symbol = "USDC";
    
    constructor() {
        _totalSupply = 1000000 * 10**6; // 1M USDC
        _balances[msg.sender] = _totalSupply;
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(from, to, amount);
        _approve(from, msg.sender, currentAllowance - amount);
        return true;
    }
    
    function decimals() external pure returns (uint8) {
        return 6;
    }
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
    }
}

// Mock ERC20 token for testing
contract MockERC20Token is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    uint8 private _decimals;
    string public name;
    string public symbol;
    
    constructor(string memory _name, string memory _symbol, uint8 __decimals) {
        name = _name;
        symbol = _symbol;
        _decimals = __decimals;
        _totalSupply = 1000000 * 10**__decimals;
        _balances[msg.sender] = _totalSupply;
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(from, to, amount);
        _approve(from, msg.sender, currentAllowance - amount);
        return true;
    }
    
    function decimals() external view returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
    }
}

contract KipuBankV3SecureTest is Test {
    KipuBankV3 public bank;
    MockUSDCToken public mockUSDC;
    MockERC20Token public mockWBTC;
    MockAggregatorV3 public ethPriceFeed;
    MockAggregatorV3 public wbtcPriceFeed;
    
    address public constant owner = address(0x1);
    address public constant user1 = address(0x2);
    address public constant user2 = address(0x3);
    address public constant attacker = address(0x4);
    
    uint256 public constant ETH_PRICE = 2000e8; // $2000 ETH
    uint256 public constant WBTC_PRICE = 35000e8; // $35000 WBTC
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock contracts
        mockUSDC = new MockUSDCToken();
        mockWBTC = new MockERC20Token("Wrapped BTC", "WBTC", 8);
        ethPriceFeed = new MockAggregatorV3(int256(ETH_PRICE));
        wbtcPriceFeed = new MockAggregatorV3(int256(WBTC_PRICE));
        
        // Deploy KipuBank
        bank = new KipuBankV3(
            owner,
            address(ethPriceFeed),
            address(mockUSDC),
            address(ethPriceFeed), // Using ETH price feed as USDC feed for simplicity
            address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) // Uniswap V2 Router
        );
        
        // Configure additional supported tokens  
        bank.addSupportedToken(address(mockWBTC), address(wbtcPriceFeed), 8); // WBTC
        
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(attacker, 100 ether);
        
        mockWBTC.mint(user1, 10 * 10**8); // 10 WBTC
        mockWBTC.mint(user2, 10 * 10**8); // 10 WBTC
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testReentrancyProtection() public {
        // Deposit some ETH first
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        // Create malicious contract
        ReentrancyAttacker maliciousContract = new ReentrancyAttacker(bank);
        vm.deal(address(maliciousContract), 1 ether);
        
        // Fund the contract and try reentrancy attack
        maliciousContract.deposit{value: 1 ether}();
        
        // Attempt reentrancy attack - should fail
        vm.expectRevert("ReentrancyGuard: reentrant call");
        maliciousContract.attack();
    }
    
    /*//////////////////////////////////////////////////////////////
                    PRECISION MATH TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testPrecisionMathConsistency() public {
        uint256 depositAmount = 1 ether; // 1 ETH
        
        vm.startPrank(user1);
        
        // Deposit ETH
        bank.depositETH{value: depositAmount}();
        uint256 userBalanceAfterDeposit = bank.getUserBalance(user1);
        
        // Immediately withdraw the same amount
        bank.withdrawETH(userBalanceAfterDeposit);
        uint256 userBalanceAfterWithdraw = bank.getUserBalance(user1);
        
        vm.stopPrank();
        
        // User should have minimal balance left (due to precision improvements)
        assertEq(userBalanceAfterWithdraw, 0, "Should have exact balance");
    }
    
    function testLargeAmountPrecision() public {
        uint256 largeAmount = 100 ether; // 100 ETH
        
        vm.startPrank(user1);
        vm.deal(user1, largeAmount);
        
        bank.depositETH{value: largeAmount}();
        uint256 usdcEquivalent = bank.getUserBalance(user1);
        
        // Withdraw half
        uint256 halfAmount = usdcEquivalent / 2;
        bank.withdrawETH(halfAmount);
        
        uint256 remainingBalance = bank.getUserBalance(user1);
        
        vm.stopPrank();
        
        // Remaining balance should be approximately half (within precision tolerance)
        assertApproxEqRel(remainingBalance, halfAmount, 0.001e18, "Large amount precision error");
    }
    
    /*//////////////////////////////////////////////////////////////
                    ORACLE SECURITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testStalePriceProtection() public {
        // Make price stale
        ethPriceFeed.setStalePrice(true);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("StalePrice()"));
        bank.depositETH{value: 1 ether}();
    }
    
    function testNegativePriceProtection() public {
        ethPriceFeed.setNegativePrice(true);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidPrice()"));
        bank.depositETH{value: 1 ether}();
    }
    
    function testCircuitBreakerProtection() public {
        vm.startPrank(user1);
        
        // First deposit with normal price
        bank.depositETH{value: 1 ether}();
        uint256 balanceBeforePriceChange = bank.getUserBalance(user1);
        
        // Simulate extreme price increase (50% - should trigger circuit breaker)
        ethPriceFeed.setPrice(int256(ETH_PRICE * 150 / 100)); // 50% increase
        
        // Should use last valid price instead of new extreme price
        bank.depositETH{value: 1 ether}();
        uint256 balanceAfterPriceChange = bank.getUserBalance(user1);
        
        vm.stopPrank();
        
        // Second deposit should use similar conversion rate as first
        uint256 expectedIncrease = balanceBeforePriceChange;
        assertApproxEqRel(
            balanceAfterPriceChange - balanceBeforePriceChange,
            expectedIncrease,
            0.1e18, // 10% tolerance for circuit breaker
            "Circuit breaker failed"
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                    LIMIT TESTING
    //////////////////////////////////////////////////////////////*/
    
    function testSingleDepositLimit() public {
        // Try to deposit more than MAX_SINGLE_DEPOSIT (50,000 USDC equivalent)
        uint256 maxDepositInEth = 25 ether; // ~50,000 USDC at $2000/ETH
        uint256 excessiveAmount = maxDepositInEth + 1 ether;
        
        vm.deal(user1, excessiveAmount);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("LimitExceeded()"));
        bank.depositETH{value: excessiveAmount}();
    }
    
    function testDailyWithdrawalLimit() public {
        // Deposit large amount first
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        bank.depositETH{value: 50 ether}(); // ~100,000 USDC
        
        uint256 userBalance = bank.getUserBalance(user1);
        
        vm.startPrank(user1);
        
        // First withdrawal should work (within daily limit)
        uint256 firstWithdraw = 50000 * 10**6; // 50,000 USDC
        bank.withdrawETH(firstWithdraw);
        
        // Second withdrawal should exceed daily limit
        uint256 secondWithdraw = 60000 * 10**6; // 60,000 USDC (total would be 110,000)
        vm.expectRevert(abi.encodeWithSignature("LimitExceeded()"));
        bank.withdrawETH(secondWithdraw);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testOnlyOwnerFunctions() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        bank.addSupportedToken(address(0x123), address(0x456), 18);
    }
    
    function testPauseUnpauseFunctionality() public {
        vm.prank(owner);
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("Paused()"));
        bank.depositETH{value: 1 ether}();
        
        vm.prank(owner);
        bank.unpause();
        
        // Should work after unpause
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        assertGt(bank.getUserBalance(user1), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                    EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testZeroAmountDeposit() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        bank.depositETH{value: 0}();
    }
    
    function testZeroAmountWithdrawal() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        bank.withdrawETH(0);
    }
    
    function testWithdrawMoreThanBalance() public {
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 balance = bank.getUserBalance(user1);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("InsufficientBal()"));
        bank.withdrawETH(balance + 1);
    }
    
    function testCapacityLimit() public {
        // Get max capacity constant (100,000 USDC = 100000000000 with 6 decimals)
        uint256 maxCap = 100000000000; // 100,000 USDC
        uint256 ethNeededForCap = (maxCap * 1e18) / ETH_PRICE; // Convert USDC to ETH
        
        vm.deal(user1, ethNeededForCap + 1 ether);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("CapExceeded()"));
        bank.depositETH{value: ethNeededForCap + 1 ether}();
    }
    
    /*//////////////////////////////////////////////////////////////
                    GAS OPTIMIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testGasOptimizedDeposit() public {
        vm.prank(user1);
        uint256 gasBefore = gasleft();
        bank.depositETH{value: 1 ether}();
        uint256 gasUsed = gasBefore - gasleft();
        
        // Gas should be reasonable (less than 200k)
        assertLt(gasUsed, 200000, "Gas usage too high for deposit");
    }
    
    function testGasOptimizedWithdrawal() public {
        vm.startPrank(user1);
        bank.depositETH{value: 1 ether}();
        uint256 balance = bank.getUserBalance(user1);
        
        uint256 gasBefore = gasleft();
        bank.withdrawETH(balance);
        uint256 gasUsed = gasBefore - gasleft();
        
        vm.stopPrank();
        
        // Gas should be reasonable (less than 150k)
        assertLt(gasUsed, 150000, "Gas usage too high for withdrawal");
    }
    
    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testMultiUserInteractions() public {
        // User1 deposits ETH
        vm.prank(user1);
        bank.depositETH{value: 5 ether}();
        
        // User2 deposits ETH
        vm.prank(user2);
        bank.depositETH{value: 3 ether}();
        
        uint256 user1Balance = bank.getUserBalance(user1);
        uint256 user2Balance = bank.getUserBalance(user2);
        
        // Balances should be proportional to deposits
        assertApproxEqRel(user1Balance * 3, user2Balance * 5, 0.01e18, "Proportional balances");
        
        // Both users withdraw
        vm.prank(user1);
        bank.withdrawETH(user1Balance / 2);
        
        vm.prank(user2);
        bank.withdrawETH(user2Balance / 2);
        
        // Check final balances
        assertEq(bank.getUserBalance(user1), user1Balance / 2);
        assertEq(bank.getUserBalance(user2), user2Balance / 2);
    }
    
    /*//////////////////////////////////////////////////////////////
                    FUZZING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzzDeposit(uint256 amount) public {
        // Bound to reasonable range
        amount = bound(amount, 0.01 ether, 20 ether);
        
        vm.deal(user1, amount);
        vm.prank(user1);
        bank.depositETH{value: amount}();
        
        assertGt(bank.getUserBalance(user1), 0);
    }
    
    function testFuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 20 ether);
        
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        bank.depositETH{value: depositAmount}();
        
        uint256 balance = bank.getUserBalance(user1);
        withdrawAmount = bound(withdrawAmount, 1, balance);
        
        vm.prank(user1);
        bank.withdrawETH(withdrawAmount);
        
        assertEq(bank.getUserBalance(user1), balance - withdrawAmount);
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
        if (attacking && address(bank).balance > 0) {
            uint256 balance = bank.getUserBalance(address(this));
            if (balance > 0) {
                bank.withdrawETH(balance);
            }
        }
    }
}