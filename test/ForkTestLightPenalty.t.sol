// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/NFTStaking.sol";
import "../src/rent/Rent.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract ForkTestLightPenalty is Test {
    address constant STAKING_PROXY = 0x6268Aba94D0d0e4FB917cC02765f631f309a7388;
    address constant RENT_PROXY = 0xDA9EfdfF9CA7B7065b7706406a1a79C0e483815A;
    address constant UPGRADE_ADDR = 0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8;

    NFTStaking staking;
    Rent rent;

    function setUp() public {
        staking = NFTStaking(STAKING_PROXY);
        rent = Rent(RENT_PROXY);
    }

    function test_preUpgradeState() public view {
        uint256 ver = staking.version();
        console.log("Current NFTStaking version:", ver);
        assertEq(ver, 9, "Should be version 9 before upgrade");
    }

    function test_upgradeAndVerify() public {
        // 模拟 canUpgradeAddress 执行升级
        vm.startPrank(UPGRADE_ADDR);

        // 升级 NFTStaking
        NFTStaking newImpl = new NFTStaking();
        staking.upgradeToAndCall(address(newImpl), "");
        
        uint256 newVer = staking.version();
        console.log("New NFTStaking version:", newVer);
        assertEq(newVer, 10, "Should be version 10 after upgrade");

        // 升级 Rent
        Rent newRentImpl = new Rent();
        rent.upgradeToAndCall(address(newRentImpl), "");

        vm.stopPrank();
        console.log("Both contracts upgraded successfully");
    }

    function test_lightPenaltyOnFork() public {
        // 升级合约
        vm.startPrank(UPGRADE_ADDR);
        NFTStaking newImpl = new NFTStaking();
        staking.upgradeToAndCall(address(newImpl), "");
        Rent newRentImpl = new Rent();
        rent.upgradeToAndCall(address(newRentImpl), "");
        vm.stopPrank();

        // 找一台活跃的出租中机器测试
        // 用已知的 machine_id
        string memory machineId = "82d5f725d35af07e6134c6a513806c6e3296e683db531623755d725575eee22b";
        
        bool isStakingBefore = staking.isStaking(machineId);
        bool isRentedBefore = rent.isRented(machineId);
        console.log("Before penalty - isStaking:", isStakingBefore);
        console.log("Before penalty - isRented:", isRentedBefore);

        if (isStakingBefore && isRentedBefore) {
            // 模拟 DDN 离线通知
            address dbcAI = address(staking.dbcAIContract());
            vm.prank(dbcAI);
            rent.notify(Rent.NotifyType.MachineOffline, machineId);

            bool isStakingAfter = staking.isStaking(machineId);
            bool isRentedAfter = rent.isRented(machineId);
            console.log("After light penalty - isStaking:", isStakingAfter);
            console.log("After light penalty - isRented:", isRentedAfter);

            // 轻量惩罚：保持质押，租赁终止
            assertTrue(isStakingAfter, "Should still be staking after light penalty");
            assertFalse(isRentedAfter, "Rental should be terminated");

            // 验证版本
            assertEq(staking.version(), 10);
            console.log("=== Light penalty test PASSED on mainnet fork ===");
        } else {
            console.log("Machine not actively rented, skipping penalty test");
        }
    }
}
