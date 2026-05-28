# Payout Wallet Feature — 矿工收款钱包分离设计 (NFTStaking v17 / Rent v12)

**状态**: 设计草案, 待多专家审计
**作者**: 2026-05-28
**目标**: 矿工 DLC/DLP 收益允许独立 payout 钱包, 当前钱包仅作管理签名, 资金安全提升

## 1. 设计目标

- 矿工 (stakeholder) 可设置独立的 **收款钱包** (payoutWallet)
- 修改 payoutWallet 需 **管理钱包 (stakeholder) + 官方钱包 (payoutAdmin)** 双签
- 设置后, 所有 DLC 挖矿奖励 + DLP 租金自动发到 payoutWallet
- 没设过的矿工: 默认发到 stakeholder 本身 (向后兼容)
- 立即生效, 无 timelock
- 历史奖励全部发新 payoutWallet

## 2. 信任模型

| 实体 | 权力 | 风险 |
|------|------|------|
| 矿工 (stakeholder) | 提议 payoutWallet, 签名 1 | 单独无法改, 还需官方签 |
| 官方 (payoutAdmin) | 批准 payoutWallet, 签名 2 | 单独无法改, 还需矿工签 |
| 合约 owner | 升级合约, 设 payoutAdmin | 中心化风险 (跟 v16 一致) |

**核心保证**: 即使矿工管理钱包**完全泄露**, 攻击者也无法把奖励转走 — 必须同时拿到官方签名.

## 3. 关键问题决策 (已敲定)

| 问题 | 决策 |
|------|------|
| 官方钱包 | 复用 contract owner `0x244f8191010a9C20aaE96DC4afa4E1D63983802E` (单点 OK, 双签机制保证) |
| Timelock | 无, 立即生效 |
| 历史奖励 | 不区分, 设置后**全部**发新 payoutWallet |
| 客户端兼容 | 默认 payoutWallet=0 表示发 stakeholder, 老客户端 0 影响 |

## 4. NFTStaking v17 改动

### 4.1 新增 Storage (注意 UUPS 顺序 — append only)
```solidity
// 添加到现有 storage 末尾
mapping(address => address) public stakerPayoutWallet;  // staker => payout (0 = use staker)
mapping(address => uint256) public payoutNonce;          // staker => nonce (replay防护)
address public payoutAdmin;                              // 官方签名钱包 (默认 = owner)
```

### 4.2 新增函数 — setPayoutWallet
```solidity
event PayoutWalletChanged(address indexed staker, address oldPayout, address newPayout);
event PayoutAdminChanged(address oldAdmin, address newAdmin);

/// @notice 设置/更新矿工 payout 钱包 (双签验证)
/// @param staker 矿工地址 (stakeholder, 通常等于 ownerSig 的签名者)
/// @param newPayout 新收款钱包 (设 0 = 清除, 回退到 staker 本身)
/// @param nonce 当前 nonce (== payoutNonce[staker])
/// @param deadline UNIX 时间戳, 过期后签名失效
/// @param ownerSig staker 的 EIP-191 签名
/// @param adminSig payoutAdmin 的 EIP-191 签名
function setPayoutWallet(
    address staker,
    address newPayout,
    uint256 nonce,
    uint256 deadline,
    bytes calldata ownerSig,
    bytes calldata adminSig
) external {
    require(staker != address(0), ZeroAddress());
    require(block.timestamp <= deadline, ExpiredSignature());
    require(nonce == payoutNonce[staker], InvalidNonce());

    // EIP-191 消息: "DEEPLINK_PAYOUT_v1" | chainId | thisContract | staker | newPayout | nonce | deadline
    bytes32 digest = keccak256(abi.encodePacked(
        "DEEPLINK_PAYOUT_v1",
        block.chainid,
        address(this),
        staker,
        newPayout,
        nonce,
        deadline
    ));
    bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));

    address recoveredOwner = ECDSA.recover(ethSignedHash, ownerSig);
    require(recoveredOwner == staker, InvalidOwnerSignature());

    address recoveredAdmin = ECDSA.recover(ethSignedHash, adminSig);
    require(recoveredAdmin == payoutAdmin, InvalidAdminSignature());

    address oldPayout = stakerPayoutWallet[staker];
    stakerPayoutWallet[staker] = newPayout;
    payoutNonce[staker]++;  // 一次性, 防重放

    emit PayoutWalletChanged(staker, oldPayout, newPayout);
}

/// @notice 仅 owner 可改官方签名钱包
function setPayoutAdmin(address newAdmin) external onlyOwner {
    require(newAdmin != address(0), ZeroAddress());
    address old = payoutAdmin;
    payoutAdmin = newAdmin;
    emit PayoutAdminChanged(old, newAdmin);
}

/// @notice 初始化 payoutAdmin (仅升级后调一次)
function initializePayoutAdmin(address admin) external onlyOwner {
    require(payoutAdmin == address(0), AlreadyInitialized());
    payoutAdmin = admin;
}
```

