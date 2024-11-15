// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStakingState} from "../../src/state/NFTStakingState.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployState is Script {
    function run() external returns (address) {
        address proxy = deploy();
        return proxy;
    }

    function deploy() public returns (address) {
        vm.startBroadcast();
        NFTStakingState staking = new NFTStakingState();
        ERC1967Proxy proxy = new ERC1967Proxy(address(staking), "");
        NFTStakingState(address(proxy)).initialize(
            msg.sender, address(0xb1ba8D79abecdDa60Fa2f19e7d8328A8602275a3), address(0x00), address(0x00), 1
        );
        vm.stopBroadcast();
        return address(proxy);
    }
}
