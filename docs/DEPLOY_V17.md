# PayoutWallet v17/v12 部署 Runbook

**版本**: NFTStaking v16 → v17, Rent v11 → v12
**预计时间**: testnet 联调 1 天, mainnet 升级 1 小时窗口

## 前置 Checklist

### 钱包准备
- [ ] **canUpgradeAddress** (`0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8`): 已有, 用于 upgradeTo 操作
- [ ] **owner** (`0x244f8191010a9C20aaE96DC4afa4E1D63983802E`): 已有, 用于 initializePayout
- [ ] **deployer**: 部署新 implementation (可用 canUpgradeAddress 或独立 deploy 钱包)
- [ ] **payoutAdmin**: 服务端代矿工签 adminSig + 上链. 推荐复用 owner (`0x244f8191`) 简化运维
- [ ] **gas wallet**: 充值至少 100 DBC 用于矿工 setPayoutWallet 代付

### 基础设施
- [ ] K8s secret 注入 env `PAYOUT_ADMIN_KEY` = payoutAdmin 钱包私钥
- [ ] 监控告警配置:
  - PayoutWalletChanged event 订阅 (业务统计)
  - PayoutAdminChanged event 订阅 (P0 告警, 旋转必须有计划)
  - Rent PayoutLookupFailed event 订阅 (P0 告警, NFTStaking 升级 bug 信号)

### 代码 push
- [x] NFTStaking v17 + Rent v12: master `e7076fc`
- [x] 后端 cyc.js: main `d107f76`
- [x] 前端 admin-vue: main `b0edbaa`

---

## 第一阶段: testnet (chainId 19850818)

### Step 1: 编译 + 部署 NFTStaking v17 implementation
```bash
cd C:/project/deeplink2/DeepLinkOrionMiningShortTermLeaseContract
export TESTNET_RPC="https://rpc.dbcwallet.io"   # 或 testnet 专用 RPC
export DEPLOYER_PK="0x..."  # canUpgradeAddress testnet 私钥

forge build
forge create src/NFTStaking.sol:NFTStaking \
  --rpc-url $TESTNET_RPC \
  --private-key $DEPLOYER_PK \
  --legacy
# 记录新 implementation 地址 → $NEW_STAKING_IMPL
```

### Step 2: canUpgradeAddress 调 upgradeTo
```bash
export STAKING_PROXY="0x..."  # testnet 上 NFTStaking proxy 地址
export CAN_UPGRADE_PK="0x..."  # canUpgradeAddress testnet 私钥

cast send $STAKING_PROXY \
  "upgradeTo(address)" \
  $NEW_STAKING_IMPL \
  --rpc-url $TESTNET_RPC \
  --private-key $CAN_UPGRADE_PK \
  --legacy

# 验证: cast call $STAKING_PROXY "version()(uint256)" --rpc-url $TESTNET_RPC
# 应返回 17
```

### Step 3: owner 调 initializePayout (★ 必须分开 tx, 因为 owner ≠ canUpgradeAddress)
```bash
export OWNER_PK="0x..."  # owner testnet 私钥
export PAYOUT_ADMIN="0x244f8191010a9C20aaE96DC4afa4E1D63983802E"

cast send $STAKING_PROXY \
  "initializePayout(address)" \
  $PAYOUT_ADMIN \
  --rpc-url $TESTNET_RPC \
  --private-key $OWNER_PK \
  --legacy

# 验证:
# cast call $STAKING_PROXY "payoutAdmin()(address)" --rpc-url $TESTNET_RPC
# 应返回 $PAYOUT_ADMIN
```

### Step 4: 部署 Rent v12 implementation
```bash
forge create src/rent/Rent.sol:Rent \
  --rpc-url $TESTNET_RPC \
  --private-key $DEPLOYER_PK \
  --legacy
# 记录 → $NEW_RENT_IMPL
```

### Step 5: canUpgradeAddress 升级 Rent proxy
```bash
export RENT_PROXY="0x..."  # testnet Rent proxy

cast send $RENT_PROXY \
  "upgradeTo(address)" \
  $NEW_RENT_IMPL \
  --rpc-url $TESTNET_RPC \
  --private-key $CAN_UPGRADE_PK \
  --legacy

# 验证: cast call $RENT_PROXY "version()(uint256)" --rpc-url $TESTNET_RPC
# 应返回 12
```

### Step 6: 联调测试
1. 启动后端 (PM2 dl-api-router 或本地 node):
   ```bash
   PAYOUT_ADMIN_KEY=$PAYOUT_ADMIN_PK node HttpRequest/deeplink_evm_router.js
   ```

2. 启动前端 (本地 dev server):
   ```bash
   cd C:/project/deeplink2/DeepLinkGame/admin-vue
   npm run serve
   ```

3. 用真实矿工钱包 (testnet 上有 stake 记录) 测试:
   - 访问 `/ops/payout-mgmt`
   - 输入 staker 地址, 验证当前状态显示
   - 设新 payout, MetaMask 签名
   - 验证链上 PayoutWalletChanged event
   - 矿工 claim 验证 DLC 发到新 payout
   - 矿工租赁 + endRent 验证 DLP 发到新 payout

4. 故意失败测试:
   - 错误 nonce → revert
   - deadline 过期 → revert
   - 合约地址作 newPayout → revert PayoutCannotBeContract
   - sig 不匹配 → revert InvalidOwnerSignature

### Step 7: 监控
- 检查 testnet 上 PayoutWalletChanged event 是否正确 emit
- 检查 pending_payout_changes 集合状态机
- payoutAdmin gas 是否正常消耗

