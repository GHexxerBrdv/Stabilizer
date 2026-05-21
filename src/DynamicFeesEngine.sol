// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// the dynamic fee is depends on following factors
// 1. imbalance ratio : |USDT - USDC| / (USDC + USDT)
// - high imbalance that means high fees: 70% USDc and 30% USDT -> incentivised traders to rebalance the pool
// - low imbalance that means low fees: 50.5% USDc and 49.5% USDT -> more balances -> more cheap trades
//
// 2. Volatility
// - price deviation from oracle feeds
// - standard deviation of recent trades
// - slippage severity
//
// -> high volatility -> high fees (no such huge effect for usdc/usdt pool)
// -> low volatility -> low fees (no such huge effect for usdc/usdt pool)
//
// ToDo: will plane in future just not focus on this as of now
// 3. Trading volume & liquidity depth
// - Low volume → Higher fees (to attract LPs, compensate for low activity)
// - High volume → Lower fees (incentivize larger trades, increase TVL)
// Liquidity depth:
// - Shallow liquidity → Higher fees
// - Deep liquidity → Lower fees

import {StabilizerInvariant} from "./Invariant.sol";
import {Math} from "./Math.sol";

library DynamicFeesEngine {
    using Math for uint256;

    uint16 private constant MAX_BPS = 10000;
    uint16 private constant IMBALANCE_SCALE = 10000;

    uint16 private constant MAX_IMBALANCE_FEE = 200;

    uint16 private constant MAX_PRICE_DEVIATION_FEE = 300;

    function calculateDynamicFee(
        uint256 usdcReserves,
        uint256 usdtReserves,
        uint256 usdcPrice,
        uint256 usdtPrice,
        uint16 baseFee,
        uint16 maxDynamicFee
    ) internal pure returns (uint16) {
        if (usdcReserves == 0 || usdtReserves == 0) {
            return baseFee;
        }

        uint16 imbalanceFeeBps = _calculateImbalanceFeeBps(usdcReserves, usdtReserves);
        uint16 priceDeviationFeeBps = _calculatePriceDeviationFeeBps(usdcPrice, usdtPrice);
        uint256 fee = uint256(baseFee) + uint256(imbalanceFeeBps) + uint256(priceDeviationFeeBps);
        return uint16(fee.min(uint256(maxDynamicFee)));
    }

    function calculateImbalance(uint256 usdcReserves, uint256 usdtReserves) internal pure returns (uint256) {
        return _calculateImbalance(usdcReserves, usdtReserves);
    }

    function _calculateImbalanceFeeBps(uint256 usdcReserves, uint256 usdtReserves) private pure returns (uint16) {
        uint256 imbalanceBps = _calculateImbalance(usdcReserves, usdtReserves);
        uint256 linear = imbalanceBps / 10;
        uint256 quadratic = (imbalanceBps * imbalanceBps) / 20000;
        uint256 imbalanceFeeBps = linear + quadratic;
        return uint16(imbalanceFeeBps.min(uint256(MAX_IMBALANCE_FEE)));
    }

    function _calculatePriceDeviationFeeBps(uint256 usdcPrice, uint256 usdtPrice) private pure returns (uint16) {
        if (usdcPrice == 0 || usdtPrice == 0) {
            return 0;
        }
        uint256 deviationBps = _calculateDeviation(usdcPrice, usdtPrice);
        uint256 deviationFeeBps = (deviationBps * deviationBps * 2) / MAX_BPS;
        return uint16(deviationFeeBps.min(uint256(MAX_PRICE_DEVIATION_FEE)));
    }

    function _calculateImbalance(uint256 usdcReserves, uint256 usdtReserves) private pure returns (uint256) {
        uint256 difference = usdcReserves.absDiff(usdtReserves);
        uint256 total = usdcReserves + usdtReserves;

        if (total == 0) {
            return 0;
        }

        uint256 imbalance = (difference * MAX_BPS) / total;
        return imbalance.min(uint256(IMBALANCE_SCALE));
    }

    function _calculateDeviation(uint256 usdcPrice, uint256 usdtPrice) private pure returns (uint256) {
        uint256 priceDifference = usdcPrice.absDiff(usdtPrice);
        uint256 maxPrice = usdcPrice.max(usdtPrice);

        if (maxPrice == 0) {
            return 0;
        }

        uint256 deviation = (priceDifference * IMBALANCE_SCALE) / maxPrice;
        return deviation.min(uint256(IMBALANCE_SCALE));
    }
}
