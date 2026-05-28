// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {IStakingContract} from "../src/interface/IStakingContract.sol";
import {IOracle} from "../src/interface/IOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

/// @title PayoutWallet feature tests (v17 NFTStaking)
/// @notice 覆盖 EIP-712 双签设置 + 跨合约读 + 兜底 + 防重放 + chainId 隔离
contract PayoutWalletTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    IPrecompileContract public precompileContract;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;

    address owner = address(0x01);

    // 矿工 / payoutAdmin / newPayout 用 vm.addr(pk) 生成确定地址 (方便 vm.sign)
    uint256 constant STAKER_PK = 0xA11CE;
    uint256 constant ADMIN_PK = 0xB0B;
    uint256 constant WRONG_PK = 0xDEAD;
    address stakerAddr;
    address payoutAdminAddr;
    address wrongAddr;
    address newPayout = address(0xC0FFEE);
    address otherPayout = address(0xDECAF);

    bytes32 constant SET_PAYOUT_TYPEHASH = keccak256(
        "SetPayoutWallet(address staker,address newPayout,address payoutAdmin,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        stakerAddr = vm.addr(STAKER_PK);
        payoutAdminAddr = vm.addr(ADMIN_PK);
        wrongAddr = vm.addr(WRONG_PK);

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

        // 给 NFTStaking 充足 reward token 用于发奖
        deal(address(rewardToken), address(nftStaking), 180000000 * 1e18);

        // 设 reward start + 注册 owner 为 dlc client wallet
        nftStaking.setRewardStartAt(block.timestamp);
        address[] memory addrs = new address[](1);
        addrs[0] = owner;
        nftStaking.setDLCClientWallets(addrs);

        // mock dbcAI 调用
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

        // 初始化 payoutAdmin
        nftStaking.initializePayout(payoutAdminAddr);

        vm.stopPrank();

        passHours(1);
    }

    // ====== Test helper: 让 stakerAddr 完成质押 ======
    function _stake(string memory machineId, uint256 reserveAmount, uint256 stakeHours, bool isPersonal) internal {
        // mock dbcAI 返回机器属于 stakerAddr
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

        // 给 stakerAddr NFT + DLC 余额, approve nftStaking
        vm.startPrank(stakerAddr);
        dealERC1155(address(nftToken), stakerAddr, 1, 1, false);
        deal(address(rewardToken), stakerAddr, 100000 ether);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);
        vm.stopPrank();

        // owner (dlcClient) 代 stakerAddr 调 stakeV2
        vm.startPrank(owner);
        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        nftStaking.stakeV2(stakerAddr, machineId, nftTokens, nftTokensBalance, stakeHours, isPersonal);
        if (reserveAmount > 0) {
            nftStaking.addDLCToStake(machineId, reserveAmount);
        }
        vm.stopPrank();
    }

    function _setPayout(address newPayoutAddr) internal {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 currentNonce = nftStaking.payoutNonce(stakerAddr);
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayoutAddr, payoutAdminAddr, currentNonce, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayoutAddr, payoutAdminAddr, currentNonce, deadline);
        nftStaking.setPayoutWallet(stakerAddr, newPayoutAddr, currentNonce, deadline, ownerSig, adminSig);
    }

    function passHours(uint256 n) public {
        uint256 secondsToAdvance = n * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / 6;
        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    // ====== EIP-712 helper ======
    function _domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("DeepLinkPayout"),
            keccak256("1"),
            block.chainid,
            verifyingContract
        ));
    }

    function _signSetPayout(
        uint256 pk,
        address staker,
        address payout,
        address admin,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            SET_PAYOUT_TYPEHASH, staker, payout, admin, nonce, deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(address(nftStaking)), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // ====== 1. Happy path ======
    function test_setPayoutWallet_happy_path() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);

        assertEq(nftStaking.stakerPayoutWallet(stakerAddr), newPayout, "payout stored");
        assertEq(nftStaking.payoutNonce(stakerAddr), 1, "nonce incremented");
        assertEq(nftStaking.getPayoutFor(stakerAddr), newPayout, "getPayoutFor returns payout");
    }

    // ====== 2. Replay protection ======
    function test_setPayoutWallet_replay_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);

        // 同一 sig 重放
        vm.expectRevert(NFTStaking.InvalidNonce.selector);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 3. Expired deadline ======
    function test_setPayoutWallet_expired_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        vm.warp(deadline + 1);

        vm.expectRevert(NFTStaking.ExpiredSignature.selector);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 4. Wrong owner sig ======
    function test_setPayoutWallet_wrong_owner_sig_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(WRONG_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        vm.expectRevert(NFTStaking.InvalidOwnerSignature.selector);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 5. Wrong admin sig ======
    function test_setPayoutWallet_wrong_admin_sig_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(WRONG_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        vm.expectRevert(NFTStaking.InvalidAdminSignature.selector);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 6. payoutAdmin 旋转使 in-flight sig 失效 ======
    /// @dev 由于 typed data 含 payoutAdmin 字段, admin 旋转后:
    ///      旧 structHash (含旧 admin) != 新 structHash (含新 admin)
    ///      → 两个签名都对应旧 structHash, 用新 structHash 验证全部失败
    ///      → 合约先检查 ownerSig, revert InvalidOwnerSignature (设计意图: 集体失效)
    function test_setPayoutWallet_admin_rotation_invalidates_pending() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        address newAdmin = vm.addr(0xCAFE);
        vm.prank(owner);
        nftStaking.setPayoutAdmin(newAdmin);

        // 任一 sig 失效都 OK, 实际先 hit ownerSig 校验
        vm.expectRevert(NFTStaking.InvalidOwnerSignature.selector);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 7. 拒绝合约地址作为 payout ======
    function test_setPayoutWallet_contract_address_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        // 部署一个空合约做 payout 目标
        address contractPayout = address(new EmptyContract());
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, contractPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, contractPayout, payoutAdminAddr, 0, deadline);

        vm.expectRevert(NFTStaking.PayoutCannotBeContract.selector);
        nftStaking.setPayoutWallet(stakerAddr, contractPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 8. newPayout=0 清除语义 ======
    function test_setPayoutWallet_clear_with_zero() public {
        uint256 deadline = block.timestamp + 1 hours;
        // 先设一个 payout
        bytes memory ownerSig1 = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig1 = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig1, adminSig1);
        assertEq(nftStaking.stakerPayoutWallet(stakerAddr), newPayout);

        // 再用 nonce=1 清除 (newPayout=0)
        bytes memory ownerSig2 = _signSetPayout(STAKER_PK, stakerAddr, address(0), payoutAdminAddr, 1, deadline);
        bytes memory adminSig2 = _signSetPayout(ADMIN_PK, stakerAddr, address(0), payoutAdminAddr, 1, deadline);
        nftStaking.setPayoutWallet(stakerAddr, address(0), 1, deadline, ownerSig2, adminSig2);

        assertEq(nftStaking.stakerPayoutWallet(stakerAddr), address(0));
        assertEq(nftStaking.getPayoutFor(stakerAddr), stakerAddr, "fallback to staker");
    }

    // ====== 9. initializePayout 重复调用 ======
    function test_initializePayout_twice_reverts() public {
        vm.prank(owner);
        vm.expectRevert(NFTStaking.PayoutAlreadyInitialized.selector);
        nftStaking.initializePayout(vm.addr(0xBEEF));
    }

    // ====== 10. setPayoutAdmin(0) 拒绝 ======
    function test_setPayoutAdmin_zero_reverts() public {
        vm.prank(owner);
        vm.expectRevert(NFTStaking.ZeroAddress.selector);
        nftStaking.setPayoutAdmin(address(0));
    }

    // ====== 11b. staker 是合约钱包 → 拒绝 (P1.4 Agent2) ======
    function test_setPayoutWallet_contract_staker_reverts() public {
        // 部署一个空合约作 staker
        EmptyContract contractStaker = new EmptyContract();
        address contractStakerAddr = address(contractStaker);

        uint256 deadline = block.timestamp + 1 hours;
        // 用 stakerAddr 的 sig (因为 contractStakerAddr 没法签)
        // 但即使有 sig, 合约层会先 reject contract staker
        bytes memory ownerSig = _signSetPayout(STAKER_PK, contractStakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, contractStakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        vm.expectRevert(NFTStaking.StakerMustBeEOA.selector);
        nftStaking.setPayoutWallet(contractStakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 11. newPayout == staker (无意义) ======
    function test_setPayoutWallet_self_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, stakerAddr, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, stakerAddr, payoutAdminAddr, 0, deadline);

        vm.expectRevert(NFTStaking.RedundantPayout.selector);
        nftStaking.setPayoutWallet(stakerAddr, stakerAddr, 0, deadline, ownerSig, adminSig);
    }

    // ====== 12. PayoutAdmin 未初始化时 setPayoutWallet revert ======
    function test_setPayoutWallet_before_init_reverts() public {
        // 单独部署一个未 init 的 NFTStaking
        vm.startPrank(owner);
        ERC1967Proxy newProxy = new ERC1967Proxy(address(new NFTStaking()), "");
        NFTStaking freshStaking = NFTStaking(address(newProxy));
        freshStaking.initialize(
            owner, address(nftToken), address(rewardToken), address(rent), address(dbcAIContract), 1
        );
        vm.stopPrank();

        // 未调 initializePayout → payoutAdmin = 0
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        vm.expectRevert(NFTStaking.PayoutAdminNotInitialized.selector);
        freshStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 13. getPayoutFor 默认 (未设过) → staker ======
    function test_getPayoutFor_default_to_staker() public view {
        address randomStaker = address(0xBEEF);
        assertEq(nftStaking.getPayoutFor(randomStaker), randomStaker);
    }

    // ====== 14. Cross-chain replay protection ======
    function test_setPayoutWallet_cross_chain_replay_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;

        // 在当前 chain 签
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        // 切换 chainId — domain separator 变, 但 cache 仍是旧的, 实际 _domainSeparator 会 rebuild
        vm.chainId(99999);

        // ownerSig 因 domain separator 变化而验签失败
        vm.expectRevert(NFTStaking.InvalidOwnerSignature.selector);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 15. Nonce jump (skip) reverts ======
    function test_setPayoutWallet_nonce_skip_reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 5, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 5, deadline);

        vm.expectRevert(NFTStaking.InvalidNonce.selector);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 5, deadline, ownerSig, adminSig);
    }

    // ====== 16. version bump ======
    function test_version_is_17() public view {
        assertEq(nftStaking.version(), 17);
    }

    // ====== 17. deadline 上限拒绝 (Round-8 Agent B P0) ======
    function test_setPayoutWallet_deadline_too_far_reverts() public {
        uint256 deadline = block.timestamp + 8 days;  // 超过 7 天上限
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        vm.expectRevert(NFTStaking.DeadlineTooFar.selector);
        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 18. deadline 上限边界 (恰好 7 天) ======
    function test_setPayoutWallet_deadline_at_limit() public {
        uint256 deadline = block.timestamp + 7 days;  // 恰好 7 天, 应通过
        bytes memory ownerSig = _signSetPayout(STAKER_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);
        bytes memory adminSig = _signSetPayout(ADMIN_PK, stakerAddr, newPayout, payoutAdminAddr, 0, deadline);

        nftStaking.setPayoutWallet(stakerAddr, newPayout, 0, deadline, ownerSig, adminSig);
        assertEq(nftStaking.stakerPayoutWallet(stakerAddr), newPayout);
    }

    // ============================================================
    // P0 集成测试: 锁住 claim / unStake / Rent 跨合约的设计承诺
    // ============================================================

    // ====== P0-17: setPayout 后 claim 走新 payout (核心承诺) ======
    function test_claim_routes_to_payout_after_set() public {
        string memory machineId = "machineP0_17";
        _stake(machineId, 0, 72, true);
        passHours(24);  // 累计 1 天 reward

        // 设置 payout
        _setPayout(newPayout);
        assertEq(nftStaking.getPayoutFor(stakerAddr), newPayout);

        uint256 payoutBalanceBefore = rewardToken.balanceOf(newPayout);
        uint256 stakerBalanceBefore = rewardToken.balanceOf(stakerAddr);

        // staker 调 claim
        vm.prank(stakerAddr);
        nftStaking.claim(machineId);

        uint256 payoutBalanceAfter = rewardToken.balanceOf(newPayout);
        uint256 stakerBalanceAfter = rewardToken.balanceOf(stakerAddr);

        assertGt(payoutBalanceAfter, payoutBalanceBefore, "newPayout received DLC reward");
        assertEq(stakerBalanceAfter, stakerBalanceBefore, "staker NOT received reward");
    }

    // ====== P0-18: 未设 payout 时 claim 兜底发 staker (向后兼容) ======
    function test_claim_without_payout_falls_back_to_staker() public {
        string memory machineId = "machineP0_18";
        _stake(machineId, 0, 72, true);
        passHours(24);

        // 不调 setPayout
        assertEq(nftStaking.stakerPayoutWallet(stakerAddr), address(0));

        uint256 stakerBalanceBefore = rewardToken.balanceOf(stakerAddr);

        vm.prank(stakerAddr);
        nftStaking.claim(machineId);

        uint256 stakerBalanceAfter = rewardToken.balanceOf(stakerAddr);
        assertGt(stakerBalanceAfter, stakerBalanceBefore, "staker received DLC (default)");
    }

    // ====== P0-19: unStake reservedAmount 永远发 staker (锁住设计承诺) ======
    /// @dev 这是双密钥泄露兜底关键: payout 失守不影响本金
    function test_unStake_reservedAmount_always_to_staker() public {
        string memory machineId = "machineP0_19";
        uint256 reserveAmount = 10_000 ether;  // BASE_RESERVE_AMOUNT
        _stake(machineId, reserveAmount, 2, true);  // 2 小时 (合约最小要求)

        // 设 payout 到 newPayout
        _setPayout(newPayout);

        // 等质押到期
        passHours(3);

        uint256 stakerBalanceBefore = rewardToken.balanceOf(stakerAddr);

        // mock dbcAI 让 isRegistered 返回 false (让 unStakeByHolder 通过)
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, false)
        );

        vm.prank(stakerAddr);
        nftStaking.unStakeByHolder(machineId);

        uint256 payoutBalanceAfter = rewardToken.balanceOf(newPayout);
        uint256 stakerBalanceAfter = rewardToken.balanceOf(stakerAddr);

        // 关键断言: reservedAmount 进 staker, 不进 payout
        uint256 stakerGain = stakerBalanceAfter - stakerBalanceBefore;
        assertGe(stakerGain, reserveAmount, "staker received reservedAmount as principal refund");
        emit log_named_uint("payout balance after", payoutBalanceAfter);
        emit log_named_uint("staker balance after", stakerBalanceAfter);
    }

    // ====== P0-20: Rent.endRent 通过 IStakingContract.getPayoutFor 跨合约读 (用 mock) ======
    function test_rent_getPayoutFor_cross_contract_call() public {
        // 部署 mock IStakingContract 实现 getPayoutFor
        MockStakingForRent mockStaking = new MockStakingForRent();
        mockStaking.setPayout(stakerAddr, newPayout);

        // 验证 mock 返回正确
        assertEq(mockStaking.getPayoutFor(stakerAddr), newPayout);
        assertEq(mockStaking.getPayoutFor(address(0x999)), address(0));

        // 真实 NFTStaking 在 happy path 也应该跨合约返回 payout
        _setPayout(otherPayout);
        assertEq(nftStaking.getPayoutFor(stakerAddr), otherPayout);

        // 模拟 Rent 通过 IStakingContract 接口调
        IStakingContract istaking = IStakingContract(address(nftStaking));
        assertEq(istaking.getPayoutFor(stakerAddr), otherPayout);
    }

    // ====== P0-21: Rent 兜底 (真实跑 Rent._getPayoutFor + 验 emit) ======
    /// @dev 部署 RentExposed (继承 Rent 暴露 _getPayoutFor), mockCall NFTStaking revert
    ///      验证: (1) emit PayoutLookupFailed(stakeHolder) (2) 返回 stakeHolder (兜底)
    function test_rent_fallback_emits_PayoutLookupFailed() public {
        // 部署一个独立的 RentExposed (绕过 proxy, 简化测试)
        // 共享 nftStaking 实例
        ERC1967Proxy exposedProxy = new ERC1967Proxy(address(new RentExposed()), "");
        RentExposed exposedRent = RentExposed(address(exposedProxy));
        vm.prank(owner);
        exposedRent.initialize(
            owner, address(precompileContract), address(nftStaking), address(dbcAIContract), address(rewardToken)
        );

        // mockCallRevert: 让 nftStaking.getPayoutFor revert
        vm.mockCallRevert(
            address(nftStaking),
            abi.encodeWithSelector(IStakingContract.getPayoutFor.selector, stakerAddr),
            "simulated NFTStaking failure"
        );

        // 期望 emit PayoutLookupFailed(stakerAddr)
        vm.expectEmit(true, false, false, false, address(exposedRent));
        emit Rent.PayoutLookupFailed(stakerAddr);

        // 触发 Rent._getPayoutFor (通过暴露的 helper)
        address result = exposedRent.exposedGetPayoutFor(stakerAddr);

        // 兜底返回 stakeHolder (即 stakerAddr 自己)
        assertEq(result, stakerAddr, "fallback returns stakeHolder");
    }

    // ====== P0-22: Rent _getPayoutFor 跨合约 happy path 端到端 ======
    /// @dev 真实跑 Rent → NFTStaking.getPayoutFor → 返回 newPayout
    function test_rent_getPayoutFor_happy_path() public {
        ERC1967Proxy exposedProxy = new ERC1967Proxy(address(new RentExposed()), "");
        RentExposed exposedRent = RentExposed(address(exposedProxy));
        vm.prank(owner);
        exposedRent.initialize(
            owner, address(precompileContract), address(nftStaking), address(dbcAIContract), address(rewardToken)
        );

        // 设 stakerAddr 的 payout 到 newPayout
        _setPayout(newPayout);
        assertEq(nftStaking.getPayoutFor(stakerAddr), newPayout);

        // Rent.exposedGetPayoutFor 应通过跨合约调用拿到 newPayout
        address result = exposedRent.exposedGetPayoutFor(stakerAddr);
        assertEq(result, newPayout, "cross-contract returns payout");

        // 未设 payout 的 staker 应返回他自己 (兜底)
        address unsetStaker = address(0xBEEFCAFE);
        address result2 = exposedRent.exposedGetPayoutFor(unsetStaker);
        assertEq(result2, unsetStaker, "unset staker returns himself");
    }
}

/// @dev RentExposed 继承 Rent 暴露 _getPayoutFor 给测试用
contract RentExposed is Rent {
    function exposedGetPayoutFor(address stakeHolder) external returns (address) {
        return _getPayoutFor(stakeHolder);
    }
}

/// @dev mock IStakingContract 实现 getPayoutFor (用于 Rent 跨合约测试)
contract MockStakingForRent {
    mapping(address => address) public payoutOf;

    function setPayout(address staker, address payout) external {
        payoutOf[staker] = payout;
    }

    function getPayoutFor(address staker) external view returns (address) {
        return payoutOf[staker];
    }
}

/// @dev mock NFTStaking 让 getPayoutFor revert (验证 Rent 兜底)
contract RevertingStakingMock {
    function getPayoutFor(address) external pure returns (address) {
        revert("mock revert");
    }
}

/// @dev 测试用空合约 — 部署后 code.length > 0
contract EmptyContract {
    receive() external payable {}
}
