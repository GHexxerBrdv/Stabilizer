// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DynamicFeesEngine} from "./DynamicFeesEngine.sol";
import {StabilizerInvariant} from "./Invariant.sol";
import {StabilizerOracle} from "./StabilizerOracle.sol";
import {Math} from "./Math.sol";

library StabilizerLogic {
    using DynamicFeesEngine for uint256;
    using StabilizerInvariant for uint256;
    using Math for uint256;

    function calculateStbMintAmount(
        uint256 oldUsdcReserve,
        uint256 oldUsdtReserve,
        uint256 newUsdcReserve,
        uint256 newUsdtReserve,
        uint256 stbSupply,
        uint256 a,
        uint256 minLiquidity
    ) internal pure returns (uint256 stbAmount) {
        uint256 dNew = newUsdcReserve.getD(newUsdtReserve, a);
        if (stbSupply == 0) {
            require(dNew > minLiquidity, "Insufficient initial deposit");
            return dNew - minLiquidity;
        }
        uint256 dOld = oldUsdcReserve.getD(oldUsdtReserve, a);
        require(dNew >= dOld, "Invalid D");

        uint256 dDiff = dNew - dOld;

        stbAmount = dDiff * stbSupply / dOld;
    }

    function calculateWithdrawAmounts(uint256 amountStb, uint256 usdcReserve, uint256 usdtReserve, uint256 stbSupply)
        internal
        pure
        returns (uint256 usdcAmount, uint256 usdtAmount)
    {
        require(amountStb > 0, "Invalid Stb amount");
        require(amountStb <= stbSupply, "Invalid Stb amount");
        require(usdcReserve > 0 && usdtReserve > 0, "Invalid token balances");
        usdcAmount = amountStb * usdcReserve / stbSupply;
        require(usdcAmount > 0, "Invalid usdc amount");
        usdtAmount = amountStb * usdtReserve / stbSupply;
        require(usdtAmount > 0, "Invalid usdt amount");
    }

    function isStabilizing(uint256 usdcBefore, uint256 usdtBefore, uint256 usdcAfter, uint256 usdtAfter)
        internal
        pure
        returns (bool, uint256)
    {
        uint256 imbalanceBefore = usdcBefore.calculateImbalance(usdtBefore);
        uint256 imbalanceAfter = usdcAfter.calculateImbalance(usdtAfter);
        (bool isStabilizing, uint256 imbalanceDelta) = (imbalanceAfter < imbalanceBefore)
            ? (true, imbalanceBefore - imbalanceAfter)
            : (false, imbalanceAfter - imbalanceBefore);
        return (isStabilizing, imbalanceDelta);
    }

    function applyDirectionalAdjustment(uint256 imbalanceDelta, uint16 dynamicFee, uint16 baseFee, bool isStabilizing)
        internal
        pure
        returns (uint16)
    {
        if (isStabilizing) {
            uint256 discount = (imbalanceDelta * 3) / 100;
            discount = discount.min(50);
            return uint16((dynamicFee - discount).max(baseFee));
        } else {
            uint256 surcharge = (imbalanceDelta * 5) / 100;
            surcharge = surcharge.min(100);
            return uint16((dynamicFee + surcharge).max(baseFee));
        }
    }

    function calculationExchangeAmount(
        uint256 amount,
        address token,
        address usdc,
        address usdt,
        address oracle,
        uint256 usdcReserveCurrent,
        uint256 usdtReserveCurrent,
        uint256 amp,
        uint16 baseFeeBps,
        uint16 maxFeeBps
    ) internal view returns (uint256, uint256) {
        require(amount > 0, "Invalid amount");

        uint256 usdcPrice = StabilizerOracle(oracle).getPrice(usdc);
        uint256 usdtPrice = StabilizerOracle(oracle).getPrice(usdt);

        uint256 quoteAmount = getQuoteAmount(amount, token, usdc, usdcReserveCurrent, usdtReserveCurrent, amp);

        uint256 usdcReserveNew;
        uint256 usdtReserveNew;
        bool stabilizing;
        uint256 imbalanceDelta;
        {
            if (token == usdc) {
                usdcReserveNew = usdcReserveCurrent + amount;
                usdtReserveNew = usdtReserveCurrent - quoteAmount;
            } else {
                usdcReserveNew = usdcReserveCurrent - quoteAmount;
                usdtReserveNew = usdtReserveCurrent + amount;
            }

            (stabilizing, imbalanceDelta) =
                isStabilizing(usdcReserveCurrent, usdtReserveCurrent, usdcReserveNew, usdtReserveNew);
        }

        uint16 dynamicFee =
            usdcReserveCurrent.calculateDynamicFee(usdtReserveCurrent, usdcPrice, usdtPrice, baseFeeBps, maxFeeBps);

        uint16 payableFee = applyDirectionalAdjustment(imbalanceDelta, dynamicFee, baseFeeBps, stabilizing);

        uint256 fee = quoteAmount * payableFee / 10000;
        uint256 outAmount = quoteAmount - fee;
        return (outAmount, fee);
    }

    function getQuoteAmount(
        uint256 amount,
        address token,
        address usdc,
        uint256 usdcReserve,
        uint256 usdtReserve,
        uint256 amp
    ) internal pure returns (uint256) {
        uint256 usdcReserveNew = usdcReserve;
        uint256 usdtReserveNew = usdtReserve;
        uint256 d = usdcReserve.getD(usdtReserve, amp);
        uint256 y;
        uint256 quoteAmount;
        if (token == usdc) {
            usdcReserveNew += amount;
            y = usdcReserveNew.getY(d, amp);
            quoteAmount = usdtReserve - y;
        } else {
            usdtReserveNew += amount;
            y = usdtReserveNew.getY(d, amp);
            quoteAmount = usdcReserve - y;
        }
        return quoteAmount;
    }
}
