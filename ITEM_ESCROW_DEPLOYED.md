# ItemTradeEscrow — 主网部署记录 (DBC mainnet)

**部署时间**: 2026-06-13 (boss 批准, owner 冷存确认)
**网络**: DBC 主网 (chainId 19880818, RPC rpc.dbcwallet.io)

## 地址 (★ 前后端用 PROXY)
| 角色 | 地址 |
|------|------|
| **PROXY (合约地址, ITEM_ESCROW_ADDRESS)** | `0xc7d5aa73514382Cf61e5e06e9C57D7F105a33e9b` |
| implementation | `0x96d0f076F06D468272b698Bd485B65c4eFc2ED3A` |
| owner / canUpgradeAddress | `0x244f8191010a9C20aaE96DC4afa4E1D63983802E` (冷存) |
| dlpToken (结算 DLP) | `0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6` |
| feeRecipient (2.5% 手续费) | `0xCAA5cB0983cd544283346c82f3870931a295365B` |
| arbiter (纠纷裁决) | `0xB5A5ab31E5dEd47Cd61de1bbD62b1Dd161daA6f2` |

## 部署校验 (链上自校验 8/8 ✅)
version==1 / dlpToken / feeRecipient / arbiter / owner / feeBps==250 / autoConfirmPeriod==7d / canUpgradeAddress==owner

## 部署方式
- 脚本 `scripts/deploy_item_escrow.mjs` (owner+主网地址硬断言 + DLP 探针 symbol=DLP/decimals=18 + DRY_RUN 闸; 3 轮专家审 + 30/30 forge test)
- proxy + initialize 原子一笔 (ERC1967Proxy constructor 内 initialize, 无 front-run)
- 一次性 deployer (gas-only, 部署后弃用): `0xd10e8D35Dd4CE39ECf6519189f249388D564fF8b`

## 后续
- [ ] 后端 `DeepLinkServerNodeJS` 配 `ITEM_ESCROW_ADDRESS=0xc7d5aa73514382Cf61e5e06e9C57D7F105a33e9b` + 上 testweb 联调
- [ ] arbiter 私钥迁 KMS
- [ ] 前端从 `GET /api/trade/games` 自动拿 escrow_address (后端配 env 即 ready)
