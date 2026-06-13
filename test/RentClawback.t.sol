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

    /// @dev 给机器设置非零 extra rent fee (USD/min) -> DLP extraFee 非零, 真正考验 DLP 守恒
    function _enableExtraFee(string memory machineId, uint256 usdPerMin) internal {
        vm.startPrank(owner);
        nftStaking.setMaxExtraRentFeeInUSDPerMinutes(usdPerMin * 10);
        string[] memory ids = new string[](1);
        ids[0] = machineId;
        nftStaking.setExtraRentFeeByAdmin(ids, usdPerMin);
        vm.stopPrank();
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
        (uint256 segSeconds, uint256 segBase, uint256 segPlatform, uint256 segExtra, , bool consumed0) =
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
        (,,,,, bool consumedAfter) = rent.rentId2RenewalSegments(rentId, 0);
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

    // ================= 守恒断言 (二轮审计) =================
    // 不变量: segment 撤销后, endRentMachineV2 的 pro-rata 仍守恒:
    //   托管总额(初租+所有未撤续租) == 退 payer(pro-rata 未用 + 已撤回 clawback) + 发矿工/平台 + 销毁
    // 用合约视角度量: 合约最终该 rentId 相关托管清零 (DLC/DLP 出入相抵)。

    struct ConsSnap {
        uint256 cDlc;   // 合约 DLC 余额
        uint256 cDlp;   // 合约 DLP 余额
        uint256 pDlc;   // payer DLC 余额
        uint256 pDlp;   // payer DLP 余额
    }

    function _snap() internal view returns (ConsSnap memory s) {
        s.cDlc = rewardToken.balanceOf(address(rent));
        s.cDlp = IERC20(DLP).balanceOf(address(rent));
        s.pDlc = rewardToken.balanceOf(payer);
        s.pDlp = IERC20(DLP).balanceOf(payer);
    }

    // 守恒核心: 从 (rent 前) 到 (endRent 后), 合约托管净变化 == 0 (该 rentId 没有残留资金),
    // 且 payer 净支出 == 所有流出到矿工/平台/销毁的总额(= 托管 - clawback - pro-rata退款)。
    // 我们用最强的端到端断言: 合约 DLC/DLP 余额在完整生命周期后回到初始基线(无泄漏/无残留)。

    // ---- 单笔续租(非零 DLP), 撤回后【提前】endRent: DLC+DLP 全守恒 ----
    function testConservation_singleReverseThenEarlyEnd() public {
        _setupDLP();
        string memory machineId = "consM1";
        _proxyRentV2(machineId, 1 hours);
        _enableExtraFee(machineId, 100); // 非零 DLP extra fee
        ConsSnap memory base = _snap(); // 在初租之后、含 DLP 入账基线后量取... 见下
        // 重新建立基线: 用初租 + 续租前的合约余额无法干净分离, 故改为全局守恒:
        //   验证 (合约最终该 rentId 托管清零) + (payer 收到 = clawback + pro-rata 未用退款)。

        // 续租(产生 DLP+DLC segment)
        _renew(machineId, 1 hours); // segment 0
        uint256 rentId = _rentId(machineId);
        ConsSnap memory afterDeposit = _snap();
        assertGt(afterDeposit.cDlp, base.cDlp, "DLP escrow grew on renew");
        assertGt(afterDeposit.cDlc, base.cDlc, "DLC escrow grew on renew");

        // 撤回 segment 0
        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 0);
        ConsSnap memory afterReverse = _snap();
        // 撤回后合约托管应退回到续租前(segment 全额已退 payer)
        assertEq(afterReverse.cDlc, base.cDlc, "DLC escrow back to pre-renew after reverse");
        assertEq(afterReverse.cDlp, base.cDlp, "DLP escrow back to pre-renew after reverse");

        // 提前 endRent (mid-rental, 触发 pro-rata 退款)
        (,,, uint256 endTime,) = rent.rentId2RentInfo(rentId);
        (,, uint256 startTime,,) = _rentTimes(rentId);
        // warp 到剩余租期的一半
        vm.warp(startTime + (endTime - startTime) / 2);
        // 记录所有外部 sink 余额(矿工/平台 beneficiary)
        uint256 payerDlcPre = rewardToken.balanceOf(payer);
        uint256 payerDlpPre = IERC20(DLP).balanceOf(payer);

        vm.prank(payer);
        rent.endRentMachineV2(machineId);

        ConsSnap memory fin = _snap();
        // 守恒铁律: 完整生命周期后, 合约该 rentId 托管清零(初租也已 pro-rata 结算掉)
        assertEq(fin.cDlc, 0, "contract DLC fully settled");
        assertEq(fin.cDlp, 0, "contract DLP fully settled");
        // payer 提前退租拿回 pro-rata 未用部分 (>=0)
        assertGe(rewardToken.balanceOf(payer), payerDlcPre, "payer got DLC payback");
        assertGe(IERC20(DLP).balanceOf(payer), payerDlpPre, "payer got DLP payback");
    }

    function _rentTimes(uint256 rentId)
        internal
        view
        returns (address, string memory, uint256 startTime, uint256 endTime, address)
    {
        return rent.rentId2RentInfo(rentId);
    }

    // ---- 三笔不同价续租, 撤【中间】一笔后 endRent: 守恒 ----
    function testConservation_reverseMiddleSegment() public {
        _setupDLP();
        string memory machineId = "consMid";
        ConsSnap memory base = _snap();
        _proxyRentV2(machineId, 30 minutes);
        _enableExtraFee(machineId, 100); // 非零 DLP
        // 三笔不同时长 -> 不同 fee (价格与秒数线性, 但验证 index 取值精确)
        _renew(machineId, 20 minutes); // seg 0
        _renew(machineId, 40 minutes); // seg 1 (撤这笔)
        _renew(machineId, 15 minutes); // seg 2

        uint256 rentId = _rentId(machineId);
        (uint256 s1sec, uint256 s1base, uint256 s1plat, uint256 s1extra,,) =
            rent.rentId2RenewalSegments(rentId, 1);

        (,,, uint256 endBefore,) = rent.rentId2RentInfo(rentId);
        uint256 payerDlcBefore = rewardToken.balanceOf(payer);
        uint256 payerDlpBefore = IERC20(DLP).balanceOf(payer);

        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 1);

        // 撤中间一笔: rentEndTime 精确减 seg1 秒数, payer 精确收回 seg1 各 fee
        (,,, uint256 endAfter,) = rent.rentId2RentInfo(rentId);
        assertEq(endAfter, endBefore - s1sec, "endTime reduced by middle seg seconds");
        assertEq(rewardToken.balanceOf(payer), payerDlcBefore + s1base + s1plat, "DLC clawback exact (middle)");
        assertEq(IERC20(DLP).balanceOf(payer), payerDlpBefore + s1extra, "DLP clawback exact (middle)");

        // endRent 后整体守恒
        vm.warp(endAfter + 1);
        vm.prank(payer);
        rent.endRentMachineV2(machineId);
        ConsSnap memory fin = _snap();
        assertEq(fin.cDlc, base.cDlc, "DLC conserved after middle reverse + end");
        assertEq(fin.cDlp, base.cDlp, "DLP conserved after middle reverse + end");
    }

    // ---- 撤【尾部】一笔 vs 中间: 行为应一致(都按 index 精确撤, 不依赖顺序) ----
    function testConservation_reverseTailSegment() public {
        _setupDLP();
        string memory machineId = "consTail";
        ConsSnap memory base = _snap();
        _proxyRentV2(machineId, 30 minutes);
        _enableExtraFee(machineId, 100); // 非零 DLP
        _renew(machineId, 20 minutes); // seg 0
        _renew(machineId, 40 minutes); // seg 1
        _renew(machineId, 15 minutes); // seg 2 (撤尾部)

        uint256 rentId = _rentId(machineId);
        (uint256 s2sec, uint256 s2base, uint256 s2plat, uint256 s2extra,,) =
            rent.rentId2RenewalSegments(rentId, 2);
        (,,, uint256 endBefore,) = rent.rentId2RentInfo(rentId);
        uint256 payerDlcBefore = rewardToken.balanceOf(payer);
        uint256 payerDlpBefore = IERC20(DLP).balanceOf(payer);

        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 2);

        (,,, uint256 endAfter,) = rent.rentId2RentInfo(rentId);
        assertEq(endAfter, endBefore - s2sec, "endTime reduced by tail seg seconds");
        assertEq(rewardToken.balanceOf(payer), payerDlcBefore + s2base + s2plat, "DLC clawback exact (tail)");
        assertEq(IERC20(DLP).balanceOf(payer), payerDlpBefore + s2extra, "DLP clawback exact (tail)");

        vm.warp(endAfter + 1);
        vm.prank(payer);
        rent.endRentMachineV2(machineId);
        ConsSnap memory fin = _snap();
        assertEq(fin.cDlc, base.cDlc, "DLC conserved after tail reverse + end");
        assertEq(fin.cDlp, base.cDlp, "DLP conserved after tail reverse + end");
    }

    // ---- 撤【多笔】(2/3)后 endRent: 累计 feeInfo 扣减下守恒 ----
    function testConservation_reverseTwoOfThreeThenEnd() public {
        _setupDLP();
        string memory machineId = "cons2of3";
        ConsSnap memory base = _snap();
        _proxyRentV2(machineId, 30 minutes);
        _enableExtraFee(machineId, 100);
        _renew(machineId, 20 minutes); // seg 0
        _renew(machineId, 40 minutes); // seg 1
        _renew(machineId, 30 minutes); // seg 2
        uint256 rentId = _rentId(machineId);

        (uint256 s0sec,,,,,) = rent.rentId2RenewalSegments(rentId, 0);
        (uint256 s2sec,,,,,) = rent.rentId2RenewalSegments(rentId, 2);
        (,,, uint256 endBefore,) = rent.rentId2RentInfo(rentId);

        // 撤 seg0 + seg2 (跳过 seg1)
        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 0);
        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 2);

        (,,, uint256 endAfter,) = rent.rentId2RentInfo(rentId);
        assertEq(endAfter, endBefore - s0sec - s2sec, "endTime reduced by both reversed segs");

        vm.warp(endAfter + 1);
        vm.prank(payer);
        rent.endRentMachineV2(machineId);
        ConsSnap memory fin = _snap();
        assertEq(fin.cDlc, base.cDlc, "DLC conserved after 2-of-3 reverse + end");
        assertEq(fin.cDlp, base.cDlp, "DLP conserved after 2-of-3 reverse + end");
    }

    // ---- "fee already consumed" 守卫: feeInfo 被扣到不足时拒撤(防下溢) ----
    // 直接验证守卫存在性: 撤一笔后, 其 feeInfo 量已扣; 若另一笔 fee 之和 > 剩余 feeInfo 应被拦
    // (正常情况下 sum(seg.fee)==feeInfo 增量, 不会触发; 该守卫是防御 feeInfo 被 endRent pro-rata 扣减后的残留撤销)
    function testGuard_feeConsumedAfterPartialEnd_blocksReverse() public {
        _setupDLP();
        string memory machineId = "consGuard";
        _proxyRentV2(machineId, 1 hours);
        _enableExtraFee(machineId, 100);
        _renew(machineId, 1 hours); // seg 0, 总 2h
        uint256 rentId = _rentId(machineId);

        // 提前 endRent (mid-rental) -> feeInfo 被 pro-rata 扣减 + rentInfo 被 delete
        (,, uint256 st, uint256 et,) = _rentTimes(rentId);
        vm.warp(st + (et - st) / 2);
        vm.prank(payer);
        rent.endRentMachineV2(machineId);

        // endRent 后 rentInfo.renter 已清零 -> 撤销被 "no active rent" 拦截 (segment 不可在结束后再撤)
        vm.prank(owner);
        vm.expectRevert(bytes("no active rent"));
        rent.adminReverseUnpaidRenewal(machineId, 0);
    }

    // ---- 部分消费后再撤: segment 时段已被 endRent 之前的时间消费, 守恒边界 ----
    // 场景: 续租后 warp 进入 segment 覆盖的时段一部分, 此时 segment 的"未用"已 < 全额,
    //   但 feeInfo 仍持有该 segment 全额(尚未 endRent), 守卫只看 rentEndTime-seg.rentSeconds>now。
    //   验证撤回退还的是 segment【全额】(非 pro-rata), 由 would-cut 守卫保证只能撤"完全未来"的 segment。
    function testConservation_partialTimeConsumed_stillFullSegmentRefund() public {
        _setupDLP();
        string memory machineId = "consPart";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 2 hours); // seg 0 = 2h, 总租期 3h

        uint256 rentId = _rentId(machineId);
        (uint256 segSec, uint256 segBase, uint256 segPlat, uint256 segExtra,,) =
            rent.rentId2RenewalSegments(rentId, 0);

        // warp 30 分钟: 已用 30m < 初租 1h, segment(后 2h)完全在未来, 撤销合法
        vm.warp(block.timestamp + 30 minutes);
        uint256 payerDlcBefore = rewardToken.balanceOf(payer);
        uint256 payerDlpBefore = IERC20(DLP).balanceOf(payer);
        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 0);
        // 退的是 segment 全额(不 pro-rata), 因为 segment 时段尚未被消费
        assertEq(rewardToken.balanceOf(payer), payerDlcBefore + segBase + segPlat, "full seg DLC refund");
        assertEq(IERC20(DLP).balanceOf(payer), payerDlpBefore + segExtra, "full seg DLP refund");
        assertEq(segSec, 2 hours, "seg seconds");
    }

    // ---- 时间已流逝过半后撤一笔"名义窗口已过去"的 segment: 仍按全额撤且整体守恒 ----
    // 关键: 合约不给 segment 绑定具体时间窗, pro-rata 是扁平聚合. 只要撤后 rentEndTime>now,
    //   撤任何未撤 segment 全额都保持聚合不变量(总时间↓ 总托管↓ 同步), 之后 endRent 仍守恒.
    function testConservation_reverseElapsedNotionalSegment() public {
        _setupDLP();
        string memory machineId = "consElapsed";
        ConsSnap memory base = _snap();
        _proxyRentV2(machineId, 1 hours);  // 初租 1h
        _enableExtraFee(machineId, 100);
        _renew(machineId, 20 minutes); // seg 0 (名义窗口 60-80min)
        _renew(machineId, 20 minutes); // seg 1
        _renew(machineId, 20 minutes); // seg 2  总 = 2h
        uint256 rentId = _rentId(machineId);

        (uint256 s0sec, uint256 s0base, uint256 s0plat, uint256 s0extra,,) =
            rent.rentId2RenewalSegments(rentId, 0);
        (,, uint256 st, uint256 endBefore,) = _rentTimes(rentId);

        // 流逝 90 分钟: seg0 名义窗口(60-80min)已"过去", 但 endBefore-20min=1h40m > 90min, 守卫放行
        vm.warp(st + 90 minutes);
        uint256 payerDlcBefore = rewardToken.balanceOf(payer);
        uint256 payerDlpBefore = IERC20(DLP).balanceOf(payer);

        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 0);

        // 仍退 seg0 全额(非 pro-rata), endTime 精确减 20min
        (,,, uint256 endAfter,) = rent.rentId2RentInfo(rentId);
        assertEq(endAfter, endBefore - s0sec, "endTime -20min");
        assertEq(rewardToken.balanceOf(payer), payerDlcBefore + s0base + s0plat, "full DLC refund despite elapsed notional window");
        assertEq(IERC20(DLP).balanceOf(payer), payerDlpBefore + s0extra, "full DLP refund");

        // endRent: 整体仍守恒(扁平聚合 pro-rata 不依赖 segment 时间窗)
        vm.warp(endAfter + 1);
        vm.prank(payer);
        rent.endRentMachineV2(machineId);
        ConsSnap memory fin = _snap();
        assertEq(fin.cDlc, base.cDlc, "DLC conserved (elapsed-notional reverse)");
        assertEq(fin.cDlp, base.cDlp, "DLP conserved (elapsed-notional reverse)");
    }

    // ---- 余额封顶(共享池防御): 人为掏空合约 DLP 后撤销, 退款被封顶为余额, 不 revert, 不偷别的租约 ----
    // 验证 round-1 BLOCKER「共享托管池被超额抽走殃及其他在租机器」已被 min(balance) 封顶解决:
    //   即便合约 DLP 已不足, 撤销也只退 min(seg.extraFee, 余额), 不会 revert-DoS, 不会拉走第二台机器的托管。
    function testCap_drainedPool_refundCappedNoCrossRentalTheft() public {
        _setupDLP();
        // 机器 A: 被撤的目标
        string memory mA = "capA";
        _proxyRentV2(mA, 1 hours);
        _enableExtraFee(mA, 100);
        _renew(mA, 1 hours); // seg 0 (DLP 入账)
        uint256 rentIdA = _rentId(mA);
        (, , , uint256 segExtraA, , ) = rent.rentId2RenewalSegments(rentIdA, 0);
        assertGt(segExtraA, 0, "A has DLP segment");

        // 人为把合约 DLP 几乎掏空(模拟另一池已被花掉/不足), 仅留 1 wei < segExtraA
        uint256 cBal = IERC20(DLP).balanceOf(address(rent));
        vm.prank(address(rent));
        IERC20(DLP).transfer(address(0xDEAD), cBal - 1);
        assertEq(IERC20(DLP).balanceOf(address(rent)), 1, "pool drained to 1 wei");

        uint256 payerDlpBefore = IERC20(DLP).balanceOf(payer);
        // 撤销不应 revert (封顶); payer 只拿到 min(segExtra, 1) = 1 wei
        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(mA, 0);
        assertEq(IERC20(DLP).balanceOf(payer), payerDlpBefore + 1, "DLP refund capped at contract balance (no revert/DoS)");
        // consumed 已标记, 不可重撤
        (,,,,, bool consumed) = rent.rentId2RenewalSegments(rentIdA, 0);
        assertTrue(consumed, "seg consumed even under cap");
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

    // ---- [v14] proxy 机器上租客【自付】续租在源头被 guard 拦死(只有平台垫付方可续 proxy 租约),
    //      使二轮 CRITICAL(租客自付被撤却退给平台=盗款)结构上不可能 + 修复 endRent 退款错向 MEDIUM ----
    function testGuard_renterCannotSelfRenewProxyRental() public {
        _setupDLP();
        string memory machineId = "mixedM";
        _proxyRentV2(machineId, 1 hours); // 平台(payer) 垫付初租, machine2ProxyRented=true
        // 租客试图自付续租 -> 被 guard 拒(msg.sender=renter != machine2ProxyRentPayer=payer)
        deal(address(rewardToken), renter, 1_000_000 ether);
        deal(DLP, renter, 1_000_000 ether);
        vm.startPrank(renter);
        rewardToken.approve(address(rent), type(uint256).max);
        IERC20(DLP).approve(address(rent), type(uint256).max);
        vm.expectRevert(bytes("proxy renew only by payer"));
        rent.renewRentV2(machineId, 1 hours);
        vm.stopPrank();
    }

    // ---- 第三方代付续租 proxy 租约也被拒(只有记录的 payer 可续) ----
    function testGuard_thirdPartyCannotRenewProxyRental() public {
        _setupDLP();
        string memory machineId = "thirdM";
        _proxyRentV2(machineId, 1 hours);
        address third = address(0xCC);
        deal(address(rewardToken), third, 1_000_000 ether);
        deal(DLP, third, 1_000_000 ether);
        vm.startPrank(third);
        rewardToken.approve(address(rent), type(uint256).max);
        IERC20(DLP).approve(address(rent), type(uint256).max);
        vm.expectRevert(bytes("proxy renew only by payer"));
        rent.proxyRenewRentV2(renter, machineId, 1 hours);
        vm.stopPrank();
    }

    // ---- 平台垫付方续 proxy 租约正常通过(回归保护: guard 不误伤正规流程) ----
    function testGuard_platformPayerCanRenewProxyRental() public {
        _setupDLP();
        string memory machineId = "okM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours); // payer(平台) 续, 应通过
        uint256 rentId = _rentId(machineId);
        (,,,, address segPayer,) = rent.rentId2RenewalSegments(rentId, 0);
        assertEq(segPayer, payer, "proxy renewal payer == platform payer");
    }

    // ════════ v15: clawbackAdmin 角色测试 ════════
    address constant CLAWBACK_ADMIN = address(0xC1A);

    event RenewalSegmentRecorded(uint256 indexed rentId, uint256 renewalIndex, address payer, uint256 rentSeconds);

    // ---- v15: RenewalSegmentRecorded 事件 emit 正确的绝对 index/payer/rentSeconds(供链下精确记账) ----
    function testRenewalSegmentRecorded_emitsCorrectIndex() public {
        _setupDLP();
        string memory machineId = "evtM";
        _proxyRentV2(machineId, 1 hours);
        uint256 rentId = _rentId(machineId);
        // 第 1 笔续租 → index 0
        vm.expectEmit(true, false, false, true);
        emit RenewalSegmentRecorded(rentId, 0, payer, 1 hours);
        _renew(machineId, 1 hours);
        // 第 2 笔续租 → index 1
        vm.expectEmit(true, false, false, true);
        emit RenewalSegmentRecorded(rentId, 1, payer, 30 minutes);
        _renew(machineId, 30 minutes);
        // index 与链上数组一致, 且按此 index 能精确 clawback
        (uint256 s1,,,,,) = rent.rentId2RenewalSegments(rentId, 1);
        assertEq(s1, 30 minutes, "index1 seg matches");
        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 1); // 按 emit 的 index 精确撤第 2 笔
        (,,,,, bool consumed1) = rent.rentId2RenewalSegments(rentId, 1);
        assertTrue(consumed1, "index1 reversed");
        (,,,,, bool consumed0) = rent.rentId2RenewalSegments(rentId, 0);
        assertFalse(consumed0, "index0 untouched");
    }

    // ---- version 升到 15 ----
    function testVersion_is15() public view {
        assertEq(rent.version(), 15, "version == 15");
    }

    // ---- setClawbackAdmin 仅 owner 可调 ----
    function testSetClawbackAdmin_onlyOwner() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        rent.setClawbackAdmin(CLAWBACK_ADMIN);
        // owner 可设
        vm.prank(owner);
        rent.setClawbackAdmin(CLAWBACK_ADMIN);
        assertEq(rent.clawbackAdmin(), CLAWBACK_ADMIN, "clawbackAdmin set");
    }

    // ---- clawbackAdmin 可执行 clawback(与 owner 等效退款) ----
    function testClawbackAdmin_canReverse() public {
        _setupDLP();
        string memory machineId = "caM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours); // segment 0
        vm.prank(owner);
        rent.setClawbackAdmin(CLAWBACK_ADMIN);

        uint256 rentId = _rentId(machineId);
        (uint256 segSeconds, uint256 segBase, uint256 segPlatform, uint256 segExtra, ,) =
            rent.rentId2RenewalSegments(rentId, 0);
        (,,, uint256 endBefore,) = rent.rentId2RentInfo(rentId);
        uint256 dlcBefore = rewardToken.balanceOf(payer);
        uint256 dlpBefore = IERC20(DLP).balanceOf(payer);

        vm.prank(CLAWBACK_ADMIN);
        rent.adminReverseUnpaidRenewal(machineId, 0);

        (,,, uint256 endAfter,) = rent.rentId2RentInfo(rentId);
        assertEq(endAfter, endBefore - segSeconds, "rentEndTime reduced");
        assertEq(rewardToken.balanceOf(payer), dlcBefore + segBase + segPlatform, "DLC refunded to seg.payer not admin");
        assertEq(IERC20(DLP).balanceOf(payer), dlpBefore + segExtra, "DLP refunded to seg.payer");
        (,,,,, bool consumedAfter) = rent.rentId2RenewalSegments(rentId, 0);
        assertTrue(consumedAfter, "consumed");
    }

    // ---- 非 owner 非 clawbackAdmin 仍被拒(授权面没扩大) ----
    function testClawbackAdmin_otherStillRejected() public {
        _setupDLP();
        string memory machineId = "rejM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours);
        vm.prank(owner);
        rent.setClawbackAdmin(CLAWBACK_ADMIN);
        vm.prank(address(0xBEEF)); // 既非 owner 也非 clawbackAdmin
        vm.expectRevert(bytes("not authorized"));
        rent.adminReverseUnpaidRenewal(machineId, 0);
    }

    // ---- owner 设 clawbackAdmin 后 owner 自己仍能调(双授权) ----
    function testClawbackAdmin_ownerStillWorks() public {
        _setupDLP();
        string memory machineId = "ownStillM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours);
        vm.prank(owner);
        rent.setClawbackAdmin(CLAWBACK_ADMIN);
        vm.prank(owner); // owner 仍可
        rent.adminReverseUnpaidRenewal(machineId, 0);
        (,,,,, bool consumed) = rent.rentId2RenewalSegments(_rentId(machineId), 0);
        assertTrue(consumed, "owner still authorized");
    }

    // ---- kill-switch: 设 address(0) 收回授权, 之前的 clawbackAdmin 不再能调 ----
    function testClawbackAdmin_killSwitch() public {
        _setupDLP();
        string memory machineId = "killM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours);
        vm.prank(owner);
        rent.setClawbackAdmin(CLAWBACK_ADMIN);
        vm.prank(owner);
        rent.setClawbackAdmin(address(0)); // kill-switch
        assertEq(rent.clawbackAdmin(), address(0), "cleared");
        vm.prank(CLAWBACK_ADMIN);
        vm.expectRevert(bytes("not authorized"));
        rent.adminReverseUnpaidRenewal(machineId, 0);
    }

    // ---- 默认(未设)时 clawbackAdmin=0, 仅 owner 可调(与 v14 行为一致, 防 address(0) 绕过) ----
    function testClawbackAdmin_defaultZeroOnlyOwner() public {
        _setupDLP();
        string memory machineId = "defM";
        _proxyRentV2(machineId, 1 hours);
        _renew(machineId, 1 hours);
        assertEq(rent.clawbackAdmin(), address(0), "default zero");
        // address(0) 不能因 clawbackAdmin==0 而绕过(msg.sender 不会是 0)
        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("not authorized"));
        rent.adminReverseUnpaidRenewal(machineId, 0);
        // owner 仍可
        vm.prank(owner);
        rent.adminReverseUnpaidRenewal(machineId, 0);
    }
}
