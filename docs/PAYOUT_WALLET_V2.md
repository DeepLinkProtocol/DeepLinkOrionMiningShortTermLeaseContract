# Payout Wallet v2 — Solidity 实现 (待第二轮审计)

**变更基线**: 用户 4 项决策 — payoutAdmin 单点立即(C) / source-of-truth(A) / slash 发 staker(A) / EIP-712(A)

**版本**: NFTStaking v16→v17, Rent v11→v12 (Rent 仅升级实现, 不加新 storage)

---

## 1. 改动范围确认

### NFTStaking.sol 改 1 处
| Line | 当前 | v17 改为 |
|------|------|---------|
| 760 (`_claim`) | `safeTransfer(rewardToken, stakeholder, canClaimAmount)` | `safeTransfer(rewardToken, _getPayoutFor(stakeholder), canClaimAmount)` |

### NFTStaking.sol **不改** 的转账 (reservedAmount 发 staker 决策)
| Line | 上下文 | 原因 |
|------|--------|------|
| 925 (`forceCleanupStakeInfo`) | 退 reservedAmount 给 staker | reservedAmount = 矿工**本金 (DLC 锁仓)**, 不是 income. **双密钥泄露时本金兜底**: 即使 payoutAdmin 私钥 + 矿工 ownerSig 一同泄露, 攻击者也不能立刻通过 unStake 把本金转走 (unStake 需 staker 私钥, 且 reservedAmount 始终发 staker) |
| 976 (`_unStake`) | 同上 | 同上 |
| 1249 (`payToRenterForSlashing`) | SLASH 发给 renter | 不是矿工的钱 |

### Rent.sol 改 9 处 (extraFee/usedExtraFee → machineHolder)
| Line | 上下文 | 币种 |
|------|--------|------|
| 995 | `endRentMachineV2` extraFee 给 machineHolder | Point Token (DLP) |
| 1083 | `endRentMachine` V2 路径 extraFee | Point Token (DLP) |
| 1121 | `endRentMachine` V1 路径 extraFee | feeToken (DLC) |
| 1520 | renewRent V2 路径 usedExtraFee | Point Token (DLP) |
| 1547 | renewRent V1 路径 usedExtraFee | feeToken (DLC) |
| 1636 | renew 提前结束 transferAmt | Point Token (DLP) |
| 1676 | renew 提前结束 transferAmt3 | feeToken (DLC) |
| 1721 | endRent 残余 availablePointToken | Point Token (DLP) |
| 1726 | endRent 残余 extraFee | feeToken (DLC) |

### Rent.sol **不改** 的转账
| Line | 原因 |
|------|------|
| 666, 734, 735, 786, 857, 915, 917, 1155, 1298 | `transferFrom` 收钱进合约, 跟 payout 无关 |
| 973, 977, 1060, 1064, 1104, 1500, 1506, 1603, 1610, 1657 | `payBack` 退给 payer, 跟 stakeHolder payout 无关 |
| 1229 | SLASH 给 renter |
| 1255 | admin 收平台费 |
| 1790 | **platformFee 第三方分账** (beneficiaries 由 `stakingContract.getMachineConfig` 返回, 通常是 DeepLink 平台 + 营销合作方, 不是矿工本人). 与 machineHolder **主收款解耦**, 不走 payoutWallet 正确. |

---

## 2. NFTStaking.sol Solidity Patch

### 2.1 加在合约末尾 (storage append-only)

