# 🔒 Time-Locked Wallet

A Clarity smart contract that allows users to create time-locked wallets where funds are locked until a specified future block height. Perfect for learning about block height mechanics and conditional logic in Clarity! ⏰

## 🌟 Features

- 🏦 **Create Multiple Wallets**: Users can create multiple time-locked wallets
- 💰 **Deposit Funds**: Add STX tokens to your locked wallets
- ⏳ **Time-Based Unlocking**: Funds unlock automatically at specified block heights
- 🔓 **Flexible Withdrawals**: Withdraw partial or full amounts once unlocked
- 📈 **Extend Lock Period**: Extend the lock time for additional security
- 🗑️ **Cleanup**: Delete empty wallets to keep things tidy

## 🤝 Multi-Signature Co-Ownership System

Transforms time-locked wallets into collaborative financial instruments with multi-signature approval workflows, enabling shared ownership and governance for business accounts, family savings, and joint ventures.

### ✨ Core Capabilities
- **Shared Ownership**: Multiple co-owners can manage wallet operations together
- **Configurable Thresholds**: Set custom approval requirements (1-20 co-owners)
- **Proposal System**: Any co-owner can propose withdrawal operations
- **Approval Workflow**: Transparent voting mechanism with execution gates

### 🔧 Multisig Operations
1. **Wallet Creation**: `create-multisig-wallet` with approval threshold
2. **Owner Management**: `add-co-owner`/`remove-co-owner` for access control
3. **Operation Proposals**: `propose-withdrawal` initiates approval process
4. **Approval Collection**: `approve-operation` gathers required signatures
5. **Execution**: `execute-multisig-withdrawal` completes approved operations

### 🛡️ Security Framework
- **Threshold Validation**: Prevents unsafe approval configurations
- **Double-Vote Prevention**: Approval tracking blocks duplicate signatures
- **Activity Integration**: Multisig operations update wallet activity
- **Permission Controls**: Owner-only management with co-owner operation rights

### 🎯 Enterprise Applications
- **Business Accounts**: Shared treasury management with corporate governance
- **Family Savings**: Joint financial planning with spousal approval requirements
- **Investment Groups**: Collective fund management with member consensus
- **Partnership Funds**: Multi-party approval for business expenditures

### 📊 Technical Features
- **Backwards Compatible**: Existing single-owner wallets remain unchanged
- **Scalable Design**: Supports up to 20 co-owners per wallet
- **Operation Tracking**: Comprehensive approval and execution logging
- **Read-Only Functions**: Complete visibility into multisig status and approvals

## 🚀 Quick Start

### Creating a Wallet

```clarity
(contract-call? .time-locked-wallet create-wallet u1000)
```

Creates a new wallet that unlocks at block height 1000. Returns the wallet ID.

### Depositing Funds

```clarity
(contract-call? .time-locked-wallet deposit u1 u1000000)
```

Deposits 1 STX (1,000,000 microSTX) into wallet ID 1.

### Withdrawing Funds

```clarity
(contract-call? .time-locked-wallet withdraw u1 u500000)
```

Withdraws 0.5 STX from wallet ID 1 (only works if unlocked).

### Withdraw All Funds

```clarity
(contract-call? .time-locked-wallet withdraw-all u1)
```

Withdraws all funds from wallet ID 1.

## 📖 Core Functions

### Public Functions

| Function | Description |
|----------|-------------|
| `create-wallet` | 🆕 Create a new time-locked wallet |
| `deposit` | 💳 Add STX to a wallet |
| `withdraw` | 💸 Remove specific amount from unlocked wallet |
| `withdraw-all` | 🏧 Remove all funds from unlocked wallet |
| `extend-lock` | ⏰ Extend the unlock time |
| `delete-empty-wallet` | 🗑️ Remove empty wallets |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-wallet` | 📋 Get complete wallet information |
| `get-wallet-balance` | 💰 Check wallet balance |
| `is-wallet-unlocked` | 🔓 Check if wallet is unlocked |
| `get-blocks-until-unlock` | ⏳ Blocks remaining until unlock |
| `get-current-block-height` | 📊 Current blockchain height |

## 🎯 Use Cases

- 💎 **Savings Goals**: Lock funds until a future date
- 🎁 **Gift Wallets**: Create wallets that unlock on special occasions
- 💼 **Business Escrow**: Time-based fund releases
- 🏦 **Personal Banking**: Prevent impulsive spending
- 📚 **Learning Tool**: Understand block height mechanics

## ⚠️ Error Codes

| Code | Description |
|------|-------------|
| `u100` | Owner only operation |
| `u101` | Wallet not found |
| `u102` | Wallet still locked |
| `u103` | Wallet already exists |
| `u104` | Insufficient balance |
| `u105` | Invalid unlock height |
| `u106` | Unauthorized access |

## 🔧 Development

### Prerequisites

- Clarinet CLI installed
- Basic understanding of Clarity language

### Testing

```bash
clarinet test
```

### Deployment

```bash
clarinet deploy
```

## 📝 Example Workflow

1. **Create Wallet** 🆕
   ```clarity
   (contract-call? .time-locked-wallet create-wallet u2000)
   ;; Returns: (ok u1)
   ```

2. **Deposit Funds** 💰
   ```clarity
   (contract-call? .time-locked-wallet deposit u1 u5000000)
   ;; Deposits 5 STX
   ```

3. **Check Status** 📊
   ```clarity
   (contract-call? .time-locked-wallet is-wallet-unlocked u1)
   ;; Returns: false (if still locked)
   ```

4. **Wait for Unlock** ⏳
   ```clarity
   (contract-call? .time-locked-wallet get-blocks-until-unlock u1)
   ;; Returns: remaining blocks
   ```

5. **Withdraw** 💸
   ```clarity
   (contract-call? .time-locked-wallet withdraw-all u1)
   ;; Withdraws all funds once unlocked
   ```

## 🤝 Contributing

Feel free to submit issues and enhancement requests! This is a learning project perfect for Clarity beginners.

## 📄 License

MIT License - feel free to use this code for learning and building! 🎉
```

**Git Commit Message:**
```
feat: implement time-locked wallet MVP with deposit/withdraw functionality
```

**GitHub Pull Request Title:**
```
🔒 Add Time-Locked Wallet Smart Contract MVP
```

**GitHub Pull Request Description:**
```
## 🔒 Time-Locked Wallet Implementation

This PR adds a complete MVP implementation of a time-locked wallet smart contract in Clarity.

### ✨ Features Added
- Create multiple time-locked wallets with custom unlock heights
- Deposit STX tokens into locked wallets
- Withdraw funds only after unlock block height is reached
- Extend lock periods for additional security
- Complete wallet management (view, delete empty wallets)
- Comprehensive read-only functions for wallet status checking

### 🎯 Learning Objectives Covered
- Block height mechanics and conditional logic
- STX token transfers and balance management
- Map data structures and principal-based access control
- Error handling and validation patterns

### 📋 Contract Functions
- **Public**: `create-wallet`, `deposit`, `withdraw`, `withdraw-all`, `extend-lock`, `delete-empty-wallet`
- **Read-only**: `get-wallet`, `is-wallet-unlocked`, `get-blocks-until-unlock`, and more

### 🧪 Ready for Testing
The contract includes proper error handling, input validation, and is ready for Clarinet testing and deployment.

Perfect for developers learning Clarity fundamentals! 🚀
