// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStakingV7} from "../src/NFTStaking.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external returns (address) {
        address proxy = deploy();
        return proxy;
    }

    function deploy() public returns (address) {
        vm.startBroadcast();
        NFTStakingV7 staking = new NFTStakingV7();
        ERC1967Proxy proxy = new ERC1967Proxy(address(staking), "");
        NFTStakingV7(address(proxy)).initialize(
            msg.sender,
            address(0xfabDca15b28d8437C148EcC484817Fc28a85aDB8),
            address(0x6e3c821b32950ABcf44bCE71c7f905a3cB960113),
            address(0xb1ba8D79abecdDa60Fa2f19e7d8328A8602275a3),
            1
        );
        vm.stopBroadcast();
        return address(proxy);
    }
}
