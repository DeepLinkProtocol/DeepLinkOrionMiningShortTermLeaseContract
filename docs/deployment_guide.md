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

## 合约升级通用流程

> 以下步骤同时适用于 Rent 和 NFTStaking 合约，替换对应路径和地址即可。

| 合约 | Proxy 地址 | 源码路径 |
|------|-----------|---------|
| Rent | `0xda9efdff9ca7b7065b7706406a1a79c0e483815a` | `src/rent/Rent.sol:Rent` |
| NFTStaking | `0x6268aba94d0d0e4fb917cc02765f631f309a7388` | `src/NFTStaking.sol:NFTStaking` |

### 前置条件
- 执行升级的地址必须是 `canUpgradeAddress`（当前为 `0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8`，owner 可通过 `setUpgradeAddress` 临时修改）
- 账户需要有足够的 DBC 支付 gas
- 合约 `version()` 已递增

### 步骤 1：编译 + 测试

```bash
cd DeepLinkOrionMiningShortTermLeaseContract
forge build --force
forge test
```

### 步骤 2：部署新实现合约

```bash
# Rent:
forge create src/rent/Rent.sol:Rent \
  --rpc-url https://rpc2.dbcwallet.io \
  --private-key $PRIVATE_KEY \
  --legacy --broadcast

# NFTStaking:
forge create src/NFTStaking.sol:NFTStaking \
  --rpc-url https://rpc2.dbcwallet.io \
  --private-key $PRIVATE_KEY \
  --legacy --broadcast
```

记录输出的 **`Deployed to: 0x...`** 地址。

### 步骤 3~5：升级代理合约（ethers.js 脚本）

> **重要**：DBC 链上 `cast send` 发送写交易时 gas 估算不准确（`eth_estimateGas` 返回的值偏低），会导致交易用完 gasLimit 后 revert（status=0），即使 `eth_call` 模拟成功。**必须使用 ethers.js 脚本并设置充足的 gasLimit**。

```javascript
// upgrade_contract.mjs
import { ethers } from 'ethers';
import fs from 'fs';

const RPC = 'https://rpc2.dbcwallet.io';
const PROXY = '0x...';           // 替换为目标 Proxy 地址
const NEW_IMPL = '0x...';        // 替换为步骤 2 的新实现地址
const ORIGINAL_CAN_UPGRADE = '0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8';

const envContent = fs.readFileSync('.env', 'utf8');
const PRIVATE_KEY = envContent.match(/PRIVATE_KEY=(.*)/)?.[1]?.trim();

const provider = new ethers.JsonRpcProvider(RPC, { chainId: 19880818, name: 'dbc' }, { staticNetwork: true });
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

const abi = [
  'function setUpgradeAddress(address addr) external',
  'function canUpgradeAddress() view returns (address)',
  'function owner() view returns (address)',
  'function version() view returns (uint256)',
  'function upgradeToAndCall(address newImplementation, bytes data) external payable',
];
const contract = new ethers.Contract(PROXY, abi, wallet);

async function main() {
  console.log('Wallet:', wallet.address);
  console.log('Owner:', await contract.owner());
  console.log('canUpgradeAddress:', await contract.canUpgradeAddress());
  console.log('Current version:', (await contract.version()).toString());

  // Step 3: 临时设置 canUpgradeAddress 为 owner（gasLimit ≥ 1M）
  const tx1 = await contract.setUpgradeAddress(wallet.address, { type: 0, gasLimit: 1000000 });
  const r1 = await tx1.wait();
  console.log('setUpgradeAddress → owner:', r1.status === 1 ? 'OK' : 'FAILED');
  if (r1.status !== 1) return;

  // Step 4: 执行 UUPS 升级（gasLimit ≥ 2M）
  const tx2 = await contract.upgradeToAndCall(NEW_IMPL, '0x', { type: 0, gasLimit: 2000000 });
  const r2 = await tx2.wait();
  console.log('upgradeToAndCall:', r2.status === 1 ? 'OK' : 'FAILED');
  console.log('New version:', (await contract.version()).toString());
  if (r2.status !== 1) return;

  // Step 5: 恢复 canUpgradeAddress 为原值
  const tx3 = await contract.setUpgradeAddress(ORIGINAL_CAN_UPGRADE, { type: 0, gasLimit: 1000000 });
  const r3 = await tx3.wait();
  console.log('Restore canUpgradeAddress:', r3.status === 1 ? 'OK' : 'FAILED');
  console.log('canUpgradeAddress:', await contract.canUpgradeAddress());
}
main().catch(e => console.error('ERROR:', e.message));
```

运行：`node upgrade_contract.mjs`

### 步骤 6：验证合约源码（Blockscout）

