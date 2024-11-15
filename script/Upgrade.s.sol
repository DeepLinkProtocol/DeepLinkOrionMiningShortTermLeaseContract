// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
//import  {Options} from  "openzeppelin-foundry-upgrades/Options.sol";
import {console} from "forge-std/Test.sol";

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

        address stakingProxy = vm.envAddress("STAKING_PROXY");
        console.log("Staking Proxy Address:", stakingProxy);
        address transparentProxy = address(stakingProxy);

        //                Options memory opts;
        //
        //                opts.referenceContract = "NFTStakingOld.sol:NFTStaking";
        //
        //                Upgrades.validateUpgrade("NFTStaking.sol:NFTStaking", opts);

        Upgrades.upgradeProxy(transparentProxy, "NFTStaking.sol:NFTStaking", "");

        vm.stopBroadcast();
    }
}
