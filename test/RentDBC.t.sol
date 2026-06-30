// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RentDBC} from "../src/rent/RentDBC.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Token} from "./MockRewardToken.sol";
import {DBCStakingContractMock} from "./MockDBCAIContract.sol";

contract RentDBCTest is Test {
    RentDBC public rentDbc;
    Token public dbc; // 支付/销毁币种
    Token public dlp; // DLP 积分（矿工租金）
    DBCStakingContractMock public dbcAI;

    address owner = address(0x01);
    address platform = address(0x100);
    address priceSetter = address(0x101);
    address payerWallet = address(0xCAFE); // 后端代付钱包
    address renter = address(0xBEEF);
    address minerPayout = address(0x60D); // 矿工自定义收款
    string constant MID = "machineId"; // mock 中 calcPoint=100

    uint256 constant ONE_HOUR = 1 hours;

    function setUp() public {
        vm.startPrank(owner);
        dbc = new Token();
        dbc.initialize(owner);
        dlp = new Token();
        dlp.initialize(owner);
        dbcAI = new DBCStakingContractMock();

        ERC1967Proxy proxy = new ERC1967Proxy(address(new RentDBC()), "");
        rentDbc = RentDBC(address(proxy));
        rentDbc.initialize(owner, address(dbcAI), address(dbc), address(dlp), platform);

        rentDbc.setPriceSetter(priceSetter);
        rentDbc.setPlatformFeeRate(10); // 10%
        rentDbc.setExtraRentFeePerMinuteUSD(1000); // USD 6-decimals/min → 矿工 DLP 租金
        address[] memory admins = new address[](1);
        admins[0] = payerWallet;
        rentDbc.setRentAdmins(admins, true);
        vm.stopPrank();

        // 推送 DBC 价格（priceSetter）
        vm.prank(priceSetter);
        rentDbc.setTokenPriceInUSD(5000); // DBC/USD * 1e6 口径，任意正值

        // 给代付钱包充足 DBC + DLP 并授权
        deal(address(dbc), payerWallet, 1_000_000_000 ether);
        deal(address(dlp), payerWallet, 1_000_000_000 ether);
        vm.startPrank(payerWallet);
        dbc.approve(address(rentDbc), type(uint256).max);
        dlp.approve(address(rentDbc), type(uint256).max);
        vm.stopPrank();
    }

    function _rent(uint256 rentSeconds) internal returns (uint256 base, uint256 plat, uint256 extra) {
        (base, plat, extra) = rentDbc.getRentFees(MID, rentSeconds);
        vm.prank(payerWallet);
        rentDbc.rentProxy(renter, minerPayout, MID, rentSeconds);
    }

    function test_RentProxy_EscrowsDbcAndDlp() public {
        (uint256 base, uint256 plat, uint256 extra) = rentDbc.getRentFees(MID, ONE_HOUR);
        assertGt(base, 0, "base>0");
        assertGt(extra, 0, "extra>0");

        uint256 payerDbcBefore = dbc.balanceOf(payerWallet);
        uint256 payerDlpBefore = dlp.balanceOf(payerWallet);

        vm.prank(payerWallet);
        rentDbc.rentProxy(renter, minerPayout, MID, ONE_HOUR);

        // 合约托管 DBC(base+plat) + DLP(extra)
        assertEq(dbc.balanceOf(address(rentDbc)), base + plat, "contract holds DBC");
        assertEq(dlp.balanceOf(address(rentDbc)), extra, "contract holds DLP");
        assertEq(payerDbcBefore - dbc.balanceOf(payerWallet), base + plat, "payer paid DBC");
        assertEq(payerDlpBefore - dlp.balanceOf(payerWallet), extra, "payer paid DLP");
        assertTrue(rentDbc.isRented(MID), "rented");
        assertEq(rentDbc.getRenter(MID), renter, "renter");
    }

    function test_RentProxy_OnlyRentAdmin() public {
        vm.prank(renter);
        vm.expectRevert(RentDBC.NotRentAdmin.selector);
        rentDbc.rentProxy(renter, minerPayout, MID, ONE_HOUR);
    }

    // [#8 B 方案] getRentCostInPoint 把平台总成本(base+plat DBC + extra DLP)折算成统一积分口径，
    //   供后端「租客付 = 成本 × 加价」结构上保证 revenue ≥ cost。验证公式正确 + 覆盖全额代付。
    function test_GetRentCostInPoint_MatchesOutlayInPointTerms() public {
        (uint256 base, uint256 plat, uint256 extra) = rentDbc.getRentFees(MID, ONE_HOUR);
        uint256 price = 5000; // = setUp 的 setTokenPriceInUSD(5000)，USD 6dec/DBC
        uint256 expected = (base + plat) * price * 1e15 / 1e18 + extra;
        uint256 got = rentDbc.getRentCostInPoint(MID, ONE_HOUR);
        assertEq(got, expected, "cost-in-point formula");
        assertGt(got, 0, "cost>0");
        // extra 已是积分口径，必然 ≤ 总成本积分；DBC 部分也被计入（cost > extra 当 base/plat>0）
        assertGe(got, extra, "covers extra point");
        assertGt(got, extra, "includes dbc portion");
    }

    // 单调：租期翻倍，成本积分单调增（防定价被时长绕过）
    function test_GetRentCostInPoint_MonotonicInDuration() public {
        assertGt(
            rentDbc.getRentCostInPoint(MID, 2 * ONE_HOUR),
            rentDbc.getRentCostInPoint(MID, ONE_HOUR),
            "longer rent costs more"
        );
    }

    function test_RentProxy_RejectsBadDuration() public {
        vm.prank(payerWallet);
        vm.expectRevert(abi.encodeWithSelector(RentDBC.InvalidRentDuration.selector, uint256(5 minutes)));
        rentDbc.rentProxy(renter, minerPayout, MID, 5 minutes);
    }

    // [审计修 HIGH] renter=0 必须拒绝：否则破坏 isRented 哨兵 → 双租 + escrow 孤儿锁死
    function test_RentProxy_RejectsZeroRenter() public {
        vm.prank(payerWallet);
        vm.expectRevert(RentDBC.ZeroAddress.selector);
        rentDbc.rentProxy(address(0), minerPayout, MID, ONE_HOUR);
    }

    function test_RentProxy_RejectsDoubleRent() public {
        _rent(ONE_HOUR);
        vm.prank(payerWallet);
        vm.expectRevert(RentDBC.MachineAlreadyRented.selector);
        rentDbc.rentProxy(renter, minerPayout, MID, ONE_HOUR);
    }

    function test_EndRent_FullDuration_BurnsBase_PaysMiner_AndPlatform() public {
        (uint256 base, uint256 plat, uint256 extra) = _rent(ONE_HOUR);
        uint256 burnedBefore = rentDbc.totalBurnedAmount();
        address burnAddr = rentDbc.burnAddress(); // 默认 0x…dEaD
        uint256 burnAddrBefore = dbc.balanceOf(burnAddr);

        // 租期结束后退租
        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID);

        // [boss] base 的 DBC "销毁" = transfer 到 burnAddress（不再 burnFrom，故 totalSupply 不变）
        assertEq(rentDbc.totalBurnedAmount() - burnedBefore, base, "burned base (counter)");
        assertEq(dbc.balanceOf(burnAddr) - burnAddrBefore, base, "base sent to burnAddress");
        // platform 拿到 platformFee（DBC）
        assertEq(dbc.balanceOf(platform), plat, "platform fee");
        // 矿工拿到 extra（DLP）
        assertEq(dlp.balanceOf(minerPayout), extra, "miner DLP");
        // 合约清空
        assertEq(dbc.balanceOf(address(rentDbc)), 0, "contract DBC drained");
        assertEq(dlp.balanceOf(address(rentDbc)), 0, "contract DLP drained");
        assertFalse(rentDbc.isRented(MID) && rentDbc.getRenter(MID) != address(0), "rent cleared");
    }

    function test_EndRent_EarlyProrate_RefundsPayer() public {
        (uint256 base, uint256 plat, uint256 extra) = _rent(ONE_HOUR);
        uint256 payerDbcBefore = dbc.balanceOf(payerWallet);
        uint256 payerDlpBefore = dlp.balanceOf(payerWallet);

        // 用了一半时间，租客提前退
        vm.warp(block.timestamp + ONE_HOUR / 2);
        vm.prank(renter);
        rentDbc.endRentMachine(MID);

        uint256 usedBase = base / 2;
        uint256 usedPlat = plat / 2;
        uint256 usedExtra = extra / 2;

        // 已用 base 销毁
        assertEq(rentDbc.totalBurnedAmount(), usedBase, "burned half base");
        // platform 拿已用一半
        assertEq(dbc.balanceOf(platform), usedPlat, "platform half");
        // 矿工拿已用一半 DLP
        assertEq(dlp.balanceOf(minerPayout), usedExtra, "miner half DLP");
        // 未用部分退回 payer
        assertEq(dbc.balanceOf(payerWallet) - payerDbcBefore, (base - usedBase) + (plat - usedPlat), "DBC refund");
        assertEq(dlp.balanceOf(payerWallet) - payerDlpBefore, extra - usedExtra, "DLP refund");
    }

    function test_RenewRent_AddsFees_ExtendsEnd() public {
        _rent(ONE_HOUR);
        uint256 rentId = rentDbc.machineId2RentId(MID);
        ( , , , uint256 endBefore, , ) = rentDbc.rentId2RentInfo(rentId);

        (uint256 addBase, uint256 addPlat, uint256 addExtra) = rentDbc.getRentFees(MID, ONE_HOUR);
        vm.prank(payerWallet);
        rentDbc.renewRent(MID, ONE_HOUR);

        ( , , , uint256 endAfter, , ) = rentDbc.rentId2RentInfo(rentId);
        assertEq(endAfter - endBefore, ONE_HOUR, "end extended");
        (uint256 base2, uint256 extra2, uint256 plat2) = rentDbc.rentId2FeeInfo(rentId);
        // feeInfo 累加（注意 struct 字段顺序：baseFee, extraFee, platformFee）
        assertGt(base2, addBase - 1, "base accumulated");
        assertGt(extra2, addExtra - 1, "extra accumulated");
        assertGt(plat2, addPlat - 1, "plat accumulated");
    }

    function test_EndRent_ByStranger_BeforeEnd_Reverts() public {
        _rent(ONE_HOUR);
        vm.warp(block.timestamp + ONE_HOUR / 2);
        vm.prank(address(0xDEAD));
        vm.expectRevert(RentDBC.RentNotEnd.selector);
        rentDbc.endRentMachine(MID);
    }

    // ── 审计修复回归测试 ──

    // [HIGH] 另一个 rentAdmin 不能提前踢掉别人的租约
    function test_EndRent_OtherRentAdmin_BeforeEnd_Reverts() public {
        _rent(ONE_HOUR);
        address otherAdmin = address(0xA11);
        address[] memory admins = new address[](1);
        admins[0] = otherAdmin;
        vm.prank(owner);
        rentDbc.setRentAdmins(admins, true);

        vm.warp(block.timestamp + ONE_HOUR / 2);
        vm.prank(otherAdmin);
        vm.expectRevert(RentDBC.RentNotEnd.selector);
        rentDbc.endRentMachine(MID);
    }

    // [MED-HIGH] 续租必须由原 payer 发起
    function test_RenewRent_ByOtherAdmin_Reverts() public {
        _rent(ONE_HOUR);
        address otherAdmin = address(0xA12);
        address[] memory admins = new address[](1);
        admins[0] = otherAdmin;
        vm.prank(owner);
        rentDbc.setRentAdmins(admins, true);
        deal(address(dbc), otherAdmin, 1_000_000 ether);
        deal(address(dlp), otherAdmin, 1_000_000 ether);
        vm.startPrank(otherAdmin);
        dbc.approve(address(rentDbc), type(uint256).max);
        dlp.approve(address(rentDbc), type(uint256).max);
        vm.expectRevert(RentDBC.NotOriginalPayer.selector);
        rentDbc.renewRent(MID, ONE_HOUR);
        vm.stopPrank();
    }

    // [MED] 有活跃租约时不能切换 token
    function test_SetToken_WhileActive_Reverts() public {
        _rent(ONE_HOUR);
        vm.startPrank(owner);
        vm.expectRevert(RentDBC.TokenLockedWhileRentalsActive.selector);
        rentDbc.setFeeToken(address(0x1234));
        vm.expectRevert(RentDBC.TokenLockedWhileRentalsActive.selector);
        rentDbc.setPointToken(address(0x1234));
        vm.stopPrank();
        // 退租后可切换
        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID);
        assertEq(rentDbc.activeRentalCount(), 0);
        vm.prank(owner);
        rentDbc.setPointToken(address(dlp)); // 不 revert
    }

    // [HIGH] 黑名单的 minerPayout（point token transfer 直接 revert）不能卡死 endRent；DLP 转入 pending 可 claim
    function test_EndRent_BlacklistedMinerPayout_DefersNotBricks() public {
        // 换成可黑名单的 point token（无活跃租约时允许切换）
        BlacklistableToken bl = new BlacklistableToken();
        vm.prank(owner);
        rentDbc.setPointToken(address(bl));
        bl.mint(payerWallet, 1_000_000_000 ether);
        vm.prank(payerWallet);
        bl.approve(address(rentDbc), type(uint256).max);

        address bad = address(0xBAD);
        (, , uint256 extra) = rentDbc.getRentFees(MID, ONE_HOUR);
        vm.prank(payerWallet);
        rentDbc.rentProxy(renter, bad, MID, ONE_HOUR);

        bl.setBlocked(bad, true); // 矿工 payout 地址被 point token 拉黑

        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID); // 不应 revert

        assertEq(rentDbc.pendingPointPayout(bad), extra, "deferred to pending");
        assertEq(rentDbc.getRenter(MID), address(0), "machine freed");
        assertEq(rentDbc.activeRentalCount(), 0, "count decremented");

        // 解除黑名单后矿工可 claim
        bl.setBlocked(bad, false);
        vm.prank(bad);
        rentDbc.claimPointPayout();
        assertEq(bl.balanceOf(bad), extra, "claimed");
        assertEq(rentDbc.pendingPointPayout(bad), 0, "pending cleared");
    }

    // [boss 2026-06-30] "销毁" = transfer 到指定 burnAddress（owner 可改），不依赖 burnFrom
    function test_BurnGoesToDesignatedAddress() public {
        address collector = address(0xC0FFEE);
        vm.prank(owner);
        rentDbc.setBurnAddress(collector);
        assertEq(rentDbc.burnAddress(), collector, "burnAddress set");

        (uint256 base,,) = _rent(ONE_HOUR);
        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID);
        assertEq(dbc.balanceOf(collector), base, "base sent to designated burn address");
        assertEq(rentDbc.totalBurnedAmount(), base, "burn counter");
    }

    function test_SetBurnAddress_RejectsZero_OnlyOwner() public {
        vm.prank(owner);
        vm.expectRevert(RentDBC.ZeroAddress.selector);
        rentDbc.setBurnAddress(address(0));
        vm.prank(renter); // 非 owner
        vm.expectRevert();
        rentDbc.setBurnAddress(address(0x123));
    }

    // [审计加固 2026-06-30] payer DBC 退款腿被拉黑时 → defer 不卡死 + 可 claimDbcPayout（顺带测 burn try/catch 不 revert）
    function test_EndRent_BlacklistedPayer_DefersDbcNotBricks() public {
        BlacklistableToken bl = new BlacklistableToken();
        vm.prank(owner);
        rentDbc.setFeeToken(address(bl)); // 无活跃租约时允许切 DBC 币
        bl.mint(payerWallet, 1_000_000_000 ether);
        vm.prank(payerWallet);
        bl.approve(address(rentDbc), type(uint256).max);

        vm.prank(payerWallet);
        rentDbc.rentProxy(renter, minerPayout, MID, ONE_HOUR);

        // 提前退租(用一半) → 有 paybackDBC 退给 payer；先把 payer 在 DBC token 拉黑
        vm.warp(block.timestamp + 30 minutes);
        bl.setBlocked(payerWallet, true);

        vm.prank(renter);
        rentDbc.endRentMachine(MID); // 不应 revert（payer DBC 退款 + burn 失败都被隔离）

        uint256 owed = rentDbc.pendingDbcPayout(payerWallet);
        assertGt(owed, 0, "payer DBC payback deferred");
        assertEq(rentDbc.getRenter(MID), address(0), "machine freed");
        assertEq(rentDbc.activeRentalCount(), 0, "count decremented");

        // 解除黑名单后 payer 可 claim
        bl.setBlocked(payerWallet, false);
        uint256 beforeBal = bl.balanceOf(payerWallet);
        vm.prank(payerWallet);
        rentDbc.claimDbcPayout();
        assertEq(bl.balanceOf(payerWallet) - beforeBal, owed, "claimed");
        assertEq(rentDbc.pendingDbcPayout(payerWallet), 0, "pending cleared");
    }

    // [LOW→MED] 续租总时长上限
    function test_RenewRent_ExceedsCap_Reverts() public {
        vm.prank(owner);
        rentDbc.setMaxRentDuration(90 minutes); // 1h 起租 + 续 1h = 2h > 1.5h 上限
        _rent(ONE_HOUR);
        vm.prank(payerWallet);
        vm.expectRevert();
        rentDbc.renewRent(MID, ONE_HOUR);
    }

    // ── Round 2 审计修复回归 ──

    // [R2 HIGH] 有未领 pending 时不能 setPointToken（否则旧 DLP 困死/新币被挪用）
    function test_SetPointToken_WithPending_Reverts() public {
        BlacklistableToken bl = new BlacklistableToken();
        vm.prank(owner);
        rentDbc.setPointToken(address(bl));
        bl.mint(payerWallet, 1_000_000_000 ether);
        vm.prank(payerWallet);
        bl.approve(address(rentDbc), type(uint256).max);

        address bad = address(0xBAD2);
        vm.prank(payerWallet);
        rentDbc.rentProxy(renter, bad, MID, ONE_HOUR);
        bl.setBlocked(bad, true);
        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID); // defer → totalPendingPointPayout > 0

        assertGt(rentDbc.totalPendingPointPayout(), 0, "has pending");
        assertEq(rentDbc.activeRentalCount(), 0, "no active rentals");
        // 即使无活跃租约，pending 未清也不能换币
        vm.prank(owner);
        vm.expectRevert(RentDBC.PendingPayoutsOutstanding.selector);
        rentDbc.setPointToken(address(dlp));

        // 矿工 claim 清空 pending 后可换币
        bl.setBlocked(bad, false);
        vm.prank(bad);
        rentDbc.claimPointPayout();
        assertEq(rentDbc.totalPendingPointPayout(), 0, "pending cleared");
        vm.prank(owner);
        rentDbc.setPointToken(address(dlp)); // 不 revert
    }

    // [R2 LOW] returns false（不 revert）的 token 也走 defer 分支
    function test_EndRent_PointReturnsFalse_Defers() public {
        ReturnsFalseToken rf = new ReturnsFalseToken();
        vm.prank(owner);
        rentDbc.setPointToken(address(rf));
        rf.mint(payerWallet, 1_000_000_000 ether);
        vm.prank(payerWallet);
        rf.approve(address(rentDbc), type(uint256).max);

        address miner = address(0x71);
        (, , uint256 extra) = rentDbc.getRentFees(MID, ONE_HOUR);
        vm.prank(payerWallet);
        rentDbc.rentProxy(renter, miner, MID, ONE_HOUR);
        rf.setReturnFalse(true); // payout transfer 返回 false（不 revert）

        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID); // 不 revert，走 ok==false → defer
        assertEq(rentDbc.pendingPointPayout(miner), extra, "deferred on false");
        assertEq(rentDbc.totalPendingPointPayout(), extra, "total tracked");
    }

    // [R2 LOW] owner 可 rescue 误转入的代币（仅无义务时）
    function test_RescueToken_OnlyWhenNoObligations() public {
        // 误转入一些 DBC
        deal(address(dbc), address(rentDbc), 123 ether);
        // 有活跃租约时不能 rescue
        _rent(ONE_HOUR);
        vm.prank(owner);
        vm.expectRevert(RentDBC.HasObligations.selector);
        rentDbc.rescueToken(address(dbc), owner, 1 ether);
        // 退租后可 rescue 误转入余额
        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID);
        uint256 stray = dbc.balanceOf(address(rentDbc));
        assertGt(stray, 0, "stray dbc present");
        vm.prank(owner);
        rentDbc.rescueToken(address(dbc), owner, stray);
        assertEq(dbc.balanceOf(address(rentDbc)), 0, "rescued");
    }

    // ── Round 3 审计修复回归 ──

    // [R3 MED] owner 强制清理卡死租约：解锁机器 + 解 activeRentalCount，之后可 rescue 残留
    function test_ForceCleanup_UnsticksMachine() public {
        _rent(ONE_HOUR);
        assertTrue(rentDbc.isRented(MID), "rented");
        assertEq(rentDbc.activeRentalCount(), 1);

        vm.prank(owner);
        rentDbc.forceCleanupRentInfoByOwner(MID);

        assertEq(rentDbc.getRenter(MID), address(0), "cleared");
        assertEq(rentDbc.activeRentalCount(), 0, "count freed");
        // 残留 escrow 可救回
        uint256 dlpStray = dlp.balanceOf(address(rentDbc));
        if (dlpStray > 0) {
            vm.prank(owner);
            rentDbc.rescueToken(address(dlp), owner, dlpStray);
        }
    }

    function test_ForceCleanup_OnlyOwner() public {
        _rent(ONE_HOUR);
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        rentDbc.forceCleanupRentInfoByOwner(MID);
    }

    // [R3 HIGH] dbcAI 命名空间参数可配
    function test_SetDbcAIQueryIsDeepLink() public {
        assertEq(rentDbc.dbcAIQueryIsDeepLink(), false, "default false");
        vm.prank(owner);
        rentDbc.setDbcAIQueryIsDeepLink(true);
        assertEq(rentDbc.dbcAIQueryIsDeepLink(), true, "now true");
        // 定价仍可工作（mock 忽略 flag）
        (uint256 base,,) = rentDbc.getRentFees(MID, ONE_HOUR);
        assertGt(base, 0);
    }

    // [+30% 桥] rentProxy 通知 true、endRent 通知 false
    function test_RentBonusBridge_NotifiedOnRentAndEnd() public {
        BridgeMock bridge = new BridgeMock();
        vm.prank(owner);
        rentDbc.setRentBonusBridge(address(bridge));

        _rent(ONE_HOUR);
        assertEq(bridge.callCount(), 1, "notified on rent");
        assertTrue(bridge.lastRented(), "rented=true");

        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID);
        assertEq(bridge.callCount(), 2, "notified on end");
        assertFalse(bridge.lastRented(), "rented=false");
    }

    // [+30% 桥] 桥 revert 不阻塞租用/退租（bonus 非关键路径）
    function test_RentBonusBridge_FailureDoesNotBlock() public {
        BridgeMock bridge = new BridgeMock();
        bridge.setShouldRevert(true);
        vm.prank(owner);
        rentDbc.setRentBonusBridge(address(bridge));

        // 桥 revert，但租用照常成功
        _rent(ONE_HOUR);
        assertTrue(rentDbc.isRented(MID), "rent succeeded despite bridge down");
        assertEq(bridge.callCount(), 0, "bridge reverted, no record");

        // 退租也照常
        vm.warp(block.timestamp + ONE_HOUR + 1);
        rentDbc.endRentMachine(MID);
        assertEq(rentDbc.getRenter(MID), address(0), "end succeeded despite bridge down");
    }

    // [+30% 桥] 未配置桥(0)时正常运行
    function test_RentBonusBridge_DisabledByDefault() public {
        assertEq(rentDbc.rentBonusBridge(), address(0), "disabled by default");
        _rent(ONE_HOUR); // 不 revert
        assertTrue(rentDbc.isRented(MID));
    }

    // [R3 MED] 价格超龄回退 oracle
    function test_StalePrice_FallsBackToOracle() public {
        // 部署一个返回固定价的 oracle mock
        OracleMock om = new OracleMock(7777);
        vm.startPrank(owner);
        rentDbc.setOracle(address(om));
        rentDbc.setMaxPriceAge(1 hours);
        vm.stopPrank();
        // 当前 tokenPriceInfo=5000（setUp 推送）。未超龄 → 用 5000
        (uint256 baseFresh,,) = rentDbc.getRentFees(MID, ONE_HOUR);
        // 超龄后 → 回退 oracle(7777)，价格不同 → base 不同
        vm.warp(block.timestamp + 2 hours);
        (uint256 baseStale,,) = rentDbc.getRentFees(MID, ONE_HOUR);
        assertTrue(baseFresh != baseStale, "stale falls back to oracle price");
    }
}

