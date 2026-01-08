# DeepLink Orion Mining Short Term Lease Contract

## 项目概述

这是 DeepLink 项目的短期租赁合约系统，运行在 DeepBrainChain (DBC) 链上。系统允许用户租用 GPU 算力机器，支持 DLC 代币和积分两种支付方式。

---

## 核心合约

| 合约 | 代理地址 | 文档 |
|-----|---------|------|
| NFTStaking (质押) | `0x6268aba94d0d0e4fb917cc02765f631f309a7388` | `docs/dev_staking_contract_zh.md` |
| Rent (租赁) | `0xda9efdff9ca7b7065b7706406a1a79c0e483815a` | `docs/dev_rent_contract_zh.md` |

**注意**: 以上是代理合约地址，实现合约会随升级变化。查询当前实现地址：
```powershell
cast call 代理地址 "getImplementation()(address)" --rpc-url https://rpc2.dbcwallet.io
```

---

## 代币地址

| 代币 | 地址 | 用途 |
|-----|------|------|
| DLC Token | `0x6f8F70C74FE7d7a61C8EAC0f35A4Ba39a51E1BEe` | 主要支付代币，租金基础费用 |
| Point Token | `0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6` | 积分代币，用于支付额外租金 (extraFee) |
| NFT | `0xFDB11c63b82828774D6A9E893f85D1998E6B36BF` | 机器 NFT |
| DBCAI | `0xa7B9f404653841227AF204a561455113F36d8EC8` | DBC AI 合约 |

---

## 业务流程

### 1. 机器质押流程 (NFTStaking)

```
机器持有者
    │
    ├─> stake() 质押机器 + NFT + 押金(DLC)
    │     ├─> 机器开始获得 DLC 奖励
    │     └─> 机器可被租用
    │
    ├─> addStakeHours() 延长质押时长
    │
    ├─> reserveDLC() 补充押金
    │
    ├─> claim() 领取奖励
    │     ├─> 10% 立即释放
    │     └─> 90% 线性释放 (180天)
    │
    └─> unStake() 解除质押
          └─> 必须无租赁、质押期满
```

### 2. 机器租赁流程 (Rent)

```
租户
    │
    ├─> rentMachineV2() 租用机器
    │     ├─> 支付 baseFee (DLC) → 销毁
    │     ├─> 支付 extraFee (Point Token) → 机器持有者
    │     └─> 支付 platformFee (DLC) → 平台管理员
    │
    ├─> renewRentV2() 续租
    │
    └─> endRentMachine() 退租
          ├─> 提前退租: 按比例退费
          └─> 到期退租: 不退费
```

### 3. 机器离线处理流程 (Slash)

```
机器离线 (DBC 链检测)
    │
    └─> notify(MachineOffline)
          │
          ├─ 情况1: 租赁进行中
          │   ├─> 惩罚: 1000 DLC → 租户
          │   ├─> 按比例退费给租户
          │   ├─> 已用费用正常分配
          │   ├─> 清理租赁状态
          │   └─> 强制解除质押
          │
          ├─ 情况2: 租赁已过期未清理
          │   ├─> 费用全部分配（无惩罚）
          │   └─> 清理租赁状态
          │
          └─ 情况3: 无租赁
              └─> stopRewarding() 停止奖励
```

---

## 租赁费用结构

| 费用类型 | 说明 | 支付代币 | 去向 |
|---------|------|---------|------|
| baseFee | 基础租金 | DLC | 销毁 (burn) |
| extraFee | 额外租金 | Point Token (V2) / DLC (V1) | 机器持有者 |
| platformFee | 平台费 | DLC | 平台管理员 |

### 租赁函数版本

| 函数 | 支付方式 |
|-----|---------|
| `rentMachine` / `_rentMachine` | 全部用 DLC 支付 |
| `rentMachineV2` / `_rentMachineV2` | baseFee+platformFee 用 DLC，extraFee 用 Point Token |
| `endRentMachine` / `endRentMachineV2` | 退租，提前退租按比例退费 |

---

## 奖励机制

### Phase 系统

| phase | 奖励时长 | initRewardAmount |
|-------|---------|------------------|
| 1 | 60 天 | 180,000,000 DLC |
| 2 | 120 天 | 240,000,000 DLC |
| 3 | 180 天 | 580,000,000 DLC |
| 4 | 240 天 | 580,000,000 DLC |
| 5 | 300 天 | 580,000,000 DLC |
| 6 | 420 天 | 580,000,000 DLC |

