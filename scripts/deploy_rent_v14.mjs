#!/usr/bin/env node
// Rent v12 -> v14 升级 (owner 签名) — adminReverseUnpaidRenewal clawback (含 v13 dlcPriceMarkupBps, 默认不涨)
// 用法: 在 .env 设 OWNER_KEY, 然后 PREFLIGHT_ONLY=1 node scripts/deploy_rent_v14.mjs (只读检查)
//       确认无误后 node scripts/deploy_rent_v14.mjs (真升级)
// 步骤:
//   1. owner.setCanUpgradeAddress(owner) — 临时获得升级权 (Rent 是 setCanUpgradeAddress, 非 setUpgradeAddress)
//   2. CREATE 部署新实现 (impl version 必须 == 14)
//   3. owner.upgradeToAndCall(newImpl, "0x") — 切 proxy (空 data, v14 仅追加 mapping 无 initializer)
//   4. owner.setCanUpgradeAddress(0x36Ede4...) — 恢复 (★ 切勿跳过)
//   5. 升级后验证: version=14, owner/feeToken/pointToken 不变(storage 完好), canUpgradeAddress 已恢复
// 全部 type:0 legacy tx (DBC 链对 cast/EIP-1559 不兼容)

import { ethers } from 'ethers'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import dotenv from 'dotenv'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(__dirname, '..')
// .env 优先用中央(秘钥在那), 回退本地
const CENTRAL_ENV = 'C:/Project/Fengxia/deeplink2/project-secret-files-2026-06-12/DeepLinkOrionMiningShortTermLeaseContract/.env'
dotenv.config({ path: fs.existsSync(CENTRAL_ENV) ? CENTRAL_ENV : path.join(repoRoot, '.env') })

const RPC_URL = 'https://rpc.dbcwallet.io'
const CHAIN_ID = 19880818
const RENT_PROXY = process.env.RENT_PROXY || '0xda9efdff9ca7b7065b7706406a1a79c0e483815a'
const ORIGINAL_CAN_UPGRADE = process.env.CAN_UPGRADE_ADDRESS || '0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8'
const OWNER_KEY = process.env.OWNER_KEY
const PREFLIGHT_ONLY = process.env.PREFLIGHT_ONLY === '1'

if (!OWNER_KEY) { console.error('FATAL: OWNER_KEY not set'); process.exit(1) }

const artifact = JSON.parse(fs.readFileSync(path.join(repoRoot, 'out/Rent.sol/Rent.json'), 'utf8'))
const bytecode = artifact.bytecode.object || artifact.bytecode
const abi = artifact.abi

const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: 'dbc' }, { staticNetwork: true })
const ownerKey = OWNER_KEY.startsWith('0x') ? OWNER_KEY : '0x' + OWNER_KEY
const wallet = new ethers.Wallet(ownerKey, provider)
const proxy = new ethers.Contract(RENT_PROXY, abi, wallet)

function sectionLog(t) { console.log('\n' + '='.repeat(70) + '\n' + t + '\n' + '='.repeat(70)) }
async function legacy(extra = {}) { const f = await provider.getFeeData(); return { gasPrice: f.gasPrice, type: 0, ...extra } }