---

## 第二阶段: mainnet (chainId 19880818)

### 升级窗口
- **周末凌晨 02:00-04:00 KST** (用户量最低)
- **Discord/Telegram 48h 公告**: "PayoutWallet feature 上线, 矿工可选设独立 payout 钱包"

### 灰度策略
1. 部署后**前 2 周仅对 2 个测试矿工开放前端**
2. 后端校验 staker whitelist (硬编码 2 个测试钱包)
3. 2 周无问题后移除 whitelist, 全开

### 部署命令 (跟 testnet 一致, 改 RPC + 私钥)
```bash
export MAINNET_RPC="https://rpc.dbcwallet.io"
export CAN_UPGRADE_PK="<mainnet canUpgradeAddress 私钥>"
export OWNER_PK="<mainnet owner 私钥>"

# Step 1: 部署 NFTStaking v17 impl
forge create src/NFTStaking.sol:NFTStaking --rpc-url $MAINNET_RPC --private-key $CAN_UPGRADE_PK --legacy
NEW_STAKING_IMPL="0x..."  # 记录

# Step 2: 升级 NFTStaking proxy
cast send 0x6268aba94d0d0e4fb917cc02765f631f309a7388 \
  "upgradeTo(address)" $NEW_STAKING_IMPL \
  --rpc-url $MAINNET_RPC --private-key $CAN_UPGRADE_PK --legacy

# Step 3: owner 调 initializePayout (注意切换私钥到 OWNER_PK!)
cast send 0x6268aba94d0d0e4fb917cc02765f631f309a7388 \
  "initializePayout(address)" 0x244f8191010a9C20aaE96DC4afa4E1D63983802E \
  --rpc-url $MAINNET_RPC --private-key $OWNER_PK --legacy

# Step 4: 部署 Rent v12 impl
forge create src/rent/Rent.sol:Rent --rpc-url $MAINNET_RPC --private-key $CAN_UPGRADE_PK --legacy
NEW_RENT_IMPL="0x..."

# Step 5: 升级 Rent proxy
cast send 0xda9efdff9ca7b7065b7706406a1a79c0e483815a \
  "upgradeTo(address)" $NEW_RENT_IMPL \
  --rpc-url $MAINNET_RPC --private-key $CAN_UPGRADE_PK --legacy

# 验证
cast call 0x6268aba94d0d0e4fb917cc02765f631f309a7388 "version()(uint256)" --rpc-url $MAINNET_RPC  # = 17
cast call 0xda9efdff9ca7b7065b7706406a1a79c0e483815a "version()(uint256)" --rpc-url $MAINNET_RPC  # = 12
cast call 0x6268aba94d0d0e4fb917cc02765f631f309a7388 "payoutAdmin()(address)" --rpc-url $MAINNET_RPC  # = 0x244f8191...
```

### 反序部署后果 (★ 必须先 NFTStaking 后 Rent)
反序时 Rent v12 调 v16 NFTStaking 的 getPayoutFor (不存在) → try/catch 兜底 → emit PayoutLookupFailed → 发 stakeHolder. 安全但每笔 endRent 喷日志噪音, 监控会被刷屏.

---

## 回滚预案

### 紧急回滚 NFTStaking
```bash
# canUpgradeAddress 调 upgradeTo 旧 impl (从 commit 8b4797c 找 v16 impl 地址)
cast send 0x6268aba94d0d0e4fb917cc02765f631f309a7388 \
  "upgradeTo(address)" $OLD_STAKING_IMPL \
  --rpc-url $MAINNET_RPC --private-key $CAN_UPGRADE_PK --legacy
```
- payout mapping 数据保留, downgrade 后被忽略
- 现有矿工的 stake 不受影响
- 已设 payout 的矿工: 回到 v16 兼容路径 (发 staker), payout 失效

### 紧急回滚 Rent
- 类似 NFTStaking 回滚
- 没 storage 改动, 零副作用

---

## 监控告警 SOP

### 必装告警 (Round-6 Agent D)
1. `PayoutAdminChanged` event 任何 emit → 立即告警 owner + 冻结前端入口 (除非白名单计划内 tx hash)
2. `PayoutLookupFailed` event 任何 emit → PagerDuty (NFTStaking 升级 bug 信号)
3. `setPayoutWallet` 失败率 > 10% / 5min → 告警
4. payoutAdmin 钱包余额 < 100 DBC → 告警, < 20 DBC → 紧急

### 业务监控 (Round-4 Agent D)
- `PayoutWalletChanged` event: 记录到 DB 时间线
- 每个矿工首次设置后发 Telegram 通知 (用户教育 + 反钓鱼)

---

## 测试矿工 whitelist (灰度 2 周)

后端 cyc.js `submitPayoutChange` 加 whitelist check:
```js
const PAYOUT_WHITELIST_TESTNET = [
  '0xtestminer1...',
  '0xtestminer2...'
]
if (!PAYOUT_WHITELIST_TESTNET.includes(staker.toLowerCase())) {
  return res.json({ code: -100, msg: 'payout feature in gradual rollout' })
}
```

2 周后移除即全开.

---

## 部署完成 Sign-off

部署人:  __________
部署时间:  __________
NFTStaking new impl:  __________
Rent new impl:  __________
NFTStaking version 验证:  __________ (应 = 17)
Rent version 验证:  __________ (应 = 12)
payoutAdmin 验证:  __________ (应 = 0x244f8191...)
后端 K8s deploy:  __________
前端 admin-vue deploy:  __________
监控告警配置:  __________
