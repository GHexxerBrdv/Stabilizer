# Stabilizer: Dynamic-Fee Stableswap Liquidity Protocol

A production-grade, highly optimized, non-custodial Stableswap Liquidity Pool and Exchange designed specifically for pegged assets (USDC/USDT). Combining the high-efficiency Curve Stableswap invariant with an innovative real-time Dynamic Fees Engine and robust configurable safety thresholds, Stabilizer represents a state-of-the-art solution to liquidity provision, toxic flow mitigation, and capital efficiency.

---

# StableStream: Rust based indexer for Stabilizer

- [StableStream](https://github.com/GHexxerBrdv/StableStream.git)

## Overview

### Problem Statement

Standard Constant Product Market Maker (CPMM) AMMs ($x \cdot y = k$) suffer from high slippage and capital inefficiency when handling pegged assets like stablecoins. While traditional Stableswap models ($x + y$ mixed with $x \cdot y$) significantly reduce slippage, they rely on static swap fees. Static fee models fail to:

1. Penalize trades that severely skew the pool's reserves, leaving the pool vulnerable to structural imbalance.
2. Incentivize arbitrageurs to restore pool balance under high volatility or oracle depeg scenarios.
3. Block toxic flow automatically during extreme stablecoin depeg events, exposing Liquidity Providers (LPs) to significant capital loss (impermanent loss crystallization).



### Solution Provided

**Stabilizer** addresses these vulnerabilities by introducing a multi-tiered, state-aware AMM architecture:

- **Deep Liquidity Engine**: Implements the Curve Stableswap invariant for two tokens ($n=2$), dramatically reducing slippage for large transactions.
- **Directional Dynamic Fees Engine**: Computes real-time swap fees that scale quadratically based on reserve imbalance and oracle price deviation. Crucially, it applies **directional adjustments**—discounting fees for stabilizing trades to attract arbitrageurs, while surcharging destabilizing trades to protect LP capital.
- **Configurable Safety Thresholds (Circuit Breakers)**: Enforces hard limits on reserve imbalance and oracle price deviation, reverting toxic swap transactions before pool drainage occurs.

---



## Key Features

- **Curve Stableswap Invariant ($n=2$)**: Optimized Newton-Raphson iterative solver for $D$ (equilibrium pool value) and $y$ (target asset balance) in Solidity, capped at $255$ iterations with 1-wei convergence precision.
- **Real-time Dynamic Fee Calculation**: Swaps are priced using a base fee ($2$ BPS) plus quadratic premiums derived from pool reserve skewness (up to $15$ BPS) and Chainlink oracle price deviation (up to $3$ BPS).
- **Directional Fee Adjustments**: Offers up to a $5$ BPS fee discount (stabilizing rebate) for swaps that move the pool back toward a $50:50$ ratio, and up to a $10$ BPS surcharge (destabilizing tax) for swaps that increase pool imbalance.
- **Automatic Circuit Breakers**:
  - **Max Imbalance Threshold**: Blocks swap transactions that push pool imbalance past a configured threshold (default $80$) unless the swap is stabilizing (reducing imbalance).
  - **Max Price Deviation Threshold**: Automatically pauses swaps if the Chainlink oracle price deviation between USDC and USDT exceeds the configured limit (default $1$), protecting LPs from depegged assets.
- **Robust Security Mechanics**:
  - **Inflation Attack Shield**: Locks the first $1,000$ wei ($MINLIQUIDITY$) of LP supply by minting it to `0xdead` on first deposit.
  - **Stale Oracle Price Protection**: Enforces strict heartbeat validation ($24$ hours) on Chainlink feeds, reverting on stale, zero, or negative price data.
  - **Safe Token Standard Integration**: Employs OpenZeppelin's `SafeERC20` wrapper to safely handle non-standard ERC20 token transfer quirks (e.g., return values of USDT/USDC).
- **Structural LP Backing Fee Mechanics**: 30% of collected swap fees are sent to the `feeReceiver` (admin/treasury), while 70% of fees structurally accumulate inside the contract, directly increasing the backing value of the STB LP tokens and generating organic yield.

---

## Deployments addresses


| contract    | address                                      | chain        |
| ----------- | -------------------------------------------- | ------------ |
| USDC (mock) | `0x6162A003B0DbEccEA328924d0F2382eF07588eE5` | Polygon Amoy |
| USDT (mock) | `0x0e6eDa717c28536746594f4D2D0e699f639bdC06` | Polygon Amoy |
| Oracle      | `0x2B156643d89AFecd1E6c1a67df29a0E8b9C638D8` | Polygon Amoy |
| Stabilizer  | `0xEb1598206b58D87d671d137228712d8919914D16` | Polygon Amoy |



## Installation

### Prerequisites

1. **Git**: For cloning the repository.
2. **Foundry**: Install via standard terminal shell scripts.

### Step-by-Step Setup

1. **Clone the Repository**:
  ```bash
    git clone https://github.com/GHexxerBrdv/Stabilizer.git
    cd Stabilizer
  ```
2. **Install Foundry Toolchain** (if not already installed):
  ```bash
    curl -L https://foundry.paradigm.xyz | bash
    foundryup
  ```
3. **Install Dependencies** (Submodules):
  ```bash
    forge install
  ```
4. **Build Contracts**:
  ```bash
    forge build
  ```

---



## Environment Variables

To deploy to public networks or run fork testing, copy `.env.example` into a `.env` file:


| Variable            | Purpose                                                          | Required                            |
| ------------------- | ---------------------------------------------------------------- | ----------------------------------- |
| `RPC_URL`           | Endpoint provider for connecting to Target EVM chains            | Yes (for deployment & fork testing) |
| `PRIVATE_KEY`       | EOA deployer private key used to sign transactions.              | Yes (for deployment)                |
| `ETHERSCAN_API_KEY` | Key used to automatically verify source code on block explorers. | No (optional)                       |


> [!WARNING]
> **Note:** Never put private key directly in environment variables or commit it to source control either wallet has funds or not.

---



## Testing



### Development and Local Compilation

To compile the contracts and output contract ABIs and bytecodes:

```bash
forge build
```



### Running Test Suite

Execute the entire test suite (unit, integration, and revert assertions):

```bash
forge test
```



### Run Tests with Verbose Logging

To view event logs, console outputs, and gas reports during test execution:

```bash
forge test -vvv
```



### Run Specific Test Suites

To run only a specific contract's tests (e.g., Dynamic Fee calculations):

```bash
forge test --match-contract DynamicFeesEngineTest
```

---



## API Documentation

See [api](./documentation/api.md) for detailed API documentation.

---



## Internal Bookkeeping vs. Contract Balances

Standard AMMs often query `IERC20(token).balanceOf(address(this))` directly to calculate swap outputs, making them highly vulnerable to flashloan-driven price manipulation or "donation attacks" (where tokens are directly transferred to the contract to artificially inflate reserves).

To mitigate this, Stabilizer maintains explicit internal accounting variables:

```solidity
uint256 usdcReserves;
uint256 usdtReserves;
```

Reserves are only modified internally when users deposit, withdraw, or swap via standard protocol interfaces. External direct transfers of USDC or USDT to the contract are ignored by calculations, securing the invariant math from manipulation.

---



## Security Features

See [security](./documentation/security.md) for detailed API documentation.

---



## Performance Considerations

See [performance](./documentation/performance.md) for detailed API documentation.

---



## Coverage

The project maintains a highly comprehensive test suite built in Foundry. The testing strategy prioritizes strict boundary conditions, extreme skews, oracle price deviations, and circuit breaker activations.

### Test Coverage Highlights

The project achieves:

<img src="./assets/test_coverage.png" alt="Test Coverage">


### Running Coverage

- **Check Test Coverage Metrics**:
  ```bash
  forge coverage
  ```

---



## Deployment

This repository focuses on deploying smart contracts on polygon amoy testnet, However if  you want to try other blockchains you can modify the deployment script command to deploy to your preferred chain.

### Environment Variables

Create a `.env` file in the root directory and copy the contents from `.env.example`.

```bash
cp .env.example .env
```

set up the environment variables in the `.env` file.

### Deploy contracts

The deployment of contracts in this repository is standalon that means you have to deploy each contract individually. if you want to deploy all contracts at once then you can build yourown script by taking reference from the current deployment script.

Run the following order of the scripts to deploy the contracts:

To deploy tokens (you can take already deployed tokens from the explorer, but they must be stablecoins):

```bash
forge script script/DeployTokens.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast -vvvv
```

To deploy oracle contract(the current oracle is only supporting data feed for usdc/usd and usdt/usd on polygon amoy, you always can choose appropriate data feed address in your case):

```bash
forge script script/DeployOracle.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast -vvvv
```

To deploy the stabilizer contract:

```bash
forge script script/DeployStabilizer.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast -vvvv
```



## Gas Report

Access [gasReport.md](documentation/gasReport.md)

## Challenges and Engineering Decisions

