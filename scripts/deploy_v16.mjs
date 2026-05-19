#!/usr/bin/env node
// NFTStaking v13 -> v16 升级脚本（owner 签名）
// 用法: cd 到合约仓库目录, node scripts/deploy_v16.mjs
//
// 步骤:
//   1. owner.setUpgradeAddress(owner) — 给 owner 临时升级权限
//   2. CREATE 部署新实现合约
//   3. owner.upgradeToAndCall(newImpl, "0x") — 切换 proxy 指向新实现
//   4. owner.setUpgradeAddress(0x36Ede4...) — 恢复原 canUpgradeAddress
//   5. 链上验证: version()=16, getCurrentMiningPhase()=6, getDailyRewardAmount, getGlobalState
//
// 用 ethers.js 而非 cast/forge 因为 DBC 链 RPC 对 cast 有兼容问题

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

if (!OWNER_KEY) {
  console.error('FATAL: OWNER_KEY not set in .env')
  process.exit(1)
}

const artifactPath = path.join(repoRoot, 'out/NFTStaking.sol/NFTStaking.json')
const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))
const bytecode = artifact.bytecode.object || artifact.bytecode
const abi = artifact.abi

const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: 'dbc' }, { staticNetwork: true })
const ownerKey = OWNER_KEY.startsWith('0x') ? OWNER_KEY : '0x' + OWNER_KEY
const wallet = new ethers.Wallet(ownerKey, provider)

const proxy = new ethers.Contract(STAKING_PROXY, abi, wallet)

function sectionLog(title) {
  console.log('\n' + '='.repeat(70))
  console.log(title)
  console.log('='.repeat(70))
}

async function getLegacyOverrides() {
  // DBC chain requires legacy tx; gasPrice from node
  const feeData = await provider.getFeeData()
  return { gasPrice: feeData.gasPrice, type: 0 }
}

