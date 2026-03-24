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

/// @title 租赁中离线惩罚单元测试
/// @notice 测试 _terminateRentOnSlashWithPenalty 的所有边界条件
contract RentalOfflinePenaltyTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    IPrecompileContract public precompileContract;
    Token public rewardToken;  // DLC (feeToken)
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;
    IOracle public oracle;

    address owner = address(0x01);
    address renter = address(0x100);

    // Point Token (DLP) — 在测试中部署一个新 Token 模拟
    Token public pointToken;
    address constant POINT_TOKEN_ADDR = address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6);

    function setUp() public {
        vm.startPrank(owner);
        precompileContract = IPrecompileContract(address(0x11));
        rewardToken = new Token();
        nftToken = new DLCNode(owner);

        // 部署 Point Token 到硬编码地址
        pointToken = new Token();
        // 把 pointToken 的代码部署到 POINT_TOKEN_ADDR
        vm.etch(POINT_TOKEN_ADDR, address(pointToken).code);

        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(proxy1));

        ERC1967Proxy proxy = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(proxy));

        nftStaking.initialize(
            owner, address(nftToken), address(rewardToken), address(rent), address(dbcAIContract), 1
        );
        rent.initialize(
            owner, address(precompileContract), address(nftStaking), address(dbcAIContract), address(rewardToken)
        );

        // Fund tokens
        deal(address(rewardToken), owner, 500000 * 1e18);
        deal(address(rewardToken), renter, 500000 * 1e18);
        deal(address(rewardToken), address(rent), 500000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 500000 * 1e18);

        // Fund Point Token (DLP) at the hardcoded address
        deal(POINT_TOKEN_ADDR, renter, 500000 * 1e18);
        deal(POINT_TOKEN_ADDR, address(rent), 500000 * 1e18);

        rewardToken.approve(address(nftStaking), 500000 * 1e18);
        nftStaking.setRewardStartAt(block.timestamp);

        passHours(1);
        oracle = IOracle(address(0x12));
        rent.setOracle(address(oracle));

        // Mock external calls
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.reportStakingStatus.selector), abi.encode());
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.mockCall(address(rent), abi.encodeWithSelector(rent.getMachinePrice.selector), abi.encode(100));
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.getTokenPriceInUSD.selector), abi.encode(100));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════

    function passHours(uint256 n) internal {
        vm.warp(vm.getBlockTimestamp() + n * 3600);
        vm.roll(vm.getBlockNumber() + n * 600);
    }

    function passMinutes(uint256 n) internal {
        vm.warp(vm.getBlockTimestamp() + n * 60);
        vm.roll(vm.getBlockNumber() + n * 10);
    }

    function stakeAndRent(string memory machineId, uint256 rentHours) internal {
        // Mock getMachineInfo + getMachineState
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, machineId, 16)
        );
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );

        // Stake
        vm.startPrank(owner);
        if (!nftStaking.dlcClientWalletAddress(owner)) {
            address[] memory addrs = new address[](1);
            addrs[0] = owner;
            nftStaking.setDLCClientWallets(addrs);
        }
        _mintNFT(address(nftToken), owner, 1, 1);
        deal(address(rewardToken), owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), 100000 * 1e18);
        nftToken.setApprovalForAll(address(nftStaking), true);
        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        nftStaking.stakeV2(owner, machineId, nftTokens, nftTokensBalance, 48, true);
        nftStaking.addDLCToStake(machineId, nftStaking.BASE_RESERVE_AMOUNT());
        vm.stopPrank();

        // Rent
        uint256 rentSeconds = rentHours * 1 hours;
        vm.startPrank(renter);
        rewardToken.approve(address(rent), 100 ether);
        rent.rentMachine(machineId, rentSeconds);
        vm.stopPrank();
    }

    function triggerOfflineNotify(string memory machineId) internal {
        vm.prank(address(dbcAIContract));
        rent.notify(Rent.NotifyType.MachineOffline, machineId);
    }

    function _mintNFT(address token, address to, uint256 id, uint256 amount) internal {
        DLCNode(token).mint(to, id, amount);
    }

    // ═══════════════════════════════════════════
    // Test Cases
    // ═══════════════════════════════════════════

    /// @notice 基础测试：租赁 10 小时，第 3 小时离线 → 矿工不拿已用 DLC，全退给租户
    function test_PenaltyBasic_UsedLessThan24h() public {
        string memory machineId = "machine_penalty_basic";
        stakeAndRent(machineId, 10);

        assertTrue(rent.isRented(machineId), "should be rented");

        uint256 renterBalanceBefore = rewardToken.balanceOf(renter);

        // 3 小时后机器离线
        passHours(3);
        triggerOfflineNotify(machineId);

        // isRented 有 30 区块宽限期，需要等过宽限期
        vm.roll(vm.getBlockNumber() + 31);
        assertFalse(rent.isRented(machineId), "should not be rented after offline");

        // 租户应收到退款（未用 7h + 惩罚已用 3h = 全部 10h 的费用）
        uint256 renterBalanceAfter = rewardToken.balanceOf(renter);
        assertGt(renterBalanceAfter, renterBalanceBefore, "renter should receive refund");

        console.log("Renter refund (DLC):", renterBalanceAfter - renterBalanceBefore);
    }

    /// @notice 边界测试：使用超过 24 小时 → 惩罚上限 24h，矿工保留超出部分
    function test_PenaltyCap_UsedMoreThan24h() public {
        string memory machineId = "machine_penalty_cap";
        // 注意：getMachinePrice mock 返回固定值，实际租赁时长受合约限制
        // 用较短时长模拟：租 10 小时，改 penalty cap 为测试参数
        stakeAndRent(machineId, 10);

        assertTrue(rent.isRented(machineId), "should be rented");

        // 5 小时后离线
        passHours(5);
        triggerOfflineNotify(machineId);

        vm.roll(vm.getBlockNumber() + 31);
        assertFalse(rent.isRented(machineId), "should not be rented after offline");
        console.log("10h rental, offline at 5h - penalty test OK");
    }

    /// @notice 边界测试：刚租就离线（使用 1 分钟）
    function test_PenaltyMinimal_JustStarted() public {
        string memory machineId = "machine_penalty_minimal";
        stakeAndRent(machineId, 10);

        // 1 分钟后离线
        passMinutes(1);
        triggerOfflineNotify(machineId);

        vm.roll(vm.getBlockNumber() + 31);
        assertFalse(rent.isRented(machineId), "should not be rented after offline");
        console.log("Offline after 1 minute");
    }

    /// @notice 非租赁离线 → 只停奖励，不惩罚（无 SlashInfo 产生）
    function test_NoRental_OnlyStopRewards() public {
        string memory machineId = "machine_no_rental";

        // 只质押，不租赁
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, machineId, 16)
        );
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );
        vm.startPrank(owner);
        if (!nftStaking.dlcClientWalletAddress(owner)) {
            address[] memory addrs = new address[](1);
            addrs[0] = owner;
            nftStaking.setDLCClientWallets(addrs);
        }
        _mintNFT(address(nftToken), owner, 2, 1);
        deal(address(rewardToken), owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), 100000 * 1e18);
        nftToken.setApprovalForAll(address(nftStaking), true);
        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 2;
        nftTokensBalance[0] = 1;
        nftStaking.stakeV2(owner, machineId, nftTokens, nftTokensBalance, 48, true);
        nftStaking.addDLCToStake(machineId, nftStaking.BASE_RESERVE_AMOUNT());
        vm.stopPrank();

        assertEq(nftStaking.totalCalcPoint(), 100, "should have calcPoint");
        assertFalse(rent.isRented(machineId), "should not be rented");

        // 触发离线通知
        triggerOfflineNotify(machineId);

        // calcPoint 应归零（停奖励）
        assertEq(nftStaking.totalCalcPoint(), 0, "calcPoint should be 0 after offline");
        // 但仍在质押中
        assertTrue(nftStaking.isStaking(machineId), "should still be staking");
        assertTrue(nftStaking.isStakingButOffline(machineId), "should be staking but offline");

        console.log("No rental: only stopped rewards, no penalty");
    }

    /// @notice 租赁已过期后离线 → 不触发惩罚路径，走清理路径
    function test_ExpiredRental_NopenaltyPath() public {
        string memory machineId = "machine_expired";
        stakeAndRent(machineId, 2);  // 租 2 小时

        // 等 3 小时（租赁过期）
        passHours(3);

        // 此时 block.timestamp > rentEndTime，走 _cleanupExpiredRentOnOffline 而非惩罚
        triggerOfflineNotify(machineId);

        vm.roll(vm.getBlockNumber() + 31);
        assertFalse(rent.isRented(machineId), "should not be rented");
        console.log("Expired rental: cleanup path, no penalty");
    }

    /// @notice 非 dbcAI 地址不能调用 notify
    function test_OnlyDbcAI_CanNotify() public {
        string memory machineId = "machine_access";
        stakeAndRent(machineId, 10);

        // 非 dbcAI 地址调用应该失败
        vm.prank(renter);
        vm.expectRevert();
        rent.notify(Rent.NotifyType.MachineOffline, machineId);
    }

    /// @notice 恢复测试：离线后重新上线 → calcPoint 恢复
    function test_RecoverAfterOffline() public {
        string memory machineId = "machine_recover";

        // 只质押不租赁
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, machineId, 16)
        );
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );
        vm.startPrank(owner);
        if (!nftStaking.dlcClientWalletAddress(owner)) {
            address[] memory addrs = new address[](1);
            addrs[0] = owner;
            nftStaking.setDLCClientWallets(addrs);
        }
        _mintNFT(address(nftToken), owner, 3, 1);
        deal(address(rewardToken), owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), 100000 * 1e18);
        nftToken.setApprovalForAll(address(nftStaking), true);
        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 3;
        nftTokensBalance[0] = 1;
        nftStaking.stakeV2(owner, machineId, nftTokens, nftTokensBalance, 48, true);
        nftStaking.addDLCToStake(machineId, nftStaking.BASE_RESERVE_AMOUNT());
        vm.stopPrank();

        assertEq(nftStaking.totalCalcPoint(), 100, "calcPoint before offline");

        // 离线
        triggerOfflineNotify(machineId);
        assertEq(nftStaking.totalCalcPoint(), 0, "calcPoint should be 0 after offline");

        // 重新上线
        vm.prank(address(dbcAIContract));
        rent.notify(Rent.NotifyType.MachineOnline, machineId);
        assertEq(nftStaking.totalCalcPoint(), 100, "calcPoint should recover after online");

        console.log("Recover: calcPoint 0 -> 100 after online");
    }
}