### 4.3 修改: 内部转账目标
```solidity
/// @notice 获取实际收款地址 (没设过则用 staker)
function _getPayoutFor(address staker) internal view returns (address) {
    address p = stakerPayoutWallet[staker];
    return p == address(0) ? staker : p;
}

// _claim() line 760 修改:
// 原: SafeERC20.safeTransfer(rewardToken, stakeholder, canClaimAmount);
// 改: SafeERC20.safeTransfer(rewardToken, _getPayoutFor(stakeholder), canClaimAmount);

// _unStake() line 925 修改:
// 原: try rewardToken.transfer(stakeholder, reservedAmount) {} catch {}
// 改: try rewardToken.transfer(_getPayoutFor(stakeholder), reservedAmount) {} catch {}

// unStakeByHolder() line 976 修改:
// 原: SafeERC20.safeTransfer(rewardToken, stakeholder, reservedAmount);
// 改: SafeERC20.safeTransfer(rewardToken, _getPayoutFor(stakeholder), reservedAmount);

// payToRenterForSlashing — slash 仍发原 renter (不改)
// claimDLC owner 提现 — 不改
```

### 4.4 version 更新
```solidity
function version() external pure returns (uint256) {
    return 17;  // v16 → v17, 加 payoutWallet feature
}
```

### 4.5 新增 error
```solidity
error ZeroAddress();              // 已有
error ExpiredSignature();
error InvalidNonce();
error InvalidOwnerSignature();
error InvalidAdminSignature();
error AlreadyInitialized();
```

## 5. Rent v12 改动 (同样模式)

### 5.1 新增 Storage
```solidity
mapping(address => address) public stakerPayoutWallet;
mapping(address => uint256) public payoutNonce;
address public payoutAdmin;
```

### 5.2 新增 setPayoutWallet (跟 NFTStaking 镜像)
**注意**: NFTStaking 和 Rent 各自独立 mapping. 矿工需要**两个合约都设置一次** payoutWallet (或同一笔 tx 调两次). 这是简化设计, 避免合约间耦合.

**替代设计 (复杂)**: Rent 合约调 `NFTStaking.getPayoutFor(staker)` 读 NFTStaking 的 mapping. 但跨合约读 storage 浪费 gas + NFTStaking 升级影响 Rent.

**推荐**: 各自独立 mapping, **矿工设置时调用 2 个合约的 setPayoutWallet**. 也可以前端封装成 1 个 UX action.

### 5.3 修改: miner_income 转账
```solidity
// Rent.sol 内部所有 feeToken.transfer(machineHolder, ...) 改为:
//   feeToken.transfer(_getPayoutFor(machineHolder), ...)
// 同样 pointToken (DLP) 转账也改

// 受影响 function (待逐个 review):
// - rentMachineV2
// - proxyRentMachineV2
// - endRentMachineV2
// - endRentMachine
// - _renewRent
// 等等
```

### 5.4 version 11 → 12

## 6. 客户端流程 (UX)

### 6.1 矿工设置 payoutWallet
```
1. admin-vue / Deeplink-WEB:
   矿工选机器 → 点 "设置收款钱包" → 输入新 payout 地址

2. 后端 (DeepLinkServerNodeJS/cyc.js POST /setMinerPayoutWallet):
   - 验证 staker 是机器主人 (查 rent_mac_info.wallet)
   - 拿 staker 当前 nonce: 调链上 NFTStaking.payoutNonce(staker)
   - 生成 deadline = now + 1 hour
   - 返回 message hash 给前端

3. 前端 (MetaMask):
   - eth_sign 或 personal_sign 用 staker 钱包签 message
   - 提交 ownerSig 到后端

4. 后端验证 ownerSig + 用 payoutAdmin 私钥再签:
   - 服务端 ethers.signMessage(messageHash, payoutAdminKey)
   - 拿到 adminSig

5. 后端调链上:
   - NFTStaking.setPayoutWallet(staker, newPayout, nonce, deadline, ownerSig, adminSig)
   - Rent.setPayoutWallet(staker, newPayout, nonce, deadline, ownerSig, adminSig)
   (注意: NFTStaking 和 Rent 的 nonce 独立, 实际需要 2 签 2 调用)

6. 链上成功 → emit PayoutWalletChanged → 前端轮询确认
```

