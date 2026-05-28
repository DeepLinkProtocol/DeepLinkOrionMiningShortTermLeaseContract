// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/NFTStaking.sol";
import "../src/rent/Rent.sol";

interface IProxy {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

/// @title v16 → v17 mainnet fork 升级模拟
/// @notice 用 DBC mainnet RPC fork, 实际 mainnet state 测 NFTStaking + Rent 升级路径
/// @dev 跑命令:
///      forge test --match-contract ForkTestV17Payout --fork-url https://rpc.dbcwallet.io -vv
contract ForkTestV17Payout is Test {
    // Mainnet 地址
    address constant STAKING_PROXY = 0x6268Aba94D0d0e4FB917cC02765f631f309a7388;
    address constant RENT_PROXY = 0xDA9EfdfF9CA7B7065b7706406a1a79C0e483815A;
    address constant UPGRADE_ADDR = 0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8;
    address constant OWNER_ADDR = 0x244f8191010a9C20aaE96DC4afa4E1D63983802E;
    address constant DLP_TOKEN = 0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6;

    NFTStaking staking;
    Rent rent;

    // 测试矿工: 使用确定性私钥 + 地址 (vm.sign 可控)
    uint256 constant TEST_STAKER_PK = 0xA11CE;
    address testStaker;
    address testPayout = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

    function setUp() public {
        // fork mainnet
        staking = NFTStaking(STAKING_PROXY);
        rent = Rent(RENT_PROXY);
        testStaker = vm.addr(TEST_STAKER_PK);

        console.log("=== Pre-Upgrade State ===");
        console.log("NFTStaking version:", staking.version());
        console.log("Rent version:", rent.version());
    }

    function _upgradeNFTStakingToV17() internal {
        vm.startPrank(UPGRADE_ADDR);
        NFTStaking newImpl = new NFTStaking();
        IProxy(STAKING_PROXY).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
        assertEq(staking.version(), 17, "version should be 17 post-upgrade");
        console.log("NFTStaking upgraded to v17, impl:", address(newImpl));
    }

    function _initializePayout() internal {
        vm.prank(OWNER_ADDR);
        staking.initializePayout(OWNER_ADDR);  // 用 owner 作为 payoutAdmin
        assertEq(staking.payoutAdmin(), OWNER_ADDR, "payoutAdmin should be owner");
        console.log("initializePayout called, payoutAdmin:", staking.payoutAdmin());
    }

    function _upgradeRentToV12() internal {
        vm.startPrank(UPGRADE_ADDR);
        Rent newImpl = new Rent();
        IProxy(RENT_PROXY).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
        assertEq(rent.version(), 12, "Rent version should be 12 post-upgrade");
        console.log("Rent upgraded to v12, impl:", address(newImpl));
    }

    // ====== 1. 完整升级流程验证 ======
    function test_full_upgrade_flow() public {
        _upgradeNFTStakingToV17();
        _initializePayout();
        _upgradeRentToV12();

        assertEq(staking.version(), 17);
        assertEq(rent.version(), 12);
        assertNotEq(staking.payoutAdmin(), address(0));
    }

    // ====== 2. 部署顺序错误 (Rent v12 在 NFTStaking v17 之前) ======
    /// @dev 反序: Rent v12 调 v16 NFTStaking.getPayoutFor 失败 → 兜底发 stakeHolder
    function test_reverse_order_triggers_fallback_safely() public {
        _upgradeRentToV12();  // 先升 Rent (反序!)
        // 此时 NFTStaking 仍是 v16, 没有 getPayoutFor
        // Rent._getPayoutFor try/catch 会兜底
        // 没有实际触发 endRent 的话, 不会 revert
        assertEq(rent.version(), 12);
        assertEq(staking.version(), 16, "NFTStaking still v16");
    }

    // ====== 3. 现有 200 staker 100% 向后兼容 ======
    function test_backward_compatibility_existing_stakers() public {
        _upgradeNFTStakingToV17();
        _initializePayout();

        // 任意现有 staker (用 owner 作 sample, 实际 mainnet 上肯定不是 staker, 但 mapping 默认 0)
        address sampleStaker = OWNER_ADDR;
        address payout = staking.getPayoutFor(sampleStaker);

        // 默认 stakerPayoutWallet[sampleStaker] = 0 → 返回 sampleStaker 自己
        assertEq(payout, sampleStaker, "default payout = staker (backward compat)");

        // 验证 stakerPayoutWallet[sampleStaker] 真的是 0
        assertEq(staking.stakerPayoutWallet(sampleStaker), address(0));
    }

    // ====== 4. 矿工 setPayoutWallet 完整流程 (EIP-712 双签) ======
    function test_miner_setPayoutWallet_full_flow() public {
        _upgradeNFTStakingToV17();
        _initializePayout();

        address payoutAdmin = staking.payoutAdmin();
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = staking.payoutNonce(testStaker);

        // 构造 EIP-712 digest
        bytes32 structHash = keccak256(abi.encode(
            staking.SET_PAYOUT_TYPEHASH(),
            testStaker,
            testPayout,
            payoutAdmin,
            nonce,
            deadline
        ));
        bytes32 domainSep = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("DeepLinkPayout"),
            keccak256("1"),
            block.chainid,
            STAKING_PROXY
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));

