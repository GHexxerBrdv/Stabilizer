// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DynamicFeesEngine} from "../engine/DynamicFeesEngine.sol";
import {StabilizerInvariant} from "../engine/Invariant.sol";
import {StabilizerOracle} from "../StabilizerOracle.sol";
import {Math} from "../utils/Math.sol";
import {DataTypes} from "../Types/DataTypes.sol";

library StabilizerLogic {
    using DynamicFeesEngine for uint256;
    using StabilizerInvariant for uint256;
    using Math for uint256;

    error InsufficientDeposit();
    error InvalidD();
    error InvalidAmount();
    error ThresholdExceeded();

    function calculateStbMintAmount(DataTypes.StbMintParams memory params) internal pure returns (uint256 stbAmount) {
        uint256 dNew = params.newUsdcReserve.getD(params.newUsdtReserve, params.a);
        if (params.stbSupply == 0) {
            require(dNew > params.minLiquidity, InsufficientDeposit());
            return dNew - params.minLiquidity;
        }
        uint256 dOld = params.oldUsdcReserve.getD(params.oldUsdtReserve, params.a);
        require(dNew >= dOld, InvalidD());

        uint256 dDiff = dNew - dOld;

        stbAmount = dDiff * params.stbSupply / dOld;
    }

    function calculateWithdrawAmounts(DataTypes.WithdrawParams memory params)
        internal
        pure
        returns (uint256 usdcAmount, uint256 usdtAmount)
    {
        require(params.stbAmount > 0, InvalidAmount());
        require(params.stbAmount <= params.stbSupply, InvalidAmount());
        require(params.usdcReserve > 0 && params.usdtReserve > 0, InvalidAmount());
        usdcAmount = params.stbAmount * params.usdcReserve / params.stbSupply;
        require(usdcAmount > 0, InvalidAmount());
        usdtAmount = params.stbAmount * params.usdtReserve / params.stbSupply;
        require(usdtAmount > 0, InvalidAmount());
    }

    function calculateExchangeAmount(DataTypes.ExchangeParams memory params) internal view returns (uint256, uint256) {
        require(params.amount > 0, InvalidAmount());

        uint256 quoteAmount = getQuoteAmount(
            params.amount, params.token, params.usdc, params.usdcReserve, params.usdtReserve, params.amp
        );

        {
            uint256 usdcPrice = StabilizerOracle(params.oracle).getPrice(params.usdc);
            uint256 usdtPrice = StabilizerOracle(params.oracle).getPrice(params.usdt);
            require(
                DynamicFeesEngine.calculateDeviation(usdcPrice, usdtPrice) <= params.maxPriceDeviationThreshold,
                ThresholdExceeded()
            );
        }

        uint256 usdcReserveNew;
        uint256 usdtReserveNew;

        if (params.token == params.usdc) {
            usdcReserveNew = params.usdcReserve + params.amount;
            usdtReserveNew = params.usdtReserve - quoteAmount;
        } else {
            usdcReserveNew = params.usdcReserve - quoteAmount;
            usdtReserveNew = params.usdtReserve + params.amount;
        }

        {
            uint256 initialImbalance = DynamicFeesEngine.calculateImbalance(params.usdcReserve, params.usdtReserve);
            uint256 finalImbalance = DynamicFeesEngine.calculateImbalance(usdcReserveNew, usdtReserveNew);
            if (finalImbalance > params.maxImbalanceThreshold) {
                require(finalImbalance < initialImbalance, ThresholdExceeded());
            }
        }

        uint16 dynamicFee;
        {
            uint256 usdcPrice = StabilizerOracle(params.oracle).getPrice(params.usdc);
            uint256 usdtPrice = StabilizerOracle(params.oracle).getPrice(params.usdt);
            dynamicFee = DynamicFeesEngine.calculateFinalFeeBps(
                DataTypes.FeeParams({
                    usdcReserveBefore: params.usdcReserve,
                    usdtReserveBefore: params.usdtReserve,
                    usdcReserveAfter: usdcReserveNew,
                    usdtReserveAfter: usdtReserveNew,
                    usdcPrice: usdcPrice,
                    usdtPrice: usdtPrice
                })
            );
        }

        uint256 fee = quoteAmount * dynamicFee / 10000;
        return (quoteAmount - fee, fee);
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