async function main() {
  sectionLog('Rent v12 → v14 升级 (clawback)' + (PREFLIGHT_ONLY ? '  [PREFLIGHT_ONLY 只读]' : ''))

  // ----- Pre-flight -----
  sectionLog('Pre-flight 检查')
  console.log('Owner wallet:', wallet.address)
  const balance = await provider.getBalance(wallet.address)
  console.log('Owner DBC balance:', ethers.formatEther(balance))
  if (balance < ethers.parseEther('0.5')) throw new Error(`Owner balance too low: ${ethers.formatEther(balance)} DBC`)

  const curOwner = await proxy.owner()
  const curCanUpgrade = await proxy.canUpgradeAddress()
  const curVersion = await proxy.version()
  // 捕获 storage 不变量(升级后必须一致, 证明 storage 未错位)
  const feeToken = await proxy.feeToken()
  const stakingContract = await proxy.stakingContract()
  const lastRentId = await proxy.lastRentId()
  console.log('owner:', curOwner, '| canUpgradeAddress:', curCanUpgrade, '| version:', curVersion.toString())
  console.log('feeToken(before):', feeToken)
  console.log('stakingContract(before):', stakingContract)
  console.log('lastRentId(before):', lastRentId.toString(), '(升级后必须一致, 强 storage 校验)')
  if (curOwner.toLowerCase() !== wallet.address.toLowerCase()) throw new Error(`Owner mismatch: ${curOwner}`)
  if (curVersion !== 12n) throw new Error(`Expected version 12 on-chain, got ${curVersion}`)
  console.log('Pre-flight 通过.')

  if (PREFLIGHT_ONLY) { sectionLog('PREFLIGHT_ONLY — 不发任何交易, 退出'); return }

  // ----- Step 1: setCanUpgradeAddress(owner) -----
  sectionLog('Step 1: setCanUpgradeAddress(owner) — 临时升级权')
  if (curCanUpgrade.toLowerCase() !== wallet.address.toLowerCase()) {
    const tx1 = await proxy.setCanUpgradeAddress(wallet.address, await legacy({ gasLimit: 1000000n }))
    console.log('  tx1:', tx1.hash); await tx1.wait()
    if ((await proxy.canUpgradeAddress()).toLowerCase() !== wallet.address.toLowerCase()) throw new Error('setCanUpgradeAddress(owner) failed')
  } else console.log('  owner 已是 canUpgradeAddress, skip')

  // ----- Step 2: deploy new impl -----
  sectionLog('Step 2: 部署 v14 实现合约')
  const factory = new ethers.ContractFactory(abi, bytecode, wallet)
  const newImpl = await factory.deploy(await legacy({ gasLimit: 18000000n }))
  console.log('  deploy tx:', newImpl.deploymentTransaction().hash)
  await newImpl.waitForDeployment()
  const newImplAddr = await newImpl.getAddress()
  console.log('  new impl:', newImplAddr)
  const code = await provider.getCode(newImplAddr)
  if (!code || code === '0x') throw new Error('new impl codeless (OOG?) — 中止')
  const implVer = await new ethers.Contract(newImplAddr, abi, provider).version()
  if (implVer !== 14n) throw new Error(`new impl version mismatch: expected 14, got ${implVer}`)
  console.log('  impl version() = 14 ✓, code 非空 ✓')

  // ----- Step 3: upgradeToAndCall (空 data, 无 initializer) -----
  sectionLog('Step 3: upgradeToAndCall(newImpl, "0x")')
  const tx3 = await proxy.upgradeToAndCall(newImplAddr, '0x', await legacy({ gasLimit: 2500000n }))
  console.log('  tx3:', tx3.hash); await tx3.wait()
  if ((await proxy.version()) !== 14n) throw new Error('Post-upgrade version != 14')
  console.log('  version() = 14 ✓')

  // ----- Step 4: 恢复 canUpgradeAddress -----
  sectionLog('Step 4: setCanUpgradeAddress(0x36Ede4...) — 恢复升级权')
  const tx4 = await proxy.setCanUpgradeAddress(ORIGINAL_CAN_UPGRADE, await legacy({ gasLimit: 1000000n }))
  console.log('  tx4:', tx4.hash); await tx4.wait()
  const finalCU = await proxy.canUpgradeAddress()
  if (finalCU.toLowerCase() !== ORIGINAL_CAN_UPGRADE.toLowerCase()) throw new Error(`Restore failed: ${finalCU}`)
  console.log('  canUpgradeAddress 恢复为:', finalCU, '✓')

  // ----- Step 5: 升级后总验证 (storage 不变量) -----
  sectionLog('Step 5: 升级后验证')
  const ver = await proxy.version()
  const owner2 = await proxy.owner()
  const feeToken2 = await proxy.feeToken()
  const stakingContract2 = await proxy.stakingContract()
  const lastRentId2 = await proxy.lastRentId()
  const markup = await proxy.dlcPriceMarkupBps().catch(() => null)  // v14 新, 应=0/FACTOR(不涨)
  const FACTOR = await proxy.FACTOR().catch(() => null)
  console.log('  version()         =', ver.toString(), '(期望 14)')
  console.log('  owner()           =', owner2, owner2.toLowerCase() === curOwner.toLowerCase() ? '✓ 不变' : '✗ 变了!')
  console.log('  feeToken()        =', feeToken2, feeToken.toLowerCase() === feeToken2.toLowerCase() ? '✓ 不变' : '✗ 错位!')
  console.log('  stakingContract() =', stakingContract2, stakingContract.toLowerCase() === stakingContract2.toLowerCase() ? '✓ 不变' : '✗ 错位!')
  console.log('  lastRentId()      =', lastRentId2.toString(), lastRentId === lastRentId2 ? '✓ 不变(storage 完好)' : '✗ 错位!')
  console.log('  dlcPriceMarkupBps =', markup?.toString(), '| FACTOR =', FACTOR?.toString(), '(相等或0=不涨价, 安全)')
  console.log('  canUpgradeAddress =', finalCU)
  if (ver !== 14n) throw new Error('Final version != 14')
  if (owner2.toLowerCase() !== curOwner.toLowerCase()) throw new Error('owner 被改动!')
  if (feeToken.toLowerCase() !== feeToken2.toLowerCase()) throw new Error('feeToken 错位 — storage 损坏!')
  if (stakingContract.toLowerCase() !== stakingContract2.toLowerCase()) throw new Error('stakingContract 错位 — storage 损坏!')
  if (lastRentId !== lastRentId2) throw new Error('lastRentId 错位 — storage 损坏!')

  sectionLog('✅ Rent v14 升级完成')
  console.log(`New impl:   ${newImplAddr}`)
  console.log(`upgrade tx: ${tx3.hash}`)
  console.log('注: dlcPriceMarkupBps 默认不涨; 如需 +6% 由 owner 另调 setDlcPriceMarkupBps(10600)')
  console.log('注: clawback adminReverseUnpaidRenewal 现可用(onlyOwner), 撤销已垫付未付款续租')
}

main().catch(err => { console.error('\n❌ 升级失败:', err.message || err); if (err.stack) console.error(err.stack); process.exit(1) })
