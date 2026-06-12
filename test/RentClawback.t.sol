// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {Token} from "./MockRewardToken.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RentTest} from "./Rent.t.sol";

/// @notice v14 adminReverseUnpaidRenewal clawback 测试 (复用 RentTest 的 setUp + stakeByOwner)
contract RentClawbackTest is RentTest {
    // DLP point token 在 Rent.sol 内硬编码 0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6
    address constant DLP = 0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6;

    address payer = address(0xAA);   // 平台垫付方
    address renter = address(0xBB);  // 租客

    function _setupDLP() internal returns (Token dlp) {
        // 在硬编码地址 etch 一个 ERC20 的运行时代码, 供续租 DLP 转账使用
        Token tmpl = new Token();
        vm.etch(DLP, address(tmpl).code);
        dlp = Token(DLP);
    }

    /// @dev 建一台 personal 机器(自动入白名单) + V2 proxy 租赁(payer 垫付, renter 租)
    function _proxyRentV2(string memory machineId, uint256 rentSeconds) internal {
        stakeByOwner(machineId, 0, 100, true); // personal, 质押 100h 足够长
        // payer 准备 DLC(feeToken=rewardToken)
        deal(address(rewardToken), payer, 1_000_000 ether);
        // DLP 余额 + 授权
        deal(DLP, payer, 1_000_000 ether);
        vm.startPrank(payer);
        rewardToken.approve(address(rent), type(uint256).max);
        IERC20(DLP).approve(address(rent), type(uint256).max);
        vm.stopPrank();
        // getMachineState mock(rentMachine 需要)
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );
        vm.prank(payer);
        rent.rentProxyMachineV2(renter, machineId, rentSeconds);
        assertTrue(rent.machine2ProxyRented(machineId), "should be proxy rented");
        assertEq(rent.machine2ProxyRentPayer(machineId), payer, "payer recorded");
    }

    function _renew(string memory machineId, uint256 seconds_) internal {
        vm.prank(payer);
        rent.proxyRenewRentV2(renter, machineId, seconds_);
    }

    function _rentId(string memory machineId) internal view returns (uint256) {
        return rent.machineId2RentId(machineId);
    }

    // ---- 正常路径: 撤销一笔续租, 精确退回 payer, 缩短 rentEndTime, 标 consumed ----
    function testReverseRenewal_happyPath() public {
        _setupDLP();
        string memory machineId = "clawbackM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours); // segment 0

        uint256 rentId = _rentId(machineId);
        (uint256 segSeconds, uint256 segBase, uint256 segPlatform, uint256 segExtra, bool consumed0) =
            rent.rentId2RenewalSegments(rentId, 0);
        assertFalse(consumed0, "seg not consumed yet");

        (,,, uint256 endBefore,) = rent.rentId2RentInfo(rentId);
        uint256 payerDlcBefore = rewardToken.balanceOf(payer);
        uint256 payerDlpBefore = IERC20(DLP).balanceOf(payer);

        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 0);

        (,,, uint256 endAfter,) = rent.rentId2RentInfo(rentId);
        assertEq(endAfter, endBefore - segSeconds, "rentEndTime reduced by exact seg seconds");
        assertEq(rewardToken.balanceOf(payer), payerDlcBefore + segBase + segPlatform, "DLC refunded exact");
        assertEq(IERC20(DLP).balanceOf(payer), payerDlpBefore + segExtra, "DLP refunded exact");
        (,,,, bool consumedAfter) = rent.rentId2RenewalSegments(rentId, 0);
        assertTrue(consumedAfter, "seg marked consumed");
    }

    // ---- 重复撤销同一笔 -> revert already reversed ----
    function testReverse_doubleReverts() public {
        _setupDLP();
        string memory machineId = "dblM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours);
        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 0);
        vm.prank(owner);
        vm.expectRevert(bytes("already reversed"));
        rent.adminReverseUnpaidRenewal(machineId, 0);
    }

    // ---- 非 owner 调 -> revert ----
    function testReverse_onlyOwner() public {
        _setupDLP();
        string memory machineId = "ownM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours);
        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("not authorized"));
        rent.adminReverseUnpaidRenewal(machineId, 0);
    }

    // ---- 坏 index -> revert ----
    function testReverse_badIndex() public {
        _setupDLP();
        string memory machineId = "idxM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours);
        vm.prank(owner);
        vm.expectRevert(bytes("bad renewalIndex"));
        rent.adminReverseUnpaidRenewal(machineId, 5);
    }

    // ---- 会切到已用/在用时段 -> revert (撤销秒数 > 剩余未用) ----
    function testReverse_wouldCutActiveTime() public {
        _setupDLP();
        string memory machineId = "cutM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours); // 总 2h, seg=1h, rentEndTime = rentStart + 2h
        // 推进到 rentStart + 1h1m: rent 仍活(< rentStart+2h), 但撤 1h 会使 rentEndTime-1h = rentStart+1h < now
        vm.warp(block.timestamp + 1 hours + 60);
        vm.prank(owner);
        vm.expectRevert(bytes("would cut used/active time"));
        rent.adminReverseUnpaidRenewal(machineId, 0);
    }

    // ---- 普通 V2 直租(非 proxy) 不可撤 -> revert not proxy-rented ----
    function testReverse_nonProxyRejected() public {
        _setupDLP();
        string memory machineId = "directM";
        stakeByOwner(machineId, 0, 100, true);
        deal(address(rewardToken), renter, 1_000_000 ether);
        deal(DLP, renter, 1_000_000 ether);
        vm.startPrank(renter);
        rewardToken.approve(address(rent), type(uint256).max);
        IERC20(DLP).approve(address(rent), type(uint256).max);
        vm.stopPrank();
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );
        vm.prank(renter);
        rent.rentMachineV2(machineId, 1 hours); // 直租, machine2ProxyRented=false
        vm.prank(renter);
        rent.renewRentV2(machineId, 1 hours);
        vm.prank(owner);
        vm.expectRevert(bytes("not proxy-rented"));
        rent.adminReverseUnpaidRenewal(machineId, 0);
    }
}
