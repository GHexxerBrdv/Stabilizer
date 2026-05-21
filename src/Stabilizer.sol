// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StabilizerInvariant} from "./Invariant.sol";
import {StabilizerOracle} from "./StabilizerOracle.sol";
import {DynamicFeesEngine} from "./DynamicFeesEngine.sol";
import {StabilizerLogic} from "./StabilizerLogic.sol";
import {Math} from "./Math.sol";

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
    uint16 private feeBps;
    uint16 private maxFeeBps;
    bool private stabilizerPaused;
    bool private swapPaused;

    uint256 usdcReserves;
    uint256 usdtReserves;

    uint256 private amp;

    uint256 private constant MIN_LIQUIDITY = 1000;

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

    event Stabilized(uint48 timestamp);
    event LiquidityAdded(uint256 amountUsdc, uint256 amountUsdt, uint256 amountStb, address receiver);
    event LiquidityRemoved(uint256 amountUsdc, uint256 amountUsdt, uint256 amountStb, address receiver);
    event Exchange(
        address token, uint256 amount, uint256 quoteAmount, uint256 fees, address receiver, address feeReceiver
    );
    event FeeBpsUpdate(uint16 feeBps, uint16 maxFeeBps);
    event OracleUpdate(address oldOracle, address newOracle);
    event AmpUpdate(uint256 amp);
    event FeeReceiverUpdate(address oldFeeReceiver, address newFeeReceiver);

    constructor(
        address admin,
        address _usdc,
        address _usdt,
        uint16 _baseFees,
        uint16 _maxFees,
        uint256 _amp,
        address _oracle,
        address _feeReceiver
    ) Ownable(admin) {
        usdc = _usdc;
        usdt = _usdt;
        feeBps = _baseFees;
        maxFeeBps = _maxFees;
        amp = _amp;
        oracle = _oracle;
        feeReceiver = _feeReceiver;
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        require(_feeReceiver != address(0), "Zero address");
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdate(address(0), _feeReceiver);
    }

    function updateFeeBps(uint16 _feeBps, uint16 _maxFeeBps) external onlyOwner {
        require(_feeBps > 0 && _maxFeeBps > 0, "Invalid feeBps");
        require(_feeBps <= _maxFeeBps, "Invalid feeBps");
        feeBps = _feeBps;
        maxFeeBps = _maxFeeBps;
        emit FeeBpsUpdate(_feeBps, _maxFeeBps);
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
    {
        require(amountUsdc > 0 || amountUsdt > 0, "Invalid amount");
        require(receiver != address(0), "Zero address");
        require(minAmountStb > 0, "Invalid Amount");

        uint256 oldUsdcBalance = usdcReserves;
        uint256 oldUsdtBalance = usdtReserves;
        uint256 stbSupply = totalSupply();

        usdcReserves += amountUsdc;
        usdtReserves += amountUsdt;

        uint256 amountStb = oldUsdcBalance.calculateStbMintAmount(
            oldUsdtBalance, usdcReserves, usdtReserves, stbSupply, amp, MIN_LIQUIDITY
        );
        require(amountStb > 0, "Insufficient STB amount");
        require(amountStb >= minAmountStb, "Insufficient STB amount");

        if (stbSupply == 0) {
            _mint(address(0), MIN_LIQUIDITY);
        }

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amountUsdc);
        IERC20(usdt).safeTransferFrom(msg.sender, address(this), amountUsdt);

        _mint(receiver, amountStb);

        emit LiquidityAdded(amountUsdc, amountUsdt, amountStb, receiver);
    }

    function removeLiquidity(uint256 amountStb, uint256 minAmountUsdc, uint256 minAmountUsdt, address receiver)
        external
        whenNotPaused
    {
        require(amountStb > 0, "Invalid Stb amount");

        uint256 oldUsdcBalance = usdcReserves;
        uint256 oldUsdtBalance = usdtReserves;
        uint256 stbSupply = totalSupply();
        (uint256 amountUsdc, uint256 amountUsdt) =
            amountStb.calculateWithdrawAmounts(oldUsdcBalance, oldUsdtBalance, stbSupply);

        require(amountUsdc >= minAmountUsdc && amountUsdt >= minAmountUsdt, "Insufficient token amount");

        usdcReserves -= amountUsdc;
        usdtReserves -= amountUsdt;

        _burn(msg.sender, amountStb);

        IERC20(usdc).safeTransfer(receiver, amountUsdc);
        IERC20(usdt).safeTransfer(receiver, amountUsdt);

        emit LiquidityRemoved(amountUsdc, amountUsdt, amountStb, receiver);
    }

    function exchange(address token, uint256 amount, uint256 minAmountOut, address receiver) external ensureSwapStatus {
        require(token == usdc || token == usdt, "Invalid token");
        require(oracle != address(0), "Oracle not set");
        require(amount > 0, "Invalid amount");
        require(receiver != address(0), "Invalid receiver");
        require(usdcReserves > 0 && usdtReserves > 0, "Insufficient reserves");

        (uint256 quoteAmount, uint256 fees) = amount.calculationExchangeAmount(
            token, usdc, usdt, oracle, usdcReserves, usdtReserves, amp, feeBps, maxFeeBps
        );
        require(quoteAmount >= minAmountOut, "Insufficient output amount");
        _poolInteraction(token, amount, quoteAmount, fees, receiver);
        emit Exchange(token, amount, quoteAmount, fees, receiver, feeReceiver);
    }

    function _poolInteraction(address token, uint256 amount, uint256 quoteAmount, uint256 fee, address receiver)
        private
    {
        if (token == usdc) {
            usdcReserves += amount;
            usdtReserves -= (quoteAmount + fee);
            IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(usdt).safeTransfer(receiver, quoteAmount);
            IERC20(usdt).safeTransfer(feeReceiver, fee);
        } else {
            usdcReserves -= (quoteAmount + fee);
            usdtReserves += amount;
            IERC20(usdt).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(usdc).safeTransfer(receiver, quoteAmount);
            IERC20(usdc).safeTransfer(feeReceiver, fee);
        }
    }

    function _getDynamicFee() private view returns (uint16) {
        uint256 usdcPrice = StabilizerOracle(oracle).getPrice(usdc);
        uint256 usdtPrice = StabilizerOracle(oracle).getPrice(usdt);

        return usdcReserves.calculateDynamicFee(usdtReserves, usdcPrice, usdtPrice, feeBps, maxFeeBps);
    }

    function stabilize() external onlyOwnerOrFeeReceiver {
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
        uint256 usdtBalance = IERC20(usdt).balanceOf(address(this));

        if (usdcBalance > usdcReserves) {
            uint256 extraUsdc = usdcBalance - usdcReserves;
            IERC20(usdc).safeTransfer(feeReceiver, extraUsdc);
        }
        if (usdtBalance > usdtReserves) {
            uint256 extraUsdt = usdtBalance - usdtReserves;
            IERC20(usdt).safeTransfer(feeReceiver, extraUsdt);
        }
        emit Stabilized(uint48(block.timestamp));
    }

    function getCurrentDynamicFees() external view returns (uint16) {
        require(oracle != address(0), "Invalid oracle");
        return _getDynamicFee();
    }

    function getStabilizerMatrix()
        external
        view
        returns (
            uint256 usdcReserveAmount,
            uint256 usdtReserveAmount,
            uint16 currentDynamicFee,
            uint256 usdcPrice,
            uint256 usdtPrice
        )
    {
        require(oracle != address(0), "Oracle not set");
        usdcReserveAmount = usdcReserves;
        usdtReserveAmount = usdtReserves;
        currentDynamicFee = _getDynamicFee();
        usdcPrice = StabilizerOracle(oracle).getPrice(usdc);
        usdtPrice = StabilizerOracle(oracle).getPrice(usdt);
    }
}
