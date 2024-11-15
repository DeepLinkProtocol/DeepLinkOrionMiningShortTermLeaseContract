// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
//import  {Options} from  "openzeppelin-foundry-upgrades/Options.sol";
import "forge-std/console.sol";

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

        Upgrades.upgradeProxy(rentProxy, "Rent.sol:Rent", "");

        vm.stopBroadcast();
    }
}
