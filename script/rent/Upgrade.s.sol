// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
//import  {Options} from  "openzeppelin-foundry-upgrades/Options.sol";
import "forge-std/console.sol";
import "../../src/rent/Rent.sol";

contract Upgrade is Script {
    function run() public {
        string memory privateKeyString = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;

        if (
            bytes(privateKeyString).length > 0 && bytes(privateKeyString)[0] == "0" && bytes(privateKeyString)[1] == "x"
        ) {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        }

        vm.startBroadcast(deployerPrivateKey);

        address rentProxy = vm.envAddress("RENT_PROXY");
        console.log("Rent Proxy Address:", rentProxy);

        // 升级合约
        Upgrades.upgradeProxy(rentProxy, "Rent.sol:Rent", "");
        console.log("Upgrade completed");

        // 调用 reinitialize 初始化 ReentrancyGuard
        Rent(rentProxy).reinitialize();
        console.log("Reinitialize completed");

        vm.stopBroadcast();
    }
}
