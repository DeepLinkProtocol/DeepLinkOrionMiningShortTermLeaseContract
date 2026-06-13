#!/usr/bin/env node
// Rent v15 -> v16 升级 (owner 签名) — getTokenPrice 加 maxPriceAge 防喂价 cron 死后按旧价烧错钱
// 用法: 在 .env 设 OWNER_KEY, 然后 PREFLIGHT_ONLY=1 node scripts/deploy_rent_v16.mjs (只读检查)
//       确认无误后 node scripts/deploy_rent_v16.mjs (真升级)
//       升级后另启用过期防护(可选): DO_SET_MAX_PRICE_AGE=1 MAX_PRICE_AGE_SECONDS=1800 node scripts/deploy_rent_v16.mjs
// 步骤:
//   1. owner.setCanUpgradeAddress(owner) — 临时获得升级权 (Rent 是 setCanUpgradeAddress, 非 NFTStaking 的 setUpgradeAddress)
//   2. CREATE 部署新实现 (impl version 必须 == 16)
//   3. owner.upgradeToAndCall(newImpl, "0x") — 切 proxy (空 data, v16 仅追加 storage maxPriceAge + getter 改动, 无 initializer)
//   4. owner.setCanUpgradeAddress(0x36Ede4...) — 恢复 (★ 切勿跳过)
//   5. 验证: version=16, owner/feeToken/stakingContract/lastRentId/dlcPriceMarkupBps/clawbackAdmin 不变(storage 完好), maxPriceAge=0(待启用)
//   6. (可选) DO_SET_MAX_PRICE_AGE=1 时 owner.setMaxPriceAge(MAX_PRICE_AGE_SECONDS) 启用喂价过期防护
// 全部 type:0 legacy tx (DBC 链对 cast/EIP-1559 不兼容)

import { ethers } from 'ethers'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import dotenv from 'dotenv'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(__dirname, '..')
const CENTRAL_ENV = 'C:/Project/Fengxia/deeplink2/project-secret-files-2026-06-12/DeepLinkOrionMiningShortTermLeaseContract/.env'
dotenv.config({ path: fs.existsSync(CENTRAL_ENV) ? CENTRAL_ENV : path.join(repoRoot, '.env') })

