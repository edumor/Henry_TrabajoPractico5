// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";

/// @title Tests de Cobertura Adicionales para KipuBankV3
/// @notice Tests enfocados en mejorar la cobertura de código y edge cases
contract KipuBankV3CoverageTest is Test {
    KipuBankV3 public bank;
    MockERC20_Coverage public weth;
    MockERC20_Coverage public usdc;
    MockERC20_Coverage public unsupportedToken;
    MockChainlinkFeed_Coverage public ethUsdFeed;
    
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    
    uint256 constant INITIAL_BALANCE = 100 ether;
    
    event Deposit(address indexed user, uint256 usdcAmount, uint256 tokenAmount, uint256 timestamp);
    event Withdrawal(address indexed user, uint256 amount, uint256 timestamp);
    
    function setUp() public {
        // Deploy mocks
        weth = new MockERC20_Coverage("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20_Coverage("USD Coin", "USDC", 6);
        unsupportedToken = new MockERC20_Coverage("Random Token", "RAND", 18);
        ethUsdFeed = new MockChainlinkFeed_Coverage();
        
        // Set initial ETH/USD price: $2000
        ethUsdFeed.setPrice(2000 * 10**8);
        
        // Create mock router and factory
        MockUniswapRouter_Coverage mockRouter = new MockUniswapRouter_Coverage();
        MockUniswapFactory_Coverage mockFactory = new MockUniswapFactory_Coverage();
        
        // Deploy bank
        bank = new KipuBankV3(
            address(weth),
            address(usdc),
            address(ethUsdFeed),
            address(mockRouter),
            address(mockFactory)
        );
        
        // Fund users
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(user3, INITIAL_BALANCE);
        
        // Mint tokens to users
        weth.mint(user1, 100 ether);
        weth.mint(user2, 100 ether);
        usdc.mint(address(bank), 1000000 * 10**6); // 1M USDC for withdrawals
    }
    
    /// @notice Test: Verificar límite de retiro diario
    function test_DailyWithdrawalLimit() public {
        // Deposit 10 ETH = 20,000 USDC
        vm.startPrank(user1);
        bank.depositETH{value: 10 ether}();
        
        uint256 userBalance = bank.getUserBalance(user1);
        assertEq(userBalance, 20000 * 10**6, "Balance should be 20,000 USDC");
        
        // First withdrawal: 10,000 USDC (should succeed)
        bank.withdrawUSDC(10000 * 10**6);
        
        // Second withdrawal: another 10,000 USDC (should succeed - same day)
        bank.withdrawUSDC(10000 * 10**6);
        
        // Try to withdraw more (should fail - daily limit exceeded)
        vm.expectRevert("Daily withdrawal limit exceeded");
        bank.withdrawUSDC(1 * 10**6);
        
        vm.stopPrank();
    }
    
    /// @notice Test: Reseteo del límite diario después de 24 horas
    function test_DailyLimitReset() public {
        vm.startPrank(user1);
        bank.depositETH{value: 10 ether}();
        
        // Withdraw 20,000 USDC
        bank.withdrawUSDC(20000 * 10**6);
        
        // Deposit more
        bank.depositETH{value: 10 ether}();
        
        // Try to withdraw again (should fail - daily limit)
        vm.expectRevert("Daily withdrawal limit exceeded");
        bank.withdrawUSDC(1 * 10**6);
        
        // Advance time by 1 day + 1 second
        vm.warp(block.timestamp + 1 days + 1);
        
        // Now withdrawal should succeed (new day)
        bank.withdrawUSDC(10000 * 10**6);
        
        vm.stopPrank();
    }
    
    /// @notice Test: Múltiples usuarios con límites independientes
    function test_IndependentDailyLimits() public {
        // User1 deposits and withdraws
        vm.startPrank(user1);
        bank.depositETH{value: 10 ether}();
        bank.withdrawUSDC(20000 * 10**6);
        vm.stopPrank();
        
        // User2 should have independent limit
        vm.startPrank(user2);
        bank.depositETH{value: 10 ether}();
        bank.withdrawUSDC(20000 * 10**6); // Should succeed
        vm.stopPrank();
    }
    
    /// @notice Test: Deposit con precio del oráculo en el límite inferior
    function test_OraclePriceAtLowerBound() public {
        // Set price to minimum acceptable (just above 0)
        ethUsdFeed.setPrice(1); // $0.00000001
        
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        uint256 balance = bank.getUserBalance(user1);
        assertTrue(balance > 0, "Should have some balance");
    }
    
    /// @notice Test: Verificar que se emiten eventos correctamente
    function test_DepositEmitsEvent() public {
        vm.prank(user1);
        
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, 2000 * 10**6, 1 ether, block.timestamp);
        
        bank.depositETH{value: 1 ether}();
    }
    
    /// @notice Test: Verificar que withdrawal emite evento
    function test_WithdrawalEmitsEvent() public {
        vm.startPrank(user1);
        bank.depositETH{value: 1 ether}();
        
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(user1, 1 ether, block.timestamp);
        
        bank.withdrawETH(2000 * 10**6);
        vm.stopPrank();
    }
    
    /// @notice Test: Capacidad actual se actualiza correctamente
    function test_CurrentCapacityTracking() public {
        assertEq(bank.currentCapUSDC(), 0, "Initial capacity should be 0");
        
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        assertEq(bank.currentCapUSDC(), 2000 * 10**6, "Capacity should be 2000 USDC");
        
        vm.prank(user1);
        bank.withdrawUSDC(1000 * 10**6);
        
        assertEq(bank.currentCapUSDC(), 1000 * 10**6, "Capacity should be 1000 USDC after withdrawal");
    }
    
    /// @notice Test: Múltiples depósitos pequeños no deben causar problemas de precisión
    function test_MultipleSmallDeposits() public {
        vm.startPrank(user1);
        
        // 100 depósitos de 0.01 ETH cada uno
        for (uint i = 0; i < 100; i++) {
            bank.depositETH{value: 0.01 ether}();
        }
        
        // Total should be approximately 100 * 0.01 * 2000 = 2000 USDC
        uint256 balance = bank.getUserBalance(user1);
        assertGe(balance, 1990 * 10**6, "Balance should be at least 1990 USDC");
        assertLe(balance, 2010 * 10**6, "Balance should be at most 2010 USDC");
        
        vm.stopPrank();
    }
    
    /// @notice Test: Verificar que paused bloquea todas las funciones principales
    function test_PauseBlocksAllFunctions() public {
        bank.pause();
        
        vm.startPrank(user1);
        
        // depositETH should fail
        vm.expectRevert();
        bank.depositETH{value: 1 ether}();
        
        vm.stopPrank();
        
        bank.unpause();
        
        // Deposit to have balance
        vm.prank(user1);
        bank.depositETH{value: 1 ether}();
        
        bank.pause();
        
        vm.startPrank(user1);
        
        // withdrawETH should fail when paused
        vm.expectRevert();
        bank.withdrawETH(100 * 10**6);
        
        // withdrawUSDC should fail when paused
        vm.expectRevert();
        bank.withdrawUSDC(100 * 10**6);
        
        vm.stopPrank();
    }
    
    /// @notice Test: Solo owner puede pausar/despausar
    function test_OnlyOwnerCanPauseUnpause() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        bank.pause();
        
        vm.expectRevert();
        bank.unpause();
        
        vm.stopPrank();
    }
    
    /// @notice Test: Retiro de ETH con balance exacto
    function test_WithdrawExactETHBalance() public {
        vm.startPrank(user1);
        
        bank.depositETH{value: 1 ether}();
        uint256 balance = bank.getUserBalance(user1);
        
        // Withdraw exact balance
        bank.withdrawETH(balance);
        
        assertEq(bank.getUserBalance(user1), 0, "Balance should be 0");
        
        vm.stopPrank();
    }
    
    /// @notice Test: Retiro de USDC con balance exacto
    function test_WithdrawExactUSDCBalance() public {
        vm.startPrank(user1);
        
        bank.depositETH{value: 1 ether}();
        uint256 balance = bank.getUserBalance(user1);
        
        // Withdraw exact balance
        bank.withdrawUSDC(balance);
        
        assertEq(bank.getUserBalance(user1), 0, "Balance should be 0");
        
        vm.stopPrank();
    }
    
    /// @notice Test: Capacidad máxima con múltiples usuarios
    function test_MaxCapacityMultipleUsers() public {
        uint256 maxCap = 100000000000; // 100,000 USDC with 6 decimals
        
        // Calculate how much ETH needed for max capacity
        // Max = 100,000 USDC, price = $2000/ETH
        // Need: 100,000 / 2000 = 50 ETH
        
        vm.prank(user1);
        bank.depositETH{value: 25 ether}();
        
        vm.prank(user2);
        bank.depositETH{value: 25 ether}();
        
        assertEq(bank.currentCapUSDC(), maxCap, "Should be at max capacity");
        
        // Next deposit should fail
        vm.prank(user3);
        vm.expectRevert(KipuBankV3.LimitExceeded.selector);
        bank.depositETH{value: 1 ether}();
    }
    
    /// @notice Test: getUserBalance returns correct value
    function test_GetUserBalanceAccuracy() public {
        vm.startPrank(user1);
        
        assertEq(bank.getUserBalance(user1), 0, "Initial balance should be 0");
        
        bank.depositETH{value: 5 ether}();
        
        uint256 expectedBalance = 5 ether * 2000; // 5 ETH * $2000 = 10,000 USDC
        uint256 actualBalance = bank.getUserBalance(user1);
        
        // Allow 1% tolerance for conversion
        assertApproxEqRel(actualBalance, expectedBalance, 0.01e18, "Balance should match deposit");
        
        vm.stopPrank();
    }
    
    /// @notice Test: Transferencia de ownership
    function test_OwnershipTransferUpdatesOwner() public {
        address newOwner = address(0x999);
        
        bank.transferOwnership(newOwner);
        
        assertEq(bank.owner(), newOwner, "Owner should be updated");
        
        // Old owner should not be able to pause
        vm.expectRevert();
        bank.pause();
        
        // New owner should be able to pause
        vm.prank(newOwner);
        bank.pause();
        
        assertTrue(bank.isPaused(), "Contract should be paused");
    }
    
    /// @notice Test: Depósito cuando ya está cerca del límite
    function test_DepositNearCapacityLimit() public {
        // Deposit to get close to limit
        vm.prank(user1);
        bank.depositETH{value: 49 ether}(); // 49 ETH = 98,000 USDC
        
        // Small deposit should still work
        vm.prank(user2);
        bank.depositETH{value: 1 ether}(); // 1 ETH = 2,000 USDC -> Total: 100,000
        
        uint256 maxCap = 100000000000; // 100,000 USDC with 6 decimals
        assertEq(bank.currentCapUSDC(), maxCap, "Should be at max");
    }
    
    /// @notice Test: Precio negativo del oráculo debería fallar
    function test_NegativeOraclePriceReverts() public {
        ethUsdFeed.setPrice(-1000 * 10**8);
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.InvalidPrice.selector);
        bank.depositETH{value: 1 ether}();
    }
    
    /// @notice Test: Precio cero del oráculo debería fallar
    function test_ZeroOraclePriceReverts() public {
        ethUsdFeed.setPrice(0);
        
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.InvalidPrice.selector);
        bank.depositETH{value: 1 ether}();
    }
}

// Mock ERC20 Token for Coverage Tests
contract MockERC20_Coverage {
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
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// Mock Chainlink Price Feed for Coverage Tests
contract MockChainlinkFeed_Coverage {
    int256 private price;
    uint80 private roundId;
    
    constructor() {
        roundId = 1;
    }
    
    function setPrice(int256 _price) external {
        price = _price;
        roundId++;
    }
    
    function latestRoundData()
        external
        view
        returns (
            uint80 _roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (roundId, price, block.timestamp, block.timestamp, roundId);
    }
}

// Mock Uniswap Router for Coverage Tests
contract MockUniswapRouter_Coverage {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external pure returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn * 2; // Simple 2:1 ratio for testing
        return amounts;
    }
}

// Mock Uniswap Factory for Coverage Tests
contract MockUniswapFactory_Coverage {
    function getPair(address, address) external pure returns (address) {
        return address(1); // Return non-zero address
    }
}
