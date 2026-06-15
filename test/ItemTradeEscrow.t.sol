// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ItemTradeEscrow} from "../src/ItemTradeEscrow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDLP is ERC20 {
    constructor() ERC20("DeepLink Point", "DLP") {}
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}

contract ItemTradeEscrowTest is Test {
    ItemTradeEscrow esc;
    MockDLP dlp;

    address owner    = address(0xA11CE);
    address feeRecv  = address(0xFEE);
    address arbiter  = address(0xA2B1);
    address buyer    = address(0xB0B);
    address seller   = address(0x5E11E2);
    address stranger = address(0x57A);

    uint256 constant PRICE = 100_000 ether; // 100k DLP
    bytes32 constant OID = keccak256("order-1");

    function setUp() public {
        dlp = new MockDLP();
        ItemTradeEscrow impl = new ItemTradeEscrow();
        bytes memory initData = abi.encodeCall(
            ItemTradeEscrow.initialize, (address(dlp), feeRecv, arbiter, owner)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        esc = ItemTradeEscrow(address(proxy));

        dlp.mint(buyer, 1_000_000 ether);
        vm.prank(buyer);
        dlp.approve(address(esc), type(uint256).max);
    }

    // ───────── helpers
    function _create(bytes32 oid) internal {
        vm.prank(buyer);
        esc.createOrder(oid, seller, PRICE);
    }

    // ───────── init / config
    function test_init() public view {
        assertEq(address(esc.dlpToken()), address(dlp));
        assertEq(esc.feeRecipient(), feeRecv);
        assertEq(esc.arbiter(), arbiter);
        assertEq(esc.feeBps(), 250);
        assertEq(esc.autoConfirmPeriod(), 7 days);
        assertEq(esc.owner(), owner);
        assertEq(esc.version(), 2);
        assertEq(esc.disputeTimeout(), 0); // 灾难兜底出厂默认关闭
    }

    function test_cannot_reinitialize() public {
        vm.expectRevert();
        esc.initialize(address(dlp), feeRecv, arbiter, owner);
    }

    // ───────── createOrder
    function test_createOrder_locksFunds() public {
        _create(OID);
        assertEq(dlp.balanceOf(address(esc)), PRICE);
        ItemTradeEscrow.Order memory o = esc.getOrder(OID);
        assertEq(o.buyer, buyer);
        assertEq(o.seller, seller);
        assertEq(o.amount, PRICE);
        assertEq(uint8(o.state), uint8(ItemTradeEscrow.State.Paid));
    }

    function test_createOrder_rejects_selfTrade() public {
        vm.prank(seller);
        dlp.approve(address(esc), type(uint256).max);
        vm.prank(seller);
        vm.expectRevert(bytes("self trade"));
        esc.createOrder(OID, seller, PRICE);
    }

    function test_createOrder_rejects_zeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("amount=0"));
        esc.createOrder(OID, seller, 0);
    }

    function test_createOrder_rejects_duplicateId() public {
        _create(OID);
        vm.prank(buyer);
        vm.expectRevert(bytes("order exists"));
        esc.createOrder(OID, seller, PRICE); // replay same id
    }

    function test_createOrder_rejects_zeroSeller() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("seller=0"));
        esc.createOrder(OID, address(0), PRICE);
    }

    // ───────── happy path: deliver → confirm → release with fee
    function test_confirm_releasesWithFee() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);

        uint256 fee = PRICE * 250 / 10000;
        uint256 net = PRICE - fee;

        vm.prank(buyer);
        esc.confirmReceived(OID);

        assertEq(dlp.balanceOf(seller), net);
        assertEq(dlp.balanceOf(feeRecv), fee);
        assertEq(dlp.balanceOf(address(esc)), 0);
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Released));
    }

    function test_confirm_fromPaid_withoutDelivery() public {
        _create(OID);
        vm.prank(buyer);
        esc.confirmReceived(OID); // buyer may confirm even before seller marks delivered
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Released));
    }

    function test_confirm_onlyBuyer() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(stranger);
        vm.expectRevert(bytes("not buyer"));
        esc.confirmReceived(OID);
    }

    function test_cannot_doubleRelease() public {
        _create(OID);
        vm.prank(buyer);
        esc.confirmReceived(OID);
        vm.prank(buyer);
        vm.expectRevert(bytes("bad state"));
        esc.confirmReceived(OID);
    }

    // ───────── markDelivered
    function test_markDelivered_onlySeller() public {
        _create(OID);
        vm.prank(stranger);
        vm.expectRevert(bytes("not seller"));
        esc.markDelivered(OID);
    }

    // ───────── claimAfterTimeout
    function test_claimAfterTimeout_releases() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);

        vm.expectRevert(bytes("too early"));
        esc.claimAfterTimeout(OID);

        vm.warp(block.timestamp + 7 days);
        // permissionless: stranger can trigger
        vm.prank(stranger);
        esc.claimAfterTimeout(OID);

        uint256 fee = PRICE * 250 / 10000;
        assertEq(dlp.balanceOf(seller), PRICE - fee);
        assertEq(dlp.balanceOf(feeRecv), fee);
    }

    function test_claimAfterTimeout_requiresDelivered() public {
        _create(OID); // still Paid, no deliveredAt
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(bytes("not delivered"));
        esc.claimAfterTimeout(OID);
    }

    function test_isClaimable() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        assertFalse(esc.isClaimable(OID));
        vm.warp(block.timestamp + 7 days);
        assertTrue(esc.isClaimable(OID));
    }

    // ───────── cancel
    function test_cancel_refundsBuyer() public {
        _create(OID);
        uint256 before = dlp.balanceOf(buyer);
        vm.prank(seller); // seller declines
        esc.cancel(OID);
        assertEq(dlp.balanceOf(buyer), before + PRICE);
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Cancelled));
    }

    function test_cancel_rejected_afterDelivered() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(buyer);
        vm.expectRevert(bytes("not cancellable"));
        esc.cancel(OID);
    }

    function test_cancel_sellerOnly() public {
        _create(OID);
        // 反诈 F-1: 买家不能单方取消退款（防收货后自退）
        vm.prank(buyer);
        vm.expectRevert(bytes("not seller"));
        esc.cancel(OID);
        // 陌生人也不行
        vm.prank(stranger);
        vm.expectRevert(bytes("not seller"));
        esc.cancel(OID);
        // 买家付款后想退出 → 走 openDispute（arbiter 退款）
        vm.prank(buyer);
        esc.openDispute(OID);
        uint256 before = dlp.balanceOf(buyer);
        vm.prank(arbiter);
        esc.resolveDispute(OID, false);
        assertEq(dlp.balanceOf(buyer), before + PRICE);
    }

    // ───────── dispute / resolve
    function test_dispute_resolveToSeller() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(buyer);
        esc.openDispute(OID);

        vm.prank(arbiter);
        esc.resolveDispute(OID, true);
        uint256 fee = PRICE * 250 / 10000;
        assertEq(dlp.balanceOf(seller), PRICE - fee);
        assertEq(dlp.balanceOf(feeRecv), fee);
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Released));
    }

    function test_dispute_resolveToBuyer_fullRefund_noFee() public {
        _create(OID);
        vm.prank(buyer);
        esc.openDispute(OID);
        uint256 before = dlp.balanceOf(buyer);

        vm.prank(arbiter);
        esc.resolveDispute(OID, false);
        assertEq(dlp.balanceOf(buyer), before + PRICE); // full, no fee
        assertEq(dlp.balanceOf(feeRecv), 0);
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Refunded));
    }

    function test_resolve_onlyArbiter() public {
        _create(OID);
        vm.prank(buyer);
        esc.openDispute(OID);
        vm.prank(stranger);
        vm.expectRevert(bytes("not arbiter/owner"));
        esc.resolveDispute(OID, true);
    }

    function test_resolve_ownerFallback() public {
        // arbiter 私钥丢失时 owner 兜底裁决，防 Disputed 资金永久锁死
        _create(OID);
        vm.prank(buyer);
        esc.openDispute(OID);
        uint256 before = dlp.balanceOf(buyer);
        vm.prank(owner);
        esc.resolveDispute(OID, false); // owner 退款买家
        assertEq(dlp.balanceOf(buyer), before + PRICE);
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Refunded));
    }

    function test_feeBps_snapshotAtCreate() public {
        // 下单时锁定 2.5%；owner 事后改费率不影响在途订单
        _create(OID);
        vm.prank(owner);
        esc.setFeeBps(1000); // 改到 10%
        uint256 expectFee = PRICE * 250 / 10000; // 仍按下单时 2.5%
        vm.prank(buyer);
        esc.confirmReceived(OID);
        assertEq(dlp.balanceOf(feeRecv), expectFee);
        assertEq(dlp.balanceOf(seller), PRICE - expectFee);
        // 新订单才用新费率
        bytes32 oid2 = keccak256("order-2");
        vm.prank(buyer);
        esc.createOrder(oid2, seller, PRICE);
        assertEq(esc.getOrder(oid2).feeBps, 1000);
    }

    function test_openDispute_onlyParties() public {
        _create(OID);
        vm.prank(stranger);
        vm.expectRevert(bytes("forbidden"));
        esc.openDispute(OID);
    }

    // ───────── governance + access control
    function test_setFeeBps_capped() public {
        vm.prank(owner);
        vm.expectRevert(bytes("fee too high"));
        esc.setFeeBps(1001);
        vm.prank(owner);
        esc.setFeeBps(300);
        assertEq(esc.feeBps(), 300);
    }

    function test_setters_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        esc.setFeeRecipient(stranger);
        vm.prank(stranger);
        vm.expectRevert();
        esc.setArbiter(stranger);
    }

    function test_setAutoConfirm_bounds() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("out of range"));
        esc.setAutoConfirmPeriod(1 hours);
        vm.expectRevert(bytes("out of range"));
        esc.setAutoConfirmPeriod(31 days);
        esc.setAutoConfirmPeriod(3 days);
        assertEq(esc.autoConfirmPeriod(), 3 days);
        vm.stopPrank();
    }

    // ───────── upgrade auth
    function test_upgrade_onlyCanUpgrade() public {
        ItemTradeEscrow impl2 = new ItemTradeEscrow();
        vm.prank(stranger);
        vm.expectRevert(bytes("not upgrader"));
        esc.upgradeToAndCall(address(impl2), "");
        // owner is canUpgradeAddress by default
        vm.prank(owner);
        esc.upgradeToAndCall(address(impl2), "");
        assertEq(esc.version(), 2);
    }

    function test_upgrade_ownerFallback_afterCanUpgradeChanged() public {
        // 即使 canUpgradeAddress 改成别处，owner 仍能兜底升级（防 H-1 永久锁死）
        vm.prank(owner);
        esc.setCanUpgradeAddress(stranger);
        ItemTradeEscrow impl2 = new ItemTradeEscrow();
        vm.prank(owner);
        esc.upgradeToAndCall(address(impl2), "");
        assertEq(esc.version(), 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //   claimDisputeTimeout — 恶意冻结灾难兜底（方向 B，出厂默认关闭）
    // ═══════════════════════════════════════════════════════════════════════

    function test_disputeTimeout_default_off() public view {
        assertEq(esc.disputeTimeout(), 0); // 出厂默认关闭（kill-switch）
        assertEq(esc.MIN_DISPUTE_TIMEOUT(), 14 days);
        assertEq(esc.MAX_DISPUTE_TIMEOUT(), 90 days);
        assertEq(esc.version(), 2);
    }

    // 1) Delivered → buyer openDispute → setDisputeTimeout(30d) → warp → seller 自救放款
    function test_claimDisputeTimeout_releasesToSeller_withFee() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(buyer); // 买家恶意冻结
        esc.openDispute(OID);

        vm.prank(owner);
        esc.setDisputeTimeout(30 days);

        vm.warp(block.timestamp + 30 days);
        vm.prank(seller); // 卖家自救
        esc.claimDisputeTimeout(OID);

        uint256 fee = PRICE * 250 / 10000; // feeBps 锁定 = 下单时 2.5%
        uint256 net = PRICE - fee;
        assertEq(dlp.balanceOf(seller), net);
        assertEq(dlp.balanceOf(feeRecv), fee);
        assertEq(dlp.balanceOf(address(esc)), 0);
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Released));
    }

    // 2) 红队约束1命门：Paid（从未 markDelivered）→ openDispute → warp 很久 → revert("never delivered")
    function test_claimDisputeTimeout_rejects_neverDelivered() public {
        _create(OID); // 仅 Paid，deliveredAt == 0
        vm.prank(buyer);
        esc.openDispute(OID);
        vm.prank(owner);
        esc.setDisputeTimeout(14 days);

        vm.warp(block.timestamp + 365 days); // 等再久也不行
        vm.prank(seller);
        vm.expectRevert(bytes("never delivered"));
        esc.claimDisputeTimeout(OID);
    }

    // 3) 窗口未到：warp(timeout - 1) → revert("too early")
    function test_claimDisputeTimeout_tooEarly() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        uint64 deliveredAt = esc.getOrder(OID).deliveredAt;
        vm.prank(buyer);
        esc.openDispute(OID);
        vm.prank(owner);
        esc.setDisputeTimeout(30 days);

        vm.warp(uint256(deliveredAt) + 30 days - 1); // 差 1 秒
        vm.prank(seller);
        vm.expectRevert(bytes("too early"));
        esc.claimDisputeTimeout(OID);
    }

    // 4) disputeTimeout == 0（默认/被 owner 关闭）→ revert("timeout disabled")
    function test_claimDisputeTimeout_disabledByDefault() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(buyer);
        esc.openDispute(OID);
        // 未设 disputeTimeout，仍为 0
        vm.warp(block.timestamp + 365 days);
        vm.prank(seller);
        vm.expectRevert(bytes("timeout disabled"));
        esc.claimDisputeTimeout(OID);
    }

    function test_claimDisputeTimeout_killSwitch_relock() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(buyer);
        esc.openDispute(OID);
        vm.startPrank(owner);
        esc.setDisputeTimeout(30 days);
        esc.setDisputeTimeout(0); // kill-switch 重新关闭
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);
        vm.prank(seller);
        vm.expectRevert(bytes("timeout disabled"));
        esc.claimDisputeTimeout(OID);
    }

    // 5) 仲裁优先：窗口内 resolveDispute(false) 全退买家，事后 claim → revert("not disputed")
    function test_claimDisputeTimeout_arbiterTakesPriority() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(buyer);
        esc.openDispute(OID);
        vm.prank(owner);
        esc.setDisputeTimeout(30 days);

        uint256 before = dlp.balanceOf(buyer);
        vm.prank(arbiter); // 窗口内仲裁先于自救生效
        esc.resolveDispute(OID, false);
        assertEq(dlp.balanceOf(buyer), before + PRICE); // 全退买家，无 fee
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Refunded));

        vm.warp(block.timestamp + 30 days);
        vm.prank(seller);
        vm.expectRevert(bytes("not disputed")); // 已终结
        esc.claimDisputeTimeout(OID);
    }

    // 6a) 权限：非 seller 调 → revert("not seller")
    function test_claimDisputeTimeout_onlySeller() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(buyer);
        esc.openDispute(OID);
        vm.prank(owner);
        esc.setDisputeTimeout(30 days);
        vm.warp(block.timestamp + 30 days);

        vm.prank(buyer);
        vm.expectRevert(bytes("not seller"));
        esc.claimDisputeTimeout(OID);
        vm.prank(stranger);
        vm.expectRevert(bytes("not seller"));
        esc.claimDisputeTimeout(OID);
        vm.prank(arbiter);
        vm.expectRevert(bytes("not seller"));
        esc.claimDisputeTimeout(OID);
    }

    // 6b) setDisputeTimeout 非 owner → revert
    function test_setDisputeTimeout_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        esc.setDisputeTimeout(30 days);
        vm.prank(arbiter);
        vm.expectRevert();
        esc.setDisputeTimeout(30 days);
    }

    // 6c) 上下界：13d/91d revert；0/14d/90d ok
    function test_setDisputeTimeout_bounds() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("out of range"));
        esc.setDisputeTimeout(13 days);
        vm.expectRevert(bytes("out of range"));
        esc.setDisputeTimeout(91 days);

        esc.setDisputeTimeout(14 days);
        assertEq(esc.disputeTimeout(), 14 days);
        esc.setDisputeTimeout(90 days);
        assertEq(esc.disputeTimeout(), 90 days);
        esc.setDisputeTimeout(0); // kill-switch 允许
        assertEq(esc.disputeTimeout(), 0);
        vm.stopPrank();
    }

    // 7) claim 后再 claim / confirm / resolve 全 revert（终态不可逆）
    function test_claimDisputeTimeout_terminalIrreversible() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.prank(buyer);
        esc.openDispute(OID);
        vm.prank(owner);
        esc.setDisputeTimeout(30 days);
        vm.warp(block.timestamp + 30 days);
        vm.prank(seller);
        esc.claimDisputeTimeout(OID); // → Released

        vm.prank(seller);
        vm.expectRevert(bytes("not disputed"));
        esc.claimDisputeTimeout(OID);
        vm.prank(buyer);
        vm.expectRevert(bytes("bad state"));
        esc.confirmReceived(OID);
        vm.prank(arbiter);
        vm.expectRevert(bytes("not disputed"));
        esc.resolveDispute(OID, true);
    }

    // 8) 非 Disputed 态（Paid / Delivered / Released）调 claimDisputeTimeout → revert("not disputed")
    function test_claimDisputeTimeout_rejects_nonDisputedStates() public {
        vm.prank(owner);
        esc.setDisputeTimeout(30 days);

        // Paid
        _create(OID);
        vm.warp(block.timestamp + 365 days);
        vm.prank(seller);
        vm.expectRevert(bytes("not disputed"));
        esc.claimDisputeTimeout(OID);

        // Delivered
        vm.prank(seller);
        esc.markDelivered(OID);
        vm.warp(block.timestamp + 365 days);
        vm.prank(seller);
        vm.expectRevert(bytes("not disputed"));
        esc.claimDisputeTimeout(OID);

        // Released (买家确认)
        vm.prank(buyer);
        esc.confirmReceived(OID);
        vm.prank(seller);
        vm.expectRevert(bytes("not disputed"));
        esc.claimDisputeTimeout(OID);
    }

    // ───────────────────────────────────────────────────────────────────────
    //   红队向量3：disputeInitiator 闸门 —— 仅买家发起的纠纷才允许卖家超时自救
    // ───────────────────────────────────────────────────────────────────────

    // 10) 🔴 BLOCKER：seller 自走 markDelivered(不真发货)→seller 自己 openDispute→
    //     warp(disputeTimeout)→seller claimDisputeTimeout 必须 revert("not buyer-initiated")。
    //     堵死骗子卖家单方提走买家本金的攻击向量。
    function test_claimDisputeTimeout_rejects_sellerInitiated() public {
        _create(OID);
        vm.startPrank(seller);
        esc.markDelivered(OID);
        esc.openDispute(OID); // 卖家自开纠纷
        vm.stopPrank();

        // 记录的发起方应是 seller（不是 buyer）
        assertEq(esc.disputeInitiator(OID), seller);

        vm.prank(owner);
        esc.setDisputeTimeout(30 days);
        vm.warp(block.timestamp + 30 days);

        vm.prank(seller);
        vm.expectRevert(bytes("not buyer-initiated"));
        esc.claimDisputeTimeout(OID);

        // 资金仍锁在合约，订单仍 Disputed，只能等 arbiter 裁
        assertEq(dlp.balanceOf(address(esc)), PRICE);
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Disputed));
    }

    // 11) seller 自开纠纷后，arbiter 仍可正常裁决（兜底路径不受影响）
    function test_sellerInitiated_arbiterCanStillResolve() public {
        _create(OID);
        vm.startPrank(seller);
        esc.markDelivered(OID);
        esc.openDispute(OID);
        vm.stopPrank();
        assertEq(esc.disputeInitiator(OID), seller);

        uint256 before = dlp.balanceOf(buyer);
        vm.prank(arbiter);
        esc.resolveDispute(OID, false); // 卖家没真发货 → 退买家
        assertEq(dlp.balanceOf(buyer), before + PRICE);
        assertEq(uint8(esc.getOrder(OID).state), uint8(ItemTradeEscrow.State.Refunded));
    }

    // 12) disputeInitiator 记录正确：buyer 开记 buyer
    function test_disputeInitiator_recordsBuyer() public {
        _create(OID);
        vm.prank(seller);
        esc.markDelivered(OID);
        assertEq(esc.disputeInitiator(OID), address(0)); // 开纠纷前为 0
        vm.prank(buyer);
        esc.openDispute(OID);
        assertEq(esc.disputeInitiator(OID), buyer);
    }

    // 13) disputeInitiator 记录正确：seller 开记 seller（Paid 态直接开）
    function test_disputeInitiator_recordsSeller() public {
        _create(OID);
        vm.prank(seller);
        esc.openDispute(OID); // Paid 态卖家开纠纷
        assertEq(esc.disputeInitiator(OID), seller);
    }

    // 9) fuzz：claimDisputeTimeout 路径放款 net + fee == amount, fee <= amount
    function testFuzz_claimDisputeTimeout_feeMath(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);
        dlp.mint(buyer, amount);
        bytes32 oid = keccak256(abi.encode("dt", amount));
        vm.prank(buyer);
        esc.createOrder(oid, seller, amount);
        vm.prank(seller);
        esc.markDelivered(oid);
        vm.prank(buyer);
        esc.openDispute(oid);
        vm.prank(owner);
        esc.setDisputeTimeout(14 days);
        vm.warp(block.timestamp + 14 days);

        uint256 sellerBefore = dlp.balanceOf(seller);
        uint256 feeBefore = dlp.balanceOf(feeRecv);
        vm.prank(seller);
        esc.claimDisputeTimeout(oid);
        uint256 paidNet = dlp.balanceOf(seller) - sellerBefore;
        uint256 paidFee = dlp.balanceOf(feeRecv) - feeBefore;
        assertEq(paidNet + paidFee, amount);
        assertLe(paidFee, amount);
    }

    // ───────── fuzz fee math invariant: net + fee == amount, fee <= amount
    function testFuzz_feeMath(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);
        dlp.mint(buyer, amount);
        bytes32 oid = keccak256(abi.encode("f", amount));
        vm.prank(buyer);
        esc.createOrder(oid, seller, amount);
        uint256 sellerBefore = dlp.balanceOf(seller);
        uint256 feeBefore = dlp.balanceOf(feeRecv);
        vm.prank(buyer);
        esc.confirmReceived(oid);
        uint256 paidNet = dlp.balanceOf(seller) - sellerBefore;
        uint256 paidFee = dlp.balanceOf(feeRecv) - feeBefore;
        assertEq(paidNet + paidFee, amount);
        assertLe(paidFee, amount);
    }
}
