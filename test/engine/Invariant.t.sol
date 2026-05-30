// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console2} from "forge-std/Test.sol";
import {StabilizerInvariant} from "../../src/engine/Invariant.sol";

/// @dev External wrapper so `vm.expectRevert` sees an external call depth.
contract InvariantHarness {
    function getD(uint256 usdcBalance, uint256 usdtBalance, uint256 amp) external pure returns (uint256) {
        return StabilizerInvariant.getD(usdcBalance, usdtBalance, amp);
    }

    function getY(uint256 tokenBalanceOther, uint256 d, uint256 amp) external pure returns (uint256) {
        return StabilizerInvariant.getY(tokenBalanceOther, d, amp);
    }
}

contract InvariantTest is Test {
    InvariantHarness internal harness;

    uint256 internal constant AMP = 100;

    function setUp() public {
        harness = new InvariantHarness();
    }

    function test_getD_revertsWhenUsdcBalanceIsZero() public {
        vm.expectRevert();
        harness.getD(0, 1_000_000e6, AMP);
    }

    function test_getD_revertsWhenUsdtBalanceIsZero() public {
        vm.expectRevert();
        harness.getD(1_000_000e6, 0, AMP);
    }

    function test_getD_balancedReserves_equalsSumOfBalances() public view {
        uint256 balance = 1_000_000e6;
        uint256 d = harness.getD(balance, balance, AMP);
        console2.log("d", d);
        assertEq(d, balance + balance);
    }

    function test_getD_increasesWhenReservesIncrease() public view {
        uint256 dSmall = harness.getD(100_000e6, 100_000e6, AMP);
        uint256 dLarge = harness.getD(500_000e6, 500_000e6, AMP);
        console2.log("dLarge", dLarge);
        console2.log("dSmall", dSmall);
        assertGt(dLarge, dSmall);
    }

    function test_getY_revertsWhenCounterpartyBalanceIsZero() public {
        uint256 d = harness.getD(1_000_000e6, 1_000_000e6, AMP);
        vm.expectRevert();
        harness.getY(0, d, AMP);
    }

    function test_getY_atEquilibrium_recoversOtherReserveWithinOneWei() public view {
        uint256 usdc = 1_000_000e6;
        uint256 usdt = 750_000e6;
        uint256 d = harness.getD(usdc, usdt, AMP);
        assertApproxEqAbs(harness.getY(usdc, d, AMP), usdt, 1);
        assertApproxEqAbs(harness.getY(usdt, d, AMP), usdc, 1);
    }

    function test_getY_swapQuote_usdcIn_reducesUsdtReserve() public view {
        uint256 usdcReserve = 1_000_000e6;
        uint256 usdtReserve = 1_000_000e6;
        uint256 amountIn = 10_000e6;

        uint256 d = harness.getD(usdcReserve, usdtReserve, AMP);
        uint256 usdtAfter = harness.getY(usdcReserve + amountIn, d, AMP);
        uint256 quoteOut = usdtReserve - usdtAfter;
        console2.log("quoteOut", quoteOut);
        assertLt(usdtAfter, usdtReserve);
        assertGt(quoteOut, 0);
        assertLt(quoteOut, amountIn);
    }

    function test_getY_swapQuote_usdtIn_reducesUsdcReserve() public view {
        uint256 usdcReserve = 1_000_000e6;
        uint256 usdtReserve = 1_000_000e6;
        uint256 amountIn = 10_000e6;

        uint256 d = harness.getD(usdcReserve, usdtReserve, AMP);
        uint256 usdcAfter = harness.getY(usdtReserve + amountIn, d, AMP);
        uint256 quoteOut = usdcReserve - usdcAfter;
        console2.log("quoteOut", quoteOut);
        assertLt(usdcAfter, usdcReserve);
        assertGt(quoteOut, 0);
        assertLt(quoteOut, amountIn);
    }
}
