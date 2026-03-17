// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {IOracle} from "../src/interface/IOracle.sol";
import {IRewardToken} from "../src/interface/IRewardToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

/**
 * 模拟真实 dbcAI 合约行为的 Mock：
 * - 实现 IDBCAIContract 接口
 * - 带 OpenZeppelin ReentrancyGuard（与生产 dbcAI 一致）
 * - triggerOfflineNotify() 模拟 Detection Node 上报离线，内部调 rent.notify(MachineOffline)
 * - reportStakingStatus() 带 nonReentrant，复现跨合约重入 revert
 */
contract ReentrantDBCAIMock is IDBCAIContract, ReentrancyGuard {
    Rent public rent;

    // 可配置的机器信息
    mapping(string => address) public machineOwners;
    mapping(string => bool) public onlineStatus;
    mapping(string => bool) public registeredStatus;

    constructor() {}

    function setRent(address _rent) external {
        rent = Rent(_rent);
    }

    function setMachineOwner(string calldata machineId, address owner_) external {
        machineOwners[machineId] = owner_;
    }

    function setMachineState(string calldata machineId, bool isOnline, bool isRegistered) external {
        onlineStatus[machineId] = isOnline;
        registeredStatus[machineId] = isRegistered;
    }

    // ── IDBCAIContract 实现 ──────────────────────────────

    function getMachineInfo(string calldata id, bool)
        external
        view
        override
        returns (
            address machineOwner,
            uint256 calcPoint,
            uint256 cpuRate,
            string memory gpuType,
            uint256 gpuMem,
            string memory cpuType,
            uint256 gpuCount,
            string memory machineId,
            uint256 memorySize
        )
    {
        machineOwner = machineOwners[id] != address(0) ? machineOwners[id] : address(0x10);
        calcPoint = 100;
        cpuRate = 3500;
        gpuType = "NVIDIA GeForce RTX 4060 Ti";
        gpuMem = 16;
        cpuType = "Intel";
        gpuCount = 1;
        machineId = id;
        memorySize = 32;
    }

    function getMachineState(string calldata machineId, string calldata, NFTStaking.StakingType)
        external
        view
        override
        returns (bool isOnline, bool isRegistered)
    {
        isOnline = onlineStatus[machineId];
        isRegistered = registeredStatus[machineId];
    }

    function freeGpuAmount(string calldata) external pure override returns (uint256) {
        return 1;
    }

    /**
     * 关键：带 nonReentrant 修饰符，复现生产环境重入问题。
     * 当从 _unStake → reportStakingStatus 回调时，
     * 如果 ReentrancyGuard 仍处于 _ENTERED 状态，此函数将 revert。
     */
    function reportStakingStatus(
        string calldata,
        NFTStaking.StakingType,
        string calldata,
        uint256,
        bool
    ) external override nonReentrant {
        // no-op，但 nonReentrant 会在重入时 revert
    }

    /**
     * 模拟 Detection Node 触发离线通知的入口。
     * 带 nonReentrant — 进入后 ReentrancyGuard 状态变为 _ENTERED，
     * 后续 _unStake 回调 reportStakingStatus 时会检测到重入。
     */
    function triggerOfflineNotify(string calldata machineId) external nonReentrant {
        rent.notify(Rent.NotifyType.MachineOffline, machineId);
    }

    /**
     * 不带 nonReentrant 的离线通知（对照组，模拟非重入路径）。
     */
    function triggerOfflineNotifyNoGuard(string calldata machineId) external {
        rent.notify(Rent.NotifyType.MachineOffline, machineId);
    }
}

/**
 * 测试跨合约重入场景：
 *   dbcAI.triggerOfflineNotify() [nonReentrant]
 *     → rent.notify(MachineOffline)
 *       → addSlashInfoAndReport → stakingContract.reportMachineFault()
 *         → _unStake → dbcAI.reportStakingStatus() [nonReentrant] ← 重入点
 *
 * 修复前：_unStake 直接调 reportStakingStatus → ReentrancyGuard revert → 整个 tx 失败
 * 修复后：_unStake 用 try-catch 包裹 reportStakingStatus → 即使 revert 也不影响主流程
 */
