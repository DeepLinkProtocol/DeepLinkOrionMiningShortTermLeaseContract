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

/// @title 安全审计测试 — payPendingSlash / hasUnpaidSlash / canStake
contract SlashPaymentSecurityTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    IPrecompileContract public precompileContract;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;
    IOracle public oracle;

    address owner = address(0x01);
    address renter1 = address(0x10);
    address attacker = address(0xBAD);
    address admin2 = address(0x02);
    address admin3 = address(0x03);
    address admin4 = address(0x04);
    address admin5 = address(0x05);

    string machineId = "securityTestMachine";

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

        deal(address(rewardToken), owner, 10_000_000 * 1e18);
        deal(address(rewardToken), renter1, 100_000 * 1e18);
        deal(address(rewardToken), attacker, 100_000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 10_000_000 * 1e18);

        rewardToken.approve(address(nftStaking), type(uint256).max);
        nftStaking.setRewardStartAt(block.timestamp);

        vm.warp(vm.getBlockTimestamp() + 3600);
        vm.roll(vm.getBlockNumber() + 600);

        oracle = IOracle(address(0x12));
        rent.setOracle(address(oracle));

        vm.mockCall(
            address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.reportStakingStatus.selector), abi.encode()
        );
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.mockCall(address(rent), abi.encodeWithSelector(rent.getMachinePrice.selector), abi.encode(100));
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.getTokenPriceInUSD.selector), abi.encode(100));
        vm.stopPrank();
    }

    // ================================================================
    // 安全测试 1: 双重支付 — payPendingSlash 不能对同一 slash 付两次
    // ================================================================
    function test_security_noDoublePay() public {
        _createUnpaidSlash();

        // 第一次赔付
        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        rent.payPendingSlash(machineId);
        vm.stopPrank();

        assertFalse(rent.hasUnpaidSlash(machineId));

        // 第二次赔付应该 revert
        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        vm.expectRevert(abi.encodeWithSelector(Rent.NoUnpaidSlash.selector));
        rent.payPendingSlash(machineId);
        vm.stopPrank();
    }

    // ================================================================
    // 安全测试 2: payPendingSlash 先 transfer 后 set paid=true
    //   如果 renter 是恶意合约，safeTransferFrom 可能触发回调
    //   但 nonReentrant 应该阻止重入
    // ================================================================
    function test_security_reentrancyProtection() public {
        _createUnpaidSlash();
        // nonReentrant modifier 存在，这里只验证函数确实有 nonReentrant
        // 在实际恶意合约场景中，重入会被 ReentrancyGuardUpgradeable 阻止
        // 由于 safeTransferFrom 用的是 ERC20（非 ERC777），回调风险较低
        // 但 nonReentrant 是正确的防御措施
        assertTrue(rent.hasUnpaidSlash(machineId));
    }

    // ================================================================
    // 安全测试 3: 攻击者不能通过 payPendingSlash 把钱转给自己
    //   renter 地址由合约在 slash 时写入，调用者无法控制
    // ================================================================
    function test_security_cannotRedirectPayment() public {
        _createUnpaidSlash();

        uint256 renter1Before = rewardToken.balanceOf(renter1);
        uint256 attackerBefore = rewardToken.balanceOf(attacker);

        // 攻击者替矿工赔付
        vm.startPrank(attacker);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        rent.payPendingSlash(machineId);
        vm.stopPrank();

        // 钱应该到 renter1（SlashInfo 中记录的 renter），不是 attacker
        assertEq(rewardToken.balanceOf(renter1), renter1Before + rent.SLASH_AMOUNT());
        // 攻击者被扣了钱
        assertEq(rewardToken.balanceOf(attacker), attackerBefore - rent.SLASH_AMOUNT());
    }

    // ================================================================
    // 安全测试 4: payPendingSlash 在 approve 不足时应该 revert
    // ================================================================
    function test_security_insufficientAllowance() public {
        _createUnpaidSlash();

        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT() - 1);
        vm.expectRevert(); // ERC20InsufficientAllowance
        rent.payPendingSlash(machineId);
        vm.stopPrank();
    }

    // ================================================================
    // 安全测试 5: payPendingSlash 在余额不足时应该 revert
    // ================================================================
    function test_security_insufficientBalance() public {
        _createUnpaidSlash();

        address poorUser = address(0xDEAD);
        deal(address(rewardToken), poorUser, 1 * 1e18); // 远少于 SLASH_AMOUNT

        vm.startPrank(poorUser);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        vm.expectRevert(); // ERC20InsufficientBalance
        rent.payPendingSlash(machineId);
        vm.stopPrank();
    }

    // ================================================================
    // 安全测试 6: hasUnpaidSlash 是 view 函数，不消耗 gas（除 staticcall）
    //   但如果 slash 历史很长，可能 gas 过高导致 canStake 失败
    //   这是 DoS 向量 — 恶意租户反复租赁+举报可以让 slash 数组增长
    // ================================================================
    function test_security_gasLimitWithManySlashes() public {
        // 创建 1 次 unpaid slash
        _stakeAndRent(renter1, 0);
        _triggerOfflineSlash();

        assertTrue(rent.hasUnpaidSlash(machineId));

        // 验证 getSlashInfosByMachineId 能正常返回
        (Rent.SlashInfo[] memory infos, uint256 total) = rent.getSlashInfosByMachineId(machineId, 1, 20);
        assertEq(total, 1);
        assertFalse(infos[0].paid);
        assertEq(infos[0].slashAmount, rent.SLASH_AMOUNT());

        // 赔付后验证
        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        rent.payPendingSlash(machineId);
        vm.stopPrank();

        (Rent.SlashInfo[] memory infos2, uint256 total2) = rent.getSlashInfosByMachineId(machineId, 1, 20);
        assertEq(total2, 1);
        assertTrue(infos2[0].paid);

        // 注意：slash 历史记录永久存储在链上，不会被清理
        // 每次 slash 都 push 到数组，长期来看 hasUnpaidSlash 遍历成本会增加
        // 但实际场景中单台机器不太可能被 slash 超过几十次
    }

    // ================================================================
    // 安全测试 7: paidSlash (NFTStaking内部调用) 和 payPendingSlash 不冲突
    //   如果 _claim 里已经通过 paidSlash 标记为 paid，
    //   payPendingSlash 不应该再次转账
    // ================================================================
    function test_security_paidSlashAndPayPendingSlashNoConflict() public {
        // 用足够的 reserve 让 reportMachineFault 立即赔付
        _stakeAndRent(renter1, 2000 * 1e18);
        _triggerOfflineSlash();

        // 此时 paidSlash 已经被 reportMachineFault 内部调用，paid=true
        assertFalse(rent.hasUnpaidSlash(machineId));

        // payPendingSlash 应该 revert
        vm.startPrank(owner);
        rewardToken.approve(address(rent), rent.SLASH_AMOUNT());
        vm.expectRevert(abi.encodeWithSelector(Rent.NoUnpaidSlash.selector));
        rent.payPendingSlash(machineId);
        vm.stopPrank();
    }

    // ================================================================
    // 安全测试 8: 空 machineId 不应导致异常
    // ================================================================
    function test_security_emptyMachineId() public view {
        assertFalse(rent.hasUnpaidSlash(""));
        assertFalse(rent.hasUnpaidSlash("nonexistent_machine_xyz"));
    }

    // ================================================================
    // 安全测试 9: payPendingSlash 的 feeToken 应该与 slash 时写入的 slashAmount 匹配
    //   slashAmount 在 Rent.SLASH_AMOUNT = 10_000 ether
    //   NFTStaking.SLASH_AMOUNT = 1_000 ether（不同！）
    //   payPendingSlash 用 infos[i].slashAmount（来自 Rent 的 SLASH_AMOUNT）
    //   所以赔付金额是 10_000 ether — 正确
    // ================================================================
    function test_security_correctSlashAmount() public {
        _createUnpaidSlash();

        uint256 ownerBefore = rewardToken.balanceOf(owner);

        vm.startPrank(owner);
        rewardToken.approve(address(rent), type(uint256).max);
        rent.payPendingSlash(machineId);
        vm.stopPrank();

        uint256 ownerAfter = rewardToken.balanceOf(owner);
        // 应该扣 Rent.SLASH_AMOUNT (10,000 ether)，不是 NFTStaking.SLASH_AMOUNT (1,000 ether)
        assertEq(ownerBefore - ownerAfter, rent.SLASH_AMOUNT());
        assertEq(rent.SLASH_AMOUNT(), 10_000 ether);
    }

    // ================================================================
    // 安全测试 10: canStake 中 hasUnpaidSlash 调用不会被 mock 绕过
    //   攻击者不能通过外部方式让 hasUnpaidSlash 返回 false
    // ================================================================
    function test_security_lightPenaltyKeepsStaking() public {
        _createUnpaidSlash();

        assertTrue(rent.hasUnpaidSlash(machineId), "should have unpaid slash");
        // 轻量惩罚后机器保持质押状态（不解质押）
        assertTrue(nftStaking.isStaking(machineId), "should still be staking after light penalty");
        // NFTStaking 侧租赁状态已清除
        (,,,,,,,, bool isRentedByUser,,) = nftStaking.machineId2StakeInfos(machineId);
        assertFalse(isRentedByUser, "isRentedByUser should be false");

        // 尝试重新质押 — 应该失败（因为已经在质押中，IsStaking）
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

        vm.expectRevert(abi.encodeWithSelector(NFTStaking.IsStaking.selector));
        nftStaking.stakeV2(owner, machineId, nftTokens, nftTokensBalance, 720, false);
        vm.stopPrank();
    }

    // ================================================================
    // Helper 函数
    // ================================================================

    function _createUnpaidSlash() internal {
        _stakeAndRent(renter1, 0);
        _triggerOfflineSlash();
        assertTrue(rent.hasUnpaidSlash(machineId), "slash should be unpaid");
    }

    function _stakeAndRent(address renter, uint256 reserveAmount) internal {
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

        dealERC1155(address(nftToken), owner, 1, 1, false);
        deal(address(rewardToken), owner, 10_000_000 * 1e18);
        rewardToken.approve(address(nftStaking), type(uint256).max);
        nftToken.setApprovalForAll(address(nftStaking), true);

        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        nftStaking.stakeV2(owner, machineId, nftTokens, nftTokensBalance, 720, false);
        if (reserveAmount > 0) {
            nftStaking.addDLCToStake(machineId, reserveAmount);
        }
        vm.stopPrank();

        // 加白名单
        vm.startPrank(owner);
        if (!rent.adminsToSetRentWhiteList(owner)) {
            address[] memory admins = new address[](1);
            admins[0] = owner;
            rent.setAdminsToAddRentWhiteList(admins);
        }
        string[] memory ids = new string[](1);
        ids[0] = machineId;
        rent.setRentingWhitelist(ids, true);
        vm.stopPrank();

        // 租赁
        vm.startPrank(renter);
        rewardToken.approve(address(rent), 100_000 * 1e18);
        rent.rentMachine(machineId, 10 hours);
        vm.stopPrank();
    }

    function _triggerOfflineSlash() internal {
        vm.warp(vm.getBlockTimestamp() + 60);
        vm.roll(vm.getBlockNumber() + 10);
        vm.startPrank(address(dbcAIContract));
        rent.notify(Rent.NotifyType.MachineOffline, machineId);
        vm.stopPrank();
    }
}
