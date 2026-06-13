# NFTStaking v17 → v18 升级运维手册 (stakeAdmin 管理员代延质押)

> 本手册由第三轮升级流程专家审计产出。所有交易用 **ethers .mjs 脚本**（cast 对 DBC RPC 有 "duplicate field data" 兼容问题），全部 **type:0 legacy**。

## ★ 本次部署最终决定（2026-06-13，feng 拍板 + 独立审计 GO）

- **stakeAdmin 运维钱包 = `0x584B0E811e5597f4343Bb2A2972F9A3234B6FEF6`**（= whitelist/stakeAdmin/clawbackAdmin **同一把低权钱包**，私钥已纳管 KMS）。该角色只能延长质押 endAt、碰不到资金/不能升级。
- **范围 = 只续白名单**（`STAKE_RENEW_ALLOW_ALL=false` + 配 `STAKE_RENEW_WALLET_ALLOWLIST=<网吧钱包,...>`），**绝不用 ALLOW_ALL**（会续网吧主故意想让到期的机器，2026-06-10 또와PC방教训）。
- **私钥来源已改 KMS（无需 scp 本地文件）**：`stake_auto_renew.js` 已 KMS 适配（`import _kmsEnv.js` + `loadStakeAdminKey()` 读 `process.env.STAKE_ADMIN_KEY||WHITELIST_ADMIN_KEY||CLAWBACK_ADMIN_KEY`）。0x584B0E81 私钥在 2026-06-13 clawback 转正时**已加进 rpc3 `nodejs.env` KMS bundle**（名 `CLAWBACK_ADMIN_KEY`），stake 任务直接复用，**不再需要 `stake_admin.local.json`**。
- **deploy_v18.mjs 已就绪**：加了中央 `.env` fallback（P0 后秘钥移中央）+ `PREFLIGHT_ONLY=1` 只读模式 + `STAKE_ADMIN_ADDRESS` 默认 0x584B0E81。
- **preflight 已过（2026-06-13 只读）**：链上 `version()==17`（⚠️ 旧 CLAUDE.md 写的 16 已过时，实际 17）、owner `0x244f8191`(98 DBC)、canUpgradeAddress `0x36Ede4Fe`、payoutAdmin `0xB5099738` 已初始化。
- **独立审计 GO（0 BLOCKER/0 HIGH）**：storage forge 逐槽比对 v17 slot 0-46 全不变、stakeAdmin 干净占 slot 47；adminAddStakeHours 与 addStakeHours 逐字一致只少 holder 检查；32 测试全过。任务 KMS 适配正确 + fail-closed 默认 + 链上自检兜底。
- **gas**：stakeAdmin 钱包 0x584B0E81 现约 49 DBC，够初期；任务每跑前检查 < `STAKE_RENEW_MIN_GAS_DBC`(5) 则跳过+告警。

## 关键事实（已核对源码）

- **`_authorizeUpgrade`**：`require(msg.sender == canUpgradeAddress)` — **只有 canUpgradeAddress 能升级，owner 不能直接升**。
- **`setUpgradeAddress(address)`**：`onlyOwner`，设 `canUpgradeAddress`。（⚠️ NFTStaking 是 `setUpgradeAddress`，Rent 是 `setCanUpgradeAddress` — 名字不同）
- **`setStakeAdmin(address)`**：`onlyOwner`，且**只在 v18 存在**（v17 没有此 selector，升级前调用会 revert）。
- 构造函数仅 `_disableInitializers()`，**impl 部署无状态写入**。
- **v18 不需要 initializePayout**（payoutAdmin 已在 v17 初始化过，重复调会 revert/clobber）。`setStakeAdmin` 是 v18 的对应步骤，且可重复安全调。
- `stakeAdmin` 新 storage 在 **slot 47**（v17 的 `__gap_payout[0]`，零值）— `forge inspect storage-layout` 已确认 append-safe，slot 0-46 全不变。

## 升级前预检（只读）