/// 测试用 RentBridge：记录 setMachineRentedForDeepLink 调用
contract BridgeMock {
    bool public lastRented;
    uint256 public callCount;
    bool public shouldRevert;

    function setShouldRevert(bool b) external {
        shouldRevert = b;
    }

    function setMachineRentedForDeepLink(string calldata, bool isRented) external {
        if (shouldRevert) {
            revert("bridge down");
        }
        lastRented = isRented;
        callCount += 1;
    }
}

/// 测试用 oracle：固定返回价
contract OracleMock {
    uint256 public price;

    constructor(uint256 p) {
        price = p;
    }

    function getTokenPriceInUSD(uint32, address) external view returns (uint256) {
        return price;
    }
}

/// 测试用：transfer 永远返回 false（不 revert），模拟静默失败的 token
contract ReturnsFalseToken is ERC20 {
    bool public retFalse;

    constructor() ERC20("RF", "RF") {}

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }

    function setReturnFalse(bool b) external {
        retFalse = b;
    }

    function transfer(address to, uint256 amt) public override returns (bool) {
        if (retFalse) {
            return false; // 不动账，直接返回 false
        }
        return super.transfer(to, amt);
    }
}

/// 测试用：可黑名单 ERC20，模拟 point token 对某地址 transfer revert（黑名单/暂停）
contract BlacklistableToken is ERC20 {
    mapping(address => bool) public blocked;

    constructor() ERC20("BL", "BL") {}

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }

    function setBlocked(address a, bool b) external {
        blocked[a] = b;
    }

    function transfer(address to, uint256 amt) public override returns (bool) {
        require(!blocked[to], "blocked");
        return super.transfer(to, amt);
    }

    function transferFrom(address from, address to, uint256 amt) public override returns (bool) {
        require(!blocked[to], "blocked");
        return super.transferFrom(from, to, amt);
    }
}
