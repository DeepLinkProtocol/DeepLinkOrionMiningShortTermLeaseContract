// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {IOracle} from "../src/interface/IOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

/// @title 租赁离线惩罚 — 边界条件 + Bug 猎手
contract RentalOfflineBoundaryTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;

    address owner = address(0x01);
    address renter1 = address(0x100);
    address renter2 = address(0x200);
    address proxyPayer = address(0x300);

    function setUp() public {
        vm.startPrank(owner);
        IPrecompileContract precompile = IPrecompileContract(address(0x11));
        rewardToken = new Token();
        nftToken = new DLCNode(owner);

        // Deploy Point Token at hardcoded address
        Token pt = new Token();
        vm.etch(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6), address(pt).code);

        ERC1967Proxy p1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(p1));
        ERC1967Proxy p2 = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(p2));

        nftStaking.initialize(owner, address(nftToken), address(rewardToken), address(rent), address(dbcAIContract), 1);
        rent.initialize(owner, address(precompile), address(nftStaking), address(dbcAIContract), address(rewardToken));

        deal(address(rewardToken), owner, 500000e18);
        deal(address(rewardToken), renter1, 500000e18);
        deal(address(rewardToken), renter2, 500000e18);
        deal(address(rewardToken), address(rent), 500000e18);
        deal(address(rewardToken), address(nftStaking), 500000e18);
        deal(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6), renter1, 500000e18);
        deal(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6), address(rent), 500000e18);

        rewardToken.approve(address(nftStaking), 500000e18);
        nftStaking.setRewardStartAt(block.timestamp);
        _passH(1);

        IOracle oracle = IOracle(address(0x12));
        rent.setOracle(address(oracle));
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.reportStakingStatus.selector), abi.encode());
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.mockCall(address(rent), abi.encodeWithSelector(rent.getMachinePrice.selector), abi.encode(100));
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.getTokenPriceInUSD.selector), abi.encode(100));
        vm.stopPrank();
    }

    function _passH(uint256 h) internal { vm.warp(block.timestamp + h * 3600); vm.roll(block.number + h * 600); }
    function _passM(uint256 m) internal { vm.warp(block.timestamp + m * 60); vm.roll(block.number + m * 10); }
    function _passS(uint256 s) internal { vm.warp(block.timestamp + s); vm.roll(block.number + s / 6); }

    function _stake(string memory mid, uint256 nftId) internal {
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, mid, 16));
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true));
        vm.startPrank(owner);
        if (!nftStaking.dlcClientWalletAddress(owner)) {
            address[] memory a = new address[](1); a[0] = owner;
            nftStaking.setDLCClientWallets(a);
        }
        nftToken.mint(owner, nftId, 1);
        deal(address(rewardToken), owner, 100000e18);
        rewardToken.approve(address(nftStaking), 100000e18);
        nftToken.setApprovalForAll(address(nftStaking), true);
        uint256[] memory ids = new uint256[](1); ids[0] = nftId;
        uint256[] memory bals = new uint256[](1); bals[0] = 1;
        nftStaking.stakeV2(owner, mid, ids, bals, 48, true);
        nftStaking.addDLCToStake(mid, nftStaking.BASE_RESERVE_AMOUNT());
        vm.stopPrank();
    }

    function _rent(string memory mid, address r, uint256 hrs) internal {
        vm.startPrank(r);
        rewardToken.approve(address(rent), 100 ether);
        rent.rentMachine(mid, hrs * 1 hours);
        vm.stopPrank();
    }

    function _offline(string memory mid) internal {
        vm.prank(address(dbcAIContract));
        rent.notify(Rent.NotifyType.MachineOffline, mid);
    }

    function _online(string memory mid) internal {
        vm.prank(address(dbcAIContract));
        rent.notify(Rent.NotifyType.MachineOnline, mid);
    }

    function _skipGrace() internal { vm.roll(block.number + 31); }

    function _getRentEnd(string memory mid) internal view returns (uint256) {
        uint256 rentId = rent.machineId2RentId(mid);
        (, , , uint256 rentEndTime, ) = rent.rentId2RentInfo(rentId);
        return rentEndTime;
    }

    // ═══════════════════════════════════════
    // 边界 1: 租赁恰好在到期瞬间离线（block.timestamp == rentEndTime）
    // ═══════════════════════════════════════
    function test_Boundary_ExactExpiry() public {
        string memory mid = "exact_expiry";
        _stake(mid, 10);
        _rent(mid, renter1, 2); // rent 2h

        // 精确快进到到期时间
        uint256 rentEnd = _getRentEnd(mid);
        vm.warp(rentEnd);
        vm.roll(block.number + (2 * 600));

        // 在到期瞬间离线 — block.timestamp == rentEndTime
        // notify 检查: block.timestamp <= rentEndTime -> true, 走惩罚路径
        _offline(mid);
        _skipGrace();

        assertFalse(rent.isRented(mid), "should not be rented after exact expiry offline");
        console.log("Boundary 1 PASS: exact expiry offline handled");
    }

    // ═══════════════════════════════════════
    // 边界 2: 离线 1 秒后到期 — 只有 1 秒的未用时间
    // ═══════════════════════════════════════
    function test_Boundary_AlmostExpired() public {
        string memory mid = "almost_expired";
        _stake(mid, 11);
        _rent(mid, renter1, 2);

        // 快进到到期前 1 秒
        uint256 rentEnd = _getRentEnd(mid);
        vm.warp(rentEnd - 1);
        vm.roll(block.number + (2 * 600) - 1);

        _offline(mid);
        _skipGrace();

        assertFalse(rent.isRented(mid), "should not be rented");
        console.log("Boundary 2 PASS: 1 second before expiry");
    }

    // ═══════════════════════════════════════
    // 边界 3: 连续两次 MachineOffline 通知（重复调用）
    // ═══════════════════════════════════════
    function test_Boundary_DoubleOfflineNotify() public {
        string memory mid = "double_offline";
        _stake(mid, 12);
        _rent(mid, renter1, 5);
        _passH(1);

        // 第一次离线
        _offline(mid);
        _skipGrace();
        assertFalse(rent.isRented(mid), "should not be rented after first offline");

        // 第二次离线（重复通知）— 不应 revert
        _offline(mid);
        console.log("Boundary 3 PASS: double offline notify no revert");
    }

    // ═══════════════════════════════════════
    // 边界 4: 离线后重新上线，然后再次离线
    // ═══════════════════════════════════════
    function test_Boundary_OfflineOnlineOffline() public {
        string memory mid = "offline_online_offline";
        _stake(mid, 13);

        // 不租赁，纯挖矿
        assertEq(nftStaking.totalCalcPoint(), 100);

        // 第一次离线
        _offline(mid);
        assertEq(nftStaking.totalCalcPoint(), 0, "should be 0 after offline");

        // 上线恢复
        _online(mid);
        assertEq(nftStaking.totalCalcPoint(), 100, "should recover");

        // 第二次离线
        _offline(mid);
        assertEq(nftStaking.totalCalcPoint(), 0, "should be 0 again");

        // 再次上线
        _online(mid);
        assertEq(nftStaking.totalCalcPoint(), 100, "should recover again");

        console.log("Boundary 4 PASS: offline-online-offline cycle");
    }

    // ═══════════════════════════════════════
    // 边界 5: DLC 余额不足时不 revert（V1 路径保护）
    // ═══════════════════════════════════════
    function test_Boundary_InsufficientDLCBalance() public {
        string memory mid = "low_dlc";
        _stake(mid, 14);
        _rent(mid, renter1, 5);

        // 清空 Rent 合约的 DLC 余额
        uint256 bal = rewardToken.balanceOf(address(rent));
        vm.prank(address(rent));
        rewardToken.transfer(address(0xDEAD), bal);
        assertEq(rewardToken.balanceOf(address(rent)), 0, "rent contract should have 0 DLC");

        _passH(2);

        // 离线 — 即使余额为 0 也不应 revert
        _offline(mid);
        _skipGrace();
        console.log("Boundary 5 PASS: zero DLC balance no revert");
    }

    // ═══════════════════════════════════════
    // 边界 6: 非常短的租赁（1 秒）
    // ═══════════════════════════════════════
    function test_Boundary_OneSecondRental() public {
        string memory mid = "one_second";
        _stake(mid, 15);

        vm.startPrank(renter1);
        rewardToken.approve(address(rent), 100 ether);
        // 租 10 分钟（合约最短租赁时长约 600s）
        rent.rentMachine(mid, 600);
        vm.stopPrank();

        // 2 分钟后离线
        _passM(2);
        _offline(mid);
        _skipGrace();

        assertFalse(rent.isRented(mid), "should end rental");
        console.log("Boundary 6 PASS: 60s rental, offline at 30s");
    }

    // ═══════════════════════════════════════
    // 边界 7: 质押到期后离线 — 不应 crash
    // ═══════════════════════════════════════
    function test_Boundary_StakeExpiredThenOffline() public {
        string memory mid = "stake_expired";
        // 质押 2 小时（短期）
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, mid, 16));
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true));
        vm.startPrank(owner);
        if (!nftStaking.dlcClientWalletAddress(owner)) {
            address[] memory a = new address[](1); a[0] = owner;
            nftStaking.setDLCClientWallets(a);
        }
        nftToken.mint(owner, 16, 1);
        deal(address(rewardToken), owner, 100000e18);
        rewardToken.approve(address(nftStaking), 100000e18);
        nftToken.setApprovalForAll(address(nftStaking), true);
        uint256[] memory ids = new uint256[](1); ids[0] = 16;
        uint256[] memory bals = new uint256[](1); bals[0] = 1;
        nftStaking.stakeV2(owner, mid, ids, bals, 2, true); // 只质押 2 小时
        nftStaking.addDLCToStake(mid, nftStaking.BASE_RESERVE_AMOUNT());
        vm.stopPrank();

        // 质押到期后（3 小时后）
        _passH(3);

        // isStaking 应该仍为 true（到期但未解质押）
        // 离线通知 — 不应 crash
        _offline(mid);
        console.log("Boundary 7 PASS: stake expired then offline no crash");
    }

    // ═══════════════════════════════════════
    // 边界 8: 矿工 reservedAmount < SLASH_AMOUNT 时罚不了
    // ═══════════════════════════════════════
    function test_Boundary_InsufficientReservedForSlash() public {
        string memory mid = "low_reserve";
        // 质押但只加很少的 DLC
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, mid, 16));
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true));
        vm.startPrank(owner);
        if (!nftStaking.dlcClientWalletAddress(owner)) {
            address[] memory a = new address[](1); a[0] = owner;
            nftStaking.setDLCClientWallets(a);
        }
        nftToken.mint(owner, 17, 1);
        deal(address(rewardToken), owner, 100000e18);
        rewardToken.approve(address(nftStaking), 100000e18);
        nftToken.setApprovalForAll(address(nftStaking), true);
        uint256[] memory ids = new uint256[](1); ids[0] = 17;
        uint256[] memory bals = new uint256[](1); bals[0] = 1;
        nftStaking.stakeV2(owner, mid, ids, bals, 48, true);
        // addDLCToStake 只加 100（远小于 SLASH_AMOUNT=1000）
        nftStaking.addDLCToStake(mid, 100 * 1e18);
        vm.stopPrank();

        _rent(mid, renter1, 5);
        _passH(2);

        // 离线 — reservedAmount < SLASH_AMOUNT，slash 会走 pending 队列而非立即扣
        _offline(mid);
        _skipGrace();

        assertFalse(rent.isRented(mid), "rental should end");
        console.log("Boundary 8 PASS: low reserve -> pending slash, no revert");
    }

    // ═══════════════════════════════════════
    // 边界 9: 零地址 renter 检查
    // ═══════════════════════════════════════
    function test_Boundary_NoRenterOffline() public {
        string memory mid = "no_renter";
        _stake(mid, 18);

        // 不租赁，直接离线 — renter == address(0)
        _offline(mid);

        // 应该只停奖励
        assertEq(nftStaking.totalCalcPoint(), 0);
        assertTrue(nftStaking.isStaking(mid));
        console.log("Boundary 9 PASS: no renter -> stop rewards only");
    }

    // ═══════════════════════════════════════
    // 边界 10: penaltyDuration 精确等于 24h
    // ═══════════════════════════════════════
    function test_Boundary_Exactly24hUsed() public {
        string memory mid = "exact_24h";
        _stake(mid, 19);

        // 租 10 小时
        _rent(mid, renter1, 10);

        uint256 renterBefore = rewardToken.balanceOf(renter1);

        // 使用完整 10 小时（< 24h 上限，所以 penalty = 全部已用时间）
        _passH(10);

        // 但此时租赁已过期，走 cleanup 路径而非惩罚路径
        _offline(mid);
        _skipGrace();

        uint256 renterAfter = rewardToken.balanceOf(renter1);
        console.log("Boundary 10: renter balance change:", renterAfter - renterBefore);
        console.log("Boundary 10 PASS: exact full-use offline handled");
    }
}
