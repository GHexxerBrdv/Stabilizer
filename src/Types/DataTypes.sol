// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

library DataTypes {
    struct FeeParams {
        uint256 usdcReserveBefore;
        uint256 usdtReserveBefore;
        uint256 usdcReserveAfter;
        uint256 usdtReserveAfter;
        uint256 usdcPrice;
        uint256 usdtPrice;
    }

    struct StbMintParams {
        uint256 oldUsdcReserve;
        uint256 oldUsdtReserve;
        uint256 newUsdcReserve;
        uint256 newUsdtReserve;
        uint256 stbSupply;
        uint256 a;
        uint256 minLiquidity;
    }

    struct WithdrawParams {
        uint256 stbAmount;
        uint256 usdcReserve;
        uint256 usdtReserve;
        uint256 stbSupply;
    }

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
}
