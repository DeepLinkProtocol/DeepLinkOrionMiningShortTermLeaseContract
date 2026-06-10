// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/NFTStaking.sol";

interface IProxyV18 {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

/// @title v17 → v18 mainnet fork 升级模拟 + 真实链上机器存储保全验证
/// @notice 用 DBC mainnet RPC fork, 在真实 mainnet state 上测 v18 stakeAdmin 升级 + adminAddStakeHours
/// @dev 跑命令:
///   forge test --match-contract ForkTestV18StakeAdmin --fork-url https://rpc2.dbcwallet.io -vv
contract ForkTestV18StakeAdmin is Test {
    address constant STAKING_PROXY = 0x6268Aba94D0d0e4FB917cC02765f631f309a7388;
    address constant UPGRADE_ADDR = 0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8;
    address constant OWNER_ADDR = 0x244f8191010a9C20aaE96DC4afa4E1D63983802E;

    NFTStaking staking;
    address stakeAdminWallet = vm.addr(0x57A4E);
    address randomWallet = vm.addr(0xBAD);
    string[] candidates;

    // 升级前快照存 storage(非 stack), 避免跨升级持有过多 local 导致 stack too deep
    address sHolder; uint256 sStart; uint256 sEnd; uint256 sCalc; uint256 sReserved; uint256 sNft; uint256 sNext;

    function setUp() public {
        staking = NFTStaking(STAKING_PROXY);
        // 2026-06-10 또와PC방 重新质押的机器 (应为活跃质押)
        candidates.push("4e7e6cbee8161791986a944e31432391dddc56ae67535242f81217d24b6746e7");
        candidates.push("fb9cab42531aa9197939a4780c1c571040a3ffdb6574366273d5d90073901088");
        candidates.push("df28df48c195cab41bfe6111f0dae62fed9ffdf13cc8f8d7d93410f17596cc00");
        console.log("Pre-upgrade NFTStaking version:", staking.version());
    }

    function _upgradeToV18() internal {
        vm.startPrank(UPGRADE_ADDR);
        NFTStaking newImpl = new NFTStaking();
        IProxyV18(STAKING_PROXY).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
        assertEq(staking.version(), 18, "version 18 post-upgrade");
        console.log("Upgraded to v18, impl:", address(newImpl));
    }

    // 单字段读取 helper (浅 stack)
    function _endAt(string memory mid) internal view returns (uint256 e) { ( , , , e, , , , , , , ) = staking.machineId2StakeInfos(mid); }
    function _holder(string memory mid) internal view returns (address h) { (h, , , , , , , , , , ) = staking.machineId2StakeInfos(mid); }
    function _start(string memory mid) internal view returns (uint256 s) { ( , s, , , , , , , , , ) = staking.machineId2StakeInfos(mid); }
    function _calc(string memory mid) internal view returns (uint256 c) { ( , , , , c, , , , , , ) = staking.machineId2StakeInfos(mid); }
    function _reserved(string memory mid) internal view returns (uint256 r) { ( , , , , , r, , , , , ) = staking.machineId2StakeInfos(mid); }
    function _nft(string memory mid) internal view returns (uint256 n) { ( , , , , , , n, , , , ) = staking.machineId2StakeInfos(mid); }
    function _next(string memory mid) internal view returns (uint256 nx) { ( , , , , , , , , , , nx) = staking.machineId2StakeInfos(mid); }

    function _findStaked() internal view returns (string memory) {
        for (uint256 i = 0; i < candidates.length; i++) {
            if (_endAt(candidates[i]) > block.timestamp) return candidates[i];
        }
        return "";
    }

    // ====== 1. 升级保全既有存储 (真实机器全标量字段 + owner/payoutAdmin) ======
    function test_upgrade_preserves_existing_storage() public {
        string memory mid = _findStaked();
        if (bytes(mid).length == 0) mid = candidates[0]; // 没活跃机器也能验 owner/payoutAdmin/字段一致性
        sHolder = _holder(mid); sStart = _start(mid); sEnd = _endAt(mid);
        sCalc = _calc(mid); sReserved = _reserved(mid); sNft = _nft(mid); sNext = _next(mid);
        address ownerBefore = staking.owner();
        address payoutBefore = staking.payoutAdmin();

        _upgradeToV18();

        assertEq(staking.owner(), ownerBefore, "owner preserved");
        assertEq(staking.payoutAdmin(), payoutBefore, "payoutAdmin preserved");
        assertEq(staking.stakeAdmin(), address(0), "stakeAdmin defaults 0");
        assertEq(_holder(mid), sHolder, "holder preserved");
        assertEq(_start(mid), sStart, "startAt preserved");
        assertEq(_endAt(mid), sEnd, "endAt preserved (no corruption)");
        assertEq(_calc(mid), sCalc, "calcPoint preserved");
        assertEq(_reserved(mid), sReserved, "reservedAmount preserved");
        assertEq(_nft(mid), sNft, "nftCount preserved");
        assertEq(_next(mid), sNext, "nextRenterCanRentAt preserved");
        console.log("Storage fully preserved across v17->v18");
    }

    // ====== 2. setStakeAdmin + adminAddStakeHours 对真实机器生效 ======
    function test_adminAddStakeHours_on_real_machine() public {
        _upgradeToV18();
        string memory mid = _findStaked();
        if (bytes(mid).length == 0) { console.log("WARN: no active staked candidate, skip"); return; }
        uint256 endBefore = _endAt(mid);
        vm.prank(OWNER_ADDR);
        staking.setStakeAdmin(stakeAdminWallet);
        assertEq(staking.stakeAdmin(), stakeAdminWallet);
        vm.prank(stakeAdminWallet);
        staking.adminAddStakeHours(mid, 2160);
        assertEq(_endAt(mid), endBefore + 2160 * 1 hours, "real machine endAt +3mo");
        console.log("Real machine extended OK");
    }

    // ====== 3. owner 直接调 + 未授权拒绝 + 升级权不受影响 ======
    function test_owner_extend_and_authz_and_upgrade_authority() public {
        _upgradeToV18();
        string memory mid = _findStaked();
        if (bytes(mid).length != 0) {
            uint256 e0 = _endAt(mid);
            vm.prank(OWNER_ADDR);
            staking.adminAddStakeHours(mid, 100);
            assertEq(_endAt(mid), e0 + 100 * 1 hours, "owner extend works");
            vm.prank(randomWallet);
            vm.expectRevert(NFTStaking.NotAdmin.selector);
            staking.adminAddStakeHours(mid, 2160);
        }
        // 升级权仍受 canUpgradeAddress 保护: 随机钱包不能升级
        vm.startPrank(randomWallet);
        NFTStaking another = new NFTStaking();
        vm.expectRevert();
        IProxyV18(STAKING_PROXY).upgradeToAndCall(address(another), "");
        vm.stopPrank();
    }
}
