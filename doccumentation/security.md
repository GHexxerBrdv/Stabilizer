## Security Features

Stabilizer integrates a comprehensive suite of security controls designed to handle common smart contract vulnerabilities:

### 1. Reentrancy Protection
All user-facing transactional methods (`addLiquidity`, `removeLiquidity`, `exchange`) utilize the `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard`. This enforces a mutual exclusion lock, preventing callers from executing recursive call-backs (e.g., standard ERC20 hooks like `transfer` or `fallback` triggers) to drain assets from the contract before the pool's internal reserves are updated.

### 2. Stale Oracle Price Guard (Heartbeat Validation)
Relying blindly on external price data is extremely dangerous if an oracle stops updating. Stabilizer's pricing gateway enforces three layers of validation on oracle calls:
```solidity
(uint80 roundId, int256 price,, uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();
require(price > 0, InvalidPrice());
require(updatedAt > 0, StaleFeed());
require(block.timestamp - updatedAt <= HEARTBEAT, StaleFeed());
```
Swaps automatically revert if the oracle price is non-positive or if the feed was updated more than $24$ hours ago (`HEARTBEAT`), protecting LPs from trading against outdated market rates.

### 3. ERC4626-Style Inflation Attack Mitigation
In typical share-based liquidity vaults, the first depositor can deposit a tiny amount ($1$ wei) and mint $1$ LP share. They can then transfer a large amount of tokens directly to the contract. The pool's exchange rate becomes heavily skewed ($1$ share representing millions of tokens). Subsequent depositors will have their deposits rounded down to $0$ shares, effectively donating their assets to the first depositor.

Stabilizer eliminates this attack vector by introducing a permanent liquidity lock during the pool's very first deposit:
```solidity
if (stbSupply == 0) {
    _mint(LOCKED_LIQUIDITY_HOLDER, MIN_LIQUIDITY); // Mints 1,000 LP tokens to address(0xdead)
}
```
This forces the minimum pool supply to always be at least $1,000$ units, making it economically unfeasible for an attacker to artificially inflate the share price to a point where subsequent deposits suffer from rounding loss.

### 4. Configurable Safety Threshold Circuit Breakers
To prevent extreme systemic failures, the protocol implements hard circuit breakers:
*   **Imbalance Limit**: If reserve skewness exceeds the `maxImbalanceThreshold` (e.g., the pool is $90\%$ USDC and $10\%$ USDT), any further swap that *increases* the skew (i.e. selling USDT to buy USDC) is reverted. Only stabilizing swaps that *restore* balance are allowed.
*   **Price Deviation Limit**: If the oracle price ratio between USDC and USDT deviates past the `maxPriceDeviationThreshold` (e.g., due to an active depeg event of one stablecoin), all swaps are temporarily blocked, halting the pool from acting as a "dumping ground" for the depegged asset.
