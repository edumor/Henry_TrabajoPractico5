# KipuBankV3 - DeFi Banking Protocol

![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue)
![Foundry](https://img.shields.io/badge/Foundry-Latest-red)
![Tests](https://img.shields.io/badge/Tests-32%2F46%20Passing-yellow)
![License](https://img.shields.io/badge/License-MIT-green)

## 🏦 Overview

**KipuBankV3** is an advanced DeFi banking system that implements ETH/USDC deposits and withdrawals with Uniswap V2 integration for automatic swaps and Chainlink oracles for reliable pricing. This project represents a comprehensive security analysis following the **Module 5: Audit Preparation** methodology and the **OWASP Smart Contract Top 10 (2025)**.

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

### Key Test Categories

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

The protocol maintains several critical invariants:

1. **Fund Conservation**: Total user balances ≤ contract balance
2. **Capacity Limit**: Current capacity ≤ 100,000 USDC
3. **Daily Withdrawal Limit**: User daily withdrawals ≤ 20,000 USDC
4. **Non-negative Balances**: All user balances ≥ 0
5. **Balance Consistency**: Sum of user balances = current capacity

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
- LinkedIn: [Eduardo Moreno](linkedin.com/in/eduardomoreno-15813b19b)

**Course**: TP5 - Module 5  
**Program**: Ethereum Developer Pack - KIPU 2025

---

*Last updated: November 15, 2025*  
*Document version: 1.0*
