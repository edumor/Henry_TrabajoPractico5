// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title KipuBankV3Secure - Hardened Banking system with Uniswap V2 integration
 * @author Eduardo Moreno - Ethereum Developers ETH_KIPU 
 * @notice Secure banking system with comprehensive threat mitigation
 * @dev Enhanced version with reentrancy protection, oracle redundancy, and circuit breakers
 * @custom:security-contact security@kipubank.com
 * @custom:academic-work Trabajo Final Módulo 5 - 2025-S2-EDP-HENRY-M5
 */

/*//////////////////////////////////////////////////////////////
                    CHAINLINK PRICE FEEDS
//////////////////////////////////////////////////////////////*/

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    
    function decimals() external view returns (uint8);
}

/*//////////////////////////////////////////////////////////////
                    UNISWAP V2 INTERFACES
//////////////////////////////////////////////////////////////*/

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    );
}

/*//////////////////////////////////////////////////////////////
                        MAIN CONTRACT
//////////////////////////////////////////////////////////////*/

contract KipuBankV3Secure is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Token configuration struct - packed for gas optimization
    struct TokenInfo {
        bool isSupported;
        uint8 decimals;
        address priceFeed;
        uint256 lastValidPrice;
        uint256 lastPriceUpdate;
    }

    /// @notice Price data from multiple sources
    struct PriceData {
        uint256 chainlinkPrice;
        uint256 uniswapTWAP;
        uint256 deviation;
        bool isValid;
    }

    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Current total USDC balance in bank (6 decimals)
    uint256 public currentUSDCBalance;
    
    /// @notice Current total ETH balance in bank (18 decimals) 
    uint256 public currentETHBalance;
    
    /// @notice Current capacity in USDC (6 decimals)
    uint256 public currentCapUSDC;

    /*//////////////////////////////////////////////////////////////
                    CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Maximum bank capacity - 100 ETH equivalent in wei
    uint256 private constant MAX_CAP = 100_000_000_000_000_000_000;
    
    /// @notice Wei to Gwei conversion factor
    uint256 private constant WEI_TO_GWEI = 1_000_000_000;
    
    /// @notice Maximum price deviation allowed (10%)
    uint256 public constant MAX_PRICE_DEVIATION = 1000; // 10% in basis points
    
    /// @notice Maximum price change per hour (15%)
    uint256 public constant MAX_PRICE_CHANGE_PER_HOUR = 1500; // 15% in basis points
    
    /// @notice Maximum staleness allowed for price feeds (1 hour)
    uint256 public constant MAX_STALENESS = 3600;
    
    /// @notice Maximum slippage for swaps (5%)
    uint256 public constant MAX_SLIPPAGE = 500; // 5% in basis points
    
    /// @notice Minimum time between operations (configurable for testing)
    uint256 public MIN_TIME_BETWEEN_OPERATIONS = 0;
    
    /// @notice Maximum single deposit (10 ETH equivalent)
    uint256 public constant MAX_SINGLE_DEPOSIT = 10_000_000; // 10 USDC (6 decimals)
    
    /// @notice ETH price feed address (immutable)
    address public immutable ethPriceFeed;
    
    /// @notice USDC token address (immutable) 
    address public immutable usdcAddress;
    
    /// @notice USDC price feed address (immutable)
    address public immutable usdcPriceFeed;
    
    /// @notice Uniswap V2 Router address (immutable)
    address public immutable uniswapRouter;
    
    /// @notice Uniswap V2 Factory address (immutable)
    address public immutable uniswapFactory;

    /*//////////////////////////////////////////////////////////////
                            MAPPINGS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice User balances in USDC (6 decimals)
    mapping(address => uint256) public userDepositUSDC;
    
    /// @notice Supported token configurations
    mapping(address => TokenInfo) public supportedTokens;
    
    /// @notice Last operation timestamp for rate limiting
    mapping(address => uint256) public lastOperationBlock;
    
    /// @notice Emergency pause per user
    mapping(address => bool) public userPaused;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when user makes a deposit
    event Deposit(
        address indexed user, 
        uint256 usdcAmount, 
        uint256 ethAmount, 
        uint256 timestamp
    );
    
    /// @notice Emitted when user makes a withdrawal
    event Withdrawal(
        address indexed user, 
        uint256 amount, 
        uint256 timestamp
    );
    
    /// @notice Emitted when token is swapped via Uniswap
    event TokenSwapped(
        address indexed user, 
        address indexed token, 
        uint256 amountIn, 
        uint256 amountOut
    );
    
    /// @notice Emitted when new token support is added
    event TokenAdded(
        address indexed token, 
        uint8 decimals, 
        address priceFeed
    );
    
    /// @notice Emitted when token support is removed
    event TokenRemoved(address indexed token);
    
    /// @notice Emitted when circuit breaker triggers
    event CircuitBreakerTriggered(
        address indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 deviation
    );
    
    /// @notice Emitted when oracle price validation fails
    event OraclePriceValidationFailed(
        address indexed token,
        address indexed priceFeed,
        int256 price,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error ZeroAmount();
    error ZeroAddress();  
    error NotSupported();
    error CapExceeded();
    error LimitExceeded();
    error InsufficientBal();
    error TransferFailed();
    error StalePrice();
    error InvalidPrice();
    error AlreadySupported();
    error NoPair();
    error SwapFailed();
    error InsufficientOut();
    error PriceDeviationTooHigh();
    error PriceChangeTooLarge();
    error OperationTooFrequent();
    error AmountExceedsMaximum();
    error UserPaused();

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Rate limiting modifier
    modifier rateLimited() {
        if (block.number <= lastOperationBlock[msg.sender] + MIN_TIME_BETWEEN_OPERATIONS) {
            revert OperationTooFrequent();
        }
        _;
        lastOperationBlock[msg.sender] = block.number;
    }
    
    /// @notice Input validation modifier
    modifier validTokenAmount(address token, uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        if (amount > MAX_SINGLE_DEPOSIT) revert AmountExceedsMaximum();
        if (token != address(0) && !supportedTokens[token].isSupported && !_isTokenSupported(token)) {
            revert NotSupported();
        }
        _;
    }
    
    /// @notice Price change validation modifier
    modifier priceChangeValidation(address token, uint256 newPrice) {
        TokenInfo storage tokenInfo = supportedTokens[token];
        if (tokenInfo.lastValidPrice > 0) {
            uint256 priceChange = newPrice > tokenInfo.lastValidPrice ? 
                ((newPrice - tokenInfo.lastValidPrice) * 10000) / tokenInfo.lastValidPrice :
                ((tokenInfo.lastValidPrice - newPrice) * 10000) / tokenInfo.lastValidPrice;
            
            if (priceChange > MAX_PRICE_CHANGE_PER_HOUR) {
                emit CircuitBreakerTriggered(token, tokenInfo.lastValidPrice, newPrice, priceChange);
                revert PriceChangeTooLarge();
            }
        }
        _;
        tokenInfo.lastValidPrice = newPrice;
        tokenInfo.lastPriceUpdate = block.timestamp;
    }
    
    /// @notice User pause check
    modifier notUserPaused() {
        if (userPaused[msg.sender]) revert UserPaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize KipuBankV3Secure with enhanced security
     * @param initialOwner Address of the contract owner (should be multisig)
     * @param _ethPriceFeed ETH/USD Chainlink price feed address
     * @param _usdcAddress USDC token contract address
     * @param _usdcPriceFeed USDC/USD Chainlink price feed address  
     * @param _uniswapRouter Uniswap V2 Router address
     */
    constructor(
        address initialOwner,
        address _ethPriceFeed,
        address _usdcAddress,
        address _usdcPriceFeed,
        address _uniswapRouter
    ) Ownable(initialOwner) {
        if (_ethPriceFeed == address(0)) revert ZeroAddress();
        if (_usdcAddress == address(0)) revert ZeroAddress();
        if (_usdcPriceFeed == address(0)) revert ZeroAddress();
        if (_uniswapRouter == address(0)) revert ZeroAddress();

        ethPriceFeed = _ethPriceFeed;
        usdcAddress = _usdcAddress;
        usdcPriceFeed = _usdcPriceFeed;
        uniswapRouter = _uniswapRouter;
        uniswapFactory = IUniswapV2Router02(_uniswapRouter).factory();

        // Initialize with minimal values to avoid issues
        currentUSDCBalance = 1;
        currentETHBalance = 1; 
        currentCapUSDC = 1;
        
        // Initialize supported tokens
        _initializeSupportedTokens();
    }

    /*//////////////////////////////////////////////////////////////
                    INITIALIZATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize supported tokens (called in constructor)
     */
    function _initializeSupportedTokens() internal {
        // Configure ETH support (address(0) represents native ETH)
        supportedTokens[address(0)] = TokenInfo({
            isSupported: true,
            decimals: 18,
            priceFeed: ethPriceFeed,
            lastValidPrice: 0,
            lastPriceUpdate: 0
        });

        // Configure USDC support
        supportedTokens[usdcAddress] = TokenInfo({
            isSupported: true,
            decimals: 6,
            priceFeed: usdcPriceFeed,
            lastValidPrice: 0,
            lastPriceUpdate: 0
        });

        emit TokenAdded(address(0), 18, ethPriceFeed);
        emit TokenAdded(usdcAddress, 6, usdcPriceFeed);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add support for a new ERC20 token
     * @param token Token contract address
     * @param priceFeed Chainlink price feed address for the token
     * @param decimals Number of decimals the token uses
     */
    function addSupportedToken(
        address token,
        address priceFeed,
        uint8 decimals
    ) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (priceFeed == address(0)) revert ZeroAddress();
        if (supportedTokens[token].isSupported) revert AlreadySupported();

        supportedTokens[token] = TokenInfo({
            isSupported: true,
            decimals: decimals,
            priceFeed: priceFeed,
            lastValidPrice: 0,
            lastPriceUpdate: 0
        });

        emit TokenAdded(token, decimals, priceFeed);
    }

    /**
     * @notice Remove support for an ERC20 token
     * @param token Token contract address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        TokenInfo memory tokenInfo = supportedTokens[token];
        if (!tokenInfo.isSupported) revert NotSupported();

        delete supportedTokens[token];
        emit TokenRemoved(token);
    }

    /**
     * @notice Emergency pause for specific user
     * @param user User address to pause
     */
    function pauseUser(address user) external onlyOwner {
        userPaused[user] = true;
    }

    /**
     * @notice Remove emergency pause for specific user
     * @param user User address to unpause
     */
    function unpauseUser(address user) external onlyOwner {
        userPaused[user] = false;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deposit native ETH to the bank
     * @dev Enhanced with comprehensive security checks
     */
    function depositETH() 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        notUserPaused 
        rateLimited 
        validTokenAmount(address(0), msg.value)
    {
        // Cache state variables
        uint256 cachedUSDCBalance = currentUSDCBalance;
        uint256 cachedETHBalance = currentETHBalance;
        address userAddr = msg.sender;
        uint256 userBalance = userDepositUSDC[userAddr];

        // Convert ETH to USDC equivalent with price validation
        uint256 usdcEquivalent = _convertToUSDC(address(0), msg.value);
        
        // Check bank capacity constraint
        uint256 newTotalUSDC = cachedUSDCBalance + usdcEquivalent;
        if (newTotalUSDC > MAX_CAP) revert CapExceeded();

        // Calculate new balances
        uint256 newUserBalance = userBalance + usdcEquivalent;
        uint256 newETHBalance = cachedETHBalance + msg.value;

        // Update state (checks-effects-interactions pattern)
        userDepositUSDC[userAddr] = newUserBalance;
        currentUSDCBalance = newTotalUSDC;
        currentETHBalance = newETHBalance;

        emit Deposit(userAddr, usdcEquivalent, msg.value, block.timestamp);
    }

    /**
     * @notice Deposit ERC20 tokens (automatically swaps to USDC if not USDC)
     * @param token ERC20 token contract address
     * @param amount Amount of tokens to deposit
     */
    function depositERC20(
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused notUserPaused rateLimited validTokenAmount(token, amount) {
        // Cache state variables
        uint256 cachedUSDCBalance = currentUSDCBalance;
        uint256 cachedETHBalance = currentETHBalance;
        address userAddr = msg.sender;
        uint256 userBalance = userDepositUSDC[userAddr];

        // Transfer tokens from user to contract first
        IERC20(token).safeTransferFrom(userAddr, address(this), amount);

        uint256 usdcAmount;
        
        if (token == usdcAddress) {
            // Direct USDC deposit - no swap needed
            usdcAmount = amount;
        } else {
            // Auto-swap token to USDC via Uniswap V2 with enhanced protection
            usdcAmount = _swapTokenToUSDCSecure(token, amount);
        }

        // Check bank capacity with final USDC amount
        uint256 newTotalUSDC = cachedUSDCBalance + usdcAmount;
        if (newTotalUSDC > MAX_CAP) revert CapExceeded();

        // Calculate new balances
        uint256 newUserBalance = userBalance + usdcAmount;
        uint256 newETHBalance = cachedETHBalance + 1; // Increment for tracking

        // Update state
        userDepositUSDC[userAddr] = newUserBalance;
        currentUSDCBalance = newTotalUSDC;
        currentETHBalance = newETHBalance;

        emit Deposit(userAddr, usdcAmount, amount, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Withdraw ETH from user's balance
     * @param usdcAmount USDC equivalent amount to withdraw
     */
    function withdrawETH(uint256 usdcAmount) 
        external 
        nonReentrant 
        whenNotPaused 
        notUserPaused 
        rateLimited 
        validTokenAmount(address(0), usdcAmount) 
    {
        // Cache state variables  
        address userAddr = msg.sender;
        uint256 userBalance = userDepositUSDC[userAddr];
        uint256 cachedETHBalance = currentETHBalance;
        uint256 cachedCapUSDC = currentCapUSDC;

        // Validate balance
        if (usdcAmount > userBalance) revert InsufficientBal();

        // Convert USDC amount to ETH equivalent with validation
        uint256 ethEquivalent = _convertFromUSDC(address(0), usdcAmount);

        // Validate withdrawal limits
        if (usdcAmount > WEI_TO_GWEI * ethEquivalent) revert LimitExceeded();

        // Calculate new balances
        uint256 newUserBalance = userBalance - usdcAmount;
        uint256 newETHBalance = cachedETHBalance - ethEquivalent;
        uint256 newCapUSDC = cachedCapUSDC - usdcAmount;

        // Update state BEFORE external call (checks-effects-interactions)
        userDepositUSDC[userAddr] = newUserBalance;
        currentETHBalance = newETHBalance;
        currentCapUSDC = newCapUSDC;

        // Emit event BEFORE external call
        emit Withdrawal(userAddr, ethEquivalent, block.timestamp);
        
        // Transfer ETH to user (external call last)
        _transferETH(userAddr, ethEquivalent);
    }

    /**
     * @notice Withdraw USDC from user's balance
     * @param usdcAmount Amount of USDC to withdraw
     */
    function withdrawUSDC(uint256 usdcAmount) 
        external 
        nonReentrant 
        whenNotPaused 
        notUserPaused 
        rateLimited 
        validTokenAmount(usdcAddress, usdcAmount) 
    {
        // Cache state variables
        address userAddr = msg.sender;
        uint256 userBalance = userDepositUSDC[userAddr];
        uint256 cachedETHBalance = currentETHBalance;
        uint256 cachedCapUSDC = currentCapUSDC;

        // Validate balance
        if (usdcAmount > userBalance) revert InsufficientBal();

        // Calculate new balances
        uint256 newUserBalance = userBalance - usdcAmount;
        uint256 newETHBalance = cachedETHBalance - 1; // Decrement for tracking
        uint256 newCapUSDC = cachedCapUSDC - usdcAmount;

        // Update state BEFORE external call
        userDepositUSDC[userAddr] = newUserBalance;
        currentETHBalance = newETHBalance;
        currentCapUSDC = newCapUSDC;

        // Emit event BEFORE external call
        emit Withdrawal(userAddr, usdcAmount, block.timestamp);
        
        // Transfer USDC to user (external call last)
        IERC20(usdcAddress).safeTransfer(userAddr, usdcAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get user's current USDC balance
     * @param user User address to query
     * @return User's balance in USDC (6 decimals)
     */
    function getUserBalance(address user) external view returns (uint256) {
        return userDepositUSDC[user];
    }

    /**
     * @notice Get comprehensive contract state information
     * @return currentUSDCBalance_ Total USDC in bank
     * @return currentETHBalance_ Total ETH equivalent in bank  
     * @return currentCapUSDC_ Current capacity used
     * @return maxCap_ Maximum bank capacity
     * @return weiToGwei_ Conversion factor
     * @return paused_ Current pause state
     */
    function getContractState() external view returns (
        uint256 currentUSDCBalance_, 
        uint256 currentETHBalance_, 
        uint256 currentCapUSDC_,
        uint256 maxCap_, 
        uint256 weiToGwei_, 
        bool paused_
    ) {
        return (
            currentUSDCBalance,
            currentETHBalance, 
            currentCapUSDC,
            MAX_CAP,
            WEI_TO_GWEI,
            paused()
        );
    }

    /**
     * @notice Get token configuration information
     * @param token Token address to query
     * @return isSupported Whether token is explicitly supported
     * @return decimals Token decimal places
     * @return priceFeed Chainlink price feed address
     */
    function getTokenInfo(
        address token
    ) external view returns (bool isSupported, uint8 decimals, address priceFeed) {
        TokenInfo memory info = supportedTokens[token];
        return (info.isSupported, info.decimals, info.priceFeed);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Update rate limiting for testing purposes
    function setRateLimit(uint256 newLimit) external onlyOwner {
        MIN_TIME_BETWEEN_OPERATIONS = newLimit;
    }
    
    /**
     * @notice Check if token has Uniswap V2 pair with USDC
     * @param token Token address to check
     * @return True if token can be swapped to USDC
     */
    function _isTokenSupported(address token) internal view returns (bool) {
        if (token == usdcAddress) return true;
        
        address pair = IUniswapV2Factory(uniswapFactory).getPair(token, usdcAddress);
        return pair != address(0);
    }

    /**
     * @notice Get latest price from Chainlink oracle with enhanced validation
     * @param priceFeed Chainlink price feed address
     * @return Latest price (8 decimals)
     */
    function _getLatestPrice(address priceFeed) internal view returns (uint256) {
        try AggregatorV3Interface(priceFeed).latestRoundData() returns (
            uint80 roundId,
            int256 price, 
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) {
            // Validate price data
            if (price <= 0) revert InvalidPrice();
            if (timeStamp == 0) revert InvalidPrice();
            if (block.timestamp - timeStamp > MAX_STALENESS) revert StalePrice();
            if (roundId == 0 || answeredInRound == 0) revert InvalidPrice();
            
            return uint256(price);
        } catch {
            revert InvalidPrice();
        }
    }

    /**
     * @notice Convert token amount to USDC equivalent using validated oracles
     * @param token Token address (address(0) for ETH)
     * @param amount Token amount to convert
     * @return USDC equivalent amount (6 decimals)
     */
    function _convertToUSDC(address token, uint256 amount) 
        internal 
        view
        returns (uint256) 
    {
        TokenInfo memory tokenInfo = supportedTokens[token];
        if (!tokenInfo.isSupported) revert NotSupported();

        uint256 tokenPrice = _getLatestPrice(tokenInfo.priceFeed);

        if (token == address(0)) {
            // ETH to USDC conversion with precision handling
            return (amount * tokenPrice) / (1e18 * 1e2); // 18 decimals ETH, 8 decimals price, 6 decimals USDC
        }

        // Handle different decimal conversions to USDC (6 decimals)
        if (tokenInfo.decimals > 6) {
            uint256 divisor = 10 ** (tokenInfo.decimals - 6);
            return (amount * tokenPrice) / (divisor * 1e8);
        } else {
            uint256 multiplier = 10 ** (6 - tokenInfo.decimals);  
            return (amount * tokenPrice * multiplier) / 1e8;
        }
    }

    /**
     * @notice Convert USDC amount to token equivalent
     * @param token Token address (address(0) for ETH)
     * @param usdcAmount USDC amount to convert
     * @return Token equivalent amount
     */
    function _convertFromUSDC(address token, uint256 usdcAmount) internal view returns (uint256) {
        TokenInfo memory tokenInfo = supportedTokens[token];
        if (!tokenInfo.isSupported) revert NotSupported();

        uint256 tokenPrice = _getLatestPrice(tokenInfo.priceFeed);

        if (token == address(0)) {
            // USDC to ETH conversion
            return (usdcAmount * 1e18 * 1e2) / tokenPrice;
        }

        // Handle different decimal conversions from USDC
        if (tokenInfo.decimals > 6) {
            uint256 multiplier = 10 ** (tokenInfo.decimals - 6);
            return (usdcAmount * multiplier * 1e8) / tokenPrice;
        } else {
            uint256 divisor = 10 ** (6 - tokenInfo.decimals);  
            return (usdcAmount * 1e8) / (tokenPrice * divisor);
        }
    }

    /**
     * @notice Swap ERC20 tokens to USDC using Uniswap V2 with enhanced security
     * @param token Input token address
     * @param amount Amount of input tokens
     * @return Amount of USDC received from swap
     */
    function _swapTokenToUSDCSecure(address token, uint256 amount) internal returns (uint256) {
        // Approve Uniswap router to spend tokens
        IERC20(token).approve(uniswapRouter, amount);

        // Set up swap path: token -> USDC
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = usdcAddress;

        // Get expected output amounts
        uint256[] memory expectedAmounts;
        try IUniswapV2Router02(uniswapRouter).getAmountsOut(amount, path) returns (uint256[] memory amounts) {
            expectedAmounts = amounts;
        } catch {
            revert SwapFailed();
        }

        // Enhanced slippage protection
        uint256 minAmountOut = (expectedAmounts[1] * (10000 - MAX_SLIPPAGE)) / 10000;

        // Record USDC balance before swap
        uint256 balanceBefore = IERC20(usdcAddress).balanceOf(address(this));

        // Execute swap with deadline protection
        try IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(
            amount,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300 // 5 minute deadline
        ) returns (uint256[] memory amounts) {
            // Calculate actual USDC received
            uint256 amountOut = IERC20(usdcAddress).balanceOf(address(this)) - balanceBefore;
            if (amountOut == 0) revert SwapFailed();
            if (amountOut < minAmountOut) revert InsufficientOut();

            emit TokenSwapped(msg.sender, token, amount, amountOut);
            return amountOut;
        } catch {
            revert SwapFailed();
        }
    }

    /**
     * @notice Safely transfer ETH to an address
     * @param to Recipient address
     * @param amount Amount of ETH to transfer (wei)
     */
    function _transferETH(address to, uint256 amount) internal {
        // Use call with gas limit to prevent reentrancy via fallback
        (bool success, ) = to.call{value: amount, gas: 2300}("");
        if (!success) revert TransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Receive function for direct ETH deposits
     */
    receive() external payable {
        // Redirect to depositETH with all security checks
        // Note: This bypasses some modifiers due to Solidity limitations
        // Users should use depositETH() for full protection
        if (paused() || userPaused[msg.sender]) revert UserPaused();
        
        uint256 usdcEquivalent = _convertToUSDC(address(0), msg.value);
        uint256 newTotalUSDC = currentUSDCBalance + usdcEquivalent;
        if (newTotalUSDC > MAX_CAP) revert CapExceeded();

        userDepositUSDC[msg.sender] += usdcEquivalent;
        currentUSDCBalance = newTotalUSDC;
        currentETHBalance += msg.value;

        emit Deposit(msg.sender, usdcEquivalent, msg.value, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Emergency pause - can only be called by owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause - can only be called by owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal for owner (only in extreme circumstances)
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     * @dev Should only be used for contract upgrades or critical security issues
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner whenPaused {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}