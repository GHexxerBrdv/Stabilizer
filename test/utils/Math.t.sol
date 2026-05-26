// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Math} from "../../src/utils/Math.sol";

contract MathTest is Test {
    function test_min_returnsSmallerWhenFirstIsLess() public pure {
        assertEq(Math.min(3, 7), 3);
    }

    function test_min_returnsSmallerWhenSecondIsLess() public pure {
        assertEq(Math.min(10, 4), 4);
    }

    function test_min_returnsEitherWhenEqual() public pure {
        assertEq(Math.min(5, 5), 5);
    }

    function test_max_returnsLargerWhenFirstIsGreater() public pure {
        assertEq(Math.max(9, 2), 9);
    }

    function test_max_returnsLargerWhenSecondIsGreater() public pure {
        assertEq(Math.max(1, 8), 8);
    }

    function test_max_returnsEitherWhenEqual() public pure {
        assertEq(Math.max(6, 6), 6);
    }

    function test_absDiff_whenFirstIsGreater() public pure {
        assertEq(Math.absDiff(100, 40), 60);
    }

    function test_absDiff_whenSecondIsGreater() public pure {
        assertEq(Math.absDiff(12, 50), 38);
    }

    function test_absDiff_whenEqual() public pure {
        assertEq(Math.absDiff(0, 0), 0);
    }
}