```bash
# Rent:
forge verify-contract <新实现地址> src/rent/Rent.sol:Rent \
  --verifier blockscout \
  --verifier-url https://dbcscan.io/api \
  --watch

# NFTStaking:
forge verify-contract <新实现地址> src/NFTStaking.sol:NFTStaking \
  --verifier blockscout \
  --verifier-url https://dbcscan.io/api \
  --watch
```

验证成功后可在 `https://dbcscan.io/address/<新实现地址>` 查看源码。

### 步骤 7：链上验证

通过 ethers.js 或 dbcscan.io **Read Proxy** 页面确认：
- `version()` 返回新版本号
- `owner()` / `canUpgradeAddress()` 不变
- 新增函数可调用

查询当前实现地址（ERC-1967 implementation slot）：
```bash
curl -s -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getStorageAt","params":["<PROXY>","0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc","latest"],"id":1}'
```

### 步骤 8：调用 reinitialize（如果需要）

仅在新增了需要初始化的状态变量（如 ReentrancyGuard）时需要：

```bash
# ethers.js 中:
await contract.reinitialize({ type: 0, gasLimit: 500000 });
```

---

## 升级后配套操作

- **添加 admin 钱包**（如新增了需要 admin 权限的函数）: 调用 `setAdminsToAddRentWhiteList(address[])` 添加 `pay_rent_dlc_seeds` 的 11 个钱包
- **更新 K8s stakeabi.js**（如 ABI 变更）: 更新 K8s Secret `node-api-secret`，重启相关 Pod

---

## 常用查询命令

### 查询 owner
```bash
curl -s -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"<PROXY>","data":"0x8da5cb5b"},"latest"],"id":1}'
```

### 查询 canUpgradeAddress
```bash
# selector: 0x75dfe221
curl -s -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"<PROXY>","data":"0x75dfe221"},"latest"],"id":1}'
```

或访问区块浏览器 Read Proxy 页面。

### 查询 version
```bash
# selector: 0x54fd4d50
curl -s -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"<PROXY>","data":"0x54fd4d50"},"latest"],"id":1}'
```

### 查询当前实现合约地址
```bash
curl -s -X POST https://rpc2.dbcwallet.io -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getStorageAt","params":["<PROXY>","0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc","latest"],"id":1}'
```

---

## 重要注意事项

| 项目 | 说明 |
|-----|------|
| `--legacy` | DBC 链必须加此参数，不支持 EIP-1559 |
| gas-limit | `setUpgradeAddress` 需要 ~575K（设 1M），`upgradeToAndCall` 需要 ~1.1M（设 2M） |
| `cast send` | DBC 链上 gas 估算不准，写交易**必须用 ethers.js**（`cast send` 会 revert） |
| `canUpgradeAddress` | 只有此地址才能执行升级，owner 可通过 `setUpgradeAddress` 临时修改 |
| EVM 版本 | 使用 `london`，不支持 `paris` 及以上 |
| Chain ID | mainnet: 19880818, testnet: 19850818 |
| `staticNetwork: true` | ethers.js 创建 Provider 时必须设置，防止后台 `eth_chainId` 查询 |

---

## 故障排除

### 错误：`Chain xxx not supported`
原因：OpenZeppelin Foundry Upgrades 插件不支持 DBC 链
解决：使用 `forge create` + ethers.js 手动升级，不要用 `forge script`

### 错误：`prevrandao not set`
原因：DBC 链不支持较新的 EVM 版本
解决：在 foundry.toml 设置 `evm_version = "london"`

### 错误：`cast send` 交易失败 (status: 0, gasUsed == gasLimit)
原因：DBC 链 `eth_estimateGas` 返回值偏低，`cast send` 使用估算值作为 gasLimit，导致执行时 gas 不足 revert
解决：改用 ethers.js 脚本，手动设置充足的 `gasLimit`（1M+ for setUpgradeAddress，2M+ for upgradeToAndCall）

### 错误：交易失败但 `eth_call` 模拟成功
原因：`eth_call` 不检查 gas，实际执行 gas 不足
解决：使用 ethers.js 并设置 `gasLimit: 2000000`

### 历史实现地址

| 合约 | Version | 实现地址 | 日期 |
|------|---------|---------|------|
| NFTStaking | v8 | `0xD9A21346F2Ceb8884020041404359401c0C51850` | 2026-03-17 |
| NFTStaking | v7 | `0xdD5AE990c2aed1fA583017085375aB7E6aC23929` | — |
| Rent | v5 | `0x2415fD1b5DAFa1005C1fc32497e1f9A961004253` | 2026-03-12 |
| Rent | v4 | `0x542eEff50bE288DF3fFDcCe3CD9F270747f07c15` | — |
| Rent | v2 | `0x6057C04e554537e9F118e1fc3b98393Df5600A69` | 2026-02-25 |
