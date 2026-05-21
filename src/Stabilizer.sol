// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StabilizerMath} from "./StabilizerMath.sol";
import {StabilizerOracle} from "./StabilizerOracle.sol";
import {DynamicFeesController} from "./DynamicFeesController.sol";

contract Stabilizer is ERC20("Stabilizer", "STB"), Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

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

    modifier whenNotPaused() {
        require(!stabilizerPaused, "Pool is paused");
        _;
    }

    modifier ensureSwapStatus() {
        require(!swapPaused, "Swap is paused");
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

    constructor(
        address admin,
        address _usdc,
        address _usdt,
        uint16 _baseFees,
        uint16 _maxFees,
        uint256 _amp,
        address _oracle
    ) Ownable(admin) {
        usdc = _usdc;
        usdt = _usdt;
        feeBps = _baseFees;
        maxFeeBps = _maxFees;
        amp = _amp;
        oracle = _oracle;
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
        nonReentrant
    {
        require(amountUsdc > 0 || amountUsdt > 0, "Invalid amount");
        require(receiver != address(0), "Zero address");
        require(minAmountStb > 0, "Invalid Amount");

        uint256 oldUsdcBalance = usdcReserves;
        uint256 oldUsdtBalance = usdtReserves;

        usdcReserves += amountUsdc;
        usdtReserves += amountUsdt;

        uint256 amountStb = calculateStbMintAmount(oldUsdcBalance, oldUsdtBalance);
        require(amountStb > 0, "Insufficient STB amount");
        require(amountStb >= minAmountStb, "Insufficient STB amount");

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

        (uint256 amountUsdc, uint256 amountUsdt) = calculateWithdrawAmounts(amountStb, oldUsdcBalance, oldUsdtBalance);

        require(amountUsdc >= minAmountUsdc && amountUsdt >= minAmountUsdt, "Insufficient token amount");

        usdcReserves -= amountUsdc;
        usdtReserves -= amountUsdt;

        _burn(receiver, amountStb);

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

        (uint256 quoteAmount, uint256 fees) = calculateExchangeAmount(token, amount);
        require(quoteAmount >= minAmountOut, "Insufficient output amount");
        _poolInteraction(token, amount, quoteAmount, fees, receiver);
        emit Exchange(token, amount, quoteAmount, fees, receiver, feeReceiver);
    }

    function _poolInteraction(address token, uint256 amount, uint256 quoteAmount, uint256 fees, address receiver)
        private
    {
        if (token == usdc) {
            usdcReserves += (amount - fees);
            usdtReserves -= quoteAmount;
            IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(usdt).safeTransfer(receiver, quoteAmount);
        } else {
            usdcReserves -= quoteAmount;
            usdtReserves += (amount - fees);
            IERC20(usdt).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(usdc).safeTransfer(receiver, quoteAmount);
        }
    }

    function calculateStbMintAmount(uint256 oldUsdcBalance, uint256 oldUsdtBalance) private returns (uint256) {
        uint256 a = A();
        uint256 stbSupply = totalSupply();
        uint256 newUsdcBalance = usdcReserves;
        uint256 newUsdtBalance = usdtReserves;

        uint256 d = StabilizerMath.getD(newUsdcBalance, newUsdtBalance, a);
        if (stbSupply == 0) {
            require(d > 1000, "Insufficient initial deposit");
            _mint(address(0), 1000);
            return d - 1000;
        }
        uint256 dOld = StabilizerMath.getD(oldUsdcBalance, oldUsdtBalance, a);
        uint256 dNew = StabilizerMath.getD(newUsdcBalance, newUsdtBalance, a);

        require(dNew >= dOld, "Invalid D");

        uint256 dDiff = dNew - dOld;

        uint256 stbAmount = dDiff * stbSupply / dOld;
        return stbAmount;
    }

    function calculateWithdrawAmounts(uint256 amountStb, uint256 usdcBalance, uint256 usdtBalance)
        private
        view
        returns (uint256 usdcAmount, uint256 usdtAmount)
    {
        uint256 stbSupply = totalSupply();
        require(amountStb > 0, "Invalid Stb amount");
        require(amountStb <= stbSupply, "Invalid Stb amount");
        require(usdcBalance > 0 && usdtBalance > 0, "Invalid token balances");
        usdcAmount = amountStb * usdcBalance / stbSupply;
        require(usdcAmount > 0, "Invalid usdc amount");
        usdtAmount = amountStb * usdtBalance / stbSupply;
        require(usdtAmount > 0, "Invalid usdt amount");
    }

    function calculateExchangeAmount(address token, uint256 amount) private view returns (uint256, uint256) {
        require(amount > 0, "Invalid amount");
        uint256 usdcBalance = usdcReserves;
        uint256 usdtBalance = usdtReserves;
        uint256 a = A();
        uint256 d = StabilizerMath.getD(usdcBalance, usdtBalance, a);

        uint16 dynamicFee = _getDynamicFee();
        uint256 fees = amount * dynamicFee / 10000;
        uint256 remainingAmount = amount - fees;

        uint256 newTokenAmount = token == usdc ? usdcBalance + remainingAmount : usdtBalance + remainingAmount;
        uint256 newReserveOut = StabilizerMath.getY(newTokenAmount, d, a);
        uint256 quoteAmount = token == usdc ? usdtBalance - newReserveOut : usdcBalance - newReserveOut;
        return (quoteAmount, fees);
    }

    function _getDynamicFee() private view returns (uint16) {
        uint256 usdcPrice = StabilizerOracle(oracle).getPrice(usdc);
        uint256 usdtPrice = StabilizerOracle(oracle).getPrice(usdt);

        return
            DynamicFeesController.calculateDynamicFee(
                usdcReserves, usdtReserves, usdcPrice, usdtPrice, feeBps, maxFeeBps
            );
    }

    modifier onlyOwnerOrFeeReceiver() {
        require(msg.sender == owner() || msg.sender == feeReceiver, "Not owner or fee receiver");
        _;
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
