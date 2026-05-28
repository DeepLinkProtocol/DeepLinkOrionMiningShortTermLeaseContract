# PayoutWallet 双签机制 + 官方签名钱包指南

> v17 NFTStaking 矿工 payout 钱包设置 — 完整签名流程参考
> 最后更新: 2026-05-28

## 1. 关键钱包

| 角色 | 地址 | 用途 | 私钥位置 |
|------|------|------|---------|
| **官方签名钱包 (payoutAdmin)** | `0xB5099738A42D985d9965f39bBF4c84ef9ADCf00e` | 官方审核通过时签 adminSig + 代付 gas | `DeepLinkServerNodeJS/payout_admin.local.json` (gitignore, 手动 scp 到 AWS rpc3) |
| 合约 owner | `0x244f8191010a9C20aaE96DC4afa4E1D63983802E` | 设 payoutAdmin (initializePayout) / 合约参数 | 用户保管 |
| canUpgradeAddress | `0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8` | 合约升级 (upgradeToAndCall) | 用户保管 |
| 矿工 (staker) | 各自 EOA | 签 ownerSig (设自己的 payout) | 矿工保管 |

**关键设计**: 官方签名钱包 `0xB509...f00e` 跟 owner **完全隔离**。即使此钱包私钥泄露，攻击者也:
- 动不了合约 owner 权限 (升级/参数)
- 改 payout 仍需矿工 ownerSig + 官方人工审核

## 2. 合约地址

| 合约 | Proxy 地址 | 版本 |
|------|-----------|------|
| NFTStaking | `0x6268aba94d0d0e4fb917cc02765f631f309a7388` | v17 |
| Rent | `0xda9efdff9ca7b7065b7706406a1a79c0e483815a` | v12 |

- **Chain ID**: 19880818 (DBC mainnet)
- **EIP-712 Domain**: `name="DeepLinkPayout"`, `version="1"`, `chainId=19880818`, `verifyingContract=0x6268aba94d0d0e4fb917cc02765f631f309a7388`

## 3. 双签机制

`setPayoutWallet(staker, newPayout, nonce, deadline, ownerSig, adminSig)` 需要**两个签名**:

```
ownerSig = 矿工 (staker) 签名 — 证明矿工本人同意设这个 payout
adminSig = 官方 (payoutAdmin 0xB509...f00e) 签名 — 官方审核通过
```

两个签名都是对**同一个 EIP-712 typed data** 签名。

### EIP-712 typed data 结构

```javascript
const domain = {
  name: 'DeepLinkPayout',
  version: '1',
  chainId: 19880818,
  verifyingContract: '0x6268aba94d0d0e4fb917cc02765f631f309a7388'
}

const types = {
  SetPayoutWallet: [
    { name: 'staker',      type: 'address' },
    { name: 'newPayout',   type: 'address' },
    { name: 'payoutAdmin', type: 'address' },   // ← 含 payoutAdmin 字段, admin 旋转后旧签名自动失效
    { name: 'nonce',       type: 'uint256' },
    { name: 'deadline',    type: 'uint256' }
  ]
}

const message = {
  staker:      '0x<矿工地址>',
  newPayout:   '0x<新收款地址>',         // 设 0x0 = 清除回到 staker
  payoutAdmin: '0xB5099738A42D985d9965f39bBF4c84ef9ADCf00e',  // 当前官方签名钱包
  nonce:       '<链上 payoutNonce(staker)>',   // 防重放
  deadline:    '<UNIX 秒, now + 48h>'          // 签名有效期
}
```

### ethers v6 签名代码

```javascript
import { ethers } from 'ethers'

// 矿工签 ownerSig (前端 MetaMask 或本地钱包)
const minerWallet = new ethers.Wallet(minerPrivateKey)
const ownerSig = await minerWallet.signTypedData(domain, types, message)

// 官方签 adminSig (后端用 payoutAdmin 私钥)
const adminWallet = new ethers.Wallet(payoutAdminPrivateKey)  // 0xB509...f00e 的私钥
const adminSig = await adminWallet.signTypedData(domain, types, message)

// 上链 (官方钱包付 gas)
const contract = new ethers.Contract(NFT_STAKING_PROXY, ABI, adminWallet.connect(provider))
const tx = await contract.setPayoutWallet(
  message.staker, message.newPayout, message.nonce, message.deadline,
  ownerSig, adminSig,
  { type: 0, gasLimit: 250000 }  // DBC 用 legacy tx (type 0)
)
```

## 4. 官方审核制流程 (2026-05-28 起)

不再后端自动签，改人工审核:

