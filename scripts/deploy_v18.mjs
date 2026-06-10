#!/usr/bin/env node
// NFTStaking v17 -> v18 升级脚本 (owner 签名) — 新增 stakeAdmin 管理员代延质押
// 用法: cd 合约仓库目录, 在 .env 设 OWNER_KEY + STAKE_ADMIN_ADDRESS, 然后 node scripts/deploy_v18.mjs
//
// 步骤 (详见 docs/DEPLOY_V18_STAKEADMIN.md):
//   1. owner.setUpgradeAddress(owner) — 临时获得升级权
//   2. CREATE 部署新实现 (impl version 必须 == 18)
//   3. owner.upgradeToAndCall(newImpl, "0x") — 切 proxy 指向新实现 (空 data, 切勿调 initializePayout!)
//   4. owner.setStakeAdmin(STAKE_ADMIN) — 设运维钱包 (v18 新, onlyOwner, 仅 v18 存在)
//   5. owner.setUpgradeAddress(0x36Ede4...) — 恢复原 canUpgradeAddress (★ 切勿跳过)
//   6. 验证: version=18, stakeAdmin=STAKE_ADMIN, payoutAdmin/owner 不变, canUpgradeAddress 已恢复
//
// 用 ethers.js 而非 cast/forge — DBC 链 RPC 对 cast 有 "duplicate field" 兼容问题; 全部 type:0 legacy tx

import { ethers } from 'ethers'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import dotenv from 'dotenv'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(__dirname, '..')
dotenv.config({ path: path.join(repoRoot, '.env') })

const RPC_URL = 'https://rpc.dbcwallet.io'
const CHAIN_ID = 19880818
const STAKING_PROXY = process.env.STAKING_PROXY || '0x6268aba94d0d0e4fb917cc02765f631f309a7388'
const ORIGINAL_CAN_UPGRADE = process.env.CAN_UPGRADE_ADDRESS || '0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8'
const OWNER_KEY = process.env.OWNER_KEY
const STAKE_ADMIN_ADDRESS = process.env.STAKE_ADMIN_ADDRESS  // v18 运维钱包地址 (必填)

if (!OWNER_KEY) { console.error('FATAL: OWNER_KEY not set in .env'); process.exit(1) }
if (!STAKE_ADMIN_ADDRESS || !ethers.isAddress(STAKE_ADMIN_ADDRESS)) {
  console.error('FATAL: STAKE_ADMIN_ADDRESS not set / invalid in .env (v18 运维钱包地址)'); process.exit(1)
}

const artifactPath = path.join(repoRoot, 'out/NFTStaking.sol/NFTStaking.json')
const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))
const bytecode = artifact.bytecode.object || artifact.bytecode
const abi = artifact.abi

const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: 'dbc' }, { staticNetwork: true })
const ownerKey = OWNER_KEY.startsWith('0x') ? OWNER_KEY : '0x' + OWNER_KEY
const wallet = new ethers.Wallet(ownerKey, provider)
const proxy = new ethers.Contract(STAKING_PROXY, abi, wallet)

function sectionLog(t) { console.log('\n' + '='.repeat(70) + '\n' + t + '\n' + '='.repeat(70)) }
async function legacy() { const f = await provider.getFeeData(); return { gasPrice: f.gasPrice, type: 0 } }

