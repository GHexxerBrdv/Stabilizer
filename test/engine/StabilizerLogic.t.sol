// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {StabilizerLogic} from "../../src/engine/StabilizerLogic.sol";
import {StabilizerInvariant} from "../../src/engine/Invariant.sol";
import {DynamicFeesEngine} from "../../src/engine/DynamicFeesEngine.sol";
import {StabilizerOracle} from "../../src/StabilizerOracle.sol";
import {DataTypes} from "../../src/Types/DataTypes.sol";

contract StabilizerLogicHarness {
    function calculateStbMintAmount(DataTypes.StbMintParams memory params) external pure returns (uint256) {
        return StabilizerLogic.calculateStbMintAmount(params);
    }

    function calculateWithdrawAmounts(DataTypes.WithdrawParams memory params)
        external
        pure
        returns (uint256 usdcAmount, uint256 usdtAmount)
    {
        return StabilizerLogic.calculateWithdrawAmounts(params);
    }

    function getQuoteAmount(
        uint256 amount,
        address token,
        address usdc,
        uint256 usdcReserve,
        uint256 usdtReserve,
        uint256 amp
    ) external pure returns (uint256) {
        return StabilizerLogic.getQuoteAmount(amount, token, usdc, usdcReserve, usdtReserve, amp);
    }

    function calculateExchangeAmount(DataTypes.ExchangeParams memory params)
        external
        view
        returns (uint256 outAmount, uint256 fee)
    {
        return StabilizerLogic.calculateExchangeAmount(params);
    }
}

