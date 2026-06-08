// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {StabilizerOracle} from "../src/StabilizerOracle.sol";
import {Stabilizer} from "../src/Stabilizer.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract DeployStabilizer is Script {
    Stabilizer public stabilizer;

    function run() public {
        (address oracle, address usdc, address usdt) = fetchDeployedAddress();
        uint256 amp = 500;
        address admin = vm.envAddress("ADMIN");

        vm.startBroadcast();

        stabilizer = new Stabilizer(admin, usdc, usdt, amp, oracle, admin);

        vm.stopBroadcast();

        console2.log("Stabilizer Address: ", address(stabilizer)); // 0xEb1598206b58D87d671d137228712d8919914D16
    }

    function fetchDeployedAddress() private view returns (address, address, address) {
        address oracle = DevOpsTools.get_most_recent_deployment("StabilizerOracle", block.chainid); // 0x2B156643d89AFecd1E6c1a67df29a0E8b9C638D8
        address usdc = DevOpsTools.get_most_recent_deployment("USDC", block.chainid); // 0x6162A003B0DbEccEA328924d0F2382eF07588eE5
        address usdt = DevOpsTools.get_most_recent_deployment("USDT", block.chainid); // 0x0e6eDa717c28536746594f4D2D0e699f639bdC06
        return (oracle, usdc, usdt);
    }
}
