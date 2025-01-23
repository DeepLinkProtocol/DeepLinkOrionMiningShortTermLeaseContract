// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Tool} from "../../src/Tool.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external returns (address) {
        address proxy = deploy();
        return proxy;
    }

    function deploy() public returns (address) {
        vm.startBroadcast();
        Tool tool = new Tool();
        ERC1967Proxy proxy = new ERC1967Proxy(address(tool), "");
        Tool(address(proxy)).initialize(msg.sender);
        vm.stopBroadcast();
        return address(proxy);
    }
}
