// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

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

        // 指定现有透明代理的地址
        address transparentProxy = address(0x64336D0D239543D700F95B1683d148FF53B521FF);

        //        // 设置验证升级的选项
        //        Upgrades.Options memory opts;
        //        opts.referenceContract = "StakingOld.sol";
        //
        //        // 验证升级的兼容性
        //        Upgrades.validateUpgrade(transparentProxy, "Staking.sol", opts);

        // 升级
        Upgrades.upgradeProxy(transparentProxy, "NFTStaking.sol:NFTStakingV7", "");

        vm.stopBroadcast();
    }
}
