// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StabilizerInvariant} from "./engine/Invariant.sol";
import {StabilizerOracle} from "./StabilizerOracle.sol";
import {DynamicFeesEngine} from "./engine/DynamicFeesEngine.sol";
import {StabilizerLogic} from "./engine/StabilizerLogic.sol";
import {Math} from "./utils/Math.sol";
import {DataTypes} from "./Types/DataTypes.sol";

contract Stabilizer is ERC20("Stabilizer", "STB"), Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using StabilizerInvariant for uint256;
    using DynamicFeesEngine for uint256;
    using StabilizerLogic for uint256;
    using Math for uint256;

    address private oracle;

    address private usdc;
    address private usdt;
    address private feeReceiver;
    bool private stabilizerPaused;
    bool private swapPaused;

    uint256 usdcReserves;
    uint256 usdtReserves;

    uint256 private amp;

    uint256 private constant MIN_LIQUIDITY = 1000;
    address private constant LOCKED_LIQUIDITY_HOLDER = address(0xdead);

    modifier whenNotPaused() {
        require(!stabilizerPaused, "Pool is paused");
        _;
    }

    modifier ensureSwapStatus() {
        require(!swapPaused, "Swap is paused");
        _;
    }

    modifier onlyOwnerOrFeeReceiver() {
        require(msg.sender == owner() || msg.sender == feeReceiver, "Not owner or fee receiver");
        _;
    }

    event LiquidityAdded(uint256 amountUsdc, uint256 amountUsdt, uint256 amountStb, address receiver);
    event LiquidityRemoved(uint256 amountUsdc, uint256 amountUsdt, uint256 amountStb, address receiver);
    event Exchange(
        address token, uint256 amount, uint256 quoteAmount, uint256 fees, address receiver, address feeReceiver
    );
    event FeeBpsUpdate(uint16 baseFeeBps, uint16 maxBaseFeeBps);
    event OracleUpdate(address oldOracle, address newOracle);
    event AmpUpdate(uint256 amp);
    event FeeReceiverUpdate(address oldFeeReceiver, address newFeeReceiver);
    event CleanUp(address token, uint256 amount);

    constructor(address admin, address _usdc, address _usdt, uint256 _amp, address _oracle, address _feeReceiver)
        Ownable(admin)
    {
        usdc = _usdc;
        usdt = _usdt;
        amp = _amp;
        oracle = _oracle;
        feeReceiver = _feeReceiver;
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        require(_feeReceiver != address(0), "Zero address");
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdate(address(0), _feeReceiver);
    }

    function updateOracle(address _oracle) external onlyOwner {
        address oldOracle = oracle;
        oracle = _oracle;
        emit OracleUpdate(oldOracle, _oracle);
    }

    function updateAmp(uint256 _amp) external onlyOwner {
        require(_amp > 0, "Invalid amp");
        amp = _amp;
        emit AmpUpdate(_amp);
    }

    function getOracle() external view returns (address) {
        return oracle;
    }

    function pause() external onlyOwner {
        stabilizerPaused = true;
    }

    function unpause() external onlyOwner {
        stabilizerPaused = false;
    }

    function pauseSwap() external onlyOwner {
        swapPaused = true;
    }

    function unpauseSwap() external onlyOwner {
        swapPaused = false;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function A() public view returns (uint256) {
        return amp;
    }

    function addLiquidity(uint256 amountUsdc, uint256 amountUsdt, uint256 minAmountStb, address receiver)
        external
        whenNotPaused
        nonReentrant
    {
        require(amountUsdc > 0 || amountUsdt > 0, "Invalid amount");
        require(receiver != address(0), "Zero address");
        require(minAmountStb > 0, "Invalid Amount");

        uint256 oldUsdcBalance = usdcReserves;
        uint256 oldUsdtBalance = usdtReserves;
        uint256 stbSupply = totalSupply();

        usdcReserves += amountUsdc;
        usdtReserves += amountUsdt;

        uint256 amountStb = StabilizerLogic.calculateStbMintAmount(
            DataTypes.StbMintParams({
                oldUsdcReserve: oldUsdcBalance,
                oldUsdtReserve: oldUsdtBalance,
                newUsdcReserve: usdcReserves,
                newUsdtReserve: usdtReserves,
                stbSupply: stbSupply,
                a: amp,
                minLiquidity: MIN_LIQUIDITY
            })
        );

        require(amountStb > 0, "Insufficient STB amount");
        require(amountStb >= minAmountStb, "Insufficient STB amount");

        if (stbSupply == 0) {
            _mint(LOCKED_LIQUIDITY_HOLDER, MIN_LIQUIDITY);
        }

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amountUsdc);
        IERC20(usdt).safeTransferFrom(msg.sender, address(this), amountUsdt);

        _mint(receiver, amountStb);

        emit LiquidityAdded(amountUsdc, amountUsdt, amountStb, receiver);
    }

    function removeLiquidity(uint256 amountStb, uint256 minAmountUsdc, uint256 minAmountUsdt, address receiver)
        external
        whenNotPaused
        nonReentrant
    {
        require(amountStb > 0, "Invalid Stb amount");

        uint256 oldUsdcBalance = usdcReserves;
        uint256 oldUsdtBalance = usdtReserves;
        uint256 stbSupply = totalSupply();

        (uint256 amountUsdc, uint256 amountUsdt) = StabilizerLogic.calculateWithdrawAmounts(
            DataTypes.WithdrawParams({
                stbAmount: amountStb, usdcReserve: oldUsdcBalance, usdtReserve: oldUsdtBalance, stbSupply: stbSupply
            })
        );

        require(amountUsdc >= minAmountUsdc && amountUsdt >= minAmountUsdt, "Insufficient token amount");

        usdcReserves -= amountUsdc;
        usdtReserves -= amountUsdt;

        _burn(msg.sender, amountStb);

        IERC20(usdc).safeTransfer(receiver, amountUsdc);
        IERC20(usdt).safeTransfer(receiver, amountUsdt);

        emit LiquidityRemoved(amountUsdc, amountUsdt, amountStb, receiver);
    }

    function exchange(address token, uint256 amount, uint256 minAmountOut, address receiver)
        external
        ensureSwapStatus
        nonReentrant
    {
        require(token == usdc || token == usdt, "Invalid token");
        require(oracle != address(0), "Oracle not set");
        require(amount > 0, "Invalid amount");
        require(receiver != address(0), "Invalid receiver");
        require(usdcReserves > 0 && usdtReserves > 0, "Insufficient reserves");
        require(minAmountOut > 0, "Invalid Amount");

        (uint256 outAmount, uint256 fees) = StabilizerLogic.calculateExchangeAmount(
            DataTypes.ExchangeParams(amount, token, usdc, usdt, oracle, usdcReserves, usdtReserves, amp)
        );
        require(outAmount >= minAmountOut, "Insufficient output amount");
        _poolInteraction(token, amount, outAmount, fees, receiver);
        emit Exchange(token, amount, outAmount, fees, receiver, feeReceiver);
    }

    function _poolInteraction(address token, uint256 amount, uint256 outAmount, uint256 fee, address receiver) private {
        if (token == usdc) {
            usdcReserves += amount;
            usdtReserves -= (outAmount + fee);
            IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(usdt).safeTransfer(receiver, outAmount);
        } else {
            usdcReserves -= (outAmount + fee);
            usdtReserves += amount;
            IERC20(usdt).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(usdc).safeTransfer(receiver, outAmount);
        }
        _applyFee(fee, token == usdc ? usdt : usdc);
    }

    function _applyFee(uint256 fee, address token) private {
        require(fee > 0, "Zero fee");
        uint256 feeAmount = fee * 3000 / 10000;
        IERC20(token).safeTransfer(feeReceiver, feeAmount);
    }

    function clean(address token) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(token != usdc && token != usdt, "Invalid token");
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(owner(), balance);
        }
        emit CleanUp(token, balance);
    }

    function getStabilizerMatrix()
        external
        view
        returns (uint256 usdcReserveAmount, uint256 usdtReserveAmount, uint256 usdcPrice, uint256 usdtPrice)
    {
        usdcReserveAmount = usdcReserves;
        usdtReserveAmount = usdtReserves;
        usdcPrice = oracle == address(0) ? 0 : StabilizerOracle(oracle).getPrice(usdc);
        usdtPrice = oracle == address(0) ? 0 : StabilizerOracle(oracle).getPrice(usdt);
    }
}
