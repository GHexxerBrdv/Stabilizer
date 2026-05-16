// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

library StabilizerMath {
    uint8 private constant COIN_MULTIPLIER = 4;
    uint8 private constant COIN = 2;
    uint8 private constant MAX_ITERATIONS = 255;

    function abs(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function getD(uint256 usdcBalance, uint256 usdtBalance, uint256 amp) internal pure returns (uint256) {
        require(usdcBalance > 0 && usdtBalance > 0, "Zero balance");

        uint256 s = usdcBalance + usdtBalance;
        uint256 ann = COIN_MULTIPLIER * amp;

        uint256 d = s;
        uint256 i = 0;
        for (; i < MAX_ITERATIONS;) {
            uint256 dPrev = d;

            uint256 dp = d;
            dp = dp * d / (usdcBalance * 2);
            dp = dp * d / (usdtBalance * 2);

            uint256 num = ((COIN * dp) + (ann * s)) * d;
            uint256 den = ((COIN + 1) * dp) + ((ann - 1) * d);

            d = num / den;

            if (abs(d, dPrev) <= 1) {
                return d;
            }
            unchecked {
                ++i;
            }
        }
    }

    function getY(uint256 tokenBalanceOther, uint256 d, uint256 amp) internal pure returns (uint256) {
        require(tokenBalanceOther > 0, "Zero balance");

        uint256 ann = COIN_MULTIPLIER * amp;
        uint256 b = tokenBalanceOther + d / ann;
        uint256 c = d ** (COIN + 1) / (4 * ann * tokenBalanceOther);

        uint256 y = d;
        uint256 i = 0;
        for (; i < MAX_ITERATIONS;) {
            uint256 yPrev = y;

            uint256 num = y * y + c;
            uint256 den = 2 * y + b - d;
            y = num / den;
            if (abs(y, yPrev) <= 1) {
                return y;
            }
            unchecked {
                ++i;
            }
        }
    }
}
