// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {USDC} from "./mocks/Usdc.sol";
import {USDT} from "./mocks/Usdt.sol";

contract DeployTokens is Script {
    function run() public {
        vm.startBroadcast();
        USDC usdc = new USDC();
        USDT usdt = new USDT();
        vm.stopBroadcast();

        console2.log("USDC Address: ", address(usdc));
        console2.log("USDT Address: ", address(usdt));
    }
}
