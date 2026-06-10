// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console2} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {Stabilizer} from "../../src/Stabilizer.sol";
import {StabilizerOracle} from "../../src/StabilizerOracle.sol";
import {StabilizerInvariant} from "../../src/engine/Invariant.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {StabilizerHandler} from "./handlers/StabilizerHandler.sol";

contract StabilizerInvariantTest is Test {
    address internal admin = makeAddr("admin");
    address internal feeReceiver = makeAddr("feeReceiver");

    MockERC20 internal usdc;
    MockERC20 internal usdt;
    StabilizerOracle internal oracle;
    Stabilizer internal stabilizer;
    StabilizerHandler internal handler;

    uint256 internal constant AMP = 100;
    int256 internal constant PRICE = 1e8; // $1.00 (8 decimals)

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);

        // Deploy feeds
        MockV3Aggregator usdcFeed = new MockV3Aggregator(8, PRICE);
        MockV3Aggregator usdtFeed = new MockV3Aggregator(8, PRICE);

        address[] memory tokens = new address[](2);
        address[] memory feeds = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);
        feeds[0] = address(usdcFeed);
        feeds[1] = address(usdtFeed);

        // Deploy oracle
        oracle = new StabilizerOracle(feeds, tokens);

        // Deploy pool
        stabilizer = new Stabilizer(admin, address(usdc), address(usdt), AMP, address(oracle), feeReceiver);

        // Deploy Handler
        handler = new StabilizerHandler(stabilizer, usdc, usdt);

        // Seed initial liquidity so pool math getD does not revert
        usdc.mint(address(handler), 10_000e6); // mint tokens to the handler
        usdt.mint(address(handler), 10_000e6);
        vm.startPrank(address(handler));
        stabilizer.addLiquidity(10_000e6, 10_000e6, 1, address(handler)); // add liquidity to the pool
        vm.stopPrank();

        // Register the handler contract as our target for stateful fuzzing
        targetContract(address(handler));

        // Exclude internal/helper contracts to make fuzzing cleaner
        excludeContract(address(stabilizer));
        excludeContract(address(usdc));
        excludeContract(address(usdt));
        excludeContract(address(oracle));
        excludeContract(address(usdcFeed));
        excludeContract(address(usdtFeed));
    }

    /// @dev Invariant 1: Stableswap bounds (2*sqrt(x*y) <= D <= x + y)
    function invariant_stableswap_bounds() public view {
        (uint256 usdcReserve, uint256 usdtReserve,,) = stabilizer.getStabilizerMatrix();

        if (usdcReserve == 0 || usdtReserve == 0) return;

        uint256 d = StabilizerInvariant.getD(usdcReserve, usdtReserve, AMP);

        // Constant Sum Bound (D <= x + y)
        assertGe(usdcReserve + usdtReserve, d, "D exceeds constant sum bound (x + y)");

        // Constant Product Bound (D >= 2 * sqrt(x * y))
        uint256 product = usdcReserve * usdtReserve;
        uint256 root = sqrt(product);
        assertGe(d, 2 * root, "D falls below constant product bound (2 * sqrt(x*y))");
    }

    /// @dev Invariant 3: Solvency (actual token balances >= pool reserves)
    function invariant_solvency() public view {
        (uint256 usdcReserve, uint256 usdtReserve,,) = stabilizer.getStabilizerMatrix();

        uint256 actualUsdc = usdc.balanceOf(address(stabilizer));
        uint256 actualUsdt = usdt.balanceOf(address(stabilizer));

        assertGe(actualUsdc, usdcReserve, "Pool USDC balance insolvent relative to reserves");
        assertGe(actualUsdt, usdtReserve, "Pool USDT balance insolvent relative to reserves");
    }

    /// @dev Log testing run statistics at the end of fuzzing
    function invariant_call_summary() public view {
        console2.log("--- Fuzz Run Stats ---");
        console2.log("Total Calls:     ", handler.numCalls());
        console2.log("Deposits:        ", handler.numDeposits());
        console2.log("Withdrawals:     ", handler.numWithdrawals());
        console2.log("Swaps:           ", handler.numSwaps());
    }

    // --- Helper math functions ---
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
