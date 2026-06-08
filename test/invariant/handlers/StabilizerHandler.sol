// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {Stabilizer} from "../../../src/Stabilizer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StabilizerHandler is Test {
    Stabilizer public stabilizer;
    MockERC20 public usdc;
    MockERC20 public usdt;

    // Ghost variables to track call statistics
    uint256 public numCalls;
    uint256 public numSwaps;
    uint256 public numDeposits;
    uint256 public numWithdrawals;

    constructor(Stabilizer _stabilizer, MockERC20 _usdc, MockERC20 _usdt) {
        stabilizer = _stabilizer;
        usdc = _usdc;
        usdt = _usdt;

        // Pre-approve the pool to spend handler's tokens
        usdc.approve(address(stabilizer), type(uint256).max);
        usdt.approve(address(stabilizer), type(uint256).max);
    }

    /// @dev Stateful fuzzing target for adding liquidity.
    function addLiquidity(uint256 amountUsdc, uint256 amountUsdt) external {
        // Bound inputs to reasonable ranges (1 USDC/USDT to 1,000,000 USDC/USDT)
        amountUsdc = bound(amountUsdc, 1e6, 1_000_000e6);
        amountUsdt = bound(amountUsdt, 1e6, 1_000_000e6);

        // Mint the tokens to the handler
        usdc.mint(address(this), amountUsdc);
        usdt.mint(address(this), amountUsdt);

        // Get exact quote of LP tokens to mint
        uint256 minStb = stabilizer.quoteAddLiquidity(amountUsdc, amountUsdt);
        if (minStb == 0) return;

        // Perform the deposit
        stabilizer.addLiquidity(amountUsdc, amountUsdt, minStb, address(this));

        numCalls++;
        numDeposits++;
    }

    /// @dev Stateful fuzzing target for removing liquidity.
    function removeLiquidity(uint256 amountStb) external {
        uint256 handlerStbBalance = stabilizer.balanceOf(address(this));
        if (handlerStbBalance == 0) return;

        // Bound amount to current STB balance owned by the handler
        amountStb = bound(amountStb, 1, handlerStbBalance);

        // Get expected withdrawal amounts
        (uint256 expectedUsdc, uint256 expectedUsdt) = stabilizer.quoteRemoveLiquidityAmount(amountStb);
        if (expectedUsdc == 0 || expectedUsdt == 0) return;

        // Perform withdrawal
        stabilizer.removeLiquidity(amountStb, expectedUsdc, expectedUsdt, address(this));

        numCalls++;
        numWithdrawals++;
    }

    /// @dev Stateful fuzzing target for swapping tokens.
    function exchange(bool isUsdc, uint256 amount) external {
        MockERC20 tokenIn = isUsdc ? usdc : usdt;

        // Fetch reserves
        (uint256 usdcReserve, uint256 usdtReserve,,) = stabilizer.getStabilizerMatrix();
        uint256 reserveIn = isUsdc ? usdcReserve : usdtReserve;
        uint256 reserveOut = isUsdc ? usdtReserve : usdcReserve;

        if (reserveIn == 0 || reserveOut == 0) return;

        // Bound swap size to 20% of reserveIn to avoid pool imbalance limits
        amount = bound(amount, 1e6, reserveIn / 5);

        // Mint tokenIn to the handler
        tokenIn.mint(address(this), amount);

        // Get expected amount out
        (uint256 expectedOut,) = stabilizer.quoteExchangeAmount(address(tokenIn), amount);
        if (expectedOut == 0) return;

        // Perform the exchange
        stabilizer.exchange(address(tokenIn), amount, expectedOut, address(this));

        numCalls++;
        numSwaps++;
    }
}
