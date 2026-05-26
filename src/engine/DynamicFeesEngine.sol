// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {StabilizerInvariant} from "./Invariant.sol";
import {Math} from "../utils/Math.sol";
import {DataTypes} from "../Types/DataTypes.sol";

library DynamicFeesEngine {
    using Math for uint256;

    uint16 private constant BASE_FEE_BPS = 2;
    uint16 private constant MAX_APPLICABLE_FEE_BPS = 25;
    uint16 private constant SCALE_FACTOR = 10000;
    uint16 private constant MAX_IMBALANCE_FEE_BPS = 15;
    uint16 private constant MAX_PRICE_DEVIATION_FEE_BPS = 3;

    function calculateFinalFeeBps(DataTypes.FeeParams memory params) internal pure returns (uint16 finalFeeBps) {
        uint16 imbalanceFee = calculateImbalanceFeeBps(params.usdcReserveBefore, params.usdtReserveBefore);
        uint16 priceDeviationFee = calculatePriceDeviationFeeBps(params.usdcPrice, params.usdtPrice);

        uint256 coreFee = uint256(BASE_FEE_BPS) + uint256(imbalanceFee) + uint256(priceDeviationFee);

        (bool isStabilizing, uint16 imbalanceDelta) = getDirectionalState(
            params.usdcReserveBefore, params.usdtReserveBefore, params.usdcReserveAfter, params.usdtReserveAfter
        );

        int16 directionalAdj = getDirectionalAdjustment(imbalanceDelta, isStabilizing);

        int256 adjustedFee = int256(coreFee) + int256(directionalAdj);

        if (adjustedFee < int256(uint256(BASE_FEE_BPS))) {
            adjustedFee = int256(uint256(BASE_FEE_BPS));
        }

        if (adjustedFee > int256(uint256(MAX_APPLICABLE_FEE_BPS))) {
            adjustedFee = int256(uint256(MAX_APPLICABLE_FEE_BPS));
        }
        finalFeeBps = uint16(uint256(adjustedFee));
    }

    function getDirectionalState(
        uint256 usdcReserveBefore,
        uint256 usdtReserveBefore,
        uint256 usdcReserveAfter,
        uint256 usdtReserveAfter
    ) internal pure returns (bool, uint16) {
        uint256 imbalanceBefore = calculateImbalance(usdcReserveBefore, usdtReserveBefore);
        uint256 imbalanceAfter = calculateImbalance(usdcReserveAfter, usdtReserveAfter);
        if (imbalanceAfter < imbalanceBefore) {
            return (true, uint16(imbalanceBefore - imbalanceAfter));
        } else {
            return (false, uint16(imbalanceAfter - imbalanceBefore));
        }
    }

    function getDirectionalAdjustment(uint16 imbalanceDelta, bool isStabilizing) internal pure returns (int16) {
        if (imbalanceDelta < 250) {
            return 0;
        }
        if (imbalanceDelta < 1000) {
            return isStabilizing ? int16(-1) : int16(2);
        }
        if (imbalanceDelta < 2500) {
            return isStabilizing ? int16(-2) : int16(5);
        }
        return isStabilizing ? int16(-5) : int16(10);
    }

    function calculateImbalanceFeeBps(uint256 usdcReserves, uint256 usdtReserves) internal pure returns (uint16) {
        uint256 imbalanceBps = calculateImbalance(usdcReserves, usdtReserves);
        uint256 imbalanceFeeBps = (imbalanceBps * imbalanceBps) / 2500000;
        return uint16(imbalanceFeeBps.min(uint256(MAX_IMBALANCE_FEE_BPS)));
    }

    function calculatePriceDeviationFeeBps(uint256 usdcPrice, uint256 usdtPrice) internal pure returns (uint16) {
        require(usdcPrice != 0 && usdtPrice != 0, "Zero price");
        uint256 deviationBps = calculateDeviation(usdcPrice, usdtPrice);
        uint256 deviationFeeBps = (deviationBps * deviationBps) / 20000;
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
