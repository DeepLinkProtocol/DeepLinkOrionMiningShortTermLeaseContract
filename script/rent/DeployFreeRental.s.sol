// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FreeRental} from "../../src/rent/FreeRental.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {console} from "forge-std/Test.sol";

contract DeployFreeRental is Script {
    function run() external returns (address proxy, address logic) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address pointToken = vm.envAddress("POINT_TOKEN");
        address platformWallet = vm.envAddress("PLATFORM_WALLET");

        console.log("Point Token:", pointToken);
        console.log("Platform Wallet:", platformWallet);

        vm.startBroadcast(deployerPrivateKey);

        Options memory opts;
        logic = Upgrades.deployImplementation("FreeRental.sol:FreeRental", opts);
        console.log("Implementation:", logic);

        proxy = Upgrades.deployUUPSProxy(
            "FreeRental.sol:FreeRental",
            abi.encodeCall(FreeRental.initialize, (pointToken, platformWallet))
        );

        console.log("Proxy:", proxy);

        // Set deployer as admin
        FreeRental(proxy).setAdmins(new address[](0), true); // owner is already authorized via onlyAdmin

        vm.stopBroadcast();
        return (proxy, logic);
    }
}
