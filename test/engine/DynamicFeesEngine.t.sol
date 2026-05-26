// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console2} from "forge-std/Test.sol";
import {DynamicFeesEngine} from "../../src/engine/DynamicFeesEngine.sol";
import {StabilizerInvariant} from "../../src/engine/Invariant.sol";
import {DataTypes} from "../../src/Types/DataTypes.sol";

contract DynamicFeesEngineHarness {
    function calculateFinalFeeBps(DataTypes.FeeParams memory params) external pure returns (uint16) {
        return DynamicFeesEngine.calculateFinalFeeBps(params);
    }

    function calculateImbalance(uint256 usdcReserves, uint256 usdtReserves) external pure returns (uint256) {
        return DynamicFeesEngine.calculateImbalance(usdcReserves, usdtReserves);
    }

    function calculateImbalanceFeeBps(uint256 usdcReserves, uint256 usdtReserves) external pure returns (uint16) {
        return DynamicFeesEngine.calculateImbalanceFeeBps(usdcReserves, usdtReserves);
    }

    function calculateDeviation(uint256 usdcPrice, uint256 usdtPrice) external pure returns (uint256) {
        return DynamicFeesEngine.calculateDeviation(usdcPrice, usdtPrice);
    }

    function calculatePriceDeviationFeeBps(uint256 usdcPrice, uint256 usdtPrice) external pure returns (uint16) {
        return DynamicFeesEngine.calculatePriceDeviationFeeBps(usdcPrice, usdtPrice);
    }

    function getDirectionalState(
        uint256 usdcReserveBefore,
        uint256 usdtReserveBefore,
        uint256 usdcReserveAfter,
        uint256 usdtReserveAfter
    ) external pure returns (bool isStabilizing, uint16 imbalanceDelta) {
        return DynamicFeesEngine.getDirectionalState(
            usdcReserveBefore, usdtReserveBefore, usdcReserveAfter, usdtReserveAfter
        );
    }

    function getDirectionalAdjustment(uint16 imbalanceDelta, bool isStabilizing) external pure returns (int16) {
        return DynamicFeesEngine.getDirectionalAdjustment(imbalanceDelta, isStabilizing);
    }

    function applyFeeToQuote(uint256 quoteAmount, uint16 feeBps)
        external
        pure
        returns (uint256 outAmount, uint256 feeAmount)
    {
        feeAmount = quoteAmount * feeBps / 10_000;
        outAmount = quoteAmount - feeAmount;
    }
}

