// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStakingV7} from "../src/NFTStaking.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract Deploy is Script {
    function run() external returns (address) {
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

        address proxy = deploy();
        vm.stopBroadcast();
        return address(proxy);
    }

    function deploy() public returns (address) {
        address proxy = Upgrades.deployUUPSProxy(
            "NFTStaking.sol:NFTStakingV5",
            abi.encodeCall(
                NFTStakingV7.initialize,
                (
                    msg.sender,
                    address(0xfabDca15b28d8437C148EcC484817Fc28a85aDB8),
                    address(0x6e3c821b32950ABcf44bCE71c7f905a3cB960113),
                    address(0xb1ba8D79abecdDa60Fa2f19e7d8328A8602275a3),
                    1
                )
            )
        );
        return address(proxy);
    }
}
