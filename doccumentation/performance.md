## Performance Considerations

Solidity is an execution-constrained environment where every calculation incurs gas costs. Several gas optimization design patterns are implemented:

### 1. Stateless Library Executions
Libraries (`StabilizerLogic`, `DynamicFeesEngine`, `StabilizerInvariant`) utilize Solidity's `internal` functions. When internal functions are called, the code is compiled directly into the parent contract. This avoids expensive external contract calls (`DELEGATECALL` / `CALL`) which cost substantial base gas ($100$ to $700$ gas per call), minimizing the active swap gas footprint.

### 2. High-Efficiency Newton-Raphson Solver
The iterative Newton-Raphson approximation is heavily optimized:
*   Loops are capped at a hard maximum of $255$ iterations to guarantee termination and prevent infinite loops that could run out of transaction gas.
*   The convergence condition is checked using a minimal delta check (`absDiff(dPrev) <= 1`). Once the precision converges to $1$ wei, the loop terminates immediately, saving thousands of gas units compared to fixed-iteration solvers.

### 3. In-Memory Struct Parameter Passing
Using separate variables inside functions wastes stack slots, frequently triggering Solidity's dreaded "Stack Too Deep" errors. Stabilizer solves this by packing parameters into in-memory structs defined in `DataTypes.sol`:
```solidity
struct ExchangeParams {
    uint256 amount;
    address token;
    address usdc;
    address usdt;
    address oracle;
    uint256 usdcReserve;
    uint256 usdtReserve;
    uint256 amp;
    uint256 maxImbalanceThreshold;
    uint256 maxPriceDeviationThreshold;
}
```
Passing these parameters as a single memory pointer significantly reduces compiler stack pressure and optimizes code execution speed.
