// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external returns (address) {
        address proxy = deploy();
        return proxy;
    }

    function deploy() public returns (address) {
        vm.startBroadcast();
        NFTStaking staking = new NFTStaking();
        ERC1967Proxy proxy = new ERC1967Proxy(address(staking), "");
        NFTStaking(address(proxy)).initialize(
            msg.sender,
            address(0x0),
            address(0x0),
            address(0xb1BA8d79AbEcDDA60Fa2f19e7D8328a8602275A4),
            address(0xb1BA8d79AbEcDDA60Fa2f19e7D8328a8602275A4),
            address(0x2),
            address(0x0),
            1
        );
        vm.stopBroadcast();
        return address(proxy);
    }
}
