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

    uint8 private constant BASE_FEE_BPS = 4;

    uint16 private constant MAX_DYNAMIC_FEE_BPS = 30;

    uint16 private constant SCALE_FACTOR = 10000;

    uint16 private constant MAX_IMBALANCE_FEE_BPS = 15;

    uint16 private constant MAX_PRICE_DEVIATION_FEE_BPS = 15;

    // add imbalance threshold
    // add price threshol

    function calculateDynamicFee(uint256 usdcReserves, uint256 usdtReserves, uint256 usdcPrice, uint256 usdtPrice)
        internal
        pure
        returns (uint16)
    {
        //>/ swap is not possible if one of reserve is empty
        // if (usdcReserves == 0 || usdtReserves == 0) {
        //     return baseFee;
        // }

        uint16 imbalanceFeeBps = calculateImbalanceFeeBps(usdcReserves, usdtReserves);
        uint16 priceDeviationFeeBps = calculatePriceDeviationFeeBps(usdcPrice, usdtPrice);
        uint256 fee = uint256(BASE_FEE_BPS) + uint256(imbalanceFeeBps) + uint256(priceDeviationFeeBps);
        return uint16(fee.min(uint256(MAX_DYNAMIC_FEE_BPS)));
    }

    function calculateImbalanceFeeBps(uint256 usdcReserves, uint256 usdtReserves) internal pure returns (uint16) {
        uint256 imbalanceBps = calculateImbalance(usdcReserves, usdtReserves);
        uint256 imbalanceFeeBps = (imbalanceBps * imbalanceBps) / 2500000;
        return uint16(imbalanceFeeBps.min(uint256(MAX_IMBALANCE_FEE_BPS)));
    }

    function calculatePriceDeviationFeeBps(uint256 usdcPrice, uint256 usdtPrice) internal pure returns (uint16) {
        if (usdcPrice == 0 || usdtPrice == 0) {
            return 0;
        }
        uint256 deviationBps = calculateDeviation(usdcPrice, usdtPrice);
        uint256 deviationFeeBps = (deviationBps * deviationBps * 2) / SCALE_FACTOR;
        return uint16(deviationFeeBps.min(uint256(MAX_PRICE_DEVIATION_FEE_BPS)));
    }

    function calculateImbalance(uint256 usdcReserves, uint256 usdtReserves) internal pure returns (uint256) {
        uint256 difference = usdcReserves.absDiff(usdtReserves);
        uint256 total = usdcReserves + usdtReserves;

        if (total == 0) {
            return 0;
        }

        uint256 imbalance = (difference * SCALE_FACTOR) / total;
        return imbalance.min(uint256(SCALE_FACTOR)); //>/ here scale factor is user for 100% imbalance?
    }

    function calculateDeviation(uint256 usdcPrice, uint256 usdtPrice) internal pure returns (uint256) {
        uint256 priceDifference = usdcPrice.absDiff(usdtPrice);
        uint256 maxPrice = usdcPrice.max(usdtPrice);

        if (maxPrice == 0) {
            return 0;
        }

        uint256 deviation = (priceDifference * SCALE_FACTOR) / maxPrice;
        return deviation.min(uint256(SCALE_FACTOR));
    }
}