contract DynamicFeesEngineTest is Test {
    DynamicFeesEngineHarness internal harness;

    uint16 internal constant BASE_FEE_BPS = 2;
    uint16 internal constant MAX_FEE_BPS = 25;
    uint16 internal constant MAX_IMBALANCE_FEE_BPS = 15;
    uint16 internal constant MAX_PRICE_DEVIATION_FEE_BPS = 3;

    function setUp() public {
        harness = new DynamicFeesEngineHarness();
    }

    // --- imbalance bps ---

    function test_calculateImbalance_balancedPool_isZero() public view {
        assertEq(harness.calculateImbalance(1_000_000e6, 1_000_000e6), 0);
    }

    function test_calculateImbalance_emptyPool_isZero() public view {
        assertEq(harness.calculateImbalance(0, 0), 0);
    }

    function test_calculateImbalance_skewedPool_matchesFormula() public view {
        // |700k - 300k| / 1M * 10_000 = 4000 bps (40%)
        assertEq(harness.calculateImbalance(700_000e6, 300_000e6), 4000);
    }

    // --- imbalance fee ---

    function test_calculateImbalanceFeeBps_balancedPool_isZero() public view {
        assertEq(harness.calculateImbalanceFeeBps(1_000_000e6, 1_000_000e6), 0);
    }

    function test_calculateImbalanceFeeBps_skewedPool_matchesQuadraticFormula() public view {
        // 4000^2 / 2_500_000 = 6 bps
        assertEq(harness.calculateImbalanceFeeBps(700_000e6, 300_000e6), 6);
    }

    function test_calculateImbalanceFeeBps_extremeSkew_isCappedAt15() public view {
        assertEq(harness.calculateImbalanceFeeBps(950_000e6, 50_000e6), MAX_IMBALANCE_FEE_BPS);
    }

    function test_imbalanceFee_curveGrowth() public view {
        assertEq(harness.calculateImbalanceFeeBps(550e6, 450e6), 0);
        assertEq(harness.calculateImbalanceFeeBps(600e6, 400e6), 1);
        assertEq(harness.calculateImbalanceFeeBps(650e6, 350e6), 3);
        assertEq(harness.calculateImbalanceFeeBps(700e6, 300e6), 6);
        assertEq(harness.calculateImbalanceFeeBps(750e6, 250e6), 10);
    }

    function test_imbalanceFee_monotonicity() public view {
        uint16 fee1 = harness.calculateImbalanceFeeBps(550e6, 450e6);
        uint16 fee2 = harness.calculateImbalanceFeeBps(650e6, 350e6);
        uint16 fee3 = harness.calculateImbalanceFeeBps(750e6, 250e6);

        assertLt(fee1, fee2);
        assertLt(fee2, fee3);
    }

    // --- price deviation fee ---

    function test_calculateDeviation_equalPrices_isZero() public view {
        assertEq(harness.calculateDeviation(1e8, 1e8), 0);
    }

    function test_calculatePriceDeviationFeeBps_zeroPrice_isZero() public {
        vm.expectRevert();
        harness.calculatePriceDeviationFeeBps(0, 1e8);
        vm.expectRevert();
        harness.calculatePriceDeviationFeeBps(1e8, 0);
    }

    function test_calculatePriceDeviationFeeBps_onePercentDeviation() public view {
        // 1% deviation => 100 bps; fee = 100*100/20_000 = 0
        assertEq(harness.calculateDeviation(1e8, 99_000_000), 100);
        assertEq(harness.calculatePriceDeviationFeeBps(1e8, 99_000_000), 0);
    }

    function test_calculatePriceDeviationFeeBps_largeDeviation_isCappedAt3() public view {
        // ~3% deviation => 300 bps; raw fee = 300*300/20_000 = 4.5 => 3 bps cap
        assertEq(harness.calculatePriceDeviationFeeBps(1e8, 97_000_000), MAX_PRICE_DEVIATION_FEE_BPS);
    }

    // --- directional adjustment tiers ---

    function test_getDirectionalAdjustment_smallDelta_isZero() public view {
        assertEq(harness.getDirectionalAdjustment(249, true), int16(0));
        assertEq(harness.getDirectionalAdjustment(249, false), int16(0));
    }

    function test_getDirectionalAdjustment_mediumDelta_stabilizingDiscount() public view {
        assertEq(harness.getDirectionalAdjustment(250, true), int16(-1));
        assertEq(harness.getDirectionalAdjustment(999, true), int16(-1));
    }

    function test_getDirectionalAdjustment_mediumDelta_destabilizingSurcharge() public view {
        assertEq(harness.getDirectionalAdjustment(250, false), int16(2));
        assertEq(harness.getDirectionalAdjustment(999, false), int16(2));
    }

    function test_getDirectionalAdjustment_largeDelta_stabilizingDiscount() public view {
        assertEq(harness.getDirectionalAdjustment(1000, true), int16(-2));
        assertEq(harness.getDirectionalAdjustment(2499, true), int16(-2));
    }

    function test_getDirectionalAdjustment_largeDelta_destabilizingSurcharge() public view {
        assertEq(harness.getDirectionalAdjustment(1000, false), int16(5));
        assertEq(harness.getDirectionalAdjustment(2499, false), int16(5));
    }

    function test_getDirectionalAdjustment_maxDelta() public view {
        assertEq(harness.getDirectionalAdjustment(2500, true), int16(-5));
        assertEq(harness.getDirectionalAdjustment(2500, false), int16(10));
    }

    // --- directional state ---

    function test_getDirectionalState_rebalancingSwap_isStabilizing() public view {
        (bool isStabilizing, uint16 delta) = harness.getDirectionalState(
            700_000e6,
            300_000e6,
            650_000e6,
            350_000e6 // USDT-heavy side grows toward balance
        );
        assertTrue(isStabilizing);
        assertEq(delta, 1000);
    }

    function test_getDirectionalState_worseningSwap_isDestabilizing() public view {
        (bool isStabilizing, uint16 delta) =
            harness.getDirectionalState(
                700_000e6,
                300_000e6,
                750_000e6,
                250_000e6 // skew increases
            );
        assertFalse(isStabilizing);
        assertEq(delta, 1000);
    }

    function test_getDirectionalState_unchangedReserves_notStabilizingWithZeroDelta() public view {
        (bool isStabilizing, uint16 delta) =
            harness.getDirectionalState(1_000_000e6, 1_000_000e6, 1_000_000e6, 1_000_000e6);
        assertFalse(isStabilizing);
        assertEq(delta, 0);
    }

    // --- final fee bps ---

    function test_calculateFinalFeeBps_balancedPoolAndPrices_isBaseFeeOnly() public view {
        uint16 fee =
            harness.calculateFinalFeeBps(_feeParams(1_000_000e6, 1_000_000e6, 1_000_000e6, 1_000_000e6, 1e8, 1e8));
        assertEq(fee, BASE_FEE_BPS);
    }

    function test_calculateFinalFeeBps_skewedPool_addsImbalanceFee() public view {
        uint16 fee = harness.calculateFinalFeeBps(_feeParams(700_000e6, 300_000e6, 700_000e6, 300_000e6, 1e8, 1e8));
        console2.log("fee", fee);
        // core = 2 + 6 = 8, no directional change
        assertEq(fee, 8);
    }

    function test_calculateFinalFeeBps_oracleDeviation_addsPriceFee() public view {
        uint16 fee = harness.calculateFinalFeeBps(
            _feeParams(1_000_000e6, 1_000_000e6, 1_000_000e6, 1_000_000e6, 1e8, 97_000_000)
        );
        // core = 2 + 0 + 3 = 5
        assertEq(fee, 5);
    }

    function test_calculateFinalFeeBps_stabilizingRebalance_appliesDiscount() public view {
        uint16 fee = harness.calculateFinalFeeBps(_feeParams(700_000e6, 300_000e6, 650_000e6, 350_000e6, 1e8, 1e8));
        // core 8 - 2 directional = 6
        assertEq(fee, 6);
    }

    function test_calculateFinalFeeBps_destabilizingSwap_appliesSurcharge() public view {
        uint16 fee = harness.calculateFinalFeeBps(_feeParams(700_000e6, 300_000e6, 750_000e6, 250_000e6, 1e8, 1e8));
        // core 8; imbalance delta 1000 is in [1000, 2500) tier => +5 surcharge => 13 bps
        assertEq(fee, 13);
    }

    function test_calculateFinalFeeBps_neverBelowBaseFee() public view {
        // Balanced pool with large stabilizing delta would subtract 5, but floor is 2 bps
        uint16 fee = harness.calculateFinalFeeBps(_feeParams(600_000e6, 400_000e6, 500_000e6, 500_000e6, 1e8, 1e8));
        assertGe(fee, BASE_FEE_BPS);
    }

    function test_calculateFinalFeeBps_neverAboveMaxFee() public view {
        // core = 2 + 15 (imbalance) + 3 (price) = 20; destabilizing delta 3000 => +10 => capped at 25
        uint16 fee =
            harness.calculateFinalFeeBps(_feeParams(750_000e6, 250_000e6, 900_000e6, 100_000e6, 1e8, 90_000_000));
        assertLe(fee, MAX_FEE_BPS);
        assertEq(fee, MAX_FEE_BPS);
    }

    // --- integration: fee on swap quote (same math as StabilizerLogic) ---

    function test_swapFee_usdtIn_stabilizingSwap_appliesDiscountToQuote() public view {
        uint256 usdcReserve = 700_000e6;
        uint256 usdtReserve = 300_000e6;
        uint256 amountIn = 100_000e6;
        uint256 amp = 100;

        uint256 quoteAmount = _quoteUsdtIn(usdcReserve, usdtReserve, amountIn, amp);
        uint256 usdcAfter = usdcReserve - quoteAmount;
        uint256 usdtAfter = usdtReserve + amountIn;

        uint16 feeBps =
            harness.calculateFinalFeeBps(_feeParams(usdcReserve, usdtReserve, usdcAfter, usdtAfter, 1e8, 1e8));

        (uint256 outAmount, uint256 feeAmount) = harness.applyFeeToQuote(quoteAmount, feeBps);

        // core 8 bps minus 2 bps stabilizing discount (delta in [1000, 2500) tier)
        assertEq(feeBps, 6);
        assertEq(feeAmount, quoteAmount * feeBps / 10_000);
        assertEq(outAmount, quoteAmount - feeAmount);
        assertGt(feeAmount, 0);
        console2.log("feeAmount", feeAmount);
        assertLt(outAmount, quoteAmount);
    }

    function test_swapFee_usdcIn_destabilizingSwap_costsMoreThanUsdtInStabilizing() public view {
        uint256 usdcReserve = 700_000e6;
        uint256 usdtReserve = 300_000e6;
        uint256 amountIn = 100_000e6;
        uint256 amp = 100;

        uint256 quoteUsdcIn = _quoteUsdcIn(usdcReserve, usdtReserve, amountIn, amp);
        uint16 feeUsdcIn = harness.calculateFinalFeeBps(
            _feeParams(usdcReserve, usdtReserve, usdcReserve + amountIn, usdtReserve - quoteUsdcIn, 1e8, 1e8)
        );

        uint256 quoteUsdtIn = _quoteUsdtIn(usdcReserve, usdtReserve, amountIn, amp);
        uint16 feeUsdtIn = harness.calculateFinalFeeBps(
            _feeParams(usdcReserve, usdtReserve, usdcReserve - quoteUsdtIn, usdtReserve + amountIn, 1e8, 1e8)
        );

        // Adding USDC to the heavy side worsens skew (+5 bps); adding USDT rebalances (-2 bps)
        assertEq(feeUsdcIn, 13);
        assertEq(feeUsdtIn, 6);
        assertGt(feeUsdcIn, feeUsdtIn);
    }

    function test_swapFee_balancedPool_isCheapest() public view {
        uint256 reserve = 1_000_000e6;
        uint256 amountIn = 10_000e6;
        uint256 amp = 100;

        uint256 quote = _quoteUsdcIn(reserve, reserve, amountIn, amp);
        uint16 feeSkewed = harness.calculateFinalFeeBps(
            _feeParams(700_000e6, 300_000e6, 700_000e6 + amountIn, 300_000e6 - quote, 1e8, 1e8)
        );
        uint16 feeBalanced =
            harness.calculateFinalFeeBps(_feeParams(reserve, reserve, reserve + amountIn, reserve - quote, 1e8, 1e8));

        assertGt(feeSkewed, feeBalanced);
        assertEq(feeBalanced, BASE_FEE_BPS);
    }

    function _feeParams(
        uint256 usdcBefore,
        uint256 usdtBefore,
        uint256 usdcAfter,
        uint256 usdtAfter,
        uint256 usdcPrice,
        uint256 usdtPrice
    ) internal pure returns (DataTypes.FeeParams memory) {
        return DataTypes.FeeParams({
            usdcReserveBefore: usdcBefore,
            usdtReserveBefore: usdtBefore,
            usdcReserveAfter: usdcAfter,
            usdtReserveAfter: usdtAfter,
            usdcPrice: usdcPrice,
            usdtPrice: usdtPrice
        });
    }

    function _quoteUsdcIn(uint256 usdcReserve, uint256 usdtReserve, uint256 amountIn, uint256 amp)
        internal
        pure
        returns (uint256)
    {
        uint256 d = StabilizerInvariant.getD(usdcReserve, usdtReserve, amp);
        uint256 usdtAfter = StabilizerInvariant.getY(usdcReserve + amountIn, d, amp);
        return usdtReserve - usdtAfter;
    }

    function _quoteUsdtIn(uint256 usdcReserve, uint256 usdtReserve, uint256 amountIn, uint256 amp)
        internal
        pure
        returns (uint256)
    {
        uint256 d = StabilizerInvariant.getD(usdcReserve, usdtReserve, amp);
        uint256 usdcAfter = StabilizerInvariant.getY(usdtReserve + amountIn, d, amp);
        return usdcReserve - usdcAfter;
    }
}
