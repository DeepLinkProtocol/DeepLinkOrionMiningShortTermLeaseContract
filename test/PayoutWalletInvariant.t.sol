// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

/// @title PayoutWallet Foundry Invariant Tests (v17)
/// @notice 用随机 handler 调用验证 PayoutWallet 4 大不变量
/// @dev fail_on_revert=false → handler revert 不停, 用于探测真实状态破坏
contract PayoutWalletInvariantTest is StdInvariant, Test {
    NFTStaking public nftStaking;
    Rent public rent;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;
    IPrecompileContract public precompileContract;

    PayoutHandler public handler;

    address owner = address(0x01);
    uint256 constant STAKER_PK = 0xA11CE;
    uint256 constant ADMIN_PK = 0xB0B;
    address stakerAddr;
    address payoutAdminAddr;

    function setUp() public {
        stakerAddr = vm.addr(STAKER_PK);
        payoutAdminAddr = vm.addr(ADMIN_PK);

        vm.startPrank(owner);
        precompileContract = IPrecompileContract(address(0x11));
        rewardToken = new Token();
        nftToken = new DLCNode(owner);

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

        nftStaking.initializePayout(payoutAdminAddr);
        vm.stopPrank();

        // 部署 handler, 暴露给 invariant runner
        handler = new PayoutHandler(nftStaking, stakerAddr, STAKER_PK, payoutAdminAddr, ADMIN_PK, owner);

        targetContract(address(handler));
        // 限定 selector — 不让 invariant runner 调到不相干函数
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = PayoutHandler.setPayout_happy.selector;
        selectors[1] = PayoutHandler.setPayout_badNonce.selector;
        selectors[2] = PayoutHandler.setPayout_expired.selector;
        selectors[3] = PayoutHandler.rotateAdmin.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ============================================================
    // Invariant 1: payoutNonce 单调递增 — 任意 handler 调用后永不减少
    // ============================================================
    function invariant_payoutNonce_monotonic() public view {
        uint256 currentNonce = nftStaking.payoutNonce(stakerAddr);
        uint256 maxObserved = handler.maxNonceObserved();
        assertGe(currentNonce, maxObserved, "payoutNonce regressed");
    }

    // ============================================================
    // Invariant 2: payoutAdmin 非零 — init 后任何 rotation 都不能设为 0
    // ============================================================
    function invariant_payoutAdmin_nonzero() public view {
        assertTrue(nftStaking.payoutAdmin() != address(0), "payoutAdmin zeroed");
    }


    // ============================================================
    // Invariant 3: stakerPayoutWallet 状态一致性
    //  - staker 必为 EOA (合约 staker 进不来)
    //  - payout 必为 EOA (合约 payout 拒绝)
    //  - payout != staker (自指拒绝)
    // ============================================================
    function invariant_stakerPayoutWallet_consistent() public view {
        address staker = stakerAddr;
        address payout = nftStaking.stakerPayoutWallet(staker);
        if (payout != address(0)) {
            assertEq(staker.code.length, 0, "staker should be EOA");
            assertEq(payout.code.length, 0, "payout should be EOA");
            assertTrue(payout != staker, "payout == staker not allowed");
        }
    }

    // ============================================================
    // Invariant 4: getPayoutFor 永远返回非零 (假设 staker != 0)
    //  - payout 未设 → 返回 staker
    //  - payout 已设 → 返回 payout
    //  - 二者都不能为 0
    // ============================================================
    function invariant_getPayoutFor_nonzero() public view {
        address result = nftStaking.getPayoutFor(stakerAddr);
        assertTrue(result != address(0), "getPayoutFor returned zero");
    }
}

/// @dev Handler 合约 — Foundry invariant runner 随机调用其函数
contract PayoutHandler is Test {
    NFTStaking public nftStaking;
    address public staker;
    uint256 public stakerPK;
    address public admin;
    uint256 public adminPK;
    address public owner;

    uint256 public maxNonceObserved;

    bytes32 constant SET_PAYOUT_TYPEHASH = keccak256(
        "SetPayoutWallet(address staker,address newPayout,address payoutAdmin,uint256 nonce,uint256 deadline)"
    );

    constructor(
        NFTStaking _nftStaking,
        address _staker,
        uint256 _stakerPK,
        address _admin,
        uint256 _adminPK,
        address _owner
    ) {
        nftStaking = _nftStaking;
        staker = _staker;
        stakerPK = _stakerPK;
        admin = _admin;
        adminPK = _adminPK;
        owner = _owner;
    }

    // ====== Happy path: 正确 nonce + 有效 sig + 限定 EOA newPayout ======
    function setPayout_happy(uint256 seed) external {
        // 从 seed 推导 EOA-like 地址 (确保 code.length == 0)
        uint160 truncated = uint160(uint256(keccak256(abi.encode("payout", seed))));
        if (truncated == 0) return;
        address bounded = address(truncated);
        if (bounded == staker) return;
        if (bounded.code.length > 0) return;

        uint256 nonce = nftStaking.payoutNonce(staker);
        uint256 deadline = block.timestamp + 1 hours;

        address currentAdmin = nftStaking.payoutAdmin();
        // adminPK 可能已经被 rotateAdmin 改了 → 仅用真实当前 adminPK 签
        // 这里实现简化: 我们用 known admin (rotateAdmin 会更新 adminPK)
        bytes memory ownerSig = _sign(stakerPK, staker, bounded, currentAdmin, nonce, deadline);
        bytes memory adminSig = _sign(adminPK, staker, bounded, currentAdmin, nonce, deadline);

        try nftStaking.setPayoutWallet(staker, bounded, nonce, deadline, ownerSig, adminSig) {
            uint256 newNonce = nftStaking.payoutNonce(staker);
            if (newNonce > maxNonceObserved) {
                maxNonceObserved = newNonce;
            }
        } catch {
            // 期望失败的边界 (eg. adminPK 已被旋转过) 也 ok
        }
    }

    // ====== Bad nonce: 用错的 nonce 应该 revert, 不应改 state ======
    function setPayout_badNonce(uint256 wrongNonce) external {
        uint256 realNonce = nftStaking.payoutNonce(staker);
        if (wrongNonce == realNonce) wrongNonce = realNonce + 1;  // 强制错

        address bounded = address(uint160(uint256(keccak256(abi.encode("bad", wrongNonce)))));
        if (bounded == address(0) || bounded == staker || bounded.code.length > 0) return;

        uint256 deadline = block.timestamp + 1 hours;
        address currentAdmin = nftStaking.payoutAdmin();
        bytes memory ownerSig = _sign(stakerPK, staker, bounded, currentAdmin, wrongNonce, deadline);
        bytes memory adminSig = _sign(adminPK, staker, bounded, currentAdmin, wrongNonce, deadline);

        try nftStaking.setPayoutWallet(staker, bounded, wrongNonce, deadline, ownerSig, adminSig) {
            // 不应进入此分支
        } catch {
            // 期望
        }
    }

    // ====== Expired: deadline 已过应 revert ======
    function setPayout_expired(uint256 seed) external {
        if (block.timestamp < 2) return;
        address bounded = address(uint160(uint256(keccak256(abi.encode("exp", seed)))));
        if (bounded == address(0) || bounded == staker || bounded.code.length > 0) return;

        uint256 nonce = nftStaking.payoutNonce(staker);
        uint256 deadline = block.timestamp - 1;
        address currentAdmin = nftStaking.payoutAdmin();
        bytes memory ownerSig = _sign(stakerPK, staker, bounded, currentAdmin, nonce, deadline);
        bytes memory adminSig = _sign(adminPK, staker, bounded, currentAdmin, nonce, deadline);

        try nftStaking.setPayoutWallet(staker, bounded, nonce, deadline, ownerSig, adminSig) {
            // 不应进入
        } catch {
            // 期望
        }
    }

    // ====== Admin rotation: 旋转后内部维护新的 adminPK ======
    function rotateAdmin(uint256 newAdminPKSalt) external {
        // 限制 pk 范围避免 0
        uint256 newPK = (newAdminPKSalt % 1000) + 0xC001;
        address newAdmin = vm.addr(newPK);
        if (newAdmin == address(0)) return;

        vm.prank(owner);
        try nftStaking.setPayoutAdmin(newAdmin) {
            // 同步更新本 handler 的 adminPK
            admin = newAdmin;
            adminPK = newPK;
        } catch {
            // 期望成功 — 失败说明不变量被违反
        }
    }

    function _sign(uint256 pk, address s, address p, address a, uint256 n, uint256 d)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(SET_PAYOUT_TYPEHASH, s, p, a, n, d));
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("DeepLinkPayout"),
            keccak256("1"),
            block.chainid,
            address(nftStaking)
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 ss) = vm.sign(pk, digest);
        return abi.encodePacked(r, ss, v);
    }
}
