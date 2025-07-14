# VoucherChain

A generic smart contract system for managing token vouchers - minting, redemption, and agent management. This contract can work with any ERC20 token including ETN, and others.

## Features

- **Token Agnostic**: Works with any ERC20 token
- **Secure Voucher System**: Hash-based voucher codes with expiry support
- **Agent Management**: Register and manage retail agents with commission tracking
- **Fee System**: Configurable minting and redemption fees
- **Multi-Chain Ready**: Can be deployed on any EVM-compatible blockchain
- **Treasury Functionality**: Contract acts as treasury - agents pay for vouchers when minting
- **Expired Voucher Reclamation**: Agents can reclaim expired vouchers

## Smart Contract Design

The VoucherChain contract provides:

- **Voucher Minting**: Authorized agents can mint vouchers with specific token values (agents pay for vouchers)
- **Batch Voucher Minting**: Mint multiple vouchers in a single transaction
- **Voucher Redemption**: Users can redeem vouchers to receive tokens
- **Expired Voucher Reclamation**: Agents can reclaim expired vouchers to recover their investment
- **Agent Management**: Register agents, track commissions, and settle balances
- **Fee Management**: Configurable fees for minting and redemption (fees go to treasury immediately)
- **Expiry Support**: Optional expiry dates for vouchers
- **Security**: Reentrancy protection and proper access controls


## Contract Functions

### Core Functions
- `mintVoucher(string voucherCode, uint256 tokenValue, uint256 expiryDays)` - Mint a new voucher (agent pays)
- `mintVoucherBatch(VoucherBatch batch)` - Mint multiple vouchers in one transaction
- `redeemVoucher(string voucherCode, address recipient)` - Redeem a voucher
- `reclaimExpiredVoucher(string voucherCode)` - Reclaim expired voucher (agent only)
- `getVoucherStatus(string voucherCode)` - Check voucher status

### Agent Management
- `registerAgent(address agent, uint256 commissionRate)` - Register new agent
- `deactivateAgent(address agent)` - Deactivate agent
- `settleAgentBalance(address agent)` - Settle agent commission

### Admin Functions
- `updateFees(uint256 mintingFee, uint256 redemptionFee)` - Update fee rates
- `updateToken(address newToken)` - Update token address
- `updateTreasury(address newTreasury)` - Update treasury address

## Configuration

The contract is deployed with these default settings:
- **Minting Fee**: 2% (200 basis points) - transferred to treasury immediately
- **Redemption Fee**: 1% (100 basis points) - transferred to treasury on redemption
- **Default Expiry**: 90 days
- **Max Commission Rate**: 10%

## Treasury Behavior

The contract acts as a treasury with the following behavior:

1. **Minting**: Agents pay voucher value + minting fee when minting vouchers
   - Voucher value stays in contract for redemption
   - Minting fee goes to treasury immediately

2. **Redemption**: Users redeem vouchers and receive token value minus redemption fee
   - Redemption fee goes to treasury
   - Net amount goes to user

3. **Expired Vouchers**: Agents can reclaim expired vouchers
   - Only the original issuer can reclaim
   - Voucher must be expired
   - Full voucher value is returned to agent

## Security Features

- **Reentrancy Protection**: All external calls are protected
- **Access Control**: Only authorized minters can create vouchers
- **Fee Limits**: Maximum 5% for both minting and redemption fees
- **Expiry Limits**: Maximum 365 days for voucher expiry
- **Commission Limits**: Maximum 10% agent commission rate
- **Treasury Protection**: Fees are transferred immediately to prevent manipulation

## Business Model

The system generates revenue through:
1. **Minting Fees**: 2-3% fee when agents mint vouchers (immediate treasury transfer)
2. **Redemption Fees**: 1% fee when users redeem vouchers (immediate treasury transfer)
3. **Agent Commissions**: Configurable commission rates for agents
4. **Premium Features**: Optional premium agent tools and analytics

## Development

### Adding New Features

1. Create a new branch
2. Add tests for new functionality
3. Update documentation
4. Submit pull request

### Testing Strategy

- Unit tests for all contract functions
- Integration tests for complete workflows
- Security tests for edge cases
- Gas optimization tests

## License

MIT License - see LICENSE file for details

## Support

For questions and support, please open an issue on GitHub.