### 查询奖励状态

```powershell
# 奖励开始时间
curl -s -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x6268aba94d0d0e4fb917cc02765f631f309a7388","data":"0x301a6373"},"latest"],"id":1}'

# 奖励持续时间
curl -s -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x6268aba94d0d0e4fb917cc02765f631f309a7388","data":"0x91505a12"},"latest"],"id":1}'
```

### 延长奖励期

```powershell
# 设置 phase (需要先升级合约支持对应 phase)
cast send 0x6268aba94d0d0e4fb917cc02765f631f309a7388 "setPhase(uint8)" 6 --rpc-url https://rpc2.dbcwallet.io --private-key $KEY --legacy
```

---

## 关键状态变量

### NFTStaking 合约

| 变量 | 类型 | 说明 |
|-----|------|------|
| `machineId2StakeInfos[machineId]` | StakeInfo | 质押信息 |
| `machineId2Rented[machineId]` | bool | 全局租赁标记 |
| `stakeInfo.isRentedByUser` | bool | 用户租赁标记 (30% calcPoint 加成) |
| `stakeInfo.reservedAmount` | uint256 | 押金余额 (用于 Slash) |
| `stakeInfo.endAtTimestamp` | uint256 | 质押结束时间 |
| `phase` | uint8 | 当前奖励阶段 (1-6) |

### Rent 合约

| 变量 | 类型 | 说明 |
|-----|------|------|
| `rentId2RentInfo[rentId]` | RentInfo | 租赁信息 |
| `machineId2RentId[machineId]` | uint256 | 机器当前租赁ID |
| `rentId2FeeInfoInDLC[rentId]` | FeeInfo | 费用信息 |
| `machine2ProxyRented[machineId]` | bool | 代理租用标记 |
| `totalBurnedAmount` | uint256 | 累计销毁 DLC |

### 状态一致性要求

Rent 和 Staking 合约的租赁状态必须同步：
- 租赁时: Rent 创建记录，Staking 设置 `isRentedByUser = true`
- 退租时: 两边同时清理
- 离线时: 两边同时清理（已修复）

---

## DBC 链特殊要求

| 项目 | 说明 |
|-----|------|
| `--legacy` | **必须添加**，DBC 不支持 EIP-1559 |
| `evm_version` | 使用 `london`，不支持 `paris` 及以上 |
| Chain ID | mainnet: `19880818`, testnet: `19850818` |
| RPC | mainnet: `https://rpc2.dbcwallet.io` |
| Explorer | `https://dbcscan.io` |
| Gas Limit | 升级操作建议 `1,200,000` |

---

## 构建和部署命令

### 构建
```powershell
forge build
```

### 部署新实现合约
```powershell
# NFTStaking
forge create src/NFTStaking.sol:NFTStaking --rpc-url https://rpc2.dbcwallet.io --private-key $KEY --legacy --broadcast

# Rent
forge create src/rent/Rent.sol:Rent --rpc-url https://rpc2.dbcwallet.io --private-key $KEY --legacy --broadcast
```

### 升级代理合约
```powershell
# NFTStaking (必须先升级，因为 Rent 依赖新接口)
cast send 0x6268aba94d0d0e4fb917cc02765f631f309a7388 "upgradeToAndCall(address,bytes)" 新实现地址 0x --rpc-url https://rpc2.dbcwallet.io --private-key $KEY --legacy --gas-limit 1200000

# Rent
cast send 0xda9efdff9ca7b7065b7706406a1a79c0e483815a "upgradeToAndCall(address,bytes)" 新实现地址 0x --rpc-url https://rpc2.dbcwallet.io --private-key $KEY --legacy --gas-limit 1200000
```

### 验证合约
```powershell
forge verify-contract 地址 src/rent/Rent.sol:Rent --verifier blockscout --verifier-url https://dbcscan.io/api --chain 19880818
```

---

## 权限体系

| 角色 | 说明 |
|-----|------|
| `owner` | 合约所有者，可调用 onlyOwner 函数，可升级合约 |
| `adminsToSetRentWhiteList` | 管理员，可设置租赁白名单 |
| `adminsToApprove` | 管理员，可审批故障报告，接收平台费 |
| `dlcClientWalletAddress` | DLC 客户端钱包，可调用代理租用函数 |