```
1. 矿工桌面客户端点"设置收款钱包" → 输入 newPayout → 签 ownerSig
   ↓
2. 后端 POST /api/cyc/submitPayoutChange
   - 验 ownerSig
   - 存 pending_payout_changes 集合, state='pending_review'
   - ⚠️ 不自动签 adminSig, 不上链
   ↓
3. 官方在管理后台 /ops/payout-mgmt 看到待审核队列
   ↓
4. 官方点"通过" → POST /api/cyc/admin/reviewPayout {action:'approve'}
   - 复查 deadline (48h 内) + nonce
   - 用 0xB509...f00e 私钥签 adminSig
   - 上链 setPayoutWallet
   - state='submitted' → 'confirmed'
   ↓
5. 矿工端显示 ✅ 官方认证 绿色徽章
```

拒绝路径: 官方点"拒绝" → state='rejected' → 矿工端显示 ❌ 审核未通过

## 5. 手动签名 + 上链 (应急, cast 命令)

如果需要绕过后端手动操作 (例如后端故障时):

```bash
RPC="https://rpc.dbcwallet.io"
STAKING="0x6268aba94d0d0e4fb917cc02765f631f309a7388"
STAKER="0x<矿工地址>"
NEW_PAYOUT="0x<新收款地址>"

# 1. 查当前 nonce
cast call $STAKING "payoutNonce(address)(uint256)" $STAKER --rpc-url $RPC

# 2. 查 payoutAdmin (应为 0xB509...f00e)
cast call $STAKING "payoutAdmin()(address)" $STAKER --rpc-url $RPC

# 3. deadline = now + 48h
DEADLINE=$(( $(date +%s) + 172800 ))

# 4. 矿工 + 官方分别签 EIP-712 (用上面 ethers 代码或 cast wallet sign-typed-data)
#    ownerSig / adminSig

# 5. 上链 (用官方钱包付 gas)
cast send $STAKING \
  "setPayoutWallet(address,address,uint256,uint256,bytes,bytes)" \
  $STAKER $NEW_PAYOUT $NONCE $DEADLINE $OWNER_SIG $ADMIN_SIG \
  --rpc-url $RPC --private-key $PAYOUT_ADMIN_KEY --legacy

# 6. 验证
cast call $STAKING "stakerPayoutWallet(address)(address)" $STAKER --rpc-url $RPC
cast call $STAKING "getPayoutFor(address)(address)" $STAKER --rpc-url $RPC
```

## 6. 部署前 checklist

- [ ] **充值 DBC gas** 到 `0xB5099738A42D985d9965f39bBF4c84ef9ADCf00e` (代矿工付 setPayoutWallet gas, 建议 ≥100 DBC)
- [ ] **scp 私钥** `payout_admin.local.json` 到 AWS rpc3 `DeepLinkServerNodeJS` 根目录
- [ ] 合约升级时 `initializePayout(0xB5099738A42D985d9965f39bBF4c84ef9ADCf00e)` (注意: owner 钱包调, 不是 canUpgradeAddress)
- [ ] 验证 `cast call $STAKING "payoutAdmin()(address)"` 返回 `0xB509...f00e`

## 7. payoutAdmin 钱包轮换 (如需更换)

⚠️ **严禁旋转回旧 admin 地址** (Round-7 审计 Low 发现: rotation-back stale-sig)

```bash
# owner 调 setPayoutAdmin 换新 admin (永远用新地址, 不复用历史)
cast send $STAKING "setPayoutAdmin(address)" $NEW_ADMIN \
  --rpc-url $RPC --private-key $OWNER_KEY --legacy
```

旋转后:
- 所有 in-flight 双签 (用旧 admin 签的) 自动失效 (typed data 含 payoutAdmin 字段)
- 后端更新 payout_admin.local.json 为新私钥
- 矿工需重新提交未完成的 payout 变更

## 8. 安全特性总结

| 防护 | 机制 |
|------|------|
| 防重放 | nonce 严格递增 (每次 setPayoutWallet 后 +1) |
| 防跨链重放 | EIP-712 domain 含 chainId |
| 防跨合约重放 | EIP-712 domain 含 verifyingContract |
| 防长期钓鱼 sig | deadline ≤ 7 天 (合约层) + 48h (后端默认) |
| 防合约钱包 | StakerMustBeEOA + PayoutCannotBeContract |
| 防 admin 单方作恶 | 双签 (必须矿工 ownerSig + 官方 adminSig) |
| 防后端被入侵自动签 | 人工审核制 (官方在后台点通过才签) |
| admin 旋转失效旧签 | typed data 含 payoutAdmin 字段 |
| 本金保护 | reservedAmount 永远发 staker, 不走 payout |

**经 10 轮 30 个专家 agent 审计, 无 Critical/High/Medium 级漏洞**。
