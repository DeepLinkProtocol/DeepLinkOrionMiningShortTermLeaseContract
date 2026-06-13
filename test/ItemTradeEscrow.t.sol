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
        assertEq(esc.version(), 1);
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

    function test_cancel_onlyParties() public {
        _create(OID);
        vm.prank(stranger);
        vm.expectRevert(bytes("forbidden"));
        esc.cancel(OID);
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
        vm.expectRevert(bytes("not arbiter"));
        esc.resolveDispute(OID, true);
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
        assertEq(esc.version(), 1);
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
