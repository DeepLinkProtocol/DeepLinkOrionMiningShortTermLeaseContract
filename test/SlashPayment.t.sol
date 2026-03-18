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
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

contract SlashPaymentTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    IPrecompileContract public precompileContract;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;
    IOracle public oracle;

    address owner = address(0x01);        // 矿工/stakeHolder
    address renter1 = address(0x10);      // 租户1
    address renter2 = address(0x20);      // 租户2
    address admin2 = address(0x02);
    address admin3 = address(0x03);
    address admin4 = address(0x04);
    address admin5 = address(0x05);

    string machineId = "testMachine001";

    function setUp() public {
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

        // 给各方足够的代币
        deal(address(rewardToken), owner, 1_000_000 * 1e18);
        deal(address(rewardToken), renter1, 100_000 * 1e18);
        deal(address(rewardToken), renter2, 100_000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 10_000_000 * 1e18);

        rewardToken.approve(address(nftStaking), type(uint256).max);
        nftStaking.setRewardStartAt(block.timestamp);
        passHours(1);
        oracle = IOracle(address(0x12));
        rent.setOracle(address(oracle));

        // Mock 调用
        vm.mockCall(
            address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.reportStakingStatus.selector), abi.encode()
        );
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.mockCall(address(rent), abi.encodeWithSelector(rent.getMachinePrice.selector), abi.encode(100));
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.getTokenPriceInUSD.selector), abi.encode(100));
        vm.stopPrank();
    }

    // ========== 测试 hasUnpaidSlash ==========

    function test_hasUnpaidSlash_noSlash() public view {
        // 没有惩罚记录时应该返回 false
        assertFalse(rent.hasUnpaidSlash(machineId));
    }

    function test_hasUnpaidSlash_afterOfflineSlash() public {
        // 质押 → 租赁 → 离线惩罚 → 检查 hasUnpaidSlash
        _stakeAndRent(machineId, renter1, 0);

        // 触发离线惩罚
        _triggerOfflineSlash(machineId);

        // 被惩罚后应该有未赔付记录
        assertTrue(rent.hasUnpaidSlash(machineId));
    }

    // ========== 测试 payPendingSlash ==========

    function test_payPendingSlash_success() public {
        _stakeAndRent(machineId, renter1, 0);
        _triggerOfflineSlash(machineId);

        assertTrue(rent.hasUnpaidSlash(machineId));

        // 矿工主动赔付
        uint256 renter1BalanceBefore = rewardToken.balanceOf(renter1);
        uint256 ownerBalanceBefore = rewardToken.balanceOf(owner);

        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        rent.payPendingSlash(machineId);
        vm.stopPrank();

        // 赔付后 hasUnpaidSlash 应为 false
        assertFalse(rent.hasUnpaidSlash(machineId));

        // 租户收到赔偿
        assertEq(rewardToken.balanceOf(renter1), renter1BalanceBefore + rent.SLASH_AMOUNT());

        // 矿工扣款
        assertEq(rewardToken.balanceOf(owner), ownerBalanceBefore - rent.SLASH_AMOUNT());
    }

    function test_payPendingSlash_revertIfNoUnpaid() public {
        // 没有未赔付记录时应该 revert
        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        vm.expectRevert(abi.encodeWithSelector(Rent.NoUnpaidSlash.selector));
        rent.payPendingSlash(machineId);
        vm.stopPrank();
    }

    function test_payPendingSlash_anyoneCanPay() public {
        // 任何人都可以代矿工赔付（比如管理员用矿工的私钥）
        _stakeAndRent(machineId, renter1, 0);
        _triggerOfflineSlash(machineId);

        address payer = address(0x99);
        deal(address(rewardToken), payer, 100_000 * 1e18);

        vm.startPrank(payer);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        rent.payPendingSlash(machineId);
        vm.stopPrank();

        assertFalse(rent.hasUnpaidSlash(machineId));
    }

    function test_payPendingSlash_multipleSlashes() public {
        // 用两台不同的机器各惩罚一次，验证每台独立赔付
        string memory machineId2 = "testMachine002";

        _stakeAndRent(machineId, renter1, 0);
        _triggerOfflineSlash(machineId);

        _stakeAndRent(machineId2, renter2, 0);
        _triggerOfflineSlash(machineId2);

        assertTrue(rent.hasUnpaidSlash(machineId));
        assertTrue(rent.hasUnpaidSlash(machineId2));

        // 赔付第一台
        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        rent.payPendingSlash(machineId);
        vm.stopPrank();

        assertFalse(rent.hasUnpaidSlash(machineId));
        assertTrue(rent.hasUnpaidSlash(machineId2));

        // 赔付第二台
        uint256 renter2Before = rewardToken.balanceOf(renter2);
        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        rent.payPendingSlash(machineId2);
        vm.stopPrank();

        assertFalse(rent.hasUnpaidSlash(machineId2));
        assertEq(rewardToken.balanceOf(renter2), renter2Before + rent.SLASH_AMOUNT());
    }

    // ========== 测试 canStake 阻止有未赔付 slash 的机器重新质押 ==========

    function test_canStake_blocksWithUnpaidSlash() public {
        _stakeAndRent(machineId, renter1, 0);
        _triggerOfflineSlash(machineId);

        assertTrue(rent.hasUnpaidSlash(machineId), "should have unpaid slash");

        // 准备重新质押的参数
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
        dealERC1155(address(nftToken), owner, 1, 1, false);
        nftToken.setApprovalForAll(address(nftStaking), true);

        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;

        // 尝试重新质押 — 应该失败
        vm.expectRevert(abi.encodeWithSelector(NFTStaking.MachineHasUnpaidSlash.selector, machineId));
        nftStaking.stakeV2(owner, machineId, nftTokens, nftTokensBalance, 720, false);
        vm.stopPrank();
    }

    function test_canStake_allowsAfterPaySlash() public {
        _stakeAndRent(machineId, renter1, 0);
        _triggerOfflineSlash(machineId);

        // 先赔付
        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        rent.payPendingSlash(machineId);
        vm.stopPrank();

        assertFalse(rent.hasUnpaidSlash(machineId), "should have no unpaid slash after pay");

        // 赔付后重新质押 — 应该成功
        _stake(machineId, 0);
        assertTrue(nftStaking.isStaking(machineId));
    }

    // ========== 测试 version ==========

    function test_version() public view {
        assertEq(rent.version(), 6);
        assertEq(nftStaking.version(), 9);
    }

    // ========== Helper 函数 ==========

    function passHours(uint256 n) internal {
        uint256 secondsToAdvance = n * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / 6;
        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function _stake(string memory _machineId, uint256 reserveAmount) internal {
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, _machineId, 16)
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

        dealERC1155(address(nftToken), owner, 1, 1, false);
        deal(address(rewardToken), owner, 1_000_000 * 1e18);
        rewardToken.approve(address(nftStaking), type(uint256).max);
        nftToken.setApprovalForAll(address(nftStaking), true);

        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        nftStaking.stakeV2(owner, _machineId, nftTokens, nftTokensBalance, 720, false);

        if (reserveAmount > 0) {
            nftStaking.addDLCToStake(_machineId, reserveAmount);
        }
        vm.stopPrank();
    }

    function _stakeAndRent(string memory _machineId, address renter, uint256 reserveAmount) internal {
        _stake(_machineId, reserveAmount);

        // 加白名单
        vm.startPrank(owner);
        if (!rent.adminsToSetRentWhiteList(owner)) {
            address[] memory admins = new address[](1);
            admins[0] = owner;
            rent.setAdminsToAddRentWhiteList(admins);
        }
        string[] memory ids = new string[](1);
        ids[0] = _machineId;
        rent.setRentingWhitelist(ids, true);
        vm.stopPrank();

        // 租赁
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );

        uint256 rentSeconds = 10 hours;
        vm.startPrank(renter);
        rewardToken.approve(address(rent), 100_000 * 1e18);
        rent.rentMachine(_machineId, rentSeconds);
        vm.stopPrank();
    }

    function _triggerOfflineSlash(string memory _machineId) internal {
        // 推进 1 分钟，确保在租赁期内但产生极少奖励
        vm.warp(vm.getBlockTimestamp() + 60);
        vm.roll(vm.getBlockNumber() + 10);
        // 模拟 dbcAI 合约调用 notify(MachineOffline)
        vm.startPrank(address(dbcAIContract));
        rent.notify(Rent.NotifyType.MachineOffline, _machineId);
        vm.stopPrank();
    }
}