contract StabilizerLogicTest is Test {
    StabilizerLogicHarness internal harness;

    address internal usdc;
    address internal usdt;
    StabilizerOracle internal oracle;

    uint256 internal constant AMP = 1000;
    uint256 internal constant MIN_LIQUIDITY = 1000;
    int256 internal constant PRICE = 1e8;

    function setUp() public {
        harness = new StabilizerLogicHarness();

        usdc = makeAddr("usdc");
        usdt = makeAddr("usdt");

        MockV3Aggregator usdcFeed = new MockV3Aggregator(8, PRICE);
        MockV3Aggregator usdtFeed = new MockV3Aggregator(8, PRICE);

        address[] memory tokens = new address[](2);
        address[] memory feeds = new address[](2);
        tokens[0] = usdc;
        tokens[1] = usdt;
        feeds[0] = address(usdcFeed);
        feeds[1] = address(usdtFeed);

        oracle = new StabilizerOracle(feeds, tokens);
    }

    // --- STB mint ---

    function test_calculateStbMintAmount_firstDeposit_mintsDMinusMinLiquidity() public view {
        uint256 amountUsdc = 1_000_000e6;
        uint256 amountUsdt = 1_000_000e6;
        uint256 dNew = StabilizerInvariant.getD(amountUsdc, amountUsdt, AMP);

        uint256 minted = harness.calculateStbMintAmount(_mintParams(0, 0, amountUsdc, amountUsdt, 0));

        assertEq(minted, dNew - MIN_LIQUIDITY);
        assertGt(minted, 0);
    }

    function test_calculateStbMintAmount_firstDeposit_revertsWhenDTooSmall() public {
        vm.expectRevert("Insufficient initial deposit");
        harness.calculateStbMintAmount(_mintParams(0, 0, 500, 500, 0));
    }

    function test_calculateStbMintAmount_subsequentDeposit_mintsProportionalToDIncrease() public view {
        uint256 oldUsdc = 1_000_000e6;
        uint256 oldUsdt = 1_000_000e6;
        uint256 stbSupply = 2_000_000e6 - MIN_LIQUIDITY;

        uint256 newUsdc = 1_100_000e6;
        uint256 newUsdt = 1_100_000e6;

        uint256 dOld = StabilizerInvariant.getD(oldUsdc, oldUsdt, AMP);
        uint256 dNew = StabilizerInvariant.getD(newUsdc, newUsdt, AMP);
        uint256 expected = (dNew - dOld) * stbSupply / dOld;

        uint256 minted = harness.calculateStbMintAmount(_mintParams(oldUsdc, oldUsdt, newUsdc, newUsdt, stbSupply));

        assertEq(minted, expected);
        assertApproxEqRel(minted, stbSupply / 10, 1e15);
    }

    function test_calculateStbMintAmount_subsequentDeposit_revertsWhenDDecreases() public {
        vm.expectRevert("Invalid D");
        harness.calculateStbMintAmount(_mintParams(1_000_000e6, 1_000_000e6, 900_000e6, 900_000e6, 1_000_000e6));
    }

    // --- withdraw ---

    function test_calculateWithdrawAmounts_returnsProRataShares() public view {
        (uint256 usdcOut, uint256 usdtOut) = harness.calculateWithdrawAmounts(
            DataTypes.WithdrawParams({
                stbAmount: 500_000e6, usdcReserve: 1_000_000e6, usdtReserve: 2_000_000e6, stbSupply: 1_000_000e6
            })
        );

        assertEq(usdcOut, 500_000e6);
        assertEq(usdtOut, 1_000_000e6);
    }

    function test_calculateWithdrawAmounts_revertsWhenStbZero() public {
        vm.expectRevert("Invalid Stb amount");
        harness.calculateWithdrawAmounts(
            DataTypes.WithdrawParams({stbAmount: 0, usdcReserve: 1e6, usdtReserve: 1e6, stbSupply: 1e6})
        );
    }

    function test_calculateWithdrawAmounts_revertsWhenStbExceedsSupply() public {
        vm.expectRevert("Invalid Stb amount");
        harness.calculateWithdrawAmounts(
            DataTypes.WithdrawParams({stbAmount: 2e6, usdcReserve: 1e6, usdtReserve: 1e6, stbSupply: 1e6})
        );
    }

    function test_calculateWithdrawAmounts_revertsWhenReserveZero() public {
        vm.expectRevert("Invalid token balances");
        harness.calculateWithdrawAmounts(
            DataTypes.WithdrawParams({stbAmount: 1, usdcReserve: 0, usdtReserve: 1e6, stbSupply: 1e6})
        );
    }

    function test_calculateWithdrawAmounts_revertsWhenUsdcPayoutZero() public {
        vm.expectRevert("Invalid usdc amount");
        harness.calculateWithdrawAmounts(
            DataTypes.WithdrawParams({stbAmount: 1, usdcReserve: 1_000_000, usdtReserve: 1_000_000e6, stbSupply: 1e12})
        );
    }

    // --- quote ---

    function test_getQuoteAmount_usdcIn_matchesInvariantMath() public view {
        uint256 quote = harness.getQuoteAmount(10_000e6, usdc, usdc, 1_000_000e6, 1_000_000e6, AMP);
        uint256 d = StabilizerInvariant.getD(1_000_000e6, 1_000_000e6, AMP);
        uint256 usdtAfter = StabilizerInvariant.getY(1_010_000e6, d, AMP);
        assertEq(quote, 1_000_000e6 - usdtAfter);
    }

    function test_getQuoteAmount_usdtIn_matchesInvariantMath() public view {
        uint256 quote = harness.getQuoteAmount(10_000e6, usdt, usdc, 1_000_000e6, 1_000_000e6, AMP);
        uint256 d = StabilizerInvariant.getD(1_000_000e6, 1_000_000e6, AMP);
        uint256 usdcAfter = StabilizerInvariant.getY(1_010_000e6, d, AMP);
        assertEq(quote, 1_000_000e6 - usdcAfter);
    }

    // --- exchange ---

    function test_calculateExchangeAmount_revertsWhenAmountZero() public {
        vm.expectRevert("Invalid amount");
        harness.calculateExchangeAmount(_exchangeParams(0, usdc, 1_000_000e6, 1_000_000e6));
    }

    function test_calculateExchangeAmount_balancedPool_feeIsBaseBpsOnQuote() public view {
        uint256 amountIn = 10_000e6;
        uint256 quote = harness.getQuoteAmount(amountIn, usdc, usdc, 1_000_000e6, 1_000_000e6, AMP);

        (uint256 outAmount, uint256 fee) =
            harness.calculateExchangeAmount(_exchangeParams(amountIn, usdc, 1_000_000e6, 1_000_000e6));

        assertEq(fee, quote * 2 / 10_000);
        assertEq(outAmount, quote - fee);
        assertEq(outAmount + fee, quote);
    }

    function test_calculateExchangeAmount_skewedPool_stabilizingUsdtIn_cheaperThanUsdcIn() public view {
        uint256 usdcReserve = 700_000e6;
        uint256 usdtReserve = 300_000e6;
        uint256 amountIn = 100_000e6;

        (uint256 outUsdtIn,) =
            harness.calculateExchangeAmount(_exchangeParams(amountIn, usdt, usdcReserve, usdtReserve));
        (uint256 outUsdcIn,) =
            harness.calculateExchangeAmount(_exchangeParams(amountIn, usdc, usdcReserve, usdtReserve));

        assertGt(outUsdtIn, outUsdcIn);
    }

    function test_calculateExchangeAmount_feeMatchesDynamicFeesEngine() public view {
        uint256 usdcReserve = 700_000e6;
        uint256 usdtReserve = 300_000e6;
        uint256 amountIn = 50_000e6;

        uint256 quote = harness.getQuoteAmount(amountIn, usdt, usdc, usdcReserve, usdtReserve, AMP);

        uint256 usdcAfter = usdcReserve - quote;
        uint256 usdtAfter = usdtReserve + amountIn;

        uint16 feeBps = DynamicFeesEngine.calculateFinalFeeBps(
            DataTypes.FeeParams({
                usdcReserveBefore: usdcReserve,
                usdtReserveBefore: usdtReserve,
                usdcReserveAfter: usdcAfter,
                usdtReserveAfter: usdtAfter,
                usdcPrice: uint256(PRICE),
                usdtPrice: uint256(PRICE)
            })
        );

        (uint256 outAmount, uint256 fee) =
            harness.calculateExchangeAmount(_exchangeParams(amountIn, usdt, usdcReserve, usdtReserve));

        assertEq(feeBps, 6);
        assertEq(fee, quote * feeBps / 10_000);
        assertEq(outAmount, quote - fee);
    }

    function test_calculateExchangeAmount_oraclePriceDeviation_increasesFee() public {
        uint256 amountIn = 10_000e6;
        uint256 reserve = 1_000_000e6;

        (uint256 outEqualPrices, uint256 feeEqual) =
            harness.calculateExchangeAmount(_exchangeParams(amountIn, usdc, reserve, reserve));

        MockV3Aggregator usdtFeed = new MockV3Aggregator(8, 97_000_000);
        address[] memory tokens = new address[](2);
        address[] memory feeds = new address[](2);
        tokens[0] = usdc;
        tokens[1] = usdt;
        feeds[0] = oracle.getPriceFeed(usdc);
        feeds[1] = address(usdtFeed);
        StabilizerOracle deviatingOracle = new StabilizerOracle(feeds, tokens);

        (uint256 outDeviant, uint256 feeDeviant) = harness.calculateExchangeAmount(
            DataTypes.ExchangeParams({
                amount: amountIn,
                token: usdc,
                usdc: usdc,
                usdt: usdt,
                oracle: address(deviatingOracle),
                usdcReserve: reserve,
                usdtReserve: reserve,
                amp: AMP
            })
        );

        assertGt(feeDeviant, feeEqual);
        assertLt(outDeviant, outEqualPrices);
    }

    function _mintParams(uint256 oldUsdc, uint256 oldUsdt, uint256 newUsdc, uint256 newUsdt, uint256 stbSupply)
        internal
        pure
        returns (DataTypes.StbMintParams memory)
    {
        return DataTypes.StbMintParams({
            oldUsdcReserve: oldUsdc,
            oldUsdtReserve: oldUsdt,
            newUsdcReserve: newUsdc,
            newUsdtReserve: newUsdt,
            stbSupply: stbSupply,
            a: AMP,
            minLiquidity: MIN_LIQUIDITY
        });
    }

    function _exchangeParams(uint256 amount, address token, uint256 usdcReserve, uint256 usdtReserve)
        internal
        view
        returns (DataTypes.ExchangeParams memory)
    {
        return DataTypes.ExchangeParams({
            amount: amount,
            token: token,
            usdc: usdc,
            usdt: usdt,
            oracle: address(oracle),
            usdcReserve: usdcReserve,
            usdtReserve: usdtReserve,
            amp: AMP
        });
    }
}