contract ReentrancyTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    IPrecompileContract public precompileContract;
    Token public rewardToken;
    DLCNode public nftToken;
    ReentrantDBCAIMock public dbcAI;
    IOracle public oracle;

    address owner = address(0x01);
    address renter = address(0x99);

    string constant MACHINE_ID = "machineId";

    function setUp() public {
        vm.startPrank(owner);

        precompileContract = IPrecompileContract(address(0x11));
        rewardToken = new Token();
        nftToken = new DLCNode(owner);
        dbcAI = new ReentrantDBCAIMock();
        oracle = IOracle(address(0x12));

        // Deploy NFTStaking (UUPS proxy)
        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(proxy1));

        // Deploy Rent (UUPS proxy)
        ERC1967Proxy proxy2 = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(proxy2));

        // Initialize
        nftStaking.initialize(
            owner,
            address(nftToken),
            address(rewardToken),
            address(rent),
            address(dbcAI),
            1
        );
        rent.initialize(
            owner,
            address(precompileContract),
            address(nftStaking),
            address(dbcAI),
            address(rewardToken)
        );

        // Configure dbcAI mock
        dbcAI.setRent(address(rent));
        dbcAI.setMachineOwner(MACHINE_ID, owner);
        dbcAI.setMachineState(MACHINE_ID, true, true);

        // Fund tokens
        deal(address(rewardToken), owner, 180000000 * 1e18);
        deal(address(rewardToken), renter, 10000000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 10000000 * 1e18);
        rewardToken.approve(address(nftStaking), 180000000 * 1e18);

        // Setup reward
        nftStaking.setRewardStartAt(block.timestamp);
        passHours(1);

        // Setup oracle
        rent.setOracle(address(oracle));
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.getTokenPriceInUSD.selector), abi.encode(100));

        // Setup DLC client wallet
        address[] memory wallets = new address[](1);
        wallets[0] = owner;
        nftStaking.setDLCClientWallets(wallets);

        vm.stopPrank();
    }

    // ── Helpers ──────────────────────────────────────────

    function passHours(uint256 n) internal {
        uint256 secs = n * 3600;
        vm.warp(block.timestamp + secs);
        vm.roll(block.number + secs / 6);
    }

    function stakeAndRent(uint256 stakeHours, uint256 reserveAmount) internal {
        vm.startPrank(owner);

        // Mint NFT & approve
        dealERC1155(address(nftToken), owner, 1, 1, false);
        deal(address(rewardToken), owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);

        // Stake
        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftBalances = new uint256[](1);
        nftTokens[0] = 1;
        nftBalances[0] = 1;
        nftStaking.stakeV2(owner, MACHINE_ID, nftTokens, nftBalances, stakeHours, true);
        nftStaking.addDLCToStake(MACHINE_ID, reserveAmount);
        vm.stopPrank();

        // Rent
        vm.startPrank(renter);
        rewardToken.approve(address(rent), 100 ether);
        rent.rentMachine(MACHINE_ID, 1 hours);
        vm.stopPrank();

        // 必须推进时间，否则 block.timestamp == rentStatTime，
        // notify 的条件 `block.timestamp > rentStatTime` 不满足，不走 slash 路径
        vm.warp(block.timestamp + 10);
        vm.roll(block.number + 1);
    }

    /// 辅助：检查租赁是否已终止（getRenter 为零地址 = 租赁已清理）
    /// 注意：Rent.isRented() 有 30 个区块的冷却期，不能用于判断是否已终止
    function assertRentalTerminated(string memory machineId) internal view {
        address currentRenter = rent.getRenter(machineId);
        assertEq(currentRenter, address(0), "rental should be terminated (renter should be zero)");
    }

    // ── 测试 1: 重入路径（通过 dbcAI.triggerOfflineNotify）成功完成 ─────

    /**
     * 验证修复后行为：
     * dbcAI.triggerOfflineNotify() → rent.notify → reportMachineFault → _unStake
     * → try dbcAI.reportStakingStatus() catch {} → 不 revert，_unStake 正常完成
     *
     * 预期：
     * - isStaking = false（质押已解除）
     * - getRenter = address(0)（租赁已终止）
     * - NFT 已退还给 stakeholder
     * - DLC 已退还给 stakeholder（扣除 slash 金额）
     * - calcPoint = 0
     */
    function testReentrancyPathSucceedsWithTryCatch() public {
        uint256 reserveAmount = 20000 * 1e18;
        stakeAndRent(48, reserveAmount);

        // Verify pre-conditions
        assertTrue(nftStaking.isStaking(MACHINE_ID), "should be staking before notify");
        assertTrue(rent.isRented(MACHINE_ID), "should be rented before notify");
        assertEq(nftToken.balanceOf(address(nftStaking), 1), 1, "NFT should be in staking contract");
        uint256 ownerBalanceBefore = rewardToken.balanceOf(owner);

        // Trigger offline via dbcAI (reentrancy path)
        vm.prank(address(dbcAI));
        dbcAI.triggerOfflineNotify(MACHINE_ID);

        // Verify post-conditions: unstake completed despite reentrancy
        assertFalse(nftStaking.isStaking(MACHINE_ID), "isStaking should be false after penalty");
        assertEq(nftStaking.totalCalcPoint(), 0, "calcPoint should be 0 after penalty");
        assertRentalTerminated(MACHINE_ID);

        // NFT returned to owner
        assertEq(nftToken.balanceOf(owner, 1), 1, "NFT should be returned to owner");

        // DLC returned to owner (minus slash amount, plus any accumulated rewards from _claim)
        uint256 ownerBalanceAfter = rewardToken.balanceOf(owner);
        uint256 slashAmount = nftStaking.SLASH_AMOUNT();
        uint256 netReturn = ownerBalanceAfter - ownerBalanceBefore;
        assertGe(
            netReturn,
            reserveAmount - slashAmount,
            "DLC returned should be >= reserveAmount - slashAmount"
        );

        // reservedAmount should be 0
        (,,,,, uint256 finalReserved,,,,,) = nftStaking.machineId2StakeInfos(MACHINE_ID);
        assertEq(finalReserved, 0, "reservedAmount should be 0");

        // endAtTimestamp should be set
        (,,, uint256 endAt,,,,,,,) = nftStaking.machineId2StakeInfos(MACHINE_ID);
        assertEq(endAt, block.timestamp, "endAt should be current timestamp");
    }

    // ── 测试 2: 非重入路径仍正常工作 ────────────────────────

    /**
     * 验证 try-catch 不影响正常（非重入）路径。
     * 使用 triggerOfflineNotifyNoGuard（无 nonReentrant），
     * reportStakingStatus 不会因重入 revert，try-catch 内的调用正常成功。
     */
    function testNonReentrantPathStillWorks() public {
        uint256 reserveAmount = 20000 * 1e18;
        stakeAndRent(48, reserveAmount);

        assertTrue(nftStaking.isStaking(MACHINE_ID), "should be staking");
        assertTrue(rent.isRented(MACHINE_ID), "should be rented");

        // Trigger offline WITHOUT nonReentrant guard on caller
        vm.prank(address(dbcAI));
        dbcAI.triggerOfflineNotifyNoGuard(MACHINE_ID);

        // Same expected outcome
        assertFalse(nftStaking.isStaking(MACHINE_ID), "isStaking should be false");
        assertRentalTerminated(MACHINE_ID);
        assertEq(nftToken.balanceOf(owner, 1), 1, "NFT should be returned");
    }

    // ── 测试 3: 未租赁时离线不触发 slash（仅 stopRewarding）──────

    /**
     * 机器质押但未被租赁时收到 MachineOffline，不走 slash 路径，
     * 仅 stopRewarding（设 isStakingButOffline=true）。
     */
    function testOfflineWithoutRentalOnlyStopsRewarding() public {
        // Stake without renting
        vm.startPrank(owner);
        dealERC1155(address(nftToken), owner, 1, 1, false);
        deal(address(rewardToken), owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), 20000 * 1e18);
        nftToken.setApprovalForAll(address(nftStaking), true);

        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftBalances = new uint256[](1);
        nftTokens[0] = 1;
        nftBalances[0] = 1;
        nftStaking.stakeV2(owner, MACHINE_ID, nftTokens, nftBalances, 48, true);
        nftStaking.addDLCToStake(MACHINE_ID, 20000 * 1e18);
        vm.stopPrank();

        assertTrue(nftStaking.isStaking(MACHINE_ID), "should be staking");
        assertFalse(rent.isRented(MACHINE_ID), "should not be rented");
        assertEq(nftStaking.totalCalcPoint(), 100, "calcPoint should be 100");

        // Trigger offline
        vm.prank(address(dbcAI));
        dbcAI.triggerOfflineNotify(MACHINE_ID);

        // isStaking stays true, but offline flag set
        assertTrue(nftStaking.isStaking(MACHINE_ID), "isStaking should remain true");
        assertTrue(nftStaking.isStakingButOffline(MACHINE_ID), "should be marked offline");
        assertEq(nftStaking.totalCalcPoint(), 0, "calcPoint should be 0 (offline)");

        // NFT still in staking contract
        assertEq(nftToken.balanceOf(address(nftStaking), 1), 1, "NFT should stay in staking");
    }

    // ── 测试 4: 惩罚后可重新质押 ────────────────────────────

    /**
     * 机器被罚后（isStaking=false），可重新通过 stakeV2 质押。
     * 验证新质押后 calcPoint>0，isStaking=true。
     */
    function testReStakeAfterPenalty() public {
        uint256 reserveAmount = 20000 * 1e18;
        stakeAndRent(48, reserveAmount);

        // Trigger penalty via reentrancy path
        vm.prank(address(dbcAI));
        dbcAI.triggerOfflineNotify(MACHINE_ID);

        assertFalse(nftStaking.isStaking(MACHINE_ID), "should not be staking after penalty");
        assertEq(nftToken.balanceOf(owner, 1), 1, "NFT should be with owner");

        // Wait some time, then re-stake
        passHours(24);

        // Re-register machine as online
        dbcAI.setMachineState(MACHINE_ID, true, true);

        vm.startPrank(owner);
        dealERC1155(address(nftToken), owner, 1, 1, false);
        deal(address(rewardToken), owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);

        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftBalances = new uint256[](1);
        nftTokens[0] = 1;
        nftBalances[0] = 1;
        nftStaking.stakeV2(owner, MACHINE_ID, nftTokens, nftBalances, 48, true);
        nftStaking.addDLCToStake(MACHINE_ID, reserveAmount);
        vm.stopPrank();

        // Verify re-stake succeeded
        assertTrue(nftStaking.isStaking(MACHINE_ID), "should be staking again");
        assertEq(nftStaking.totalCalcPoint(), 100, "calcPoint should be 100 after re-stake");
        (,,,, uint256 calcPoint, uint256 reserved,,,,,) = nftStaking.machineId2StakeInfos(MACHINE_ID);
        assertEq(calcPoint, 100, "calcPoint should be 100");
        assertGt(reserved, 0, "reservedAmount should be > 0");
    }

    // ── 测试 5: 零 DLC 质押时的重入路径 ─────────────────────

    /**
     * 即使没有 DLC 质押（reserveAmount=0），重入路径仍应正常完成。
     */
    function testReentrancyWithZeroReserve() public {
        stakeAndRent(48, 0);

        assertTrue(nftStaking.isStaking(MACHINE_ID), "should be staking");
        assertTrue(rent.isRented(MACHINE_ID), "should be rented");

        vm.prank(address(dbcAI));
        dbcAI.triggerOfflineNotify(MACHINE_ID);

        assertFalse(nftStaking.isStaking(MACHINE_ID), "isStaking should be false");
        assertRentalTerminated(MACHINE_ID);
        assertEq(nftToken.balanceOf(owner, 1), 1, "NFT should be returned");
    }

    // ── 测试 6: 租赁到期后的离线通知 ────────────────────────

    /**
     * 租赁已过期但未清理时收到 MachineOffline，
     * 走 _cleanupExpiredRentOnOffline 路径（不走 slash），然后 stopRewarding。
     * 租赁信息被清理，但质押保持。
     */
    function testOfflineAfterRentalExpired() public {
        stakeAndRent(48, 20000 * 1e18);

        // 等租赁过期（1 小时租期 + 30 块冷却期之后）
        passHours(2);

        assertTrue(nftStaking.isStaking(MACHINE_ID), "should still be staking");

        vm.prank(address(dbcAI));
        dbcAI.triggerOfflineNotify(MACHINE_ID);

        // 租赁过期走 cleanup 路径：清理租赁数据，但不触发 _unStake
        // isStaking 仍为 true
        assertTrue(nftStaking.isStaking(MACHINE_ID), "isStaking should remain true after expired cleanup");
        // getRenter 应为零（租赁已清理）
        assertEq(rent.getRenter(MACHINE_ID), address(0), "renter should be zero after cleanup");
    }
}
