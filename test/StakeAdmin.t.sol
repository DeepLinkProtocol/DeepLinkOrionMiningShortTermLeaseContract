// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

/// @title v18 StakeAdmin 测试 — 管理员代矿工延长质押 (adminAddStakeHours)
/// @notice 覆盖 鉴权(owner/stakeAdmin/未授权) + bounds + 未到期检查 + 批量跳过过期 + nextRenterCanRentAt 恢复 + version
contract StakeAdminTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    IPrecompileContract public precompileContract;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;

    address owner = address(0x01);
    uint256 constant STAKER_PK = 0xA11CE;
    uint256 constant ADMIN_PK = 0xB0B;
    address stakerAddr;
    address stakeAdminAddr;
    address randomAddr = address(0xBADBAD);

    function setUp() public {
        stakerAddr = vm.addr(STAKER_PK);
        stakeAdminAddr = vm.addr(ADMIN_PK);

        vm.startPrank(owner);
        precompileContract = IPrecompileContract(address(0x11));
        rewardToken = new Token();
        nftToken = new DLCNode(owner);

        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(proxy1));
        ERC1967Proxy proxy = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(proxy));

        NFTStaking(address(proxy1)).initialize(
            owner, address(nftToken), address(rewardToken), address(rent), address(dbcAIContract), 1
        );
        Rent(address(proxy)).initialize(
            owner, address(precompileContract), address(nftStaking), address(dbcAIContract), address(rewardToken)
        );

        deal(address(rewardToken), address(nftStaking), 180000000 * 1e18);
        nftStaking.setRewardStartAt(block.timestamp);
        address[] memory addrs = new address[](1);
        addrs[0] = owner;
        nftStaking.setDLCClientWallets(addrs);

        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.reportStakingStatus.selector),
            abi.encode()
        );
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.freeGpuAmount.selector),
            abi.encode(1)
        );
        vm.stopPrank();
        passHours(1);
    }

    // ====== helpers ======
    function _stake(string memory machineId, uint256 reserveAmount, uint256 stakeHours) internal {
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(stakerAddr, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, machineId, 16)
        );
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );
        vm.startPrank(stakerAddr);
        dealERC1155(address(nftToken), stakerAddr, 1, 1, false);
        deal(address(rewardToken), stakerAddr, 100000 ether);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);
        vm.stopPrank();

        vm.startPrank(owner);
        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        nftStaking.stakeV2(stakerAddr, machineId, nftTokens, nftTokensBalance, stakeHours, false);
        if (reserveAmount > 0) {
            nftStaking.addDLCToStake(machineId, reserveAmount);
        }
        vm.stopPrank();
    }

    function _endAt(string memory mid) internal view returns (uint256) {
        ( , , , uint256 endAt, , , , , , , ) = nftStaking.machineId2StakeInfos(mid);
        return endAt;
    }

    function passHours(uint256 n) public {
        uint256 secondsToAdvance = n * 60 * 60;
        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + secondsToAdvance / 6);
    }

    // ====== version ======
    function test_version_is_18() public view {
        assertEq(nftStaking.version(), 18);
    }

    // ====== setStakeAdmin ======
    function test_setStakeAdmin_onlyOwner() public {
        vm.prank(randomAddr);
        vm.expectRevert();
        nftStaking.setStakeAdmin(stakeAdminAddr);

        vm.prank(owner);
        nftStaking.setStakeAdmin(stakeAdminAddr);
        assertEq(nftStaking.stakeAdmin(), stakeAdminAddr);
    }

    function test_setStakeAdmin_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit NFTStaking.StakeAdminChanged(address(0), stakeAdminAddr);
        vm.prank(owner);
        nftStaking.setStakeAdmin(stakeAdminAddr);
    }

    // ====== adminAddStakeHours happy paths ======
    function test_adminAddStakeHours_byOwner() public {
        _stake("M1", 1000 ether, 1000);
        uint256 before = _endAt("M1");
        vm.prank(owner);
        nftStaking.adminAddStakeHours("M1", 2160); // 3 months
        assertEq(_endAt("M1"), before + 2160 * 1 hours, "endAt extended by 3 months");
    }

    function test_adminAddStakeHours_byStakeAdmin() public {
        _stake("M1", 1000 ether, 1000);
        vm.prank(owner);
        nftStaking.setStakeAdmin(stakeAdminAddr);
        uint256 before = _endAt("M1");
        vm.prank(stakeAdminAddr);
        nftStaking.adminAddStakeHours("M1", 2160);
        assertEq(_endAt("M1"), before + 2160 * 1 hours);
    }

    function test_adminAddStakeHours_emitsEvent() public {
        _stake("M1", 1000 ether, 1000);
        vm.expectEmit(true, false, false, true);
        emit NFTStaking.AdminAddedStakeHours(owner, "M1", 2160);
        vm.prank(owner);
        nftStaking.adminAddStakeHours("M1", 2160);
    }

    // ====== authz ======
    function test_adminAddStakeHours_unauthorized_reverts() public {
        _stake("M1", 1000 ether, 1000);
        vm.prank(randomAddr);
        vm.expectRevert(NFTStaking.NotAdmin.selector);
        nftStaking.adminAddStakeHours("M1", 2160);
    }

    function test_adminAddStakeHours_stakeAdminZero_onlyOwnerWorks() public {
        _stake("M1", 1000 ether, 1000);
        // stakeAdmin 未设 (=0): random 仍 revert, owner 仍可用
        vm.prank(randomAddr);
        vm.expectRevert(NFTStaking.NotAdmin.selector);
        nftStaking.adminAddStakeHours("M1", 2160);
        vm.prank(owner);
        nftStaking.adminAddStakeHours("M1", 2160); // ok
    }

    function test_adminAddStakeHours_oldStakeAdmin_revokedAfterRotation() public {
        _stake("M1", 1000 ether, 1000);
        vm.prank(owner);
        nftStaking.setStakeAdmin(stakeAdminAddr);
        vm.prank(owner);
        nftStaking.setStakeAdmin(randomAddr); // rotate away
        // old stakeAdmin 失权
        vm.prank(stakeAdminAddr);
        vm.expectRevert(NFTStaking.NotAdmin.selector);
        nftStaking.adminAddStakeHours("M1", 2160);
    }

    // ====== bounds ======
    function test_adminAddStakeHours_belowMin_reverts() public {
        _stake("M1", 1000 ether, 1000);
        vm.prank(owner);
        vm.expectRevert(NFTStaking.InvalidStakeHours.selector);
        nftStaking.adminAddStakeHours("M1", 1);
    }

    function test_adminAddStakeHours_aboveMax_reverts() public {
        _stake("M1", 1000 ether, 1000);
        vm.prank(owner);
        vm.expectRevert(NFTStaking.InvalidStakeHours.selector);
        nftStaking.adminAddStakeHours("M1", 4321);
    }

    function test_adminAddStakeHours_maxBoundary_ok() public {
        _stake("M1", 1000 ether, 1000);
        uint256 before = _endAt("M1");
        vm.prank(owner);
        nftStaking.adminAddStakeHours("M1", 4320);
        assertEq(_endAt("M1"), before + 4320 * 1 hours);
    }

    // ====== not staked / expired ======
    function test_adminAddStakeHours_notStaked_reverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NFTStaking.MachineNotStaked.selector, "GHOST"));
        nftStaking.adminAddStakeHours("GHOST", 2160);
    }

    function test_adminAddStakeHours_expired_reverts() public {
        _stake("M1", 1000 ether, 3);
        passHours(5); // 质押过期 (endAt = start+3h < now)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NFTStaking.MachineNotStaked.selector, "M1"));
        nftStaking.adminAddStakeHours("M1", 2160);
    }

    // ====== batch ======
    function test_adminAddStakeHoursBatch_happy() public {
        _stake("M1", 1000 ether, 1000);
        _stake("M2", 1000 ether, 1000);
        uint256 b1 = _endAt("M1");
        uint256 b2 = _endAt("M2");
        string[] memory ids = new string[](2);
        ids[0] = "M1";
        ids[1] = "M2";
        vm.prank(owner);
        nftStaking.adminAddStakeHoursBatch(ids, 2160);
        assertEq(_endAt("M1"), b1 + 2160 * 1 hours);
        assertEq(_endAt("M2"), b2 + 2160 * 1 hours);
    }

    function test_adminAddStakeHoursBatch_skipsExpired() public {
        _stake("M1", 1000 ether, 1000); // 长期, 不过期
        _stake("M2", 1000 ether, 3);    // 短期, 会过期
        passHours(5); // M2 过期, M1 仍有效
        uint256 b1 = _endAt("M1");
        uint256 b2 = _endAt("M2");
        string[] memory ids = new string[](2);
        ids[0] = "M1";
        ids[1] = "M2";
        vm.prank(owner);
        nftStaking.adminAddStakeHoursBatch(ids, 2160);
        assertEq(_endAt("M1"), b1 + 2160 * 1 hours, "M1 extended");
        assertEq(_endAt("M2"), b2, "M2 skipped (unchanged)");
    }

    function test_adminAddStakeHoursBatch_unauthorized_reverts() public {
        _stake("M1", 1000 ether, 1000);
        string[] memory ids = new string[](1);
        ids[0] = "M1";
        vm.prank(randomAddr);
        vm.expectRevert(NFTStaking.NotAdmin.selector);
        nftStaking.adminAddStakeHoursBatch(ids, 2160);
    }

    function test_adminAddStakeHoursBatch_badBounds_reverts() public {
        _stake("M1", 1000 ether, 1000);
        string[] memory ids = new string[](1);
        ids[0] = "M1";
        vm.prank(owner);
        vm.expectRevert(NFTStaking.InvalidStakeHours.selector);
        nftStaking.adminAddStakeHoursBatch(ids, 1);
    }

    function test_adminAddStakeHoursBatch_tooLarge_reverts() public {
        string[] memory ids = new string[](101);
        for (uint256 i = 0; i < 101; i++) ids[i] = "X";
        vm.prank(owner);
        vm.expectRevert("batch too large");
        nftStaking.adminAddStakeHoursBatch(ids, 2160);
    }

    // ====== P0: 仅延长 endAt, 其他 StakeInfo 字段全保全 ======
    function test_adminAddStakeHours_preservesOtherFields() public {
        _stake("M1", 1000 ether, 1000);
        ( address holderB, uint256 startB, uint256 claimB, uint256 endB, uint256 calcB,
          uint256 reservedB, uint256 nftB, uint256 claimedB, bool rentedB, uint256 gpuB, uint256 nextB )
          = nftStaking.machineId2StakeInfos("M1");
        vm.prank(owner);
        nftStaking.adminAddStakeHours("M1", 2160);
        ( address holderA, uint256 startA, uint256 claimA, uint256 endA, uint256 calcA,
          uint256 reservedA, uint256 nftA, uint256 claimedA, bool rentedA, uint256 gpuA, uint256 nextA )
          = nftStaking.machineId2StakeInfos("M1");
        assertEq(holderA, holderB, "holder");
        assertEq(startA, startB, "startAt");
        assertEq(claimA, claimB, "lastClaim");
        assertEq(endA, endB + 2160 * 1 hours, "endAt +3mo");
        assertEq(calcA, calcB, "calcPoint unchanged");
        assertEq(reservedA, reservedB, "reservedAmount unchanged");
        assertEq(nftA, nftB, "nftCount");
        assertEq(claimedA, claimedB, "claimed");
        assertEq(rentedA, rentedB, "isRented");
        assertEq(gpuA, gpuB, "gpuCount");
        // 新质押 nextRenterCanRentAt = stakeTime (非0) → 不重置, 保持不变
        assertEq(nextA, nextB, "nextRenterCanRentAt unchanged when nonzero");
    }

    // ====== P0: nextRenterCanRentAt==0 且未租 → 重置为 now (恢复可租) ======
    function test_adminAddStakeHours_resetsNextRenterWhenZero() public {
        _stake("M1", 1000 ether, 1000);
        vm.prank(owner);
        nftStaking.fixNextRenterCanRentAt("M1", 0); // 模拟 endRentMachine 即将到期时置 0
        vm.prank(owner);
        nftStaking.adminAddStakeHours("M1", 2160);
        ( , , , , , , , , , , uint256 nextA ) = nftStaking.machineId2StakeInfos("M1");
        assertEq(nextA, block.timestamp, "nextRenterCanRentAt reset to now");
    }

    // ====== P1: AfterAddHoursEndTime 事件携带正确的新 endTimestamp (脚本据此回写DB) ======
    function test_adminAddStakeHours_emitsAfterAddHoursEndTime() public {
        _stake("M1", 1000 ether, 1000);
        ( , , , uint256 endB, , , , , , , ) = nftStaking.machineId2StakeInfos("M1");
        vm.expectEmit(false, false, false, true);
        emit NFTStaking.AfterAddHoursEndTime("M1", endB + 2160 * 1 hours);
        vm.prank(owner);
        nftStaking.adminAddStakeHours("M1", 2160);
    }

    // ====== P2: 批量重复 id → 各延一次 (已知/文档化行为, 脚本侧 Set 去重) ======
    function test_adminAddStakeHoursBatch_duplicateIds_doubleExtend() public {
        _stake("M1", 1000 ether, 1000);
        ( , , , uint256 endB, , , , , , , ) = nftStaking.machineId2StakeInfos("M1");
        string[] memory ids = new string[](2);
        ids[0] = "M1"; ids[1] = "M1";
        vm.prank(owner);
        nftStaking.adminAddStakeHoursBatch(ids, 100);
        ( , , , uint256 endA, , , , , , , ) = nftStaking.machineId2StakeInfos("M1");
        assertEq(endA, endB + 2 * 100 * 1 hours, "duplicate id extended twice");
    }

    // ====== P2: 空数组 → 无 revert 无副作用 ======
    function test_adminAddStakeHoursBatch_emptyArray_noop() public {
        string[] memory ids = new string[](0);
        vm.prank(owner);
        nftStaking.adminAddStakeHoursBatch(ids, 2160); // 不 revert
    }

    // ====== P2: 恰好 100 台 (边界, 全不存在→全跳过) 不 revert ======
    function test_adminAddStakeHoursBatch_exactly100_ok() public {
        string[] memory ids = new string[](100);
        for (uint256 i = 0; i < 100; i++) ids[i] = "GHOST";
        vm.prank(owner);
        nftStaking.adminAddStakeHoursBatch(ids, 2160); // 100 通过, 全跳过(GHOST endAt=0)
    }

    // ====== P2: 单函数到期边界 — block.timestamp == endAt 视为到期, revert ======
    function test_adminAddStakeHours_exactlyAtExpiry_reverts() public {
        _stake("M1", 1000 ether, 3);
        ( , , , uint256 endAt, , , , , , , ) = nftStaking.machineId2StakeInfos("M1");
        vm.warp(endAt); // 正好到期时刻
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NFTStaking.MachineNotStaked.selector, "M1"));
        nftStaking.adminAddStakeHours("M1", 2160);
    }

    // ====== P2: setStakeAdmin(0) 停用 — 老 admin 失权, owner 仍可用 ======
    function test_setStakeAdmin_zeroDisables() public {
        _stake("M1", 1000 ether, 1000);
        vm.prank(owner);
        nftStaking.setStakeAdmin(stakeAdminAddr);
        vm.prank(owner);
        nftStaking.setStakeAdmin(address(0)); // 停用
        assertEq(nftStaking.stakeAdmin(), address(0));
        vm.prank(stakeAdminAddr);
        vm.expectRevert(NFTStaking.NotAdmin.selector);
        nftStaking.adminAddStakeHours("M1", 2160);
        vm.prank(owner); // owner 仍可
        nftStaking.adminAddStakeHours("M1", 2160);
    }

    // ====== P2: 批量也能用 stakeAdmin 调 ======
    function test_adminAddStakeHoursBatch_byStakeAdmin() public {
        _stake("M1", 1000 ether, 1000);
        vm.prank(owner);
        nftStaking.setStakeAdmin(stakeAdminAddr);
        ( , , , uint256 endB, , , , , , , ) = nftStaking.machineId2StakeInfos("M1");
        string[] memory ids = new string[](1);
        ids[0] = "M1";
        vm.prank(stakeAdminAddr);
        nftStaking.adminAddStakeHoursBatch(ids, 2160);
        ( , , , uint256 endA, , , , , , , ) = nftStaking.machineId2StakeInfos("M1");
        assertEq(endA, endB + 2160 * 1 hours);
    }

    // ====== P3: 模糊测试 — 合法 bounds 内 endAt 严格 +h*3600, 越界 revert ======
    function testFuzz_adminAddStakeHours_bounds(uint256 h) public {
        _stake("M1", 1000 ether, 1000); // 质押时长在 stakeV2 上限内; 不 warp 故不会提前到期
        ( , , , uint256 endB, , , , , , , ) = nftStaking.machineId2StakeInfos("M1");
        if (h >= 2 && h <= 4320) {
            vm.prank(owner);
            nftStaking.adminAddStakeHours("M1", h);
            ( , , , uint256 endA, , , , , , , ) = nftStaking.machineId2StakeInfos("M1");
            assertEq(endA, endB + h * 1 hours, "extend exact");
            assertGt(endA, endB, "monotonic increase");
        } else {
            vm.prank(owner);
            vm.expectRevert(NFTStaking.InvalidStakeHours.selector);
            nftStaking.adminAddStakeHours("M1", h);
        }
    }
}