const RPC_URL = 'https://rpc.dbcwallet.io'
const CHAIN_ID = 19880818
const RENT_PROXY = process.env.RENT_PROXY || '0xda9efdff9ca7b7065b7706406a1a79c0e483815a'
const ORIGINAL_CAN_UPGRADE = process.env.CAN_UPGRADE_ADDRESS || '0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8'
const OWNER_KEY = process.env.OWNER_KEY
const PREFLIGHT_ONLY = process.env.PREFLIGHT_ONLY === '1'
const DO_SET_MAX_PRICE_AGE = process.env.DO_SET_MAX_PRICE_AGE === '1'
const MAX_PRICE_AGE_SECONDS = BigInt(process.env.MAX_PRICE_AGE_SECONDS || '1800')

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
  sectionLog('Rent v15 → v16 升级 (maxPriceAge 喂价过期防护)' + (PREFLIGHT_ONLY ? '  [PREFLIGHT_ONLY 只读]' : ''))

  sectionLog('Pre-flight 检查')
  console.log('Owner wallet:', wallet.address)
  const balance = await provider.getBalance(wallet.address)
  console.log('Owner DBC balance:', ethers.formatEther(balance))
  if (balance < ethers.parseEther('0.5')) throw new Error(`Owner balance too low: ${ethers.formatEther(balance)} DBC`)

  const curOwner = await proxy.owner()
  const curCanUpgrade = await proxy.canUpgradeAddress()
  const curVersion = await proxy.version()
  // storage 不变量 (升级后必须一致)
  const feeToken = await proxy.feeToken()
  const stakingContract = await proxy.stakingContract()
  const lastRentId = await proxy.lastRentId()
  const dlcMarkup = await proxy.dlcPriceMarkupBps().catch(() => null)
  const clawbackAdmin = await proxy.clawbackAdmin().catch(() => null)   // v15 storage(slot38), 应=0x584B0E81
  const curMaxPriceAge = await proxy.maxPriceAge().catch(() => '(v15 无此 getter, 预期)')
  console.log('owner:', curOwner, '| canUpgradeAddress:', curCanUpgrade, '| version:', curVersion.toString())
  console.log('feeToken(before):', feeToken)
  console.log('stakingContract(before):', stakingContract)
  console.log('lastRentId(before):', lastRentId.toString(), '(升级后必须一致, 强 storage 校验)')
  console.log('dlcPriceMarkupBps(before):', dlcMarkup?.toString(), '(应=10600)')
  console.log('clawbackAdmin(before):', clawbackAdmin, '(v15, 应=0x584B0E81)')
  console.log('maxPriceAge(before):', curMaxPriceAge?.toString?.() || curMaxPriceAge, '(v15 无 getter → 升级后应=0 待启用)')
  if (curOwner.toLowerCase() !== wallet.address.toLowerCase()) throw new Error(`Owner mismatch: ${curOwner}`)
  if (curVersion !== 15n) throw new Error(`Expected version 15 on-chain, got ${curVersion}`)
  console.log('Pre-flight 通过.')

  if (PREFLIGHT_ONLY) {
    sectionLog('PREFLIGHT_ONLY — 不发任何交易, 退出')
    console.log('计划: setCanUpgradeAddress(owner) → 部署 v16 impl → upgradeToAndCall(impl,"0x") → 恢复 canUpgradeAddress')
    if (DO_SET_MAX_PRICE_AGE) console.log(`并将 setMaxPriceAge(${MAX_PRICE_AGE_SECONDS})`)
    else console.log('注: 未启用 maxPriceAge(maxPriceAge=0=惰性,行为同v15); 如需启用过期防护后续 DO_SET_MAX_PRICE_AGE=1')
    return
  }

  // ----- Step 1 -----
  sectionLog('Step 1: setCanUpgradeAddress(owner) — 临时升级权')
  if (curCanUpgrade.toLowerCase() !== wallet.address.toLowerCase()) {
    const tx1 = await proxy.setCanUpgradeAddress(wallet.address, await legacy({ gasLimit: 1000000n }))
    console.log('  tx1:', tx1.hash); await tx1.wait()
    if ((await proxy.canUpgradeAddress()).toLowerCase() !== wallet.address.toLowerCase()) throw new Error('setCanUpgradeAddress(owner) failed')
  } else console.log('  owner 已是 canUpgradeAddress, skip')

  // ----- Step 2 -----
  sectionLog('Step 2: 部署 v16 实现合约')
  const factory = new ethers.ContractFactory(abi, bytecode, wallet)
  const newImpl = await factory.deploy(await legacy({ gasLimit: 18000000n }))
  console.log('  deploy tx:', newImpl.deploymentTransaction().hash)
  await newImpl.waitForDeployment()
  const newImplAddr = await newImpl.getAddress()
  console.log('  new impl:', newImplAddr)
  const code = await provider.getCode(newImplAddr)
  if (!code || code === '0x') throw new Error('new impl codeless (OOG?) — 中止')
  const implVer = await new ethers.Contract(newImplAddr, abi, provider).version()
  if (implVer !== 16n) throw new Error(`new impl version mismatch: expected 16, got ${implVer}`)
  console.log('  impl version() = 16 ✓, code 非空 ✓')

  // ----- Step 3 -----
  sectionLog('Step 3: upgradeToAndCall(newImpl, "0x")')
  const tx3 = await proxy.upgradeToAndCall(newImplAddr, '0x', await legacy({ gasLimit: 2500000n }))
  console.log('  tx3:', tx3.hash); await tx3.wait()
  if ((await proxy.version()) !== 16n) throw new Error('Post-upgrade version != 16')
  console.log('  version() = 16 ✓')

  // ----- Step 4 -----
  sectionLog('Step 4: setCanUpgradeAddress(0x36Ede4...) — 恢复升级权')
  const tx4 = await proxy.setCanUpgradeAddress(ORIGINAL_CAN_UPGRADE, await legacy({ gasLimit: 1000000n }))
  console.log('  tx4:', tx4.hash); await tx4.wait()
  const finalCU = await proxy.canUpgradeAddress()
  if (finalCU.toLowerCase() !== ORIGINAL_CAN_UPGRADE.toLowerCase()) throw new Error(`Restore failed: ${finalCU}`)
  console.log('  canUpgradeAddress 恢复为:', finalCU, '✓')

  // ----- Step 5: storage 不变量总验证 -----
  sectionLog('Step 5: 升级后验证 (storage 完好)')
  const ver = await proxy.version()
  const owner2 = await proxy.owner()
  const feeToken2 = await proxy.feeToken()
  const stakingContract2 = await proxy.stakingContract()
  const lastRentId2 = await proxy.lastRentId()
  const dlcMarkup2 = await proxy.dlcPriceMarkupBps().catch(() => null)
  const clawbackAdmin2 = await proxy.clawbackAdmin().catch(() => null)
  const maxPriceAge2 = await proxy.maxPriceAge()   // v16 新 getter, 应=0
  console.log('  version()          =', ver.toString(), '(期望 16)')
  console.log('  owner()            =', owner2, owner2.toLowerCase() === curOwner.toLowerCase() ? '✓ 不变' : '✗ 变了!')
  console.log('  feeToken()         =', feeToken2, feeToken.toLowerCase() === feeToken2.toLowerCase() ? '✓ 不变' : '✗ 错位!')
  console.log('  stakingContract()  =', stakingContract2, stakingContract.toLowerCase() === stakingContract2.toLowerCase() ? '✓ 不变' : '✗ 错位!')
  // ⚠️ lastRentId 是实时计数器(有新租赁会+1), 不能用一字不变判 storage; 改判"只增不减且未跳天文数字"(storage 错位会变 ~10^48)
  const lastRentIdSane = (lastRentId2 >= lastRentId && lastRentId2 < lastRentId + 1000n)
  console.log('  lastRentId()       =', lastRentId2.toString(), lastRentIdSane ? `✓ 正常计数器(升级窗口内 +${(lastRentId2 - lastRentId).toString()} 笔新租赁, storage 完好)` : '✗ 错位(跳天文数字)!')
  console.log('  dlcPriceMarkupBps  =', dlcMarkup2?.toString(), dlcMarkup?.toString() === dlcMarkup2?.toString() ? '✓ 不变(+6%保留)' : '✗ 错位!')
  console.log('  clawbackAdmin()    =', clawbackAdmin2, (clawbackAdmin && clawbackAdmin2 && clawbackAdmin.toLowerCase() === clawbackAdmin2.toLowerCase()) ? '✓ 不变' : '✗ 错位!')
  console.log('  maxPriceAge()      =', maxPriceAge2.toString(), maxPriceAge2 === 0n ? '✓ =0(惰性,待启用,行为同v15)' : '(已有值)')
  if (ver !== 16n) throw new Error('Final version != 16')
  if (owner2.toLowerCase() !== curOwner.toLowerCase()) throw new Error('owner 被改动!')
  if (feeToken.toLowerCase() !== feeToken2.toLowerCase()) throw new Error('feeToken 错位 — storage 损坏!')
  if (stakingContract.toLowerCase() !== stakingContract2.toLowerCase()) throw new Error('stakingContract 错位!')
  if (!lastRentIdSane) throw new Error(`lastRentId 异常(${lastRentId}→${lastRentId2}) — storage 可能损坏!`)
  if (dlcMarkup?.toString() !== dlcMarkup2?.toString()) throw new Error('dlcPriceMarkupBps 错位!')
  if (clawbackAdmin && clawbackAdmin2 && clawbackAdmin.toLowerCase() !== clawbackAdmin2.toLowerCase()) throw new Error('clawbackAdmin 错位 — storage 损坏!')

  // ----- Step 6: (可选) setMaxPriceAge -----
  if (DO_SET_MAX_PRICE_AGE) {
    sectionLog(`Step 6: setMaxPriceAge(${MAX_PRICE_AGE_SECONDS}) — 启用喂价过期防护`)
    const tx6 = await proxy.setMaxPriceAge(MAX_PRICE_AGE_SECONDS, await legacy({ gasLimit: 1000000n }))
    console.log('  tx6:', tx6.hash); await tx6.wait()
    const mpa = await proxy.maxPriceAge()
    if (mpa !== MAX_PRICE_AGE_SECONDS) throw new Error(`setMaxPriceAge failed: ${mpa}`)
    console.log('  maxPriceAge 已设为:', mpa.toString(), '秒 ✓ (喂价超此龄→回退 oracle 实时价)')
  } else {
    console.log('\n注: 未启用 maxPriceAge(=0 惰性,行为同v15)。如需启用过期防护: DO_SET_MAX_PRICE_AGE=1 MAX_PRICE_AGE_SECONDS=1800 重跑。')
  }

  sectionLog('✅ Rent v16 升级完成')
  console.log(`New impl:   ${newImplAddr}`)
  console.log(`upgrade tx: ${tx3.hash}`)
}

main().catch(err => { console.error('\n❌ 升级失败:', err.message || err); if (err.stack) console.error(err.stack); process.exit(1) })
