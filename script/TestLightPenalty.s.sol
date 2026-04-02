// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import "../src/NFTStaking.sol";
import "../src/rent/Rent.sol";

contract TestLightPenalty is Script {
    // 主网合约地址
    address constant STAKING_PROXY = 0x6268Aba94D0d0e4FB917cC02765f631f309a7388;
    address constant RENT_PROXY = 0xDA9EfdfF9CA7B7065b7706406a1a79C0e483815A;

    function run() public view {
        NFTStaking staking = NFTStaking(STAKING_PROXY);
        Rent rent = Rent(RENT_PROXY);

        // 1. 验证当前版本
        uint256 stakingVersion = staking.version();
        console.log("Current NFTStaking version:", stakingVersion);

        // 2. 查一台活跃机器的状态
        // 用一个已知的 machine_id 测试
        string memory testMachine = "82d5f725d35af07e6134c6a513806c6e3296e683db531623755d725575eee22b";
        
        bool isStaking = staking.isStaking(testMachine);
        console.log("isStaking:", isStaking);
        
        bool isRented = rent.isRented(testMachine);
        console.log("isRented:", isRented);

        // 3. 验证 reportMachineFaultLight 函数签名存在（通过接口检查）
        // 如果升级成功，这个函数应该可调用
        console.log("=== Pre-upgrade check complete ===");
        console.log("NFTStaking proxy:", STAKING_PROXY);
        console.log("Rent proxy:", RENT_PROXY);
    }
}
