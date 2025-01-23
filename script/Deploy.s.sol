// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
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

        logic = Upgrades.deployImplementation("NFTStaking.sol:NFTStaking", opts);

        address nftContract = vm.envAddress("NFT_CONTRACT");
        console.log("nftContract Address:", nftContract);

        address rewardTokenContract = vm.envAddress("REWARD_TOKEN_CONTRACT");
        console.log("rewardTokenContract Address:", rewardTokenContract);

        address stateProxy = vm.envAddress("STATE_PROXY");
        console.log("State Proxy Address:", stateProxy);

        address rentProxy = vm.envAddress("RENT_PROXY");
        console.log("Rent Proxy Address:", rentProxy);

        address dbcAIProxy = vm.envAddress("DBC_AI_PROXY");
        console.log("DBC AI Proxy Address:", dbcAIProxy);

        address toolContractProxy = vm.envAddress("TOOL_PROXY");
        console.log("Tool contract Proxy Address:", toolContractProxy);

        uint8 phase = uint8(vm.envUint("PHASE_LEVEL"));
        console.log("phaseLevel Address:", phase);

        proxy = Upgrades.deployUUPSProxy(
            "NFTStaking.sol:NFTStaking",
            abi.encodeCall(
                NFTStaking.initialize,
                (
                    msg.sender,
                    nftContract,
                    rewardTokenContract,
                    stateProxy,
                    rentProxy,
                    dbcAIProxy,
                    toolContractProxy,
                    phase
                )
            )
        );
        return (proxy, logic);
    }
}
