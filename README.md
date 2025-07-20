# Token Staking Platform

A Clarity smart contract for staking STX tokens on the Stacks blockchain.

## Overview
This project enables users to:
- Stake STX tokens to participate in a reward pool.
- Unstake their tokens.
- View their stake and the total staked amount.

## Contract Details
- **File**: `staking-platform.clar`
- **Functions**:
  - `(stake amount)`: Stakes a specified amount of STX.
  - `(unstake amount)`: Unstakes a specified amount of STX.
  - `(get-stake user)`: Retrieves a user’s stake.
  - `(get-total-staked)`: Returns the total staked STX.

## Getting Started
1. Clone the repository.
2. Run `clarinet check` to verify the contract.
3. Deploy to a Stacks testnet.
4. Integrate with a UI for staking interactions.

## Testing
Run tests with:
```bash
clarinet test