**重要**: `_authorizeUpgrade` 检查的是 `msg.sender == owner()`，升级必须使用 owner 地址。

---

## 常用查询命令

### 查询销毁代币总量
```powershell
cast call 0xda9efdff9ca7b7065b7706406a1a79c0e483815a "getTotalBurnedRentFee()(uint256)" --rpc-url https://rpc2.dbcwallet.io
```

### 查询当前实现合约
```powershell
cast call 0xda9efdff9ca7b7065b7706406a1a79c0e483815a "getImplementation()(address)" --rpc-url https://rpc2.dbcwallet.io
```

### 查询机器信息
```powershell
# 通过 curl (避免 cast 的 RPC 兼容问题)
curl -s -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x6268aba94d0d0e4fb917cc02765f631f309a7388","data":"0x..."},"latest"],"id":1}'
```

### 查询机器是否被租用
```solidity
// Rent 合约
isRented(machineId) // rentInfo.renter != address(0)

// Staking 合约
stakeInfo.isRentedByUser // 用户直接租用标记
machineId2Rented[machineId] // 全局租赁标记
```

---

## 已知问题及修复历史

### 2026-01 修复

| 问题 | 原因 | 修复 |
|-----|------|------|
| renewRent OVERFLOW(17) | `endAtTimestamp - block.timestamp` 下溢 | 添加 `require(minEndTime > block.timestamp)` |
| endRentMachine MachineNotRented | Rent/Staking 状态不一致 | 添加 `_cleanupExpiredRentOnOffline()` |
| 租赁中离线不退费 | Slash 只惩罚不清算 | 添加 `_terminateRentOnSlash()` |
| Slash 后状态不一致 | `_unStake()` 不清理租赁状态 | 在 `reportMachineFault()` 中清理 |
| V1 租用退租时错误转 DLP | `endRentMachine` 把 V1 的 DLC extraFee 当成 Point Token 处理 | 在 `FeeInfo` 添加 `isV1` 字段区分租用类型，默认 false 兼容旧 V2 数据 |

### 管理员修复函数

```powershell
# 强制清理不一致的租赁状态
cast send 0xda9efdff9ca7b7065b7706406a1a79c0e483815a "forceCleanupRentInfo(string)" "机器ID" --rpc-url https://rpc2.dbcwallet.io --private-key $KEY --legacy --gas-limit 500000
```

---

## 文件结构

```
src/
├── rent/
│   ├── Rent.sol          # 当前租赁合约
│   └── OldRent.sol       # 旧版本参考
├── NFTStaking.sol        # 质押合约
├── NFTStakingState.sol   # 质押状态查询
├── interface/            # 接口定义
└── library/              # 工具库

script/
└── rent/
    ├── Deploy.s.sol      # 部署脚本
    └── UpgradeManual.s.sol # 手动升级脚本

docs/                     # 文档目录
short-staking-state/      # The Graph 子图
```

---

## 开发注意事项

1. **私钥安全**: 绝不在代码或文档中记录私钥
2. **升级顺序**: NFTStaking 必须先于 Rent 升级（如果 Rent 依赖新接口）
3. **升级前测试**: 升级前在本地或测试网验证
4. **Gas 估算**: DBC 链 gas 估算可能不准，建议手动设置较高的 gas-limit
5. **reinitialize**: 只在添加新的初始化逻辑时需要调用，普通升级不需要
6. **所有 forge/cast 命令必须加 `--legacy` 参数**
7. **Storage 布局**: 升级时不能删除/修改/重排现有状态变量，只能在末尾添加新变量
8. **RPC 兼容性**: cast 命令可能报错，可改用 curl 直接调用 RPC

---

## 调试技巧

### 查询机器状态
```python
# Python 脚本示例
import requests

def query_machine(machine_id):
    # 计算 function selector 和参数
    # getMachineInfo(string) = 0x...
    pass
```

### 常见错误

| 错误 | 原因 | 解决 |
|-----|------|------|
| `MachineNotRented` | Staking 的 isRentedByUser 为 false | 检查状态一致性，必要时用 forceCleanupRentInfo |
| `OVERFLOW(17)` | 时间戳计算下溢 | 检查机器质押是否过期 |
| `RentNotEnd` | 租赁未到期 | 只有租户本人可提前退租 |
| `execution reverted` | 多种可能 | 检查权限、余额、状态 |
