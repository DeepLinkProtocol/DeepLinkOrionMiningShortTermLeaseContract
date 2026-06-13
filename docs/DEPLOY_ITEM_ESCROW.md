# ItemTradeEscrow 部署 Runbook（道具交易链上托管合约）

> 一期 LC + 冒险岛 道具交易托管。资金（DLP）锁合约，平台不托管资金私钥。
> ⚠️ **资金合约：上主网前必须多专家审计 + boss 批准。** 本 runbook 只覆盖部署机制，不代表已获批。

## 0. 前置（必须先满足）

- [ ] 合约审计通过（已做 round-1 3 角度对抗审计，无盗款/重入/双花/费率漏洞 + 5 项加固已修；**建议上主网前再跑 round-2 验证 fix 无回归**）。
- [ ] boss 批准部署 + 确定 `ESCROW_OWNER` 地址（候选：主 owner `0x244f8191010a9C20aaE96DC4afa4E1D63983802E` 或 canUpgrade `0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8`）。
- [ ] 确定网络：主网小额真 DLP（推荐，与生产一致）vs 测试网假 ERC20。DLP/Point 仅主网（chainId 19880818），测试网需先部署测试 ERC20 并把 `DLP_TOKEN` 指过去。
- [ ] `forge build` 产出最新 `out/ItemTradeEscrow.sol/ItemTradeEscrow.json`（version()==1）。
- [ ] 部署钱包有足够 DBC gas（impl ~8M + proxy ~2M gas，建议 ≥0.5 DBC）。

## 1. 参数（合约 `initialize(dlpToken, feeRecipient, arbiter, owner)`）

| 参数 | 值 | 来源 |
|------|----|------|
| `DLP_TOKEN` | `0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6`（Point，主网） | stakeabi.js `point_token` |
| `FEE_RECIPIENT` | `0xCAA5cB0983cd544283346c82f3870931a295365B` | 中央 `item-trade-fee-wallet.md`（冷存，只收 2.5% 佣金） |
| `ARBITER` | `0xB5A5ab31E5dEd47Cd61de1bbD62b1Dd161daA6f2` | 中央 `item-trade-arbiter-wallet.md`（部署后迁 KMS） |
| `ESCROW_OWNER` | **待 boss 定** | 合约治理 + 升级权初值 |

初始化默认：`feeBps=250`(2.5%)、`autoConfirmPeriod=7d`、`canUpgradeAddress=owner`。

## 2. 部署

```bash
cd DeepLinkOrionMiningShortTermLeaseContract
forge build
# .env 设: DEPLOYER_KEY(付gas) + ESCROW_OWNER  (DLP_TOKEN/FEE_RECIPIENT/ARBITER 有默认值)
# 测试网额外: RPC_URL=<testnet rpc> CHAIN_ID=19850818 DLP_TOKEN=<测试ERC20>
node scripts/deploy_item_escrow.mjs
```

脚本：① 部署 implementation ② 部署 ERC1967Proxy（原子执行 initialize）③ 链上验证 8 项（version/dlpToken/feeRecipient/arbiter/owner/feeBps/autoConfirmPeriod/canUpgradeAddress）。输出 **PROXY 地址 = 前后端要用的合约地址**。

## 3. 部署后

- [ ] 记录 PROXY 地址 → 前端 `Deeplink-WEB` config + 后端 `DeepLinkServerNodeJS` trading 索引器 config。
- [ ] **arbiter 私钥迁 KMS**：把 `item-trade-arbiter-wallet.md` 的私钥按 P0 KMS 流程信封加密进 `secrets-vault/*.enc` + tmpfs `/dev/shm/deeplink-secrets/`，后端 dispute 流程用 `_kmsEnv` loader 读，代码零硬编码。feeRecipient 不迁（永久冷存）。
- [ ] 后端起链上 event 索引器监听合约 event（OrderCreated/Delivered/Released/Refunded/Cancelled/Disputed/DisputeResolved）回写订单状态。
- [ ] 前端钱包页显示链上 DLP（复用 useGetUserPoints）；下单 = approve(proxy, amount) + proxy.createOrder。
- [ ] 冒烟：小额真实跑通 createOrder → markDelivered → confirmReceived（放款 97.5%+2.5%）/ claimAfterTimeout / cancel / dispute→resolve 全路径。

## 4. 升级 / 应急

- **升级（UUPS）**：`canUpgradeAddress`（=owner）或 owner 兜底调 `upgradeToAndCall(newImpl, "0x")`。新 impl 走同样 `forge build` + 审计。
- **改费率/arbiter/owner**：owner 调 `setFeeBps(≤1000)` / `setArbiter` / `transferOwnership`+`acceptOwnership`(两步)。改费率只影响**新订单**（在途订单锁定下单时费率）。
- **纠纷兜底**：arbiter 私钥丢失时 owner 可直接 `resolveDispute`（防 Disputed 资金永久锁死）。
- **fresh deploy 无"回滚"**：未启用前不接前后端即可；已上线异常则 UUPS 升级修复或停用前端入口。

## 5. 关键安全不变量（部署后抽查）

- 合约 DLP 余额 == 所有活跃订单(Paid/Delivered/Disputed) amount 之和。
- 任一订单最多放出自身 amount（net+fee==amount 或全额退款），无跨单挪用。
- owner/arbiter 都无法把资金转给合约外任意地址（只能 seller/buyer/feeRecipient，费率 ≤10% 封顶）。
