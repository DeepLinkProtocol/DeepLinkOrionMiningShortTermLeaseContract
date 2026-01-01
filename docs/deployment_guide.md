# 部署和升级指南

## 环境准备

### 1. 安装 Foundry (Windows)

下载预编译二进制文件：
1. 访问 https://github.com/foundry-rs/foundry/releases/latest
2. 下载 `foundry_nightly_win32_amd64.zip`
3. 解压到 `C:\foundry\`
4. 添加到 PATH 环境变量

验证安装：
```powershell
forge --version
cast --version
```

### 2. 配置环境变量

创建 `.env` 文件（不要提交到 git）：
```env
PRIVATE_KEY=0x你的私钥
RENT_PROXY=0xda9efdff9ca7b7065b7706406a1a79c0e483815a
STAKING_PROXY=0x6268aba94d0d0e4fb917cc02765f631f309a7388
```

---

## 升级 Rent 合约（主网）

### 前置条件
- 执行升级的地址必须是 `canUpgradeAddress`
- 账户需要有足够的 DBC 支付 gas

### 步骤 1：部署新的实现合约

```powershell
forge create src/rent/Rent.sol:Rent --rpc-url https://rpc2.dbcwallet.io --private-key $PRIVATE_KEY --legacy --broadcast
```

记录返回的**新实现合约地址**。

### 步骤 2：升级代理合约

将下面命令中的 `新实现合约地址` 替换为步骤 1 返回的地址：

```powershell
# 先估算 gas
curl -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_estimateGas\",\"params\":[{\"to\":\"0xda9efdff9ca7b7065b7706406a1a79c0e483815a\",\"from\":\"你的地址\",\"data\":\"0x4f1ef286000000000000000000000000新实现合约地址(去掉0x,小写)00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000\"}],\"id\":1}"

# 执行升级（gas-limit 至少 1200000）
cast send 0xda9efdff9ca7b7065b7706406a1a79c0e483815a 0x4f1ef286000000000000000000000000新实现合约地址(去掉0x,小写)00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000 --rpc-url https://rpc2.dbcwallet.io --private-key $PRIVATE_KEY --legacy --gas-limit 1200000
```

### 步骤 3：调用 reinitialize（如果需要）

```powershell
cast send 0xda9efdff9ca7b7065b7706406a1a79c0e483815a "reinitialize()" --rpc-url https://rpc2.dbcwallet.io --private-key $PRIVATE_KEY --legacy --gas-limit 100000
```

---

## 验证合约源码

```powershell
forge verify-contract 新实现合约地址 src/rent/Rent.sol:Rent --verifier blockscout --verifier-url https://dbcscan.io/api --watch
```

---

## 常用查询命令

### 查询 owner
```powershell
curl -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"0xda9efdff9ca7b7065b7706406a1a79c0e483815a\",\"data\":\"0x8da5cb5b\"},\"latest\"],\"id\":1}"
```

### 查询 canUpgradeAddress
访问区块浏览器查看：https://dbcscan.io/address/0xda9efdff9ca7b7065b7706406a1a79c0e483815a?tab=read_proxy

### 查询当前实现合约地址
```powershell
curl -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getStorageAt\",\"params\":[\"0xda9efdff9ca7b7065b7706406a1a79c0e483815a\",\"0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc\",\"latest\"],\"id\":1}"
```

---

## 重要注意事项

| 项目 | 说明 |
|-----|------|
| `--legacy` | DBC 链必须加此参数，不支持 EIP-1559 |
| `gas-limit` | 升级操作需要约 1,200,000 gas |
| `canUpgradeAddress` | 只有此地址才能执行升级，可通过 `setCanUpgradeAddress` 修改 |
| EVM 版本 | 使用 `london`，不支持 `paris` 及以上 |
| Chain ID | mainnet: 19880818, testnet: 19850818 |

---

## 故障排除

### 错误：`Chain xxx not supported`
原因：OpenZeppelin Foundry Upgrades 插件不支持 DBC 链
解决：使用 `forge create` + `cast send` 手动升级，不要用 `forge script`

### 错误：`prevrandao not set`
原因：DBC 链不支持较新的 EVM 版本
解决：在 foundry.toml 设置 `evm_version = "london"`

### 错误：交易失败 (status: 0)
可能原因：
1. `canUpgradeAddress` 不是执行地址 - 需要先修改或使用正确的私钥
2. gas 不足 - 增加 `--gas-limit`
3. 权限不足 - 检查是否是 owner
