// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FreeRental} from "../src/rent/FreeRental.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";

contract FreeRentalEmergencyTest is Test {
    FreeRental public fr;
    Token public pointToken;

    address owner = address(0x01);
    address admin = address(0x02);
    address machineOwner = address(0x10);
    address renter = address(0x20);
    address platformWallet = address(0x30);

    function setUp() public {
        vm.startPrank(owner);
        pointToken = new Token();

        ERC1967Proxy proxy = new ERC1967Proxy(address(new FreeRental()), "");
        fr = FreeRental(address(proxy));
        fr.initialize(address(pointToken), platformWallet);

        // 设置 admin
        address[] memory admins = new address[](1);
        admins[0] = admin;
        fr.setAdmins(admins, true);
        vm.stopPrank();

        // 给 renter 积分并 approve
        deal(address(pointToken), renter, 100_000 * 1e18);
        vm.prank(renter);
        pointToken.approve(address(fr), type(uint256).max);
    }

    // ══════════════════════════════════════════════════════════
    //  emergencyEndRent 测试
    // ══════════════════════════════════════════════════════════

    function test_emergencyEndRent_fullRefund() public {
        // admin 注册机器
        vm.prank(admin);
        fr.registerMachine("m1", machineOwner, 500000); // $0.50/h

        // admin 租赁：1小时，1000 积分
        vm.prank(admin);
        fr.rentMachine("m1", renter, 3600, 1000 * 1e18);

        uint256 renterBefore = pointToken.balanceOf(renter);

        // owner 紧急结束租赁
        vm.prank(owner);
        fr.emergencyEndRent("m1");

        // 验证：租户获得全额退款
        uint256 renterAfter = pointToken.balanceOf(renter);
        assertEq(renterAfter - renterBefore, 1000 * 1e18, "renter should get full refund");

        // 验证：机器不再被租赁
        assertFalse(fr.machineIsRented("m1"), "machine should not be rented");

        // 验证：机器可以重新租赁
        assertTrue(fr.canRent("m1"), "machine should be rentable again");
    }

    function test_emergencyEndRent_onlyOwner() public {
        vm.prank(admin);
        fr.registerMachine("m2", machineOwner, 500000);
        vm.prank(admin);
        fr.rentMachine("m2", renter, 3600, 1000 * 1e18);

        // admin 不能调 emergencyEndRent
        vm.prank(admin);
        vm.expectRevert();
        fr.emergencyEndRent("m2");

        // renter 不能调
        vm.prank(renter);
        vm.expectRevert();
        fr.emergencyEndRent("m2");

        // machineOwner 不能调
        vm.prank(machineOwner);
        vm.expectRevert();
        fr.emergencyEndRent("m2");
    }

    function test_emergencyEndRent_noActiveRent() public {
        vm.prank(admin);
        fr.registerMachine("m3", machineOwner, 500000);

        // 没有活跃租赁，应该 revert
        vm.prank(owner);
        vm.expectRevert("no active rent");
        fr.emergencyEndRent("m3");
    }

    function test_emergencyEndRent_alreadyEnded() public {
        vm.prank(admin);
        fr.registerMachine("m4", machineOwner, 500000);
        vm.prank(admin);
        fr.rentMachine("m4", renter, 3600, 1000 * 1e18);

        // 正常结束
        vm.warp(block.timestamp + 3601);
        vm.prank(admin);
        fr.endRent("m4");

        // 紧急结束已结束的租赁应 revert
        vm.prank(owner);
        vm.expectRevert("no active rent");
        fr.emergencyEndRent("m4");
    }

    function test_emergencyEndRent_ownerGetsNothing() public {
        vm.prank(admin);
        fr.registerMachine("m5", machineOwner, 500000);
        vm.prank(admin);
        fr.rentMachine("m5", renter, 3600, 1000 * 1e18);

        uint256 ownerIncomeBefore = fr.ownerPendingIncome(machineOwner);

        vm.prank(owner);
        fr.emergencyEndRent("m5");

        uint256 ownerIncomeAfter = fr.ownerPendingIncome(machineOwner);
        assertEq(ownerIncomeAfter, ownerIncomeBefore, "owner should get no income from emergency end");
    }

    // ══════════════════════════════════════════════════════════
    //  正常流程对比测试
    // ══════════════════════════════════════════════════════════

    function test_normalEndRent_fullDuration() public {
        vm.prank(admin);
        fr.registerMachine("m6", machineOwner, 500000);
        vm.prank(admin);
        fr.rentMachine("m6", renter, 3600, 1250 * 1e18); // 1250 point, owner gets 1000, platform gets 250

        vm.warp(block.timestamp + 3601); // 租赁到期

        uint256 platformBefore = pointToken.balanceOf(platformWallet);
        vm.prank(admin);
        fr.endRent("m6");

        // 机主应得 1000 积分（1250 * 100/125）
        assertEq(fr.ownerPendingIncome(machineOwner), 1000 * 1e18, "owner should get 80% of total");

        // 平台应得 250 积分
        uint256 platformAfter = pointToken.balanceOf(platformWallet);
        assertEq(platformAfter - platformBefore, 250 * 1e18, "platform should get 20% of total");
    }

    function test_earlyEndRent_proportionalRefund() public {
        vm.prank(admin);
        fr.registerMachine("m7", machineOwner, 500000);
        vm.prank(admin);
        fr.rentMachine("m7", renter, 3600, 1000 * 1e18); // 1小时

        uint256 renterBefore = pointToken.balanceOf(renter);

        vm.warp(block.timestamp + 1800); // 半小时后退租

        vm.prank(admin);
        fr.endRent("m7");

        // 应退还约 50% 的积分
        uint256 renterAfter = pointToken.balanceOf(renter);
        uint256 refund = renterAfter - renterBefore;
        assertTrue(refund > 490 * 1e18 && refund < 510 * 1e18, "should refund ~50%");
    }

    function test_version() public view {
        assertEq(fr.VERSION(), 4, "FreeRental version should be 4");
    }
}
