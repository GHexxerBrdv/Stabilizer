// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {Stabilizer} from "../src/Stabilizer.sol";
import {USDC} from "./mocks/Usdc.sol";
import {USDT} from "./mocks/Usdt.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract Interactions is Script {
    Stabilizer public stabilizer;
    USDC public usdc;
    USDT public usdt;

    address admin = vm.envAddress("ADMIN");
    address user = makeAddr("receiver");

    function run() public {
        (address usdcAddress, address usdtAddress, address stabilizerAddress) = fetchDeployedAddress();
        stabilizer = Stabilizer(stabilizerAddress);
        usdc = USDC(usdcAddress);
        usdt = USDT(usdtAddress);

        allInter();
    }

    function fetchDeployedAddress() private view returns (address, address, address) {
        address usdc = DevOpsTools.get_most_recent_deployment("USDC", block.chainid);
        address usdt = DevOpsTools.get_most_recent_deployment("USDT", block.chainid);
        address stabilizer = DevOpsTools.get_most_recent_deployment("Stabilizer", block.chainid);
        return (usdc, usdt, stabilizer);
    }

    function addLiquidity() public {
        vm.startBroadcast();

        usdc.mint(admin, 50000e6);
        usdt.mint(admin, 50000e6);

        usdc.approve(address(stabilizer), 50000e6);
        usdt.approve(address(stabilizer), 50000e6);
        stabilizer.addLiquidity(50000e6, 50000e6, (50000e6 - 1000), admin);

        vm.stopBroadcast();
        uint256 stabilizerBalance = stabilizer.balanceOf(admin);
        console2.log("Stabilizer Balance: ", stabilizerBalance);
    }

    function removeLiquidity() public {
        uint256 amountStb = stabilizer.balanceOf(admin);
        console2.log("Amount STB: ", amountStb);
        vm.startBroadcast();
        stabilizer.removeLiquidity(amountStb, 1e6, 1e6, admin);
        vm.stopBroadcast();
        uint256 stabilizerBalance = stabilizer.balanceOf(admin);
        console2.log("Stabilizer Balance: ", stabilizerBalance);
    }

    function exchange() public {
        vm.startBroadcast();
        usdt.approve(address(stabilizer), 100e6);
        stabilizer.exchange(address(usdt), 100e6, 99e6, user);
        vm.stopBroadcast();

        uint256 userBalance = usdc.balanceOf(user);
        console2.log("User Balance: ", userBalance);
    }

    function allInter() public {
        vm.startBroadcast();
        usdc.mint(admin, 50000e6);
        usdt.mint(admin, 50000e6);

        usdc.approve(address(stabilizer), 50000e6);
        usdt.approve(address(stabilizer), 50000e6);
        stabilizer.addLiquidity(50000e6, 50000e6, (50000e6 - 1000), admin);
        bool token = false;
        for (uint256 i = 0; i < 10; i++) {
            if (token) {
                usdc.approve(address(stabilizer), 1000e6);
                stabilizer.exchange(address(usdc), 1000e6, 998e6, admin);
            } else {
                usdt.approve(address(stabilizer), 1000e6);
                stabilizer.exchange(address(usdt), 1000e6, 998e6, admin);
            }
            token = !token;
        }

        uint256 amountStb = stabilizer.balanceOf(admin);
        stabilizer.removeLiquidity(amountStb, 1e6, 1e6, admin);

        vm.stopBroadcast();
    }
}