**推荐用脚本的只读模式（一条命令跑完全部预检 + 打印计划）**：
```
cd DeepLinkOrionMiningShortTermLeaseContract
forge build --skip test                              # 确保 out/NFTStaking.sol 是 v18 (artifact version()==18)
PREFLIGHT_ONLY=1 node scripts/deploy_v18.mjs         # 只读: 查 version/owner/canUpgrade/payoutAdmin/balance, 不发任何交易
```
脚本会断言 `version()==17` + owner 匹配 + payoutAdmin 已初始化, 任一不符即中止。等价的手工 cast 检查：
```
cast call PROXY "version()(uint256)"                 # == 17
cast call PROXY "owner()(address)"                   # == 0x244f8191010a9C20aaE96DC4afa4E1D63983802E
cast call PROXY "canUpgradeAddress()(address)"       # == 0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8
cast call PROXY "payoutAdmin()(address)"             # != 0  (已初始化, 切勿重复 init)
```
> ⚠️ NFTStaking runtime ~42,966B 超 EIP-170 24KB 但 DBC 不强制此限（现网 v17 同量级正常运行）, 不影响部署（见文末说明）。

## 升级步骤（每步后必须验证状态）

地址：PROXY=`0x6268aba94d0d0e4fb917cc02765f631f309a7388`，OWNER=`0x244f8191010a9C20aaE96DC4afa4E1D63983802E`，UPGRADE_RESTORE=`0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8`

```
# 1. 部署新 impl (gasLimit 15-18M, legacy)
deploy src/NFTStaking.sol:NFTStaking  →  记录 NEW_IMPL
cast code NEW_IMPL    # 必须非空 (防 OOG/截断部署成 codeless 地址)

# 2. 临时把升级权交给 owner (owner 私钥, onlyOwner)
PROXY.setUpgradeAddress(OWNER)
# 验证: canUpgradeAddress() == OWNER

# 3. 升级 (此时 owner == canUpgradeAddress; 空 data; gasLimit 2.5M, legacy)
PROXY.upgradeToAndCall(NEW_IMPL, "0x")
# 验证: version() == 18
# ⚠️ 切勿调 initializePayout (v17-only, 会 revert/clobber)

# 4. 设 stakeAdmin 运维钱包 (owner 私钥, onlyOwner; gasLimit 1.5M, legacy)
PROXY.setStakeAdmin(OPS_WALLET)
# 验证: stakeAdmin() == OPS_WALLET

# 5. ★ 恢复升级权 (owner 私钥) — 切勿跳过
PROXY.setUpgradeAddress(0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8)
# 验证: canUpgradeAddress() == 0x36Ede4Fe...   ← 最终签收闸门

# 6. 升级后总检
# version()==18 / stakeAdmin()==OPS_WALLET / canUpgradeAddress()==0x36Ede4Fe
# payoutAdmin() 不变 / owner() 不变
# 冒烟: OPS_WALLET 对一台测试机调 adminAddStakeHours → AdminAddedStakeHours 事件
```

## 风险排序

1. **忘记第 5 步（恢复升级权）** → owner 同时握有升级权（安全分离被破坏，非砖；owner 可随时再调 `setUpgradeAddress` 修复）。**设为硬签收闸门。**
2. **照搬 v17 手册重跑 `initializePayout`** → revert 或 payoutAdmin 被覆盖。v18 无 init 步骤，用 `setStakeAdmin`。
3. **第 2/5 步传错地址给 `setUpgradeAddress`** → 唯一真正砖合约路径，且仅当 owner 私钥同时丢失才不可恢复。逐字核对地址字面量。
4. **cast "duplicate field" DBC bug** 致中途部分状态 → 用 ethers .mjs，每笔后验状态。
5. **impl 部署 OOG** → `cast code NEW_IMPL` 非空检查兜底（失败 fail-safe，upgradeToAndCall 对 codeless impl 会 revert）。