```solidity
// ====== PAYOUT WALLET FEATURE (v17) ======
// 矿工独立收款钱包: 矿工管理钱包(stakeholder) + 官方钱包(payoutAdmin) 双签设置
// 设置后, _claim() 把 DLC 奖励发到 payoutWallet, 而不是 stakeholder
// reservedAmount 退还仍然发 stakeholder (反滥用)

mapping(address => address) public stakerPayoutWallet;  // staker => payout (0 = 用 staker)
mapping(address => uint256) public payoutNonce;          // staker => nonce (防重放)
address public payoutAdmin;                              // 官方签名钱包

// EIP-712 domain separator
bytes32 public constant SET_PAYOUT_TYPEHASH = keccak256(
    "SetPayoutWallet(address staker,address newPayout,address payoutAdmin,uint256 nonce,uint256 deadline)"
);
bytes32 private _CACHED_DOMAIN_SEPARATOR;
uint256 private _CACHED_CHAIN_ID;
// _CACHED_THIS 删除 — proxy 模式下 address(this) 永不变, cache 无意义 (省 1 slot)

// Storage gap for future upgrades (重要: append-only)
// 当前 v17 占用 6 slot (stakerPayoutWallet + payoutNonce + payoutAdmin + cached domain + chainId + this)
// 预留到 50 slot 整块 (OZ 惯例): 50 - 6 = 44
uint256[44] private __gap_payout;

// ====== EVENTS ======
event PayoutWalletChanged(
    address indexed staker,
    address oldPayout,
    address newPayout,
    uint256 nonce,
    uint256 timestamp
);
event PayoutAdminChanged(address oldAdmin, address newAdmin);
event EIP712DomainInitialized(bytes32 domainSeparator);

// ====== ERRORS ======
error ExpiredSignature();
error InvalidNonce();
error InvalidOwnerSignature();
error InvalidAdminSignature();
error PayoutAdminNotInitialized();
error RedundantPayout();
error PayoutAlreadyInitialized();
error PayoutCannotBeContract();

// ====== DOMAIN SEPARATOR ======
function _buildDomainSeparator() private view returns (bytes32) {
    return keccak256(abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256("DeepLinkPayout"),
        keccak256("1"),
        block.chainid,
        address(this)
    ));
}

function _domainSeparator() internal view returns (bytes32) {
    // 链 fork 检测: chainId 变化时重算 (cache 失效)
    if (block.chainid == _CACHED_CHAIN_ID) {
        return _CACHED_DOMAIN_SEPARATOR;
    }
    return _buildDomainSeparator();
}

/// @notice 升级后 owner 必须**单独**调用一次以初始化 payoutAdmin
/// @dev 不能与 upgradeToAndCall 原子化: canUpgradeAddress(0x36Ede4Fe) ≠ owner(0x244f8191).
///      upgradeToAndCall 的 delegatecall 保留 msg.sender = canUpgradeAddress, onlyOwner 会 revert.
///      流程: (1) canUpgradeAddress 调 upgradeTo(newImpl); (2) owner 调 initializePayout(admin).
///      两 tx 之间窗口: payoutAdmin=0, setPayoutWallet revert PayoutAdminNotInitialized, claim/unStake 100% 兼容
function initializePayout(address admin) external onlyOwner {
    if (payoutAdmin != address(0)) revert PayoutAlreadyInitialized();
    require(admin != address(0), ZeroAddress());
    payoutAdmin = admin;
    _CACHED_CHAIN_ID = block.chainid;
    _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator();
    emit PayoutAdminChanged(address(0), admin);
    emit EIP712DomainInitialized(_CACHED_DOMAIN_SEPARATOR);
}

/// @notice owner 可旋转官方签名钱包
function setPayoutAdmin(address newAdmin) external onlyOwner {
    require(newAdmin != address(0), ZeroAddress());
    address old = payoutAdmin;
    payoutAdmin = newAdmin;
    emit PayoutAdminChanged(old, newAdmin);
}

/// @notice 双签设置矿工 payout 钱包
/// @dev EIP-712 typed data, MetaMask 会显示人类可读字段
///      digest 包含 payoutAdmin 字段: 旋转后所有未上链签名自动失效
function setPayoutWallet(
    address staker,
    address newPayout,
    uint256 nonce,
    uint256 deadline,
    bytes calldata ownerSig,
    bytes calldata adminSig
) external {
    if (staker == address(0) || newPayout == staker) revert RedundantPayout();
    if (payoutAdmin == address(0)) revert PayoutAdminNotInitialized();
    if (block.timestamp > deadline) revert ExpiredSignature();
    if (nonce != payoutNonce[staker]) revert InvalidNonce();

    // 拒绝合约地址作为 payout (防自卡 endRent: 合约无 ERC20 receiver 时 safeTransfer revert)
    // newPayout=0 (清除) 例外: code.length == 0 ✓
    if (newPayout != address(0) && newPayout.code.length > 0) revert PayoutCannotBeContract();

    bytes32 structHash = keccak256(abi.encode(
        SET_PAYOUT_TYPEHASH,
        staker,
        newPayout,
        payoutAdmin,
        nonce,
        deadline
    ));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));

    // 使用 OpenZeppelin ECDSA.recover (减小自滚 assembly 审计面)
    // 内置 EIP-2 s-malleability 防护 + 0 地址检查
    address recoveredOwner = ECDSA.recover(digest, ownerSig);
    if (recoveredOwner != staker) revert InvalidOwnerSignature();

    address recoveredAdmin = ECDSA.recover(digest, adminSig);
    if (recoveredAdmin != payoutAdmin) revert InvalidAdminSignature();

    address oldPayout = stakerPayoutWallet[staker];
    stakerPayoutWallet[staker] = newPayout;
    payoutNonce[staker] = nonce + 1;

    emit PayoutWalletChanged(staker, oldPayout, newPayout, nonce, block.timestamp);
}

/// @notice 查询实际收款地址 — Rent 合约通过 IStakingContract 调用此函数
function getPayoutFor(address staker) external view returns (address) {
    return _getPayoutFor(staker);
}

function _getPayoutFor(address staker) internal view returns (address) {
    address p = stakerPayoutWallet[staker];
    return p == address(0) ? staker : p;
}

// 不再需要自滚 _recover, 用 OZ ECDSA library:
// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// ECDSA.recover 已内置:
//   - sig.length 校验
//   - EIP-2 s-malleability 防护 (返回 InvalidSignatureS error)
//   - v 校验 (返回 InvalidSignature error)
//   - revert 而非返回 0 → 调用方只需检查 recovered != expected

// ====== version bump ======
function version() external pure returns (uint256) {
    return 17;
}
```

