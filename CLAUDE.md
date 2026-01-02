# DeepLink Orion Mining Short Term Lease Contract

## 项目概述

这是 DeepLink 项目的短期租赁合约系统，运行在 DeepBrainChain (DBC) 链上。系统允许用户租用 GPU 算力机器，支持 DLC 代币和积分两种支付方式。

---

## 核心合约

| 合约 | 代理地址 | 文档 |
|-----|---------|------|
| NFTStaking (质押) | `0x6268aba94d0d0e4fb917cc02765f631f309a7388` | `docs/dev_staking_contract_zh.md` |
| Rent (租赁) | `0xda9efdff9ca7b7065b7706406a1a79c0e483815a` | `docs/dev_rent_contract_zh.md` |

当前 Rent 实现合约: `0x296bbcc906E3BA78DC2BA8C5631D3848d5faD825`

---

## 代币地址

| 代币 | 地址 | 用途 |
|-----|------|------|
| DLC Token | `0x6f8F70C74FE7d7a61C8EAC0f35A4Ba39a51E1BEe` | 主要支付代币，租金基础费用 |
| Point Token | `0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6` | 积分代币，用于支付额外租金 (extraFee) |
| NFT | `0xFDB11c63b82828774D6A9E893f85D1998E6B36BF` | 机器 NFT |
| DBCAI | `0xa7B9f404653841227AF204a561455113F36d8EC8` | DBC AI 合约 |

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
| `endRentMachine` | 退租时退还 Point Token (已修复) |
| `endRentMachineV2` | 退租时退还 Point Token |

---

## DBC 链特殊要求

| 项目 | 说明 |
|-----|------|
| `--legacy` | **必须添加**，DBC 不支持 EIP-1559 |
| `evm_version` | 使用 `london`，不支持 `paris` 及以上 |
| Chain ID | mainnet: `19880818`, testnet: `19850818` |
| RPC | mainnet: `https://rpc2.dbcwallet.io` |
| Explorer | `https://dbcscan.io` |

---

## 构建和部署命令

### 构建
```powershell
forge build
```

### 部署新实现合约
```powershell
forge create src/rent/Rent.sol:Rent --rpc-url https://rpc2.dbcwallet.io --private-key $KEY --legacy --broadcast
```

### 升级代理合约
```powershell
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
| `owner` | 合约所有者，可调用 onlyOwner 函数 |
| `canUpgradeAddress` | 可执行升级的地址 (注意：实际检查的是 owner) |
| `adminsToSetRentWhiteList` | 管理员，可设置租赁白名单 |
| `adminsToApprove` | 管理员，可审批故障报告，接收平台费 |

**重要**: `_authorizeUpgrade` 检查的是 `msg.sender == owner()`，升级必须使用 owner 地址。

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

## 常用查询命令

### 查询销毁代币总量
```powershell
cast call 0xda9efdff9ca7b7065b7706406a1a79c0e483815a "getTotalBurnedRentFee()(uint256)" --rpc-url https://rpc2.dbcwallet.io
```

### 查询当前实现合约
```powershell
cast call 0xda9efdff9ca7b7065b7706406a1a79c0e483815a "getImplementation()(address)" --rpc-url https://rpc2.dbcwallet.io
```

---

## 开发注意事项

1. **私钥安全**: 绝不在代码或文档中记录私钥
2. **升级前测试**: 升级前在本地或测试网验证
3. **Gas 估算**: DBC 链 gas 估算可能不准，建议手动设置较高的 gas-limit (升级操作约 1,200,000)
4. **reinitialize**: 只在添加新的初始化逻辑时需要调用，普通升级不需要
5. **所有 forge/cast 命令必须加 `--legacy` 参数**
