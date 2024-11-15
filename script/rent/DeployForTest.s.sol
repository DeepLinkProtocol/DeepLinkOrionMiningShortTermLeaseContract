// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Rent} from "../../src/rent/Rent.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployRent is Script {
    function run() external returns (address) {
        address proxy = deploy();
        return proxy;
    }

    function deploy() public returns (address) {
        vm.startBroadcast();
        Rent rent = new Rent();
        ERC1967Proxy proxy = new ERC1967Proxy(address(rent), "");
        Rent(address(proxy)).initialize(
            msg.sender,
            address(0xb1ba8D79abecdDa60Fa2f19e7d8328A8602275a3),
            address(0xb1ba8D79abecdDa60Fa2f19e7d8328A8602275a3),
            address(0xb1ba8D79abecdDa60Fa2f19e7d8328A8602275a3),
            address(0x00),
            address(0x00)
        );
        vm.stopBroadcast();
        return address(proxy);
    }
}