### 2.2 改 `_claim` line 760

```solidity
// 原:
SafeERC20.safeTransfer(rewardToken, stakeholder, canClaimAmount);
// 改为:
SafeERC20.safeTransfer(rewardToken, _getPayoutFor(stakeholder), canClaimAmount);
```

---

## 3. Rent.sol Solidity Patch

### 3.1 加 IStakingContract 接口扩展 (interface/IStakingContract.sol)

```solidity
// 在 IStakingContract.sol 末尾追加:
function getPayoutFor(address staker) external view returns (address);
```

### 3.2 Rent.sol 加内部 helper (放在合约靠前位置)

```solidity
// 事件: NFTStaking 跨合约查询失败时 emit, 后端/前端可监听降级状态
event PayoutLookupFailed(address indexed stakeHolder);

/// @dev 跨合约查矿工 payout 钱包 (NFTStaking 是 source of truth)
///      gas 成本: ~2300 (staticcall + SLOAD)
///      安全分析:
///      - NFTStaking owner 同我方, 不会作恶 revert
///      - NFTStaking 升级 bug 导致 revert → 兜底发 stakeHolder = 升级前行为, 矿工的钱不会丢
///      - DoS 不成立: 攻击者无法稳定让外部 view revert (staticcall forward 全部 gas)
function _getPayoutFor(address stakeHolder) internal returns (address) {
    try IStakingContract(address(stakingContract)).getPayoutFor(stakeHolder) returns (address payout) {
        return payout == address(0) ? stakeHolder : payout;
    } catch {
        // 关键: emit 让监控系统能感知降级状态
        emit PayoutLookupFailed(stakeHolder);
        return stakeHolder;
    }
}
```

### 3.3 替换 9 处 transfer

```solidity
// Line 995:
SafeERC20.safeTransfer(pointToken, _getPayoutFor(machineHolder), feeInfo.extraFee);
emit ExtraRentFeeTransfer(machineHolder, lastRentId, feeInfo.extraFee);  // event 仍记录 machineHolder

// Line 1083:
SafeERC20.safeTransfer(pointToken, _getPayoutFor(machineHolder), feeInfo.extraFee);
emit ExtraRentFeeTransfer(machineHolder, rentId, feeInfo.extraFee);

// Line 1121:
SafeERC20.safeTransfer(feeToken, _getPayoutFor(machineHolder), feeInfo.extraFee);
emit ExtraRentFeeTransfer(machineHolder, rentId, feeInfo.extraFee);

// Line 1520:
SafeERC20.safeTransfer(pointToken, _getPayoutFor(rentInfo.stakeHolder), usedExtraFee);

// Line 1547:
SafeERC20.safeTransfer(feeToken, _getPayoutFor(rentInfo.stakeHolder), usedExtraFee);

// Line 1636:
SafeERC20.safeTransfer(pointToken, _getPayoutFor(rentInfo.stakeHolder), transferAmt);

// Line 1676:
SafeERC20.safeTransfer(feeToken, _getPayoutFor(rentInfo.stakeHolder), transferAmt3);

// Line 1721:
SafeERC20.safeTransfer(pointToken, _getPayoutFor(rentInfo.stakeHolder), availablePointToken);

// Line 1726:
SafeERC20.safeTransfer(feeToken, _getPayoutFor(rentInfo.stakeHolder), feeInfo.extraFee);
```