async function main() {
  sectionLog('NFTStaking v17 → v18 升级 (stakeAdmin)')

  // ----- Pre-flight -----
  sectionLog('Pre-flight 检查')
  console.log('Owner wallet:', wallet.address)
  console.log('Proxy:', STAKING_PROXY, '| 目标 stakeAdmin:', STAKE_ADMIN_ADDRESS)
  const balance = await provider.getBalance(wallet.address)
  console.log('Owner DBC balance:', ethers.formatEther(balance))
  if (balance < ethers.parseEther('0.1')) throw new Error(`Owner balance too low: ${ethers.formatEther(balance)} DBC`)

  const curOwner = await proxy.owner()
  const curCanUpgrade = await proxy.canUpgradeAddress()
  const curVersion = await proxy.version()
  const curPayoutAdmin = await proxy.payoutAdmin()   // 捕获用于升级后比对 (必须不变)
  console.log('owner:', curOwner, '| canUpgradeAddress:', curCanUpgrade, '| version:', curVersion.toString())
  console.log('payoutAdmin(before):', curPayoutAdmin)
  if (curOwner.toLowerCase() !== wallet.address.toLowerCase()) throw new Error(`Owner mismatch: ${curOwner}`)
  if (curVersion !== 17n) throw new Error(`Expected version 17 on-chain, got ${curVersion}`)
  if (curPayoutAdmin === ethers.ZeroAddress) throw new Error('payoutAdmin 未初始化 — 异常, 中止 (v18 不应重跑 initializePayout)')
  console.log('Pre-flight 通过.')

  // ----- Step 1: setUpgradeAddress(owner) -----
  sectionLog('Step 1: setUpgradeAddress(owner) — 临时升级权')
  if (curCanUpgrade.toLowerCase() !== wallet.address.toLowerCase()) {
    const tx1 = await proxy.setUpgradeAddress(wallet.address, await legacy())
    console.log('  tx1:', tx1.hash); await tx1.wait()
    if ((await proxy.canUpgradeAddress()).toLowerCase() !== wallet.address.toLowerCase()) throw new Error('setUpgradeAddress(owner) failed')
  } else console.log('  owner 已是 canUpgradeAddress, skip')

  // ----- Step 2: deploy new impl -----
  sectionLog('Step 2: 部署 v18 实现合约')
  const factory = new ethers.ContractFactory(abi, bytecode, wallet)
  const newImpl = await factory.deploy(await legacy())
  console.log('  deploy tx:', newImpl.deploymentTransaction().hash)
  await newImpl.waitForDeployment()
  const newImplAddr = await newImpl.getAddress()
  console.log('  new impl:', newImplAddr)
  const code = await provider.getCode(newImplAddr)
  if (!code || code === '0x') throw new Error('new impl 部署成 codeless 地址 (OOG?) — 中止')
  const implVer = await new ethers.Contract(newImplAddr, abi, provider).version()
  if (implVer !== 18n) throw new Error(`new impl version mismatch: expected 18, got ${implVer}`)
  console.log('  impl version() = 18 ✓, code 非空 ✓')

  // ----- Step 3: upgradeToAndCall (空 data, 切勿 initializePayout) -----
  sectionLog('Step 3: upgradeToAndCall(newImpl, "0x")')
  const tx3 = await proxy.upgradeToAndCall(newImplAddr, '0x', await legacy())
  console.log('  tx3:', tx3.hash); await tx3.wait()
  const postVer = await proxy.version()
  if (postVer !== 18n) throw new Error(`Post-upgrade version mismatch: ${postVer}`)
  console.log('  version() = 18 ✓')

  // ----- Step 4: setStakeAdmin (v18 新, onlyOwner) -----
  sectionLog('Step 4: setStakeAdmin(运维钱包)')
  const tx4 = await proxy.setStakeAdmin(STAKE_ADMIN_ADDRESS, await legacy())
  console.log('  tx4:', tx4.hash); await tx4.wait()
  const sa = await proxy.stakeAdmin()
  if (sa.toLowerCase() !== STAKE_ADMIN_ADDRESS.toLowerCase()) throw new Error(`setStakeAdmin failed: ${sa}`)
  console.log('  stakeAdmin() =', sa, '✓')

  // ----- Step 5: 恢复 canUpgradeAddress (★ 切勿跳过) -----
  sectionLog('Step 5: setUpgradeAddress(0x36Ede4...) — 恢复升级权')
  const tx5 = await proxy.setUpgradeAddress(ORIGINAL_CAN_UPGRADE, await legacy())
  console.log('  tx5:', tx5.hash); await tx5.wait()
  const finalCU = await proxy.canUpgradeAddress()
  if (finalCU.toLowerCase() !== ORIGINAL_CAN_UPGRADE.toLowerCase()) throw new Error(`Restore failed: ${finalCU}`)
  console.log('  canUpgradeAddress 恢复为:', finalCU, '✓')

  // ----- Step 6: 升级后总验证 -----
  sectionLog('Step 6: 升级后验证')
  const ver = await proxy.version()
  const owner2 = await proxy.owner()
  const payoutAdmin2 = await proxy.payoutAdmin()
  const stakeAdmin2 = await proxy.stakeAdmin()
  console.log('  version()          =', ver.toString(), '(期望 18)')
  console.log('  owner()            =', owner2, owner2.toLowerCase() === curOwner.toLowerCase() ? '✓ 不变' : '✗ 变了!')
  console.log('  payoutAdmin()      =', payoutAdmin2, payoutAdmin2.toLowerCase() === curPayoutAdmin.toLowerCase() ? '✓ 不变' : '✗ 变了!')
  console.log('  stakeAdmin()       =', stakeAdmin2)
  console.log('  canUpgradeAddress  =', finalCU)
  if (ver !== 18n) throw new Error('Final version check failed')
  if (owner2.toLowerCase() !== curOwner.toLowerCase()) throw new Error('owner 被改动!')
  if (payoutAdmin2.toLowerCase() !== curPayoutAdmin.toLowerCase()) throw new Error('payoutAdmin 被改动!')
  if (stakeAdmin2.toLowerCase() !== STAKE_ADMIN_ADDRESS.toLowerCase()) throw new Error('stakeAdmin 未正确设置!')

  sectionLog('✅ v18 升级完成')
  console.log(`New impl:    ${newImplAddr}`)
  console.log(`upgrade tx:  ${tx3.hash}`)
  console.log(`setStakeAdmin tx: ${tx4.hash}`)
  console.log('下一步: scp stake_admin.local.json 到 rpc3, 配 PM2 跑 stake_auto_renew.js (DRY_RUN 先观察)')
}

main().catch(err => { console.error('\n❌ 升级失败:', err.message || err); if (err.stack) console.error(err.stack); process.exit(1) })
