// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {Stabilizer} from "../src/Stabilizer.sol";
import {StabilizerOracle} from "../src/StabilizerOracle.sol";
import {StabilizerLogic} from "../src/engine/StabilizerLogic.sol";
import {StabilizerInvariant} from "../src/engine/Invariant.sol";
import {DataTypes} from "../src/Types/DataTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract StabilizerTest is Test {
    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");
    address internal feeReceiver = makeAddr("feeReceiver");

    MockERC20 internal usdc;
    MockERC20 internal usdt;
    StabilizerOracle internal oracle;
    Stabilizer internal stabilizer;

    uint256 internal constant AMP = 1000;
    uint256 internal constant MIN_LIQUIDITY = 1000;
    int256 internal constant PRICE = 1e8;

    uint256 internal constant INITIAL_USDC = 1_000_000e6;
    uint256 internal constant INITIAL_USDT = 1_000_000e6;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);

        MockV3Aggregator usdcFeed = new MockV3Aggregator(8, PRICE);
        MockV3Aggregator usdtFeed = new MockV3Aggregator(8, PRICE);

        address[] memory tokens = new address[](2);
        address[] memory feeds = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);
        feeds[0] = address(usdcFeed);
        feeds[1] = address(usdtFeed);

        oracle = new StabilizerOracle(feeds, tokens);

        stabilizer = new Stabilizer(admin, address(usdc), address(usdt), AMP, address(oracle), feeReceiver);

        usdc.mint(user, 10_000_000e6);
        usdt.mint(user, 10_000_000e6);
    }

    // --- setup helpers ---

    function test_constructor_setsOwnerAndAmp() public view {
        assertEq(stabilizer.owner(), admin);
        assertEq(stabilizer.A(), AMP);
        assertEq(stabilizer.decimals(), 6);
        assertEq(stabilizer.getOracle(), address(oracle));
    }

    function test_addLiquidity_firstDeposit_mintsStbAndLocksMinLiquidity() public {
        uint256 expectedStb = _expectedFirstMint(INITIAL_USDC, INITIAL_USDT);

        vm.startPrank(user);
        _approveTokens();

        vm.expectEmit(true, true, true, true);
        emit Stabilizer.LiquidityAdded(INITIAL_USDC, INITIAL_USDT, expectedStb, user);

        stabilizer.addLiquidity(INITIAL_USDC, INITIAL_USDT, expectedStb, user);
        vm.stopPrank();

        assertEq(stabilizer.balanceOf(user), expectedStb);
        assertEq(stabilizer.balanceOf(address(0xdead)), MIN_LIQUIDITY);
        assertEq(stabilizer.totalSupply(), expectedStb + MIN_LIQUIDITY);

        (uint256 usdcReserve, uint256 usdtReserve,,) = stabilizer.getStabilizerMatrix();
        assertEq(usdcReserve, INITIAL_USDC);
        assertEq(usdtReserve, INITIAL_USDT);
        assertEq(usdc.balanceOf(address(stabilizer)), INITIAL_USDC);
        assertEq(usdt.balanceOf(address(stabilizer)), INITIAL_USDT);
    }

    function test_addLiquidity_subsequentDeposit_mintsProportionalStb() public {
        _addBalancedLiquidity();

        uint256 addUsdc = 100_000e6;
        uint256 addUsdt = 100_000e6;
        uint256 supplyBefore = stabilizer.totalSupply();
        uint256 expectedMint = _expectedSubsequentMint(INITIAL_USDC, INITIAL_USDT, addUsdc, addUsdt, supplyBefore);

        vm.startPrank(user);
        stabilizer.addLiquidity(addUsdc, addUsdt, expectedMint, user);
        vm.stopPrank();

        assertEq(stabilizer.balanceOf(user), _expectedFirstMint(INITIAL_USDC, INITIAL_USDT) + expectedMint);
        (uint256 usdcReserve, uint256 usdtReserve,,) = stabilizer.getStabilizerMatrix();
        assertEq(usdcReserve, INITIAL_USDC + addUsdc);
        assertEq(usdtReserve, INITIAL_USDT + addUsdt);
    }

    function test_addLiquidity_revertsWhenPaused() public {
        _addBalancedLiquidity();
        vm.prank(admin);
        stabilizer.pause();

        vm.startPrank(user);
        vm.expectRevert("Pool is paused");
        stabilizer.addLiquidity(1e6, 1e6, 1, user);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsOnMinStbSlippage() public {
        vm.startPrank(user);
        _approveTokens();
        vm.expectRevert("Insufficient STB amount");
        stabilizer.addLiquidity(INITIAL_USDC, INITIAL_USDT, type(uint256).max, user);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsWhenBothAmountsZero() public {
        vm.startPrank(user);
        _approveTokens();
        vm.expectRevert("Invalid amount");
        stabilizer.addLiquidity(0, 0, 1, user);
        vm.stopPrank();
    }

    function test_removeLiquidity_returnsProRataTokens() public {
        uint256 stbMinted = _addBalancedLiquidity();
        uint256 burnAmount = stbMinted / 2;
        uint256 supply = stabilizer.totalSupply();

        (uint256 expectedUsdc, uint256 expectedUsdt) = StabilizerLogic.calculateWithdrawAmounts(
            DataTypes.WithdrawParams({
                stbAmount: burnAmount, usdcReserve: INITIAL_USDC, usdtReserve: INITIAL_USDT, stbSupply: supply
            })
        );

        uint256 userUsdcBefore = usdc.balanceOf(user);
        uint256 userUsdtBefore = usdt.balanceOf(user);

        vm.prank(user);
        stabilizer.removeLiquidity(burnAmount, expectedUsdc, expectedUsdt, user);

        assertEq(stabilizer.balanceOf(user), stbMinted - burnAmount);
        assertEq(usdc.balanceOf(user), userUsdcBefore + expectedUsdc);
        assertEq(usdt.balanceOf(user), userUsdtBefore + expectedUsdt);

        (uint256 usdcReserve, uint256 usdtReserve,,) = stabilizer.getStabilizerMatrix();
        assertEq(usdcReserve, INITIAL_USDC - expectedUsdc);
        assertEq(usdtReserve, INITIAL_USDT - expectedUsdt);
    }

    function test_removeLiquidity_revertsWhenPaused() public {
        uint256 stbMinted = _addBalancedLiquidity();
        vm.prank(admin);
        stabilizer.pause();

        vm.prank(user);
        vm.expectRevert("Pool is paused");
        stabilizer.removeLiquidity(stbMinted / 10, 1, 1, user);
    }

    function test_exchange_usdcToUsdt_deliversOutputAndUpdatesReserves() public {
        _addBalancedLiquidity();

        uint256 amountIn = 10_000e6;
        (uint256 expectedOut, uint256 expectedFee) = _expectedExchange(address(usdc), amountIn);

        uint256 userUsdtBefore = usdt.balanceOf(user);

        vm.prank(user);
        stabilizer.exchange(address(usdc), amountIn, expectedOut, user);

        assertEq(usdt.balanceOf(user), userUsdtBefore + expectedOut);

        (uint256 usdcReserve, uint256 usdtReserve,,) = stabilizer.getStabilizerMatrix();
        assertEq(usdcReserve, INITIAL_USDC + amountIn);
        assertEq(usdtReserve, INITIAL_USDT - expectedOut - expectedFee);
    }

    function test_exchange_usdtToUsdc_sendsFeeShareToFeeReceiver() public {
        _addSkewedLiquidity();

        uint256 amountIn = 50_000e6;
        (, uint256 expectedFee) = _expectedExchange(address(usdt), amountIn);
        uint256 expectedFeeShare = expectedFee * 3000 / 10_000;

        uint256 feeReceiverUsdtBefore = usdt.balanceOf(feeReceiver);

        vm.prank(user);
        stabilizer.exchange(address(usdt), amountIn, 1, user);

        assertEq(usdt.balanceOf(feeReceiver), feeReceiverUsdtBefore + expectedFeeShare);
    }

    function test_exchange_revertsWhenSwapPaused() public {
        _addBalancedLiquidity();
        vm.prank(admin);
        stabilizer.pauseSwap();

        vm.prank(user);
        vm.expectRevert("Swap is paused");
        stabilizer.exchange(address(usdc), 1_000e6, 1, user);
    }

    function test_exchange_revertsOnSlippage() public {
        _addBalancedLiquidity();

        vm.prank(user);
        vm.expectRevert("Insufficient output amount");
        stabilizer.exchange(address(usdc), 1_000e6, type(uint256).max, user);
    }

    function test_exchange_worksWhileLiquidityPaused() public {
        _addBalancedLiquidity();

        vm.prank(admin);
        stabilizer.pause();

        uint256 amountIn = 5_000e6;
        (uint256 expectedOut,) = _expectedExchange(address(usdc), amountIn);

        vm.prank(user);
        stabilizer.exchange(address(usdc), amountIn, expectedOut, user);

        assertGt(usdt.balanceOf(user), 0);
    }

    function test_exchange_revertsWhenReservesEmpty() public {
        vm.startPrank(user);
        _approveTokens();
        vm.expectRevert("Insufficient reserves");
        stabilizer.exchange(address(usdc), 1e6, 1, user);
        vm.stopPrank();
    }

    function test_admin_canUpdateOracleAndAmp() public {
        StabilizerOracle newOracle = oracle;

        vm.startPrank(admin);
        stabilizer.updateOracle(address(newOracle));
        stabilizer.updateAmp(200);
        vm.stopPrank();

        assertEq(stabilizer.getOracle(), address(newOracle));
        assertEq(stabilizer.A(), 200);
    }

    function test_admin_setFeeReceiver() public {
        address newReceiver = makeAddr("newFeeReceiver");

        vm.prank(admin);
        stabilizer.setFeeReceiver(newReceiver);

        _addBalancedLiquidity();

        uint256 amountIn = 10_000e6;
        (, uint256 expectedFee) = _expectedExchange(address(usdc), amountIn);

        vm.prank(user);
        stabilizer.exchange(address(usdc), amountIn, 1, user);

        assertEq(usdc.balanceOf(newReceiver), expectedFee * 3000 / 10_000);
    }

    function test_admin_clean_sweepsNonPoolToken() public {
        MockERC20 stray = new MockERC20("Stray", "STR", 6);
        stray.mint(address(stabilizer), 1_000e6);

        vm.prank(admin);
        stabilizer.clean(address(stray));

        assertEq(stray.balanceOf(admin), 1_000e6);
        assertEq(stray.balanceOf(address(stabilizer)), 0);
    }

    function test_getStabilizerMatrix_returnsPricesFromOracle() public view {
        (,, uint256 usdcPrice, uint256 usdtPrice) = stabilizer.getStabilizerMatrix();
        assertEq(usdcPrice, uint256(PRICE));
        assertEq(usdtPrice, uint256(PRICE));
    }

    // --- internal helpers ---

    function _addBalancedLiquidity() internal returns (uint256 stbMinted) {
        stbMinted = _expectedFirstMint(INITIAL_USDC, INITIAL_USDT);
        vm.startPrank(user);
        _approveTokens();
        stabilizer.addLiquidity(INITIAL_USDC, INITIAL_USDT, stbMinted, user);
        vm.stopPrank();
    }

    function _addSkewedLiquidity() internal {
        uint256 usdcAmt = 700_000e6;
        uint256 usdtAmt = 300_000e6;
        uint256 stbMinted = _expectedFirstMint(usdcAmt, usdtAmt);
        vm.startPrank(user);
        _approveTokens();
        stabilizer.addLiquidity(usdcAmt, usdtAmt, stbMinted, user);
        vm.stopPrank();
    }

    function _approveTokens() internal {
        usdc.approve(address(stabilizer), type(uint256).max);
        usdt.approve(address(stabilizer), type(uint256).max);
    }

    function _expectedFirstMint(uint256 amountUsdc, uint256 amountUsdt) internal pure returns (uint256) {
        uint256 d = StabilizerInvariant.getD(amountUsdc, amountUsdt, AMP);
        return d - MIN_LIQUIDITY;
    }

    function _expectedSubsequentMint(uint256 oldUsdc, uint256 oldUsdt, uint256 addUsdc, uint256 addUsdt, uint256 supply)
        internal
        pure
        returns (uint256)
    {
        return StabilizerLogic.calculateStbMintAmount(
            DataTypes.StbMintParams({
                oldUsdcReserve: oldUsdc,
                oldUsdtReserve: oldUsdt,
                newUsdcReserve: oldUsdc + addUsdc,
                newUsdtReserve: oldUsdt + addUsdt,
                stbSupply: supply,
                a: AMP,
                minLiquidity: MIN_LIQUIDITY
            })
        );
    }

    function _expectedExchange(address tokenIn, uint256 amountIn)
        internal
        view
        returns (uint256 outAmount, uint256 fee)
    {
        (uint256 usdcReserve, uint256 usdtReserve,,) = stabilizer.getStabilizerMatrix();
        return StabilizerLogic.calculateExchangeAmount(
            DataTypes.ExchangeParams({
                amount: amountIn,
                token: tokenIn,
                usdc: address(usdc),
                usdt: address(usdt),
                oracle: address(oracle),
                usdcReserve: usdcReserve,
                usdtReserve: usdtReserve,
                amp: AMP
            })
        );
    }
}
