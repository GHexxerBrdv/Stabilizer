// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {StabilizerOracle} from "../src/StabilizerOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DevOpsTools} from "../lib/foundry-devops/src/DevOpsTools.sol";

contract DeployOracle is Script {
    StabilizerOracle public oracle;

    function run() public {
        address usdc = DevOpsTools.get_most_recent_deployment("USDC", block.chainid); // 0x6162A003B0DbEccEA328924d0F2382eF07588eE5 on polygon amoy
        address usdt = DevOpsTools.get_most_recent_deployment("USDT", block.chainid); // 0x0e6eDa717c28536746594f4D2D0e699f639bdC06 on polygon amoy

        address[] memory tokens = new address[](2);
        tokens[0] = usdc;
        tokens[1] = usdt;

        address usdcFeed = 0x1b8739bB4CdF0089d07097A9Ae5Bd274b29C6F16;
        address usdtFeed = 0x3aC23DcB4eCfcBd24579e1f34542524d0E4eDeA8;

        address[] memory feeds = new address[](2);
        feeds[0] = usdcFeed;
        feeds[1] = usdtFeed;
        vm.startBroadcast();

        oracle = new StabilizerOracle(feeds, tokens);

        vm.stopBroadcast();

        console2.log("Oracle Address: ", address(oracle)); // 0x2B156643d89AFecd1E6c1a67df29a0E8b9C638D8

        uint256 price = oracle.getPrice(usdc);
        console2.log("USDC Price: ", price);

        price = oracle.getPrice(usdt);
        console2.log("USDT Price: ", price);
    }
}