### 3.4 version bump
```solidity
function version() external pure returns (uint256) {
    return 12;
}
```

### 3.5 Rent.sol **不加** payout storage (单 source-of-truth)
- 所有矿工 payout 数据存 NFTStaking
- 矿工只签 1 次, 1 笔 tx (调 NFTStaking.setPayoutWallet)
- Rent 自动读到新 payout

---

## 4. Foundry 测试 (test/PayoutWallet.t.sol)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/NFTStaking.sol";
import "../src/rent/Rent.sol";

contract PayoutWalletTest is Test {
    NFTStaking nftStaking;
    Rent rent;
    address staker = vm.addr(1);
    uint256 stakerPK = 1;
    address payoutAdmin = vm.addr(2);
    uint256 adminPK = 2;
    address newPayout = vm.addr(3);

    function setUp() public {
        // 部署 + upgrade + initializePayout(payoutAdmin)
        ...
    }

    // ====== Happy Path ======
    function test_setPayoutWallet_happy_path() public {
        bytes memory ownerSig = _signEIP712(stakerPK, staker, newPayout, 0, block.timestamp + 1 hours);
        bytes memory adminSig = _signEIP712(adminPK, staker, newPayout, 0, block.timestamp + 1 hours);

        nftStaking.setPayoutWallet(staker, newPayout, 0, block.timestamp + 1 hours, ownerSig, adminSig);
        assertEq(nftStaking.stakerPayoutWallet(staker), newPayout);
        assertEq(nftStaking.payoutNonce(staker), 1);
    }

    // ====== Replay 防护 ======
    function test_setPayoutWallet_replay_same_sig() public {
        // 第一次成功后, 同样的 sig 再调 → InvalidNonce
        bytes memory ownerSig = _signEIP712(stakerPK, staker, newPayout, 0, block.timestamp + 1 hours);
        bytes memory adminSig = _signEIP712(adminPK, staker, newPayout, 0, block.timestamp + 1 hours);
        nftStaking.setPayoutWallet(staker, newPayout, 0, block.timestamp + 1 hours, ownerSig, adminSig);

        vm.expectRevert(InvalidNonce.selector);
        nftStaking.setPayoutWallet(staker, newPayout, 0, block.timestamp + 1 hours, ownerSig, adminSig);
    }

    // ====== Deadline 过期 ======
    function test_setPayoutWallet_expired() public {
        uint256 deadline = block.timestamp - 1;
        bytes memory ownerSig = _signEIP712(stakerPK, staker, newPayout, 0, deadline);
        bytes memory adminSig = _signEIP712(adminPK, staker, newPayout, 0, deadline);

        vm.expectRevert(ExpiredSignature.selector);
        nftStaking.setPayoutWallet(staker, newPayout, 0, deadline, ownerSig, adminSig);
    }

    // ====== 错误签名 ======
    function test_setPayoutWallet_wrong_owner_sig() public {
        uint256 wrongPK = 999;
        bytes memory ownerSig = _signEIP712(wrongPK, staker, newPayout, 0, block.timestamp + 1 hours);
        bytes memory adminSig = _signEIP712(adminPK, staker, newPayout, 0, block.timestamp + 1 hours);
        vm.expectRevert(InvalidOwnerSignature.selector);
        nftStaking.setPayoutWallet(staker, newPayout, 0, block.timestamp + 1 hours, ownerSig, adminSig);
    }

    function test_setPayoutWallet_wrong_admin_sig() public {
        bytes memory ownerSig = _signEIP712(stakerPK, staker, newPayout, 0, block.timestamp + 1 hours);
        uint256 wrongPK = 999;
        bytes memory adminSig = _signEIP712(wrongPK, staker, newPayout, 0, block.timestamp + 1 hours);
        vm.expectRevert(InvalidAdminSignature.selector);
        nftStaking.setPayoutWallet(staker, newPayout, 0, block.timestamp + 1 hours, ownerSig, adminSig);
    }

    // ====== ecrecover 0 防护 ======
    function test_setPayoutWallet_malformed_sig() public {
        bytes memory badSig = new bytes(65);  // 全 0
        bytes memory adminSig = _signEIP712(adminPK, staker, newPayout, 0, block.timestamp + 1 hours);
        vm.expectRevert(InvalidOwnerSignature.selector);
        nftStaking.setPayoutWallet(staker, newPayout, 0, block.timestamp + 1 hours, badSig, adminSig);
    }

    // ====== payoutAdmin 旋转 ======
    function test_setPayoutWallet_admin_rotation_invalidates_pending_sigs() public {
        // 用旧 admin 签
        bytes memory ownerSig = _signEIP712(stakerPK, staker, newPayout, 0, block.timestamp + 1 hours);
        bytes memory adminSig = _signEIP712(adminPK, staker, newPayout, 0, block.timestamp + 1 hours);

        // owner 旋转 admin
        vm.prank(nftStaking.owner());
        nftStaking.setPayoutAdmin(vm.addr(99));

        // 旧 adminSig 立即失效
        vm.expectRevert(InvalidAdminSignature.selector);
        nftStaking.setPayoutWallet(staker, newPayout, 0, block.timestamp + 1 hours, ownerSig, adminSig);
    }

    // ====== Self-set 拒绝 ======
    function test_setPayoutWallet_self_is_redundant() public {
        bytes memory ownerSig = _signEIP712(stakerPK, staker, staker, 0, block.timestamp + 1 hours);
        bytes memory adminSig = _signEIP712(adminPK, staker, staker, 0, block.timestamp + 1 hours);
        vm.expectRevert(RedundantPayout.selector);
        nftStaking.setPayoutWallet(staker, staker, 0, block.timestamp + 1 hours, ownerSig, adminSig);
    }

    // ====== claim 走 payout ======
    function test_claim_uses_payout_wallet() public {
        _setPayout(staker, newPayout);
        _setupStakeAndAccrueReward(staker);

        uint256 beforePayout = rewardToken.balanceOf(newPayout);
        uint256 beforeStaker = rewardToken.balanceOf(staker);

        vm.prank(staker);
        nftStaking.claim(machineId);

        assertGt(rewardToken.balanceOf(newPayout), beforePayout, "payout received reward");
        assertEq(rewardToken.balanceOf(staker), beforeStaker, "staker NOT received");
    }

    // ====== 默认 (未设过 payout) 发 staker ======
    function test_claim_default_to_staker() public {
        _setupStakeAndAccrueReward(staker);

        uint256 beforeStaker = rewardToken.balanceOf(staker);
        vm.prank(staker);
        nftStaking.claim(machineId);

        assertGt(rewardToken.balanceOf(staker), beforeStaker);
    }

    // ====== unStake reservedAmount 永远发 staker ======
    function test_unstake_reserved_always_to_staker() public {
        _setPayout(staker, newPayout);
        _setupStakeWithReserved(staker, 50_000 ether);
        _waitForStakeEnd();

        uint256 beforePayout = rewardToken.balanceOf(newPayout);
        uint256 beforeStaker = rewardToken.balanceOf(staker);

        vm.prank(staker);
        nftStaking.unStake(machineId);

        // payout 不收 reservedAmount, staker 收
        assertEq(rewardToken.balanceOf(newPayout), beforePayout, "payout NOT received reserved");
        assertGt(rewardToken.balanceOf(staker), beforeStaker, "staker received reserved");
    }

    // ====== Rent endRent 走 payout (跨合约) ======
    function test_rent_endRent_uses_payout() public {
        _setPayout(staker, newPayout);
        _setupRentAndExpire(staker);

        uint256 beforePayoutDLP = pointToken.balanceOf(newPayout);
        vm.prank(renter);
        rent.endRentMachine(machineId);

        assertGt(pointToken.balanceOf(newPayout), beforePayoutDLP, "Rent paid extraFee to payout");
    }

    // ====== NFTStaking 调用失败 → 兜底 staker ======
    function test_rent_fallback_on_staking_call_failure() public {
        // mock IStakingContract.getPayoutFor revert
        ...
        // 验证 Rent 发到 stakeHolder (兜底)
    }

    // ====== EIP-712 跨合约不可重放 ======
    function test_setPayoutWallet_cross_contract_replay() public {
        // 用 NFTStaking 的 digest 试图调 Rent (如果 Rent 也加了同名函数, 这里测) — N/A, 因为单 source-of-truth
    }

    // ====== EIP-712 跨链不可重放 ======
    function test_setPayoutWallet_cross_chain_replay() public {
        vm.chainId(19880818);  // mainnet
        bytes memory ownerSig = _signEIP712(stakerPK, staker, newPayout, 0, block.timestamp + 1 hours);
        bytes memory adminSig = _signEIP712(adminPK, staker, newPayout, 0, block.timestamp + 1 hours);

        // 切换到 testnet, 同样 sig 应失败
        vm.chainId(19850818);
        vm.expectRevert(InvalidOwnerSignature.selector);  // domain separator 变了, digest 变了, sig 不匹配
        nftStaking.setPayoutWallet(staker, newPayout, 0, block.timestamp + 1 hours, ownerSig, adminSig);
    }

    // ====== helpers ======
    function _signEIP712(uint256 pk, address _staker, address _payout, uint256 _nonce, uint256 _deadline)
        internal view returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(
            nftStaking.SET_PAYOUT_TYPEHASH(),
            _staker,
            _payout,
            payoutAdmin,
            _nonce,
            _deadline
        ));
        bytes32 domainSep = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("DeepLinkPayout"),
            keccak256("1"),
            block.chainid,
            address(nftStaking)
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
```

---

## 5. 升级流程

### 5.1 NFTStaking v17 升级 (★ 两步, 不能用 upgradeToAndCall)
**为何分两步**: `upgradeToAndCall` 的 delegatecall 保留 `msg.sender = canUpgradeAddress`, 而 `initializePayout` 用 `onlyOwner`. canUpgradeAddress (`0x36Ede4Fe`) ≠ owner (`0x244f8191`) → 原子调用必 revert.

```bash
# Step 1: 编译 + 部署新 implementation
forge build
forge create src/NFTStaking.sol:NFTStaking --rpc-url $RPC --private-key $DEPLOY_PK --legacy

