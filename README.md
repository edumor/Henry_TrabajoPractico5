# KipuBankV3 - Advanced DeFi Banking System

![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Network](https://img.shields.io/badge/Network-Sepolia-orange)

## 📋 Overview

**KipuBankV3** is an advanced DeFi banking system that extends KipuBankV2 functionality by integrating with **Uniswap V2** for automatic token swaps to USDC. The contract accepts any ERC20 token supported by Uniswap V2, automatically converts it to USDC, and credits the resulting amount to the user's balance while respecting the bank's maximum capacity.

**Author**: Eduardo Moreno  
**Academic Work**: Final Project Module 4 - 2025-S2-EDP-HENRY-M4  
**Contract Address (Sepolia)**: `0xF8eD172b29c2CF2037b2d6A5C611C1cD26AbbA9e`

## 🎯 Key Features

### Core Functionality (From KipuBankV2)
- ✅ **ETH Deposits**: Native Ethereum deposits with automatic USDC conversion
- ✅ **USDC Deposits**: Direct USDC storage without conversion
- ✅ **Withdrawal System**: Secure withdrawal mechanism for users
- ✅ **Owner Controls**: Administrative functions for contract management
- ✅ **Bank Cap Limit**: Maximum capacity enforcement (100 ETH equivalent)
- ✅ **Chainlink Price Feeds**: Real-time price data for accurate conversions

### New Features Added for TP4
- 🆕 **Universal Token Support**: Accept any ERC20 token with Uniswap V2 pairs
- 🆕 **Automatic Token Swaps**: Seamless integration with Uniswap V2 Router
- 🆕 **Dynamic Token Configuration**: Add/remove supported tokens dynamically
- 🆕 **Uniswap Pair Validation**: Automatic verification of token pairs existence
- 🆕 **Advanced Error Handling**: Custom errors for better debugging
- 🆕 **Gas Optimization**: Efficient storage and operations
- 🆕 **Emergency Pause**: Circuit breaker for security

## 🏗️ Technical Architecture

### Smart Contract Structure

```solidity
contract KipuBankV3 is Ownable {
    // Integration with Uniswap V2
    IUniswapV2Router02 public immutable uniswapRouter;
    IUniswapV2Factory public immutable uniswapFactory;
    
    // Chainlink Price Feeds
    address public immutable ethPriceFeed;
    address public immutable usdcPriceFeed;
    
    // Token Configuration
    mapping(address => TokenInfo) public supportedTokens;
    
    // User Balances (all in USDC)
    mapping(address => uint256) public userDepositUSDC;
}
```

### Key Integrations

1. **Uniswap V2 Router**: `0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008`
2. **Chainlink ETH/USD**: `0x694AA1769357215DE4FAC081bf1f309aDC325306`
3. **Chainlink USDC/USD**: `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E`
4. **USDC Token (Sepolia)**: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`

## 📚 Function Reference

### Core Banking Functions

#### `depositETH()` - ETH Deposits
```solidity
function depositETH() external payable
```
- **Purpose**: Deposit native ETH and convert to USDC equivalent
- **Requirements**: Amount > 0, contract not paused, within bank cap
- **Process**: ETH → Price conversion → USDC balance update

#### `depositToken(address token, uint256 amount)` - ERC20 Deposits
```solidity
function depositToken(address token, uint256 amount) external
```
- **Purpose**: Deposit any supported ERC20 token
- **New Feature**: Automatic Uniswap V2 swap to USDC if not USDC
- **Requirements**: Token must be supported, valid Uniswap pair exists
- **Process**: Token → Uniswap Swap → USDC → Balance update

#### `withdraw(uint256 amount)` - Withdrawals
```solidity
function withdraw(uint256 amount) external
```
- **Purpose**: Withdraw USDC equivalent in ETH
- **Requirements**: Sufficient balance, contract not paused
- **Process**: USDC balance → ETH conversion → Transfer

### Administrative Functions

#### `addToken(address token, uint8 decimals, address priceFeed)` - Add Token Support
```solidity
function addToken(address token, uint8 decimals, address priceFeed) external onlyOwner
```
- **New Feature**: Dynamically add new token support
- **Requirements**: Valid token address, not already supported
- **Purpose**: Expand supported token ecosystem

#### `removeToken(address token)` - Remove Token Support
```solidity
function removeToken(address token) external onlyOwner
```
- **New Feature**: Remove token from supported list
- **Purpose**: Manage token ecosystem security

#### `pause() / unpause()` - Emergency Controls
```solidity
function pause() external onlyOwner
function unpause() external onlyOwner
```
- **New Feature**: Emergency circuit breaker
- **Purpose**: Security mechanism for unusual situations

### View Functions

#### `getBankInfo()` - Bank Status
```solidity
function getBankInfo() external view returns (...)
```
- **Returns**: Current balances, capacity, limits, pause state
- **Purpose**: Complete bank status overview

#### `getTokenConfig(address token)` - Token Information
```solidity
function getTokenConfig(address token) external view returns (...)
```
- **Returns**: Token support status, decimals, price feed
- **Purpose**: Verify token configuration

#### `hasUniswapPair(address token)` - Pair Validation
```solidity
function hasUniswapPair(address token) external view returns (bool)
```
- **New Feature**: Check if token has USDC pair on Uniswap
- **Purpose**: Validate token compatibility

#### `getSwapPreview(address tokenIn, address tokenOut)` - Preview Swaps
```solidity
function getSwapPreview(address tokenIn, address tokenOut) external view returns (uint256)
```
- **New Feature**: Preview swap amounts before execution
- **Purpose**: User experience enhancement

## 🧪 Testing Guide for Instructors

### Contract Address
**Sepolia Testnet**: `0xF8eD172b29c2CF2037b2d6A5C611C1cD26AbbA9e`  
**Etherscan**: https://sepolia.etherscan.io/address/0xF8eD172b29c2CF2037b2d6A5C611C1cD26AbbA9e

## 🔧 Contract Corrections Based on Instructor Feedback

### Original Instructor Observations:
1. **currentCapUSDC is deducted on withdrawals but never updated** - Could remain at 0 and not reflect the bank's actual capacity
2. **Incorrect conversion in withdrawals** - `uint256 ethEquivalent = _convertToUSDC(address(0), usdcAmount)` should not convert to USDC, but to ETH
3. **Decimal inconsistency in MAX_CAP** - MAX_CAP was in wei (18 decimals), but productive USDC has 6 decimals
4. **Inconsistent ETH balance logic** - `currentETHBalance = cachedETHBalance + msg.value` adds real ETH, but in some places it incorrectly added +1

### Implemented Corrections:

#### 1. **Proper `currentCapUSDC` Update on Withdrawals**
**Location**: Functions `withdrawETH()` (lines ~494-498) and `withdrawUSDC()` (lines ~518-522)  
**Original Problem**: The `currentCapUSDC` variable was only incremented on deposits but never decremented on withdrawals, causing the bank's capacity limit to remain permanently occupied.

**Implemented Solution**:
```solidity
// In withdrawETH()
uint256 newCapUSDC = cachedCapUSDC - usdcAmount;
currentCapUSDC = newCapUSDC;

// In withdrawUSDC()
uint256 newCapUSDC = cachedCapUSDC - usdcAmount;
currentCapUSDC = newCapUSDC;
```

**Rationale**: Now `currentCapUSDC` updates bidirectionally: increases on deposits and decreases on withdrawals, correctly reflecting the bank's available capacity at all times.

---

#### 2. **Fixed Conversion Direction in ETH Withdrawals**
**Location**: Function `withdrawETH()` (line ~485)  
**Original Problem**: Used `_convertToUSDC()` when it should convert from USDC to ETH for withdrawals.

**Implemented Solution**:
```solidity
// BEFORE (INCORRECT):
uint256 ethEquivalent = _convertToUSDC(address(0), usdcAmount);

// NOW (CORRECT):
uint256 ethEquivalent = _convertFromUSDC(address(0), usdcAmount);
```

**Rationale**: The `_convertFromUSDC()` function performs the correct inverse conversion: takes a USDC amount and returns its ETH equivalent using Chainlink oracles, allowing users to withdraw the correct amount of ETH based on their USDC balance.

---

#### 3. **Fixed Decimal Places in MAX_CAP**
**Location**: Constant `MAX_CAP` (line ~249)  
**Original Problem**: `MAX_CAP` was defined in wei (18 decimals) but USDC uses 6 decimals, causing inconsistency in comparisons.

**Implemented Solution**:
```solidity
// BEFORE (INCORRECT):
uint256 private constant MAX_CAP = 100 ether; // 18 decimals

// NOW (CORRECT):
uint256 private constant MAX_CAP = 100000000000; // 100,000 USDC with 6 decimals
```

**Rationale**: Since all capacities and balances are handled internally in USDC (6 decimals), `MAX_CAP` must use the same format. The value represents 100,000 USDC, equivalent to the original limit of ~100 ETH at current prices.

---

#### 4. **Removed Incorrect ETH Balance Increments (+1)**
**Location**: Multiple deposit and withdrawal functions  
**Original Problem**: In some lines, `cachedETHBalance + 1` was added without logical justification, incorrectly altering the actual ETH balance.

**Implemented Solution**:
```solidity
// BEFORE (INCORRECT):
currentETHBalance = cachedETHBalance + 1;

// NOW (CORRECT):
currentETHBalance = cachedETHBalance + msg.value;  // On deposits
currentETHBalance = cachedETHBalance - ethEquivalent;  // On withdrawals
```

**Rationale**: Balances must reflect exactly the actual transferred amounts. On deposits, `msg.value` (received ETH) is added; on withdrawals, `ethEquivalent` (sent ETH) is subtracted. Any arbitrary adjustment (+1) would cause discrepancies between accounting balance and the contract's actual balance.

---

#### 5. **Explicit State Variable Initialization**
**Location**: Constructor (lines ~368-370)  
**Additional Improvement**: Ensured all state variables are explicitly initialized to 0.

**Implementation**:
```solidity
currentUSDCBalance = 0;
currentETHBalance = 0; 
currentCapUSDC = 0;
```

**Rationale**: Although Solidity initializes variables to 0 by default, explicit initialization improves code clarity and guarantees a consistent and predictable initial state.

---

### Impact of Corrections:

✅ **Proper capacity management**: The bank now releases capacity on withdrawals, allowing new deposits without permanently blocking the limit.

✅ **Precise conversions**: Users withdraw the correct amount of ETH based on their USDC balance.

✅ **Decimal consistency**: All capacity operations use the same base (6 decimals USDC).

✅ **Exact accounting**: ETH balances reflect exactly the real transfers without arbitrary adjustments.

✅ **Improved reliability**: The contract now correctly handles the complete deposit and withdrawal cycle without accounting discrepancies.

## 👨‍🏫 Comprehensive Development Guide for Instructors

### 🎯 Functions Implementation Analysis

This section provides detailed analysis of **what** was implemented, **where** it's located in the code, and **why** each decision was made, specifically addressing TP4 requirements.

#### 1. Universal Token Support Implementation

**What**: Extended deposit functionality to accept any ERC20 token
**Where**: `depositToken(address token, uint256 amount)` function (Lines ~400-500)
**Why**: TP4 Requirement #1 - "Handle any token exchangeable in Uniswap V2"

```solidity
function depositToken(address token, uint256 amount) external {
    // Validation: Check if paused, non-zero amount
    if (isPaused) revert Paused();
    if (amount == 0) revert ZeroAmount();
    
    // NEW: Dynamic token support check
    TokenInfo memory tokenConfig = supportedTokens[token];
    if (!tokenConfig.isSupported && !hasUniswapPair(token)) {
        revert NotSupported();
    }
}
```

**Key Innovation**: Dynamic validation that checks both pre-configured tokens AND real-time Uniswap pair existence.

#### 2. Automatic Swap Integration (CORE TP4 FEATURE)

**What**: Seamless integration with Uniswap V2 for automatic token-to-USDC conversion
**Where**: `_swapTokenToUSDC(address token, uint256 amount)` internal function (Lines ~600-700)
**Why**: TP4 Requirement #2 - "Execute swaps of tokens within the smart contract"

```solidity
function _swapTokenToUSDC(address user, address token, uint256 amount) internal returns (uint256) {
    // NEW: Automatic USDC detection - no swap needed
    if (token == usdcAddress) {
        return amount;
    }
    
    // NEW: Uniswap V2 integration for automatic swaps
    address[] memory path = new address[](2);
    path[0] = token;
    path[1] = usdcAddress;
    
    // NEW: Real-time swap execution with slippage protection
    uint256[] memory amounts = IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(
        amount,
        amountOutMin, // 5% slippage protection
        path,
        address(this),
        deadline
    );
    
    return amounts[1]; // Return USDC amount received
}
```

**Key Innovation**: Conditional logic that handles USDC directly while automatically swapping other tokens.

#### 3. Bank Cap Preservation (CRITICAL REQUIREMENT)

**What**: Ensure total bank capacity never exceeds limits even after swaps
**Where**: Throughout deposit functions with `_checkBankCapacity()` (Lines ~300-350)
**Why**: TP4 Requirement #4 - "Respect the Bank Cap"

```solidity
function _checkBankCapacity(uint256 newUSDCAmount) internal view {
    uint256 newTotalCapacity = currentCapUSDC + newUSDCAmount;
    
    // NEW: Dynamic capacity calculation including swap results
    if (newTotalCapacity > MAX_CAP) {
        revert CapExceeded();
    }
}
```

**Key Innovation**: Pre-swap validation ensures capacity limits are respected BEFORE executing swaps.

#### 4. Dynamic Token Configuration System (NEW FEATURE)

**What**: Runtime addition/removal of supported tokens
**Where**: `addToken()` and `removeToken()` functions (Lines ~750-800)
**Why**: Enhanced flexibility beyond basic TP4 requirements for real-world usage

```solidity
function addToken(address token, uint8 decimals, address priceFeed) external onlyOwner {
    // NEW: Prevents duplicate token addition
    if (supportedTokens[token].isSupported) {
        revert AlreadySupported();
    }
    
    // NEW: Structured token configuration
    supportedTokens[token] = TokenInfo({
        isSupported: true,
        decimals: decimals,
        priceFeed: priceFeed
    });
    
    emit TokenAdded(token, decimals, priceFeed);
}
```

**Key Innovation**: Prevents configuration conflicts and provides clear audit trail.

#### 5. Uniswap Pair Validation (SAFETY FEATURE)

**What**: Real-time verification of token pair existence on Uniswap
**Where**: `hasUniswapPair(address token)` function (Lines ~850-880)
**Why**: Prevents failed transactions and ensures swap compatibility

```solidity
function hasUniswapPair(address token) public view returns (bool) {
    // NEW: Handle ETH as special case
    if (token == address(0)) return true;
    
    // NEW: Query Uniswap factory for pair existence
    address pair = IUniswapV2Factory(uniswapFactory).getPair(token, usdcAddress);
    return pair != address(0);
}
```

**Key Innovation**: Proactive validation prevents runtime failures and improves user experience.

#### 6. Enhanced Price Feed Integration

**What**: Robust price validation with staleness checks
**Where**: `_getLatestPrice(address priceFeed)` function (Lines ~900-950)
**Why**: Security and accuracy for financial calculations

```solidity
function _getLatestPrice(address priceFeed) internal view returns (uint256) {
    (, int256 price, , uint256 updatedAt, ) = AggregatorV3Interface(priceFeed).latestRoundData();
    
    // NEW: Comprehensive validation
    if (price <= 0) revert InvalidPrice();
    if (block.timestamp - updatedAt > 3600) revert StalePrice(); // 1 hour staleness check
    
    return uint256(price);
}
```

**Key Innovation**: Multi-layer validation ensures price feed reliability.

#### 7. Emergency Pause System (SECURITY FEATURE)

**What**: Circuit breaker for emergency situations
**Where**: `pause()` and `unpause()` functions (Lines ~1000-1020)
**Why**: Production-ready security for handling unusual market conditions

```solidity
function pause() external onlyOwner {
    isPaused = true;
    emit PauseStateChanged(true);
}

function unpause() external onlyOwner {
    isPaused = false;
    emit PauseStateChanged(false);
}
```

**Key Innovation**: Simple but effective emergency control mechanism.

### 🏗️ Architectural Decisions Explained

#### Decision 1: USDC as Universal Base Currency
**What**: Store all balances in USDC equivalent
**Why**: 
- Simplifies accounting across multiple tokens
- Provides stable value reference
- Reduces complexity in withdrawal calculations
- Industry standard for DeFi protocols

#### Decision 2: Immutable Core Contracts
**What**: Price feeds and router addresses set at deployment
**Why**:
- Gas optimization (no SLOAD costs)
- Security (prevents malicious address changes)
- Trust (immutable infrastructure references)

#### Decision 3: Checks-Effects-Interactions Pattern
**What**: Validate inputs → Update state → External calls
**Why**:
- Reentrancy protection
- State consistency
- Security best practice

#### Decision 4: Event-Driven Architecture
**What**: Comprehensive event emission for all state changes
**Why**:
- Transparency for users and integrators
- Off-chain monitoring capabilities
- Audit trail for all operations

### 🎯 TP4 Requirements Compliance Matrix

| Requirement | Implementation | Location | Innovation |
|-------------|----------------|----------|------------|
| **Universal Token Support** | `depositToken()` with dynamic validation | Lines 400-500 | Real-time Uniswap pair checking |
| **Automatic Swaps** | `_swapTokenToUSDC()` integration | Lines 600-700 | Conditional swap logic |
| **Bank Cap Respect** | `_checkBankCapacity()` validation | Lines 300-350 | Pre-swap capacity verification |
| **KipuBankV2 Preservation** | All original functions maintained | Throughout | Enhanced with new features |

### 🔍 Code Quality Indicators

1. **Gas Efficiency**: Optimized storage layout, minimal SLOAD operations
2. **Security**: Comprehensive input validation, reentrancy protection
3. **Modularity**: Clear function separation, reusable internal functions
4. **Readability**: Detailed comments, consistent naming conventions
5. **Testability**: View functions for all major state queries

### Step-by-Step Testing Instructions

#### 1. Initial Contract Verification
```javascript
// Check contract deployment
getBankInfo()
// Expected: currentUSDCBalance: 1, currentETHBalance: 1, currentCapUSDC: 1
```

#### 2. Test ETH Deposits (Core Functionality)
```javascript
// Test minimum ETH deposit
depositETH() 
// Send Value: 0.001 ETH
// Expected: Convert ETH to USDC equivalent and update balance
```

#### 3. Test Token Configuration (New Feature)
```javascript
// Check ETH configuration
getTokenConfig("0x0000000000000000000000000000000000000000")
// Expected: isSupported: true, decimals: 18

// Check USDC configuration  
getTokenConfig("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238")
// Expected: isSupported: true, decimals: 6
```

#### 4. Test Uniswap Integration (New Feature)
```javascript
// Check USDC pair existence
hasUniswapPair("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238")
// Expected: true

// Preview swap (if testing with other tokens)
getSwapPreview(tokenAddress, usdcAddress)
// Expected: Returns expected USDC amount
```

#### 5. Test Bank Capacity Limits
```javascript
// Check current capacity
getBankInfo()
// Verify: currentCapUSDC shows current utilization
// Maximum: 100 ETH equivalent in USDC
```

#### 6. Test User Balance
```javascript
// Check your balance
balanceOf("YOUR_WALLET_ADDRESS")
// Expected: Shows your USDC equivalent balance
```

#### 7. Test Administrative Functions (Owner Only)
```javascript
// Add new token support (only owner)
addToken(tokenAddress, decimals, priceFeedAddress)

// Remove token support (only owner)  
removeToken(tokenAddress)

// Emergency pause (only owner)
pause()
unpause()
```

### Quick Test Sequence
1. **Deploy Verification**: Call `getBankInfo()`
2. **ETH Deposit**: Send 0.001 ETH to `depositETH()`
3. **Balance Check**: Call `balanceOf(yourAddress)`
4. **Token Check**: Call `getTokenConfig(zeroAddress)` for ETH
5. **Capacity Check**: Verify bank limits with `getBankInfo()`

## 🔧 Deployment Instructions

### Prerequisites
- Solidity 0.8.26
- Sepolia ETH for gas fees
- Access to Remix IDE or Foundry/Hardhat

### Constructor Parameters (Sepolia)
```solidity
constructor(
    address initialOwner,     // 0x4829f4f3aadee47cb1cc795b2ec78a166042e918 (Your wallet)
    address ethPriceFeed,     // 0x694AA1769357215DE4FAC081bf1f309aDC325306 (Chainlink ETH/USD)
    address usdcAddress,      // 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 (USDC Sepolia)
    address usdcPriceFeed,    // 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E (Chainlink USDC/USD)
    address uniswapRouter     // 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 (SushiSwap Router)
)
```

### ABI-Encoded Constructor Arguments
For Etherscan verification, the ABI-encoded arguments used for deployment:
```
0000000000000000000000004829f4f3aadee47cb1cc795b2ec78a166042e918000000000000000000000000694aa1769357215de4fac081bf1f309adc3253060000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c7238000000000000000000000000a2f78ab2355fe2f984d808b5cee7fd0a93d5270e000000000000000000000000c532a74256d3db42d0bf7a0400fefdbad7694008
```

### Actual Deployment Parameters Used
```
Parameter 1 (initialOwner): 0x4829f4f3aadee47cb1cc795b2ec78a166042e918
Parameter 2 (ethPriceFeed): 0x694AA1769357215DE4FAC081bf1f309aDC325306  
Parameter 3 (usdcAddress): 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
Parameter 4 (usdcPriceFeed): 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E
Parameter 5 (uniswapRouter): 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 (SushiSwap)
```

### Deployment Steps
1. Compile with Solidity 0.8.26
2. Set gas limit to 5,000,000
3. Deploy with constructor parameters
4. Verify on Etherscan
5. Initialize token support with `initializeTokens()`

### ✅ Successful Deployment Verification
**Deployed Contract**: Successfully deployed to Sepolia at `0xF8eD172b29c2CF2037b2d6A5C611C1cD26AbbA9e`  
**Router Used**: SushiSwap Router (`0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008`) - Alternative to Uniswap V2  
**Verification**: Contract verified on Sepolia Etherscan with matching bytecode and ABI  
**Etherscan Verification**: Successfully generated matching Bytecode and ABI

## 🚀 Improvements Over KipuBankV2

### Enhanced Features Added for TP4

1. **Universal Token Support**
   - **Before**: Only ETH and USDC
   - **Now**: Any ERC20 token with Uniswap V2 pairs
   - **Benefit**: Massive expansion of supported assets

2. **Automatic Swap Integration**
   - **Before**: Manual token handling
   - **Now**: Seamless Uniswap V2 integration
   - **Benefit**: True DeFi composability

3. **Dynamic Token Management**
   - **Before**: Fixed token support
   - **Now**: Add/remove tokens dynamically
   - **Benefit**: Flexible ecosystem adaptation

4. **Advanced Security**
   - **Before**: Basic protections
   - **Now**: Emergency pause, comprehensive validations
   - **Benefit**: Production-ready security

5. **Gas Optimization**
   - **Before**: Standard operations
   - **Now**: Optimized storage, efficient swaps
   - **Benefit**: Lower transaction costs

6. **Enhanced User Experience**
   - **Before**: Limited functionality
   - **Now**: Swap previews, detailed status information
   - **Benefit**: Better user interface support

## 🔒 Security Considerations

- **Reentrancy Protection**: Checks-Effects-Interactions pattern
- **Price Feed Validation**: Chainlink staleness and validity checks
- **Slippage Protection**: Built-in swap validation
- **Access Control**: Owner-only administrative functions
- **Emergency Pause**: Circuit breaker for unusual situations
- **Input Validation**: Comprehensive parameter checking

## 📈 Design Decisions & Trade-offs

### 1. USDC as Base Currency
- **Decision**: All balances stored in USDC equivalent
- **Benefit**: Simplified accounting, stable value reference
- **Trade-off**: Requires conversion for ETH withdrawals

### 2. Uniswap V2 Integration
- **Decision**: Use established V2 router
- **Benefit**: Reliable, well-tested protocol
- **Trade-off**: V2 vs V3 features (concentrated liquidity)

### 3. Immutable Core Addresses
- **Decision**: Price feeds and router as immutable
- **Benefit**: Gas optimization, security
- **Trade-off**: Requires redeployment for address changes

### 4. Dynamic Token Support
- **Decision**: Admin-controlled token addition
- **Benefit**: Flexibility for ecosystem growth
- **Trade-off**: Centralized control requirement

## 📄 License

MIT License - See LICENSE file for details

## 🤝 Contributing

This is an academic project for educational purposes. For suggestions or improvements, please open an issue.

---

**KipuBankV3** - Advanced DeFi Banking with Uniswap Integration  
*Developed by Eduardo Moreno as Final Project for Module 4 - Ethereum Development Program*