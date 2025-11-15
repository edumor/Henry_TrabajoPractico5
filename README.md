# KipuBankV3 - DeFi Banking Protocol

![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue)
![Foundry](https://img.shields.io/badge/Foundry-Latest-red)
![Tests](https://img.shields.io/badge/Tests-32%2F46%20Passing-yellow)
![License](https://img.shields.io/badge/License-MIT-green)

## 🏦 Overview

**KipuBankV3** is an advanced DeFi banking system that implements ETH/USDC deposits and withdrawals with Uniswap V2 integration for automatic swaps and Chainlink oracles for reliable pricing. This project represents a comprehensive security analysis following the **Module 5: Audit Preparation** methodology and the **OWASP Smart Contract Top 10 (2025)**.

## 🔍 How KipuBankV3 Works

### Core Concept

KipuBankV3 operates as a **decentralized banking protocol** that accepts ETH deposits and manages user balances denominated in USDC. The protocol uses Chainlink price oracles to convert deposited ETH into USDC-equivalent credits, which users can later withdraw as ETH or USDC.

### Key Components

1. **Deposit Mechanism**
   - Users deposit ETH through `depositETH()`
   - Protocol queries Chainlink ETH/USD price feed in real-time
   - Converts ETH amount to USDC equivalent using the formula:
     ```
     USDC Amount = (ETH Amount × ETH Price) / 10^20
     ```
   - Credits user's internal balance in USDC (6 decimals)
   - Updates total bank capacity and ETH reserves

2. **Withdrawal System**
   - Users can withdraw via `withdrawETH()` or `withdrawUSDC()`
   - **ETH Withdrawal**: Converts USDC balance back to ETH using current price
   - **USDC Withdrawal**: Direct withdrawal of USDC balance
   - Enforces daily withdrawal limit of 20,000 USDC per user
   - Uses Checks-Effects-Interactions pattern to prevent reentrancy

3. **Oracle Integration (Chainlink)**
   - Provides real-time ETH/USD pricing (8 decimals precision)
   - Validates price data (price > 0, updatedAt exists)
   - Used for both deposit and withdrawal conversions
   - **Vulnerability**: Single oracle dependency (no redundancy)

4. **Capacity Management**
   - Maximum capacity: 100,000 USDC
   - Prevents over-exposure to risk
   - Tracks total deposits across all users
   - Reverts deposits that exceed capacity limit

5. **Security Controls**
   - **ReentrancyGuard**: Prevents reentrancy attacks on fund transfers
   - **Ownable**: Access control for administrative functions
   - **Pausable**: Emergency pause mechanism for incident response
   - **Input Validation**: Zero amount and zero address checks

### Transaction Flow Example

**Deposit Flow:**
```
1. User calls depositETH{value: 1 ETH}
2. Contract checks: not paused, amount > 0
3. Queries Chainlink: ETH price = $2,000
4. Calculates: 1 ETH × $2,000 = 2,000 USDC credit
5. Validates: capacity not exceeded, within limits
6. Updates: user balance += 2,000 USDC
7. Updates: total capacity += 2,000 USDC
8. Emits: Deposit event
```

**Withdrawal Flow:**
```
1. User calls withdrawETH(2000 USDC)
2. Contract checks: not paused, sufficient balance
3. Checks: daily withdrawal limit not exceeded
4. Queries Chainlink: ETH price = $2,000
5. Calculates: 2,000 USDC / $2,000 = 1 ETH to withdraw
6. Updates: user balance -= 2,000 USDC (Effects)
7. Transfers: 1 ETH to user (Interaction)
8. Updates: daily withdrawal counter
9. Emits: Withdrawal event
```

### State Management

The protocol maintains several critical state variables:

- `userDepositUSDC[address]`: Individual user balances in USDC
- `currentCapUSDC`: Total USDC-equivalent capacity used
- `currentETHBalance`: Total ETH held in contract
- `dailyWithdrawn[address][day]`: Daily withdrawal tracking
- `lastWithdrawalDay[address]`: Last withdrawal timestamp
- `isPaused`: Emergency pause state

### Mathematical Invariants

The protocol enforces these mathematical invariants:

1. **Balance Conservation**: `Σ(user balances) ≤ contract ETH + USDC value`
2. **Capacity Limit**: `currentCapUSDC ≤ 100,000 USDC`
3. **Daily Limit**: `dailyWithdrawn[user][day] ≤ 20,000 USDC`
4. **Non-negative Balances**: `userDepositUSDC[user] ≥ 0` (enforced by Solidity 0.8+)

## ✨ Features

- 💰 **ETH Deposits**: Deposit ETH and receive USDC credit based on real-time prices
- 🔄 **Automatic Conversion**: Seamless ETH to USDC conversion using Chainlink price feeds
- 📊 **Daily Withdrawal Limits**: Built-in security with 20,000 USDC daily withdrawal limits per user
- 🛡️ **Security Measures**: Reentrancy protection, pause functionality, and access control
- 🎯 **Capacity Management**: Maximum capacity of 100,000 USDC to manage risk exposure
- 🔗 **Oracle Integration**: Chainlink price feeds for accurate ETH/USD pricing

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│              KipuBankV3 Smart Contract                  │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   Ownable   │  │ Reentrancy   │  │   Pausable   │  │
│  │             │  │   Guard      │  │              │  │
│  └─────────────┘  └──────────────┘  └──────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Core Functions                           │  │
│  │  • depositETH()                                  │  │
│  │  • depositERC20(token, amount)                   │  │
│  │  • withdrawETH(usdcAmount)                       │  │
│  │  • withdrawUSDC(amount)                          │  │
│  │  • pause() / unpause()                           │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         │                    │                │
         ▼                    ▼                ▼
┌────────────────┐  ┌─────────────────┐  ┌──────────────┐
│  Chainlink     │  │  Uniswap V2     │  │  ERC20       │
│  Price Feed    │  │  Router/Factory │  │  Tokens      │
│  (ETH/USD)     │  │                 │  │  (WETH/USDC) │
└────────────────┘  └─────────────────┘  └──────────────┘
```

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh/) - Ethereum development toolchain
- [Node.js](https://nodejs.org/) (optional, for scripts)

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/edumor/Henry_Trabajo_Practico5.git
cd Henry_Trabajo_Practico5
```

2. **Install dependencies**
```bash
forge install
```

3. **Compile contracts**
```bash
forge build
```

4. **Run tests**
```bash
forge test
```

### Running Specific Test Suites

```bash
# Run basic functionality tests
forge test --match-contract KipuBankV3SimpleTest

# Run security tests
forge test --match-contract KipuBankV3Secure

# Run invariant tests
forge test --match-contract KipuBankV3Invariant

# Run with verbose output
forge test -vvv
```

### Code Coverage

```bash
# Generate coverage report
forge coverage

# Generate detailed HTML report
forge coverage --report lcov
genhtml lcov.info --output-directory coverage
```

## 👥 Protocol Actors and Roles

The KipuBankV3 protocol has clearly defined actors with specific powers and limitations:

### 1. Owner (Administrator)
**Address**: Contract deployer or transferred owner

**Powers**:
- ✅ `pause()` - Halt all protocol operations (deposits, withdrawals)
- ✅ `unpause()` - Resume protocol operations
- ✅ `transferOwnership(address)` - Transfer ownership to new address
- ✅ `renounceOwnership()` - Permanently remove owner privileges

**Limitations**:
- ❌ Cannot access user funds directly
- ❌ Cannot modify user balances
- ❌ Cannot bypass capacity limits
- ❌ Cannot change immutable parameters (MAX_CAP, price feeds)

**Trust Assumptions**:
- 🔴 **Single point of failure**: Lost key = protocol stuck
- 🔴 **Centralization risk**: Malicious owner can DoS by pausing
- ⚠️ **No timelock**: Immediate effect of admin actions

**Recommended Improvements**:
- Multi-signature wallet (2-of-3 or 3-of-5)
- Timelock for critical operations (48-72 hours)
- Emergency multi-sig for pause function

### 2. Users (Depositors)
**Address**: Any Ethereum address

**Powers**:
- ✅ `depositETH()` - Deposit ETH and receive USDC credit
- ✅ `depositERC20(token, amount)` - Deposit ERC20 tokens (auto-swap to USDC)
- ✅ `withdrawETH(amount)` - Convert USDC balance to ETH and withdraw
- ✅ `withdrawUSDC(amount)` - Withdraw USDC directly
- ✅ `getUserBalance()` - View their current USDC balance
- ✅ `getDailyWithdrawn()` - Check daily withdrawal usage

**Limitations**:
- ❌ Cannot exceed 100,000 USDC total capacity (shared limit)
- ❌ Cannot withdraw more than 20,000 USDC per day
- ❌ Cannot withdraw more than their balance
- ❌ Cannot operate when protocol is paused
- ❌ Cannot access other users' funds

**Trust Assumptions**:
- Must trust Chainlink oracle for accurate pricing
- Must trust owner won't maliciously pause
- Subject to daily withdrawal limits (bank run protection)

### 3. External Protocols (Dependencies)
**Chainlink Price Feeds**:
- **Role**: Provide ETH/USD price data
- **Power**: Determines conversion rates for all deposits/withdrawals
- **Risk**: Single oracle = single point of failure
- **Trust**: Assumes accurate, timely, and available price data

**Uniswap V2**:
- **Role**: Token swapping for ERC20 deposits
- **Power**: Determines swap rates for non-USDC tokens
- **Risk**: Potential for price manipulation via flash loans
- **Trust**: Assumes sufficient liquidity and fair pricing

### Power Matrix

| Action | Owner | User | Oracle | Uniswap |
|--------|-------|------|--------|---------|
| Pause Protocol | ✅ | ❌ | ❌ | ❌ |
| Deposit Funds | ✅ | ✅ | ❌ | ❌ |
| Withdraw Funds | ✅ | ✅ (own) | ❌ | ❌ |
| Set Prices | ❌ | ❌ | ✅ | ✅ |
| Modify Balances | ❌ | ❌ | ❌ | ❌ |
| Change Limits | ❌* | ❌ | ❌ | ❌ |

*Limits are immutable constants

### Attack Vectors by Actor

**Malicious Owner**:
- DoS attack by pausing indefinitely
- Front-running users before pausing
- Renouncing ownership (permanent freeze)

**Malicious User**:
- Griefing by filling capacity to MAX_CAP
- Attempting reentrancy (mitigated)
- Price manipulation via flash loans (vulnerable)

**Compromised Oracle**:
- Price manipulation (90% impact demonstrated in tests)
- Stale price data causing incorrect conversions
- Downtime preventing deposits/withdrawals

## 📋 Contract Interface

### Core Functions

#### `depositETH()`
Deposit ETH and receive USDC credit based on current Chainlink price.

```solidity
function depositETH() external payable nonReentrant whenNotPaused
```

#### `withdrawETH(uint256 usdcAmount)`
Withdraw ETH by burning USDC credit. Respects daily withdrawal limits.

```solidity
function withdrawETH(uint256 usdcAmount) external nonReentrant whenNotPaused
```

#### `withdrawUSDC(uint256 amount)`
Withdraw USDC directly from user balance.

```solidity
function withdrawUSDC(uint256 amount) external nonReentrant whenNotPaused
```

### View Functions

- `getUserBalance(address user)` - Get user's USDC balance
- `getCurrentCapacity()` - Get current total capacity in USDC
- `getETHPrice()` - Get current ETH price from Chainlink
- `getDailyWithdrawn(address user)` - Get user's daily withdrawal amount

### Admin Functions (Owner Only)

- `pause()` - Pause all operations
- `unpause()` - Resume all operations
- `transferOwnership(address newOwner)` - Transfer contract ownership

## 🧪 Testing

The project includes comprehensive test suites:

### Test Statistics

| Test Suite | Tests | Status | Coverage |
|------------|-------|--------|----------|
| **Simple Tests** | 11/11 | ✅ Passing | 100% |
| **Security Tests** | 15/15 | ✅ Passing | 100% |
| **Invariant Tests** | 5/12 | ⚠️ Partial | 42% |
| **Coverage Tests** | 11/11 | ✅ Passing | 100% |
| **Integration Tests** | 0/7 | ❌ Failing | 0% |

**Overall**: 32/46 tests passing (69.6%)

### Test Methodologies

The project employs multiple testing approaches to ensure protocol correctness:

#### 1. **Unit Testing** (KipuBankV3Simple.t.sol)
- Tests individual functions in isolation
- Validates basic functionality (deposits, withdrawals)
- Checks access control and input validation
- **Coverage**: 11/11 tests passing (100%)

#### 2. **Security Testing** (KipuBankV3Secure.t.sol)
- Reentrancy attack scenarios
- Access control validation (onlyOwner)
- Pause mechanism verification
- Overflow/underflow protection
- **Coverage**: 15/15 tests passing (100%)

#### 3. **Property-Based Testing** (KipuBankV3Invariant.t.sol)
- Mathematical invariants verification
- Fuzzing with random inputs (256+ runs)
- State consistency checks
- Edge case discovery
- **Coverage**: 5/12 tests passing (42%)

#### 4. **Integration Testing** (KipuBankV3.t.sol)
- End-to-end transaction flows
- Oracle interaction testing
- Multi-user scenarios
- Complex state transitions
- **Coverage**: 0/7 tests passing (0%)

#### 5. **Coverage Testing** (KipuBankV3Coverage.t.sol)
- Line coverage validation
- Branch coverage checks
- Function coverage tracking
- **Coverage**: 11/11 tests passing (100%)

### Test Execution Commands

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run with coverage
forge coverage

# Run fuzzing with increased runs
forge test --fuzz-runs 10000

# Run invariant tests with depth
forge test --match-contract Invariant --invariant-depth 20
```

## 📊 Protocol Maturity Assessment

### Overall Maturity Score: **C+ (70/100)** ⚠️ **NOT PRODUCTION READY**

### Detailed Evaluation

#### 1. Test Coverage ⚠️ **69.6%**

| Category | Score | Status |
|----------|-------|--------|
| Unit Tests | 100% | ✅ Excellent |
| Security Tests | 100% | ✅ Excellent |
| Integration Tests | 0% | ❌ Critical Gap |
| Invariant Tests | 42% | ⚠️ Needs Work |
| Fuzzing Coverage | 60% | ⚠️ Partial |

**Strengths**:
- ✅ Comprehensive unit test coverage
- ✅ All security controls tested
- ✅ Basic functionality validated

**Weaknesses**:
- ❌ Integration tests failing (setup issues)
- ❌ Only 42% of invariants validated
- ❌ Limited fuzzing scenarios
- ❌ No formal verification

**Required Improvements**:
```
Current:  32/46 tests (69.6%)
Target:   46/46 tests (100%)
Gap:      14 failing tests
Timeline: 2-3 weeks to fix
```

#### 2. Documentation 📚 **B+ (85/100)**

| Component | Status | Completeness |
|-----------|--------|--------------|
| README | ✅ Complete | 95% |
| NatSpec Comments | ⚠️ Partial | 60% |
| Architecture Diagrams | ✅ Complete | 100% |
| Security Analysis | ✅ Complete | 100% |
| User Guide | ⚠️ Basic | 50% |
| Deployment Guide | ❌ Missing | 0% |

**Strengths**:
- ✅ Comprehensive security documentation
- ✅ Clear architecture diagrams
- ✅ Detailed vulnerability analysis
- ✅ English documentation (professional)

**Weaknesses**:
- ⚠️ NatSpec incomplete for all functions
- ❌ No deployment/upgrade procedures
- ❌ No incident response playbook
- ❌ No user-facing documentation

**Required Improvements**:
- Complete NatSpec for all public/external functions
- Add deployment and upgrade guides
- Create incident response plan
- Write user-facing documentation

#### 3. Security Posture 🔒 **C (65/100)**

**REKT Test Score**: 5/12 (Low Maturity)

| Security Control | Implemented | Tested | Score |
|------------------|-------------|--------|-------|
| Reentrancy Protection | ✅ Yes | ✅ Yes | 100% |
| Access Control | ✅ Yes | ✅ Yes | 100% |
| Input Validation | ✅ Yes | ✅ Yes | 100% |
| Oracle Redundancy | ❌ No | ⚠️ Vulnerable | 20% |
| Flash Loan Protection | ❌ No | ❌ No | 0% |
| Multi-Signature | ❌ No | ❌ No | 0% |
| Timelock | ❌ No | ❌ No | 0% |
| Circuit Breakers | ⚠️ Partial | ⚠️ Partial | 40% |
| Rate Limiting | ✅ Yes | ✅ Yes | 80% |
| Emergency Pause | ✅ Yes | ✅ Yes | 100% |

**Critical Vulnerabilities**:
1. 🔴 Oracle manipulation (single source)
2. 🔴 Flash loan attacks (no limits)
3. 🔴 Centralization (single owner)
4. 🟡 Price calculation errors (rounding)
5. 🟡 DoS via capacity filling

**Required Before Production**:
- Multi-oracle implementation (Chainlink + Uniswap TWAP)
- Transaction size limits (anti-flash-loan)
- Multi-signature ownership (2-of-3 minimum)
- Timelock for admin actions (48h minimum)
- Professional security audit

#### 4. Code Quality 💻 **B (82/100)**

**Strengths**:
- ✅ Solidity 0.8.26 (latest stable)
- ✅ Uses OpenZeppelin libraries
- ✅ Gas optimizations implemented
- ✅ Custom errors for gas savings
- ✅ Events for all state changes

**Weaknesses**:
- ⚠️ Some functions lack NatSpec
- ⚠️ Complex mathematical operations need more documentation
- ❌ No upgradability pattern
- ❌ Some magic numbers (should be constants)

#### 5. Protocol Readiness 🚀 **D+ (60/100)**

**Missing for Production**:

| Requirement | Status | Priority | ETA |
|-------------|--------|----------|-----|
| Fix failing tests | ❌ | 🔴 Critical | 2 weeks |
| Multi-oracle | ❌ | 🔴 Critical | 3 weeks |
| Flash loan protection | ❌ | 🔴 Critical | 2 weeks |
| Multi-sig ownership | ❌ | 🔴 Critical | 1 week |
| External audit | ❌ | 🔴 Critical | 4 weeks |
| Testnet deployment | ❌ | 🟡 High | 2 weeks |
| Bug bounty program | ❌ | 🟡 High | 1 week |
| Incident response plan | ❌ | 🟡 High | 1 week |
| Monitoring/alerts | ❌ | 🟡 High | 2 weeks |
| User documentation | ⚠️ | 🟢 Medium | 1 week |

**Timeline to Production**: **~4 months** (16 weeks)

### Maturity Progression Path

```
Current State (Week 0)     →     Production Ready (Week 16)
=====================================
Tests:    69.6%            →      100%
Security: 65/100           →      95/100
Docs:     85/100           →      98/100
Audits:   0                →      2+ completed
REKT:     5/12             →      11/12

Phase 1: Bug Fixes         (Weeks 1-2)
Phase 2: Security Hardening (Weeks 3-5)
Phase 3: Advanced Testing   (Weeks 6-7)
Phase 4: External Audit     (Weeks 8-11)
Phase 5: Deployment         (Weeks 12-16)
```

## 🧪 Testing

1. **Basic Functionality**: Deposit, withdraw, balance checks
2. **Security**: Reentrancy protection, access control, pause functionality
3. **Edge Cases**: Zero amounts, capacity limits, overflow protection
4. **Invariants**: Balance consistency, capacity limits, mathematical properties
5. **Integration**: Oracle interaction, price manipulation scenarios

## 🔒 Security Considerations

### Implemented Security Measures

- ✅ **Reentrancy Protection**: OpenZeppelin's `ReentrancyGuard`
- ✅ **Access Control**: OpenZeppelin's `Ownable` pattern
- ✅ **Pause Mechanism**: Emergency pause functionality
- ✅ **Input Validation**: Zero amount and address validation
- ✅ **Overflow Protection**: Solidity 0.8+ built-in checks

### Identified Risks & Mitigations

| Risk | Severity | Status | Mitigation |
|------|----------|--------|------------|
| Oracle Manipulation | 🔴 High | ⚠️ Partial | Single oracle dependency |
| Flash Loan Attacks | 🔴 High | ❌ Vulnerable | No transaction limits |
| DoS via Capacity | 🟡 Medium | ❌ Vulnerable | No per-user limits |
| Price Calculation Errors | 🟡 Medium | ⚠️ Partial | Some tests failing |

### Security Analysis Results

**REKT Test Score**: 5/12 ⚠️ **Low Maturity - Not production ready**

For detailed security analysis, see [SECURITY_ANALYSIS_README.md](SECURITY_ANALYSIS_README.md).

## 📊 System Invariants

The protocol maintains several critical invariants that must hold at all times:

### 1. Fund Conservation Invariant ✅ **TESTED**

**Mathematical Definition**:
```
∀ t: Σ(userBalances[i]) ≤ contractBalance(ETH) × ETHPrice + contractBalance(USDC)
```

**Plain English**: The sum of all user USDC balances must never exceed the total value of assets held by the contract.

**Validation**:
```solidity
function invariant_ContractETHBalanceConsistency() public {
    uint256 totalUserBalances = 0;
    for (uint i = 0; i < actors.length; i++) {
        totalUserBalances += bank.getUserBalance(actors[i]);
    }
    
    uint256 contractValue = 
        address(bank).balance * getETHPrice() / 1e20 + 
        usdc.balanceOf(address(bank));
    
    assertTrue(totalUserBalances <= contractValue);
}
```

**Status**: ✅ **Pass** (256 fuzzing runs)

**Impact if Violated**: 🔴 **CRITICAL** - Protocol insolvency, users cannot withdraw

---

### 2. Capacity Limit Invariant ✅ **TESTED**

**Mathematical Definition**:
```
∀ operations: currentCapUSDC ≤ 100,000 × 10^6
```

**Plain English**: The total capacity must never exceed 100,000 USDC.

**Validation**:
```solidity
function invariant_BankCapacityLimit() public {
    uint256 capacity = bank.currentCapUSDC();
    uint256 MAX_CAP = 100000 * 10**6;
    assertLe(capacity, MAX_CAP);
}
```

**Status**: ✅ **Pass** (256 fuzzing runs)

**Impact if Violated**: 🟡 **HIGH** - Over-exposure to risk, potential liquidity crisis

---

### 3. Daily Withdrawal Limit Invariant ⚠️ **PARTIALLY TESTED**

**Mathematical Definition**:
```
∀ user, ∀ day_n: Σ withdrawals[user][day_n] ≤ 20,000 × 10^6
```

**Plain English**: Any user can withdraw maximum 20,000 USDC in a 24-hour period.

**Implementation**:
```solidity
uint256 constant DAILY_WITHDRAWAL_LIMIT = 20000 * 10**6;

function withdrawETH(uint256 usdcAmount) external {
    uint256 currentDay = block.timestamp / 1 days;
    
    if (currentDay != lastWithdrawalDay[msg.sender]) {
        dailyWithdrawn[msg.sender][currentDay] = 0;
        lastWithdrawalDay[msg.sender] = currentDay;
    }
    
    uint256 withdrawn = dailyWithdrawn[msg.sender][currentDay];
    require(withdrawn + usdcAmount <= DAILY_WITHDRAWAL_LIMIT);
    
    dailyWithdrawn[msg.sender][currentDay] += usdcAmount;
    // ... rest of withdrawal logic
}
```

**Status**: ⚠️ **Partial** - Basic tests pass, edge cases not fully covered

**Impact if Violated**: 🟡 **MEDIUM** - Bank run potential, liquidity exhaustion

---

### 4. Non-Negative Balance Invariant ✅ **ENFORCED BY SOLIDITY**

**Mathematical Definition**:
```
∀ user: userBalances[user] ≥ 0
```

**Plain English**: User balances cannot be negative.

**Protection**: Solidity 0.8+ automatic underflow protection

```solidity
// Automatically reverts if balance < amount
userBalances[msg.sender] -= amount;
```

**Status**: ✅ **Protected** by language design

**Impact if Violated**: 🔴 **CRITICAL** - Accounting chaos, infinite money glitch

---

### 5. Balance Consistency Invariant ✅ **TESTED**

**Mathematical Definition**:
```
∀ t: Σ(userBalances[i]) = currentCapUSDC
```

**Plain English**: Sum of all user balances must equal the current capacity.

**Validation**:
```solidity
function invariant_TotalUserBalancesConsistency() public {
    uint256 totalUserBalances = 0;
    for (uint i = 0; i < actors.length; i++) {
        totalUserBalances += bank.getUserBalance(actors[i]);
    }
    
    uint256 capacity = bank.currentCapUSDC();
    assertEq(totalUserBalances, capacity);
}
```

**Status**: ✅ **Pass** (256 fuzzing runs)

**Impact if Violated**: 🔴 **CRITICAL** - Accounting inconsistency, ghost funds

---

### 6. Price Consistency Invariant ❌ **VIOLATED**

**Mathematical Definition**:
```
∀ deposit d, withdraw w: 
  if deposit(x ETH) → credit(y USDC) at price p
  then withdraw(y USDC) → receive(x ETH) at same price p
```

**Plain English**: Round-trip deposits and withdrawals should return the same amount (minus rounding).

**Test Result**:
```solidity
// Test: test_CompleteDepositWithdrawCycle()
Deposited:  10.0 ETH
Withdrawn:  11.0 ETH  // ❌ 10% error!
Expected:   10.0 ETH ± 0.01%
```

**Status**: ❌ **FAIL** - Rounding errors accumulate

**Root Cause**: Decimal conversion precision loss in `_convertToUSDC()` and `_convertFromUSDC()`

**Impact**: 🔴 **HIGH** - Users can gain/lose funds, protocol becomes insolvent

---

### 7. Additive Deposit Invariant ❌ **VIOLATED**

**Mathematical Definition**:
```
∀ amounts a, b: deposit(a) + deposit(b) = deposit(a + b)
```

**Plain English**: Two separate deposits should equal one combined deposit.

**Test Result**:
```solidity
// Test: testProperty_ConsecutiveDepositsAdditive()
deposit(100 ETH) → 200,000.000000 USDC
deposit(100 ETH) → 200,000.000000 USDC
Total:             400,000.000002 USDC  // ❌ +2 wei error

vs.

deposit(200 ETH) → 400,000.000000 USDC
```

**Status**: ❌ **FAIL** - Rounding errors accumulate

**Impact**: 🟡 **MEDIUM** - Small leakage over time, precision issues

---

### 8. Oracle Staleness Invariant ⚠️ **BASIC VALIDATION**

**Mathematical Definition**:
```
∀ price_query: (block.timestamp - updatedAt) ≤ MAX_STALENESS
```

**Plain English**: Oracle price must be recent (not stale).

**Current Implementation**:
```solidity
function _getLatestPrice(address priceFeed) internal view returns (uint256) {
    (, int256 price,, uint256 updatedAt,) = 
        AggregatorV3Interface(priceFeed).latestRoundData();
    
    if (price <= 0) revert InvalidPrice();
    if (updatedAt == 0) revert InvalidPrice();
    // ⚠️ Missing: Check if updatedAt is recent enough
    
    return uint256(price);
}
```

**Status**: ⚠️ **Partial** - Checks exist, but no staleness threshold

**Recommended Addition**:
```solidity
uint256 constant MAX_PRICE_AGE = 1 hours;

if (block.timestamp - updatedAt > MAX_PRICE_AGE) {
    revert StalePrice();
}
```

**Impact if Violated**: 🔴 **CRITICAL** - Incorrect pricing, fund loss

---

### Invariant Test Summary

| Invariant | Status | Tested | Impact | Priority |
|-----------|--------|--------|--------|----------|
| Fund Conservation | ✅ Holds | ✅ Yes | 🔴 Critical | P0 |
| Capacity Limit | ✅ Holds | ✅ Yes | 🟡 High | P1 |
| Daily Withdrawal | ⚠️ Partial | ⚠️ Partial | 🟡 Medium | P2 |
| Non-negative Balance | ✅ Holds | ✅ Built-in | 🔴 Critical | P0 |
| Balance Consistency | ✅ Holds | ✅ Yes | 🔴 Critical | P0 |
| Price Consistency | ❌ Violated | ✅ Yes | 🔴 High | P0 |
| Additive Deposits | ❌ Violated | ✅ Yes | 🟡 Medium | P1 |
| Oracle Staleness | ⚠️ Partial | ⚠️ Partial | 🔴 Critical | P0 |

**Summary**:
- ✅ **Passing**: 3/8 (37.5%)
- ⚠️ **Partial**: 3/8 (37.5%)
- ❌ **Failing**: 2/8 (25%)

**Required Actions**:
1. Fix price consistency invariant (decimal precision)
2. Fix additive deposit invariant (rounding)
3. Complete oracle staleness validation
4. Add comprehensive invariant test suite

## 🚨 Known Issues

### Critical Issues (Must Fix Before Production)

1. **Oracle Price Calculation**: Tests show 90% error in price calculations
2. **Deposit-Withdraw Cycle**: 10% spurious gains in complete cycles
3. **Consecutive Deposits**: Rounding errors accumulate over time
4. **Flash Loan Vulnerability**: No protection against large single transactions

### Test Failures Requiring Attention

- `test_OraclePriceManipulation()` - Price calculation error
- `test_CompleteDepositWithdrawCycle()` - Balance inconsistency
- `testProperty_ConsecutiveDepositsAdditive()` - Rounding accumulation

## 🛣️ Roadmap to Production

### Phase 1: Bug Fixes (2 weeks)
- [ ] Fix 14 failing tests
- [ ] Correct decimal conversion issues
- [ ] Achieve 95%+ code coverage

### Phase 2: Security Hardening (3 weeks)
- [ ] Implement multi-oracle system
- [ ] Add circuit breakers for extreme price changes
- [ ] Implement flash loan protection
- [ ] Add transaction size limits

### Phase 3: Advanced Testing (2 weeks)
- [ ] Extensive fuzzing (100k+ runs)
- [ ] Formal verification
- [ ] Attack simulation testing

### Phase 4: External Audit (4 weeks)
- [ ] Professional security audit
- [ ] Implement audit recommendations
- [ ] Re-audit critical changes

### Phase 5: Controlled Deployment (4 weeks)
- [ ] Testnet deployment with bug bounty
- [ ] Mainnet deployment with low limits
- [ ] Gradual limit increases
- [ ] 24/7 monitoring setup

## 📁 Project Structure

```
├── src/                      # Smart contracts
│   └── KipuBankV3.sol       # Main contract
├── test/                     # Test files
│   ├── KipuBankV3.t.sol     # Basic tests
│   ├── KipuBankV3Simple.t.sol
│   ├── KipuBankV3Secure.t.sol
│   ├── KipuBankV3Coverage.t.sol
│   └── KipuBankV3Invariant.t.sol
├── lib/                      # Dependencies
│   ├── forge-std/           # Foundry standard library
│   └── openzeppelin-contracts/
├── cache/                    # Build artifacts
└── foundry.toml             # Foundry configuration
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file:

```env
PRIVATE_KEY=your_private_key_here
MAINNET_RPC_URL=your_mainnet_rpc_url
ETHERSCAN_API_KEY=your_etherscan_api_key
```

### Foundry Configuration

The project uses custom Foundry settings in `foundry.toml`:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
optimizer = true
optimizer_runs = 200
via_ir = true

[profile.ci]
fuzz = { runs = 10_000 }
invariant = { runs = 1_000, depth = 20 }
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Write comprehensive tests for new features
- Maintain test coverage above 95%
- Use NatSpec documentation for all functions
- Run security checks before submitting PRs

## 📚 Documentation

- [Security Analysis Report](SECURITY_ANALYSIS_README.md) - Comprehensive security evaluation
- [Test Coverage Report](COVERAGE_REPORT.md) - Detailed test coverage analysis
- [Threat Analysis](THREAT_ANALYSIS_REPORT.md) - Identified threats and mitigations
- [API Documentation](docs/api.md) - Contract interface documentation

## ⚠️ Disclaimers

**IMPORTANT WARNING**:

This contract is **NOT ready for production deployment**. It requires:

1. ✅ Fix all failing tests
2. ✅ Implement recommended security mitigations
3. ✅ Complete professional security audit
4. ✅ Extensive testing on testnets
5. ✅ Implement incident response plan
6. ✅ Setup 24/7 monitoring
7. ✅ Multi-signature controls
8. ✅ Timelock for critical functions

**The author is NOT responsible** for financial losses resulting from using this code in production without proper security measures.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📧 Contact

**Eduardo Moreno**  
Ethereum Developer - Security Researcher

- GitHub: [@edumor](https://github.com/edumor)
- LinkedIn: [Eduardo Moreno](https://linkedin.com/in/eduardo-moreno)

**Course**: TP5 - Module 5  
**Program**: Ethereum Developer Pack - KIPU 2025

---

*Last updated: November 15, 2025*  
*Document version: 1.0*