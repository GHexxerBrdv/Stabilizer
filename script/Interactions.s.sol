// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {Stabilizer} from "../src/Stabilizer.sol";
import {USDC} from "./mocks/Usdc.sol";
import {USDT} from "./mocks/Usdt.sol";

contract Interactions is Script {
    Stabilizer public stabilizer;
    USDC public usdc;
    USDT public usdt;

    address admin = 0xA7407106D3c9a5ab2131a7AcAa343b6219Aa1Dd6;
    address user = makeAddr("receiver");

    address constant USDC_ADDRESS = 0x6162A003B0DbEccEA328924d0F2382eF07588eE5;
    address constant USDT_ADDRESS = 0x0e6eDa717c28536746594f4D2D0e699f639bdC06;

    function run() public {
        stabilizer = Stabilizer(0xEb1598206b58D87d671d137228712d8919914D16);
        usdc = USDC(USDC_ADDRESS);
        usdt = USDT(USDT_ADDRESS);

        allInter();
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
