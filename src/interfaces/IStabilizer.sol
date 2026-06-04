// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

interface IStabilizer {
    event LiquidityAdded(uint256 amountUsdc, uint256 amountUsdt, uint256 amountStb, address receiver);
    event LiquidityRemoved(uint256 amountUsdc, uint256 amountUsdt, uint256 amountStb, address receiver);
    event Exchange(
        address token, uint256 amount, uint256 quoteAmount, uint256 fees, address receiver, address feeReceiver
    );
    event OracleUpdate(address oldOracle, address newOracle);
    event AmpUpdate(uint256 amp);
    event FeeReceiverUpdate(address oldFeeReceiver, address newFeeReceiver);
    event CleanUp(address token, uint256 amount);
    event MaxImbalanceThresholdUpdate(uint256 oldThreshold, uint256 newThreshold);
    event MaxPriceDeviationThresholdUpdate(uint256 oldThreshold, uint256 newThreshold);

    function addLiquidity(uint256 amountUsdc, uint256 amountUsdt, uint256 minAmountStb, address receiver) external;
    function removeLiquidity(uint256 amountStb, uint256 minAmountUsdc, uint256 minAmountUsdt, address receiver) external;
    function exchange(address token, uint256 amount, uint256 minAmountOut, address receiver) external;
    function getStabilizerMatrix()
        external
        view
        returns (uint256 usdcReserveAmount, uint256 usdtReserveAmount, uint256 usdcPrice, uint256 usdtPrice);
}