async function main() {
  sectionLog('NFTStaking v13 → v16 升级')

  // ----- Pre-flight -----
  sectionLog('Pre-flight 检查')
  console.log('Owner wallet:', wallet.address)
  console.log('Proxy address:', STAKING_PROXY)

  const balance = await provider.getBalance(wallet.address)
  console.log('Owner DBC balance:', ethers.formatEther(balance))
  if (balance < ethers.parseEther('0.1')) {
    throw new Error(`Owner balance too low: ${ethers.formatEther(balance)} DBC`)
  }

  const currentOwner = await proxy.owner()
  const currentCanUpgrade = await proxy.canUpgradeAddress()
  const currentVersion = await proxy.version()
  console.log('Current owner:', currentOwner)
  console.log('Current canUpgradeAddress:', currentCanUpgrade)
  console.log('Current version:', currentVersion.toString())

  if (currentOwner.toLowerCase() !== wallet.address.toLowerCase()) {
    throw new Error(`Owner mismatch: contract=${currentOwner}, wallet=${wallet.address}`)
  }
  if (currentVersion !== 13n) {
    throw new Error(`Expected version 13 on-chain, got ${currentVersion}`)
  }

  console.log('All pre-flight checks passed.')

  // ----- Step 1: setUpgradeAddress(owner) -----
  sectionLog('Step 1: owner.setUpgradeAddress(owner) — 临时获得升级权限')
  if (currentCanUpgrade.toLowerCase() !== wallet.address.toLowerCase()) {
    const overrides1 = await getLegacyOverrides()
    const tx1 = await proxy.setUpgradeAddress(wallet.address, overrides1)
    console.log('  tx1 hash:', tx1.hash)
    const r1 = await tx1.wait()
    console.log('  tx1 confirmed in block:', r1.blockNumber)
    const checkUpgrade1 = await proxy.canUpgradeAddress()
    if (checkUpgrade1.toLowerCase() !== wallet.address.toLowerCase()) {
      throw new Error(`setUpgradeAddress failed: now=${checkUpgrade1}`)
    }
  } else {
    console.log('  owner already is canUpgradeAddress, skip')
  }

  // ----- Step 2: Deploy new impl via CREATE -----
  sectionLog('Step 2: 部署新 NFTStaking v16 实现合约')
  const factory = new ethers.ContractFactory(abi, bytecode, wallet)
  const overrides2 = await getLegacyOverrides()
  const newImpl = await factory.deploy(overrides2)
  console.log('  deploy tx hash:', newImpl.deploymentTransaction().hash)
  await newImpl.waitForDeployment()
  const newImplAddr = await newImpl.getAddress()
  console.log('  new impl address:', newImplAddr)

  // Sanity check: new impl version
  const implContract = new ethers.Contract(newImplAddr, abi, provider)
  const implVersion = await implContract.version()
  console.log('  new impl version() =', implVersion.toString())
  if (implVersion !== 16n) {
    throw new Error(`new impl version mismatch: expected 16, got ${implVersion}`)
  }

  // ----- Step 3: upgradeToAndCall -----
  sectionLog('Step 3: proxy.upgradeToAndCall(newImpl, "0x")')
  const overrides3 = await getLegacyOverrides()
  const tx3 = await proxy.upgradeToAndCall(newImplAddr, '0x', overrides3)
  console.log('  tx3 hash:', tx3.hash)
  const r3 = await tx3.wait()
  console.log('  tx3 confirmed in block:', r3.blockNumber)

  const postVersion = await proxy.version()
  console.log('  proxy.version() after upgrade =', postVersion.toString())
  if (postVersion !== 16n) {
    throw new Error(`Post-upgrade version mismatch: ${postVersion}`)
  }

  // ----- Step 4: Restore canUpgradeAddress -----
  sectionLog('Step 4: owner.setUpgradeAddress(0x36Ede4...) — 恢复原 canUpgradeAddress')
  const overrides4 = await getLegacyOverrides()
  const tx4 = await proxy.setUpgradeAddress(ORIGINAL_CAN_UPGRADE, overrides4)
  console.log('  tx4 hash:', tx4.hash)
  const r4 = await tx4.wait()
  console.log('  tx4 confirmed in block:', r4.blockNumber)
  const finalCanUpgrade = await proxy.canUpgradeAddress()
  if (finalCanUpgrade.toLowerCase() !== ORIGINAL_CAN_UPGRADE.toLowerCase()) {
    throw new Error(`Restore failed: ${finalCanUpgrade}`)
  }
  console.log('  canUpgradeAddress restored to:', finalCanUpgrade)

  // ----- Step 5: Post-upgrade verification -----
  sectionLog('Step 5: 部署后验证')
  const ver = await proxy.version()
  const phase = await proxy.getCurrentMiningPhase()
  const daily = await proxy.getDailyRewardAmount()
  const [totalCalcPoint, totalReserved, rewardEndAt] = await proxy.getGlobalState()
  const rewardStartAt = await proxy.rewardStartAtTimestamp()

  console.log('  version()                = ', ver.toString(), '(expected 16)')
  console.log('  getCurrentMiningPhase()  = ', phase.toString(), '(expected 6, still in boost)')
  console.log('  getDailyRewardAmount()   = ', ethers.formatEther(daily), 'ether')
  console.log('  rewardStartAtTimestamp   = ', rewardStartAt.toString(),
              '(=', new Date(Number(rewardStartAt) * 1000).toISOString(), ')')
  console.log('  rewardEndAt              = ', rewardEndAt.toString(),
              '(=', new Date(Number(rewardEndAt) * 1000).toISOString(), ')')
  const expectedRewardEnd = rewardStartAt + 9180n * 86400n
  console.log('  expected rewardEndAt     = ', expectedRewardEnd.toString())
  if (rewardEndAt !== expectedRewardEnd) {
    throw new Error(`rewardEndAt mismatch: got ${rewardEndAt}, expected ${expectedRewardEnd}`)
  }
  console.log('  totalCalcPoint           = ', totalCalcPoint.toString())
  console.log('  totalReservedAmount      = ', ethers.formatEther(totalReserved), 'DLC')

  if (ver !== 16n) throw new Error('Final version check failed')
  if (phase !== 6n) throw new Error('Phase should be 6 pre-cliff')

  sectionLog('✅ 升级完成')
  console.log(`New implementation:  ${newImplAddr}`)
  console.log(`Step 1 tx:           setUpgradeAddress(owner)`)
  console.log(`Step 2 tx (deploy):  ${newImpl.deploymentTransaction().hash}`)
  console.log(`Step 3 tx (upgrade): ${tx3.hash}`)
  console.log(`Step 4 tx (restore): ${tx4.hash}`)
}

main().catch(err => {
  console.error('\n❌ DEPLOYMENT FAILED:', err.message || err)
  if (err.stack) console.error(err.stack)
  process.exit(1)
})