### 6.2 矿工查看当前 payout
- 调 `NFTStaking.stakerPayoutWallet(staker)` view
- 返回 0 = 未设置 / 用 staker 自己
- 返回非零 = 当前 payout

## 7. 安全考量

### 7.1 防重放
- 每次 setPayoutWallet 后 `payoutNonce[staker]++`
- 同一签名只能用一次
- 签名含 `chainid` 防跨链重放
- 签名含 `address(this)` 防跨合约重放

### 7.2 防过期
- `deadline` 限制有效期 (推荐 1 hour)
- 过期签名 revert

### 7.3 EIP-191 而非 EIP-712
- 选择 EIP-191 (personal_sign) 因为 MetaMask UI 显示**人类可读**字符串
- 用户能看到 "DEEPLINK_PAYOUT_v1" + 关键字段
- EIP-712 typed data 也行, 但需要前端 wallet 兼容性更好的库

### 7.4 payoutAdmin 单点风险
- 单点泄露 = 攻击者拿矿工自己签的 ownerSig 之后能改任意矿工 payout
- **但是攻击者还需要矿工 ownerSig** — 实际不能凭空生成
- 矿工签名前会看到目标 payout 地址, 不会签自己不知道的地址
- 风险: 攻击者**社工矿工签自己想要的 payout 地址**
- 缓解: 前端 UI 大字提示 + 二次确认

### 7.5 链上事件
- `emit PayoutWalletChanged(staker, oldPayout, newPayout)` 让所有变更可审计
- 矿工应监控自己钱包是否被未授权改 payout

## 8. 部署 / 升级流程

### 8.1 testnet (DBC testnet 19850818)
- Foundry script 部署新 implementation
- UUPS upgrade 调用 canUpgradeAddress 钱包的 `upgradeAndCall`
- 升级后调 `initializePayoutAdmin(0x244f8191...)` 设置官方钱包

### 8.2 mainnet (DBC mainnet 19880818)
- 必须先 testnet 验证 1-2 周
- 主网升级窗口 (低活跃时段)
- canUpgradeAddress (`0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8`) 签升级 tx

### 8.3 回滚预案
- 旧 implementation 保留, 紧急情况 owner 可 downgrade
- payout mapping 数据保留 (storage 不动)

## 9. 测试矩阵 (Foundry)

### 9.1 单元测试
- `test_setPayoutWallet_happy_path`: 正常双签 + 改 payout ✓
- `test_setPayoutWallet_bad_owner_sig`: 错误 ownerSig → revert
- `test_setPayoutWallet_bad_admin_sig`: 错误 adminSig → revert
- `test_setPayoutWallet_replay`: 重放同一签名 → revert (nonce 已增)
- `test_setPayoutWallet_expired`: deadline 过 → revert
- `test_setPayoutWallet_zero_address`: newPayout=0 → 清除 → claim 回 staker ✓
- `test_claim_with_payout`: 设置后 claim → DLC 发到 payoutWallet ✓
- `test_claim_without_payout`: 没设过 claim → DLC 发到 staker ✓ (向后兼容)
- `test_unstake_with_payout`: 退质押 → reservedAmount 发到 payoutWallet ✓

### 9.2 跨场景测试
- `test_payout_change_during_active_stake`: staking 中改 payout, 后续 claim 用新 payout
- `test_payout_change_during_slash`: slash 中改 payout, 不影响已锁定 reserved
- `test_payout_admin_rotation`: owner 改 payoutAdmin → 旧 admin 签名失效

### 9.3 集成测试 (NFTStaking + Rent 配合)
- 矿工设 NFTStaking payout 后, 还需设 Rent payout (分别测试)
- 设置 Rent payout 不影响 NFTStaking 数据 (mapping 独立)

## 10. 工作量估算
- 合约 coding (2 个合约): 3 天
- Foundry 测试 (~30 个 case): 3 天
- testnet 部署 + 联调: 2 天
- 后端 setMinerPayoutWallet API + 双签流程: 2 天
- admin-vue UI: 2 天
- 主网升级 + 监控: 1 天
- **总计**: ~13 天 (2-3 周, 含审计 buffer)

## 11. 多专家审计路径

待此设计 review 通过, 邀请:
1. **Solidity 安全审计** (re-entrancy / signature replay / storage layout)
2. **UUPS upgrade 专家** (storage 兼容性 / canUpgradeAddress 流程)
3. **业务流程 review** (UX / 矿工教育 / 误操作风险)
4. **跨合约一致性** (NFTStaking ↔ Rent payout 一致性)
5. **gas / DoS 评估** (大量 setPayoutWallet 调用 / batch 攻击)
