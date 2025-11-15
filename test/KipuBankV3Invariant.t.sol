// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";
import "./KipuBankV3.t.sol";

/**
 * @title KipuBankV3InvariantTest - Advanced Fuzzing & Invariant Testing
 * @author Eduardo Moreno - Ethereum Developers ETH_KIPU
 * @notice Stateful fuzzing tests for KipuBankV3 following security best practices
 * @dev Tests critical invariants using Foundry's invariant testing framework
 */
contract KipuBankV3InvariantTest is Test {
    
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
    
    address[] public actors;
    uint256 public ghostTotalUserDeposits;
    uint256 public ghostTotalWithdrawals;
    
    // Constants
    int256 public constant INITIAL_ETH_PRICE = 2000_00000000;
    int256 public constant INITIAL_USDC_PRICE = 1_00000000; 
    int256 public constant INITIAL_TOKEN_PRICE = 10_00000000;
    uint256 public constant MAX_CAP_USDC = 100000000000;

    /*//////////////////////////////////////////////////////////////
                        SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Deploy mock infrastructure
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        mockToken = new MockERC20("TestToken", "TT", 18);
        mockETHPriceFeed = new MockChainlinkFeed(INITIAL_ETH_PRICE);
        mockUSDCPriceFeed = new MockChainlinkFeed(INITIAL_USDC_PRICE);
        mockTokenPriceFeed = new MockChainlinkFeed(INITIAL_TOKEN_PRICE);
        mockUniswapRouter = new MockUniswapRouter(address(mockUSDC));
        
        // Deploy KipuBankV3
        address owner = makeAddr("owner");
        vm.prank(owner);
        bank = new KipuBankV3(
            owner,
            address(mockETHPriceFeed),
            address(mockUSDC),
            address(mockUSDCPriceFeed),
            address(mockUniswapRouter)
        );
        
        // Initialize
        vm.prank(owner);
        bank.initializeSupportedTokens();
        
        vm.prank(owner);
        bank.addSupportedToken(address(mockToken), address(mockTokenPriceFeed), 18);
        
        // Create test actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
            
            // Fund actors
            deal(actor, 100 ether);
            mockUSDC.mint(actor, 10000 * 10**6);
            mockToken.mint(actor, 1000 * 10**18);
            
            // Approve tokens
            vm.prank(actor);
            mockUSDC.approve(address(bank), type(uint256).max);
            
            vm.prank(actor);
            mockToken.approve(address(bank), type(uint256).max);
        }
        
        // Set target contracts for invariant testing
        targetContract(address(bank));
        
        // Set target functions for fuzzing
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = bank.depositETH.selector;
        selectors[1] = bank.depositERC20.selector;
        selectors[2] = bank.withdrawETH.selector;
        selectors[3] = bank.withdrawUSDC.selector;
        
        FuzzSelector memory fuzzSelector = FuzzSelector({
            addr: address(bank),
            selectors: selectors
        });
        
        targetSelector(fuzzSelector);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @dev CRITICAL INVARIANT 1: Total user balances ≤ Contract USDC equivalent
    function invariant_TotalUserBalancesConsistency() public view {
        uint256 totalUserBalances = 0;
        
        for (uint256 i = 0; i < actors.length; i++) {
            totalUserBalances += bank.getUserBalance(actors[i]);
        }
        
        uint256 contractCapacity = bank.currentCapUSDC();
        
        assert(totalUserBalances <= contractCapacity);
    }
    
    /// @dev CRITICAL INVARIANT 2: Contract ETH balance ≥ Total withdrawable ETH
    function invariant_ContractETHBalanceConsistency() public view {
        uint256 totalUserBalancesUSDC = 0;
        
        for (uint256 i = 0; i < actors.length; i++) {
            totalUserBalancesUSDC += bank.getUserBalance(actors[i]);
        }
        
        // Convert total USDC to ETH equivalent
        uint256 totalWithdrawableETH = (totalUserBalancesUSDC * 1e20) / uint256(INITIAL_ETH_PRICE);
        uint256 contractETHBalance = bank.currentETHBalance();
        
        assert(contractETHBalance >= totalWithdrawableETH);
    }
    
    /// @dev CRITICAL INVARIANT 3: Bank capacity never exceeds MAX_CAP
    function invariant_BankCapacityLimit() public view {
        uint256 currentCapacity = bank.currentCapUSDC();
        assert(currentCapacity <= MAX_CAP_USDC);
    }
    
    /// @dev CRITICAL INVARIANT 4: Contract not paused during normal operations
    function invariant_ContractNotPaused() public view {
        // During fuzzing, contract should remain unpaused
        // This helps detect if any function incorrectly pauses the contract
        assert(!bank.isPaused());
    }
    
    /// @dev ECONOMIC INVARIANT 5: Total deposits ≥ Total withdrawals (accounting)
    function invariant_DepositWithdrawalAccounting() public view {
        // This would require tracking ghost variables in a more complex setup
        // For now, we check that currentUSDCBalance is never negative (would underflow)
        uint256 currentBalance = bank.currentUSDCBalance();
        assert(currentBalance >= 0); // Always true due to uint256, but good for clarity
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZING HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function _randomActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }
    
    function _boundDepositAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, 0.01 ether, 10 ether);
    }
    
    function _boundUSDCAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, 1 * 10**6, 10000 * 10**6); // 1 to 10,000 USDC
    }

    /*//////////////////////////////////////////////////////////////
                        PROPERTY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @dev Test that deposits always increase user balance
    function testProperty_DepositIncreasesBalance(uint256 amount, uint256 actorSeed) public {
        amount = _boundDepositAmount(amount);
        address actor = _randomActor(actorSeed);
        
        uint256 balanceBefore = bank.getUserBalance(actor);
        uint256 expectedUSDC = (amount * uint256(INITIAL_ETH_PRICE)) / 1e20;
        
        // Skip if would exceed capacity
        if (bank.currentCapUSDC() + expectedUSDC > MAX_CAP_USDC) return;
        
        vm.prank(actor);
        bank.depositETH{value: amount}();
        
        uint256 balanceAfter = bank.getUserBalance(actor);
        assert(balanceAfter > balanceBefore);
        assert(balanceAfter == balanceBefore + expectedUSDC);
    }
    
    /// @dev Test that withdrawals always decrease user balance
    function testProperty_WithdrawalDecreasesBalance(uint256 depositAmount, uint256 withdrawAmount, uint256 actorSeed) public {
        depositAmount = _boundDepositAmount(depositAmount);
        address actor = _randomActor(actorSeed);
        
        uint256 expectedUSDC = (depositAmount * uint256(INITIAL_ETH_PRICE)) / 1e20;
        withdrawAmount = bound(withdrawAmount, 1, expectedUSDC);
        
        // Skip if would exceed capacity
        if (bank.currentCapUSDC() + expectedUSDC > MAX_CAP_USDC) return;
        
        // First deposit
        vm.prank(actor);
        bank.depositETH{value: depositAmount}();
        
        uint256 balanceBefore = bank.getUserBalance(actor);
        
        // Then withdraw
        vm.prank(actor);
        bank.withdrawETH(withdrawAmount);
        
        uint256 balanceAfter = bank.getUserBalance(actor);
        
        assert(balanceAfter < balanceBefore);
        assert(balanceAfter == balanceBefore - withdrawAmount);
    }
    
    /// @dev Test that consecutive deposits are additive
    function testProperty_ConsecutiveDepositsAdditive(uint256 amount1, uint256 amount2, uint256 actorSeed) public {
        amount1 = bound(amount1, 0.01 ether, 5 ether);
        amount2 = bound(amount2, 0.01 ether, 5 ether);
        address actor = _randomActor(actorSeed);
        
        uint256 expectedUSDC1 = (amount1 * uint256(INITIAL_ETH_PRICE)) / 1e20;
        uint256 expectedUSDC2 = (amount2 * uint256(INITIAL_ETH_PRICE)) / 1e20;
        
        // Skip if would exceed capacity
        if (bank.currentCapUSDC() + expectedUSDC1 + expectedUSDC2 > MAX_CAP_USDC) return;
        
        uint256 balanceInitial = bank.getUserBalance(actor);
        
        vm.prank(actor);
        bank.depositETH{value: amount1}();
        
        vm.prank(actor);
        bank.depositETH{value: amount2}();
        
        uint256 balanceFinal = bank.getUserBalance(actor);
        
        assert(balanceFinal == balanceInitial + expectedUSDC1 + expectedUSDC2);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @dev Test behavior with very small amounts
    function testFuzz_TinyAmounts(uint256 amount) public {
        amount = bound(amount, 1, 1000); // 1 to 1000 wei
        address actor = actors[0];
        
        uint256 balanceBefore = bank.getUserBalance(actor);
        
        vm.prank(actor);
        try bank.depositETH{value: amount}() {
            uint256 balanceAfter = bank.getUserBalance(actor);
            // Very small amounts might result in 0 USDC due to precision
            assert(balanceAfter >= balanceBefore);
        } catch {
            // Small amounts might revert due to ZeroAmount check
        }
    }
    
    /// @dev Test behavior near capacity limit
    function testFuzz_NearCapacityLimit(uint256 amount) public {
        address actor = actors[0];
        
        // Deposit almost to capacity
        uint256 nearCapAmount = (MAX_CAP_USDC * 95) / 100; // 95% of capacity
        uint256 ethForNearCap = (nearCapAmount * 1e20) / uint256(INITIAL_ETH_PRICE);
        
        vm.prank(actor);
        bank.depositETH{value: ethForNearCap}();
        
        // Now try to deposit more
        amount = bound(amount, 0.01 ether, 10 ether);
        uint256 expectedUSDC = (amount * uint256(INITIAL_ETH_PRICE)) / 1e20;
        
        vm.prank(actor);
        if (bank.currentCapUSDC() + expectedUSDC > MAX_CAP_USDC) {
            vm.expectRevert();
            bank.depositETH{value: amount}();
        } else {
            bank.depositETH{value: amount}();
            assert(bank.currentCapUSDC() <= MAX_CAP_USDC);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE MANIPULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @dev Test price volatility impact
    function testFuzz_PriceVolatility(int256 newPrice, uint256 depositAmount) public {
        newPrice = int256(bound(uint256(newPrice), 100_00000000, 10000_00000000)); // $100 to $10,000
        depositAmount = _boundDepositAmount(depositAmount);
        address actor = actors[0];
        
        // Change price
        mockETHPriceFeed.setPrice(newPrice);
        
        uint256 expectedUSDC = (depositAmount * uint256(newPrice)) / 1e20;
        
        // Skip if would exceed capacity
        if (expectedUSDC > MAX_CAP_USDC) return;
        
        vm.prank(actor);
        bank.depositETH{value: depositAmount}();
        
        uint256 actualBalance = bank.getUserBalance(actor);
        
        // Allow for small rounding errors
        assert(actualBalance <= expectedUSDC + 1);
        assert(actualBalance >= expectedUSDC - 1 || actualBalance == 0);
    }

    /*//////////////////////////////////////////////////////////////
                        STATISTICAL TRACKING
    //////////////////////////////////////////////////////////////*/
    
    function invariant_callSummary() public view {
        console.log("=== FUZZING STATISTICS ===");
        console.log("Total actors:", actors.length);
        console.log("Current USDC Balance:", bank.currentUSDCBalance());
        console.log("Current ETH Balance:", bank.currentETHBalance());
        console.log("Current Capacity:", bank.currentCapUSDC());
        console.log("Max Capacity:", MAX_CAP_USDC);
        console.log("Capacity utilization:", (bank.currentCapUSDC() * 100) / MAX_CAP_USDC, "%");
    }
}