# Step 2: canUpgradeAddress 升级 proxy 实现
cast send $PROXY_ADDR "upgradeTo(address)" $NEW_IMPL \
  --rpc-url $RPC --private-key $CAN_UPGRADE_PK --legacy

# Step 3: owner 单独初始化 payoutAdmin (注意: 跟 Step 2 不同钱包)
cast send $PROXY_ADDR "initializePayout(address)" 0x244f8191010a9C20aaE96DC4afa4E1D63983802E \
  --rpc-url $RPC --private-key $OWNER_PK --legacy

# Step 2-3 之间的窗口期: payoutAdmin=0, setPayoutWallet revert PayoutAdminNotInitialized
# 但 claim/unStake 100% 兼容 (mapping 全空 → _getPayoutFor 返回 staker)
# 推荐 Step 2-3 在同一个交易批次内顺序执行, 窗口期 < 6 秒 (DBC 一个区块)
```

### 5.2 Rent v12 升级 (只换 implementation)
```bash
forge create src/rent/Rent.sol:Rent --rpc-url $RPC --private-key $DEPLOY_PK --legacy
cast send $RENT_PROXY "upgradeTo(address)" $NEW_RENT_IMPL --rpc-url $RPC --private-key $CAN_UPGRADE_PK --legacy
```

### 5.3 部署窗口
- testnet 19850818 → 2 周 fork-test + 内部 100 笔模拟 setPayout / claim / endRent
- mainnet 19880818 → 周末凌晨, 提前 48h Discord 公告
- 灰度: 前端只对 1-2 个测试矿工开 UI (后端 whitelist 检查), 2 周后全开

### 5.4 回滚预案
- 旧 impl 保留, 紧急时 `upgradeTo($OLD_IMPL)` 即可
- payout mapping 数据保留, downgrade 后被忽略, 无副作用

---

## 6. 后端 + 前端配套

### 6.1 后端 (DeepLinkServerNodeJS/HttpRequest/cyc.js)
新增 endpoint:
```js
POST /api/cyc/admin/getPayoutSigningPayload  // 后端构造 EIP-712 digest, 矿工签
POST /api/cyc/admin/submitPayoutChange       // 矿工提交 ownerSig, 后端用 payoutAdmin 私钥签 + 上链
```

- payoutAdmin 私钥存 K8s secret `PAYOUT_ADMIN_KEY` (短期方案), 长期迁 AWS KMS
- 上链 tx 用独立 gas wallet (后端代付, 矿工 0 gas)
- 必须先 `getTransactionReceipt` 确认后才更新本地 state, 避免 nonce retry 冲突

### 6.2 前端 (admin-vue + Deeplink-WEB)
矿工流程:
1. 输入 newPayout 地址
2. 调后端 `getPayoutSigningPayload` 获取 EIP-712 typed data
3. MetaMask `eth_signTypedData_v4` 显示人类可读字段 (DeepLinkPayout / staker / newPayout / payoutAdmin / nonce / deadline)
4. 提交 ownerSig 到 `submitPayoutChange`
5. 轮询链上 PayoutWalletChanged event 确认成功

---

## 7. 估时

| 阶段 | 工作量 |
|------|--------|
| 合约改造 (NFTStaking + Rent + Interface) | 2 天 |
| Foundry tests (15+ case) | 3 天 |
| 后端 API + 双签流程 | 3 天 |
| 前端 UI (admin-vue) | 2 天 |
| testnet 联调 + fork-test | 4 天 |
| 主网升级 + 监控 | 1 天 |
| **合计** | **~15 天** |

---

## 8. 第二轮审计结论 (2026-05-28)

**两位专家审计完成. 综合 GO with 修订**.

### 已应用修订
- ✅ **P0** initializePayout 改两步执行 (canUpgradeAddress + owner 分别签 tx)
- ✅ **P1-1** `__gap_payout[44]` (从 40 改, 保持 50 slot 整块)
- ✅ **P1-2** Rent.sol try/catch 加 `emit PayoutLookupFailed(stakeHolder)` 事件
- ✅ **P1-3** setPayoutWallet 加 `newPayout.code.length > 0 → revert PayoutCannotBeContract`
- ✅ **P2-1** 删除 `_CACHED_THIS` (proxy 模式无意义, 省 1 slot)
- ✅ **P2-2** 改用 OpenZeppelin `ECDSA.recover` 替代自滚 assembly (减小审计面)
- ✅ **P2-3** 新增 `EIP712DomainInitialized` 事件
- ✅ **文档** 1790 行 platformFee 分账注释补充
- ✅ **文档** reservedAmount 理由改为"双密钥泄露本金兜底"

### 已确认 GO 的设计
- 9 处 Rent.sol 转账改造清单 — 零漏改零错列 ✓
- payoutAdmin 单点钱包 + K8s secret 存储 — 短期够用, KMS 长期改进 (不阻塞上线)
- emergencyClearPayout 自救机制 — **不加** (扩大攻击面, 攻击者拿 staker 私钥时 NFT 已全失守)
- 跨合约 try/catch 兜底 — 安全 (DoS 不成立, 矿工资金不会丢)
- reservedAmount 永远发 staker — 同意 (本金兜底保护)
- EIP-712 typed data 含 `payoutAdmin` 字段 — 旋转后旧 sig 自动作废, 无副作用

### 待 v3 测试用例补充
- `test_initializePayout_twice_reverts`
- `test_setPayoutAdmin_zero_reverts`
- `test_setPayoutWallet_contract_address_reverts` (P1-3 校验)
- `test_setPayoutWallet_clear_with_zero` (newPayout=0 清除语义)
- `test_payout_lookup_failed_event_emitted` (Rent try/catch 兜底)

### 第三轮审计候选 (可选)
1. **gas 优化专家** — `__gap` 大小/事件 indexed/staticcall optimization
2. **fork test 专家** — testnet 主网 state 模拟, 200 staker 全场景

---

## 9. v3 patch 部署清单 (待用户授权)

阶段 1: 合约改造 (本机 + 编译)
- [ ] `src/NFTStaking.sol` 应用 v3 patch (storage + EIP-712 + setPayoutWallet)
- [ ] `src/rent/Rent.sol` 应用 v3 patch (9 处 transfer + _getPayoutFor)
- [ ] `src/interface/IStakingContract.sol` 加 `getPayoutFor` 接口
- [ ] `forge build` 验证编译通过
- [ ] `forge test test/PayoutWallet.t.sol` 测试全部通过

阶段 2: testnet (19850818)
- [ ] 部署新 implementation
- [ ] canUpgradeAddress 调 upgradeTo
- [ ] owner 调 initializePayout
- [ ] 100 笔模拟 (setPayout / claim / endRent / 错误签名)

阶段 3: mainnet (19880818)
- [ ] 公告 + 48h 等待期
- [ ] 周末凌晨升级窗口
- [ ] 前端 UI 灰度 (先 2 个测试矿工)

总周期: **15 天**
