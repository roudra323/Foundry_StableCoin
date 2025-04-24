# Decentralized Stablecoin (DSC)

A fully decentralized, exogenously collateralized stablecoin system pegged to the US Dollar.

## Overview

DSC (Decentralized Stablecoin) is an algorithmic stablecoin designed to maintain a 1:1 peg with the US Dollar. It's:

- **Exogenously Collateralized**: Backed by assets outside the protocol (WETH, WBTC)
- **Dollar Pegged**: Maintains a target value of $1 USD
- **Algorithmically Stable**: Uses code-based mechanisms to maintain stability
- **Overcollateralized**: Always maintains collateral value greater than the minted stablecoin value

This system is similar to MakerDAO's DAI but with simpler mechanics: no governance, no fees, and only WETH and WBTC as collateral.

## Smart Contracts

### DSCEngine.sol

The core contract that manages the minting, burning, and liquidation processes:

- Handles collateral deposits and withdrawals
- Controls the minting and burning of DSC tokens
- Manages liquidations for undercollateralized positions
- Maintains the health factor (collateralization ratio) for all users

### DecentralizedStableCoin.sol

The ERC20 token implementation of the stablecoin:

- Implements standard ERC20 functionality
- Adds burn functionality for redemption
- Controlled by the DSCEngine contract

## Key Features

### Collateralization System

- **Minimum Health Factor**: 1.0 (representing 100%)
- **Liquidation Threshold**: 50% (positions must maintain 200% collateralization)
- **Liquidation Bonus**: 50% bonus for liquidators

### Liquidation Process

When a user's position becomes undercollateralized (health factor < 1.0):
1. Any user can trigger liquidation
2. The liquidator pays back some of the user's debt
3. In return, they receive an equivalent amount of collateral plus a bonus
4. This process helps maintain the protocol's overall solvency

### Price Feeds

Uses Chainlink price feeds to obtain reliable collateral valuations.

## Functions

### User Operations

- `depositeCollateralAndMintDSC`: Deposit collateral and mint DSC in one transaction
- `depositeCollateral`: Deposit supported tokens as collateral
- `redeemCollateralForDsc`: Burn DSC and redeem collateral in one transaction
- `redeemCollateral`: Withdraw collateral (subject to maintaining health factor)
- `mintDsc`: Mint new DSC tokens (subject to collateralization requirements)
- `burnDsc`: Burn DSC tokens

### Liquidation

- `liquidateDsc`: Liquidate undercollateralized positions

### View Functions

- `getHealthFactor`: Check a user's health factor
- `getAccountCollateralValueInUSD`: Get the USD value of a user's collateral
- `getAccountInformation`: Get a user's DSC debt and collateral value

## Getting Started

### Prerequisites

- Node.js and npm
- Foundry/Forge for testing

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/dsc-stablecoin.git
cd dsc-stablecoin
```

2. Install dependencies:
```bash
npm install
```

3. Compile contracts:
```bash
forge build
```

### Testing

Run the test suite:
```bash
forge test
```

### Deployment

Deploy to a local network:
```bash
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Security Considerations

- The system is designed to be overcollateralized at all times
- Liquidation mechanisms help maintain solvency
- Price feed oracles are checked for staleness
- Reentrancy protection is implemented

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

[@roudra323](https://github.com/roudra323)