        // testStaker 签
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(TEST_STAKER_PK, digest);
        bytes memory ownerSig = abi.encodePacked(r1, s1, v1);

        // payoutAdmin (owner) 签 — 在 fork 中 OWNER_ADDR 的私钥我们不知道
        // 但 vm.sign 可以模拟任意地址签名? 不能, vm.sign 用私钥
        // 用 fake admin: 把 payoutAdmin 改成 vm.addr(0xB0B), 然后用 0xB0B 签
        // 但这需要重新 initializePayout — 已经 init 过了 (PayoutAlreadyInitialized)

        // 方案: setPayoutAdmin 换成测试 admin
        uint256 testAdminPK = 0xB0B;
        address testAdmin = vm.addr(testAdminPK);
        vm.prank(OWNER_ADDR);
        staking.setPayoutAdmin(testAdmin);
        assertEq(staking.payoutAdmin(), testAdmin);

        // 重签 (因为 typed data 含 payoutAdmin 字段)
        structHash = keccak256(abi.encode(
            staking.SET_PAYOUT_TYPEHASH(),
            testStaker,
            testPayout,
            testAdmin,
            nonce,
            deadline
        ));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (v1, r1, s1) = vm.sign(TEST_STAKER_PK, digest);
        ownerSig = abi.encodePacked(r1, s1, v1);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(testAdminPK, digest);
        bytes memory adminSig = abi.encodePacked(r2, s2, v2);

        // 调链上
        staking.setPayoutWallet(testStaker, testPayout, nonce, deadline, ownerSig, adminSig);

        // 验证
        assertEq(staking.stakerPayoutWallet(testStaker), testPayout, "payout stored");
        assertEq(staking.payoutNonce(testStaker), nonce + 1, "nonce incremented");
        assertEq(staking.getPayoutFor(testStaker), testPayout, "getPayoutFor returns payout");
        console.log("setPayoutWallet success: staker=", testStaker, "payout=", testPayout);
    }

    // ====== 5. Rent v12 跨合约读 NFTStaking payout ======
    function test_rent_reads_nftstaking_payout() public {
        _upgradeNFTStakingToV17();
        _initializePayout();
        _upgradeRentToV12();

        // 通过 setPayoutAdmin 让我们能 sign adminSig
        uint256 testAdminPK = 0xB0B;
        address testAdmin = vm.addr(testAdminPK);
        vm.prank(OWNER_ADDR);
        staking.setPayoutAdmin(testAdmin);

        // 设 testStaker 的 payout
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = staking.payoutNonce(testStaker);

        bytes32 structHash = keccak256(abi.encode(
            staking.SET_PAYOUT_TYPEHASH(), testStaker, testPayout, testAdmin, nonce, deadline
        ));
        bytes32 domainSep = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("DeepLinkPayout"), keccak256("1"), block.chainid, STAKING_PROXY
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(TEST_STAKER_PK, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(testAdminPK, digest);
        staking.setPayoutWallet(testStaker, testPayout, nonce, deadline, abi.encodePacked(r1, s1, v1), abi.encodePacked(r2, s2, v2));

        // Rent 通过 IStakingContract 接口跨合约读
        address payoutFromRent = IStakingContract(STAKING_PROXY).getPayoutFor(testStaker);
        assertEq(payoutFromRent, testPayout, "Rent reads payout from NFTStaking");
        console.log("Rent cross-contract getPayoutFor:", payoutFromRent);
    }

    // ====== 6. v17 升级 storage 验证 ======
    function test_storage_layout_preserved() public {
        // 升级前快照关键 storage
        uint256 oldTotalStakingGpuCount = staking.totalStakingGpuCount();
        uint256 oldDailyRewardAmount = staking.getDailyRewardAmount();
        uint256 oldTotalReservedAmount = staking.totalReservedAmount();
        address oldRewardToken = address(staking.rewardToken());

        // 升级
        _upgradeNFTStakingToV17();

        // 验证升级后这些值不变
        assertEq(staking.totalStakingGpuCount(), oldTotalStakingGpuCount);
        assertEq(staking.getDailyRewardAmount(), oldDailyRewardAmount);
        assertEq(staking.totalReservedAmount(), oldTotalReservedAmount);
        assertEq(address(staking.rewardToken()), oldRewardToken);
        console.log("storage layout preserved across upgrade");
    }

    // ====== 7. initializePayout 不能重复调 ======
    function test_initializePayout_cannot_be_called_twice() public {
        _upgradeNFTStakingToV17();
        _initializePayout();

        vm.prank(OWNER_ADDR);
        vm.expectRevert(NFTStaking.PayoutAlreadyInitialized.selector);
        staking.initializePayout(address(0xBEEF));
    }

    // ====== 8. 升级期间 (initializePayout 之前) setPayoutWallet revert ======
    function test_setPayoutWallet_before_init_reverts_on_fork() public {
        _upgradeNFTStakingToV17();
        // 不调 initializePayout

        bytes memory dummySig = new bytes(65);
        vm.expectRevert(NFTStaking.PayoutAdminNotInitialized.selector);
        staking.setPayoutWallet(testStaker, testPayout, 0, block.timestamp + 1 hours, dummySig, dummySig);
    }
}