> ⚠️ **关于合约体积**：NFTStaking runtime ≈ **42,966 字节**，远超标准 EIP-170 的 24,576 限制。但 **DBC（DeepBrainChain，Substrate+Frontier EVM）不强制 EIP-170 24KB 限制** —— 现网 v17 就是同量级体积（~43KB）正常部署运行中。所以「<24KB」检查**不适用于 DBC**，别因 `forge build --sizes` 显示负 margin 就误判不能部署。真正的部署成功判据 = 部署后 `cast code NEW_IMPL` 非空 + `upgradeToAndCall` 不 revert。（initcode margin 仍为正，EIP-3860 49152 不触限。）

> 走通 happy path 任何错误态都可由 owner 私钥（`0x244f8191`）恢复，无不可逆砖死路径。

## 回滚（v18 发现致命 bug 时）

v17 impl 地址 = **`0xf047e9786394dF49c0a6449c3e3474c33D379913`**（CLAUDE.md 记录）。回滚步骤同升级：owner `setUpgradeAddress(owner)` → `upgradeToAndCall(0xf047e9786394dF49c0a6449c3e3474c33D379913, "0x")` → 验证 `version()==17` → `setUpgradeAddress(0x36Ede4Fe...)` 恢复。⚠️ 回滚到 v17 后 `stakeAdmin` 存储槽(slot 47)仍保留值但 v17 没有读它的函数(无害)；adminAddStakeHours 等函数消失。

## 应急 / Kill-switch（stakeAdmin 私钥泄露时）

owner 调 **`setStakeAdmin(address(0))`** 立即停用运维角色 → `adminAddStakeHours`/`Batch` 对除 owner 外所有人 revert `NotAdmin`。这是泄露后的一键封禁开关（不需升级、即时生效）。之后可换新钱包再 `setStakeAdmin(新地址)`。

## 脚本上线（合约升级后）

每日续期脚本 `DeepLinkServerNodeJS/TimeTask/stake_auto_renew.js`：
1. **私钥（已 KMS 化，无需 scp 本地文件）**：脚本已 `import _kmsEnv.js` + `loadStakeAdminKey()` 读 `process.env.STAKE_ADMIN_KEY||WHITELIST_ADMIN_KEY||CLAWBACK_ADMIN_KEY`。0x584B0E81 私钥**已在 rpc3 `nodejs.env` KMS bundle**（名 `CLAWBACK_ADMIN_KEY`，clawback 转正时加的）→ 直接复用，**不要 scp `stake_admin.local.json`**（旧路径，仅本地调试 fallback）。部署前确认 tmpfs `/dev/shm/deeplink-secrets/nodejs.env` 在场（reboot 后需先 decrypt）。
2. **充 gas**：stakeAdmin 钱包 0x584B0E81 现约 49 DBC 够初期。脚本每次跑前检查余额 < `STAKE_RENEW_MIN_GAS_DBC`(默认5) 则跳过+告警，**指定专人负责充值**。
3. **范围 fail-closed**：实跑必须显式设 `STAKE_RENEW_WALLET_ALLOWLIST=0x钱包,...`（只续指定网吧）或 `STAKE_RENEW_ALLOW_ALL=true`（全网，慎用——会续网吧主故意让到期的机器）。两者都不设 = 拒绝运行。
4. **PM2 常驻**：需 `pm2 start TimeTask/stake_auto_renew.js --name dl-task-stake-renew` + `pm2 save`（`autorestart:true`），否则 cron 不会跑。脚本内 `node-schedule` 每天 03:30 KST 触发。
5. **先 DRY_RUN 观察**：`STAKE_RENEW_DRY_RUN=true`(默认) 跑 1-2 天看 TG 告警的待续清单核对无误，再设 `false`。脚本每天会发心跳 TG（含「0 台无需续」），**静默 = 任务死了**，可据此做 dead-man 监控。
6. **环境变量**：`STAKE_RENEW_DRY_RUN` / `STAKE_RENEW_WALLET_ALLOWLIST` / `STAKE_RENEW_ALLOW_ALL` / `STAKE_RENEW_DAYS_THRESHOLD`(7) / `STAKE_RENEW_ADD_HOURS`(2160) / `STAKE_RENEW_MIN_GAS_DBC`(5) / `STAKE_RENEW_BOT_TOKEN` / `STAKE_RENEW_CHAT_ID`。
