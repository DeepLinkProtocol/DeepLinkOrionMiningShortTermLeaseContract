// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStakingState} from "../../src/state/NFTStakingState.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {console} from "forge-std/Test.sol";

contract Deploy is Script {
    function run() external returns (address proxy, address logic) {
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

        (proxy, logic) = deploy();
        vm.stopBroadcast();
        console.log("Proxy Contract deployed at:", proxy);
        console.log("Logic Contract deployed at:", logic);
        return (proxy, logic);
    }

    function deploy() public returns (address proxy, address logic) {
        Options memory opts;

        logic = Upgrades.deployImplementation("NFTStakingState.sol:NFTStakingState", opts);

        uint8 phaseLevel = uint8(vm.envUint("PHASE_LEVEL"));
        console.log("phaseLevel:", phaseLevel);

        address stakingProxy = vm.envAddress("STAKING_PROXY");
        console.log("Staking Proxy Address:", stakingProxy);

        address rentProxy = vm.envAddress("RENT_PROXY");
        console.log("Rent Proxy Address:", rentProxy);

        proxy = Upgrades.deployUUPSProxy(
            "NFTStakingState.sol:NFTStakingState",
            abi.encodeCall(NFTStakingState.initialize, (msg.sender, rentProxy, stakingProxy, phaseLevel))
        );
        return (proxy, logic);
    }
}
