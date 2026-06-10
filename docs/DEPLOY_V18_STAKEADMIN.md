# NFTStaking v17 → v18 升级运维手册 (stakeAdmin 管理员代延质押)

> 本手册由第三轮升级流程专家审计产出。所有交易用 **ethers .mjs 脚本**（cast 对 DBC RPC 有 "duplicate field data" 兼容问题），全部 **type:0 legacy**。

## 关键事实（已核对源码）

- **`_authorizeUpgrade`**：`require(msg.sender == canUpgradeAddress)` — **只有 canUpgradeAddress 能升级，owner 不能直接升**。
- **`setUpgradeAddress(address)`**：`onlyOwner`，设 `canUpgradeAddress`。（⚠️ NFTStaking 是 `setUpgradeAddress`，Rent 是 `setCanUpgradeAddress` — 名字不同）
- **`setStakeAdmin(address)`**：`onlyOwner`，且**只在 v18 存在**（v17 没有此 selector，升级前调用会 revert）。
- 构造函数仅 `_disableInitializers()`，**impl 部署无状态写入**。
- **v18 不需要 initializePayout**（payoutAdmin 已在 v17 初始化过，重复调会 revert/clobber）。`setStakeAdmin` 是 v18 的对应步骤，且可重复安全调。
- `stakeAdmin` 新 storage 在 **slot 47**（v17 的 `__gap_payout[0]`，零值）— `forge inspect storage-layout` 已确认 append-safe，slot 0-46 全不变。

## 升级前预检（只读）

```
forge build --sizes                                  # NFTStaking runtime ~42,966B (见下注)
cast call PROXY "version()(uint256)"                 # == 17
cast call PROXY "owner()(address)"                   # == 0x244f8191010a9C20aaE96DC4afa4E1D63983802E
cast call PROXY "canUpgradeAddress()(address)"       # == 0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8
cast call PROXY "payoutAdmin()(address)"             # != 0  (已初始化, 切勿重复 init)
```

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
