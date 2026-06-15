#!/usr/bin/env node
// ItemTradeEscrow v1→v2 UUPS 升级 — 新增 claimDisputeTimeout 防恶意冻结灾难兜底
// 用法: OWNER_KEY=<owner私钥> [DISPUTE_TIMEOUT_SECONDS=2592000] [DRY_RUN=1] node scripts/upgrade_item_escrow_v2.mjs
//   - owner(=canUpgradeAddress) 签 upgradeToAndCall + setDisputeTimeout; 同一钱包付 gas
//   - DBC RPC 对 cast 有兼容问题, 全用 ethers + type:0 legacy tx, gasLimit 给足
//   - 真钱主网不可逆: 全程硬断言 proxy/owner/version/config; 升级后逐项校验既有状态不变
import { ethers } from 'ethers'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(__dirname, '..')

const RPC_URL = 'https://rpc.dbcwallet.io'
const CHAIN_ID = 19880818
const PROXY = '0xc7d5aa73514382Cf61e5e06e9C57D7F105a33e9b'
const EXPECTED = {
  owner: '0x244f8191010a9C20aaE96DC4afa4E1D63983802E',
  dlpToken: '0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6',
  feeRecipient: '0xCAA5cB0983cd544283346c82f3870931a295365B',
  arbiter: '0xB5A5ab31E5dEd47Cd61de1bbD62b1Dd161daA6f2',
}
const DISPUTE_TIMEOUT = BigInt(process.env.DISPUTE_TIMEOUT_SECONDS || '2592000') // 默认 30 天
const DRY_RUN = process.env.DRY_RUN === '1'
const OWNER_KEY = process.env.OWNER_KEY

const die = (m) => { console.error('FATAL:', m); process.exit(1) }
const eq = (a, b) => !!a && !!b && a.toLowerCase() === b.toLowerCase()
if (!OWNER_KEY) die('OWNER_KEY 未设')
if (DISPUTE_TIMEOUT !== 0n && (DISPUTE_TIMEOUT < 1209600n || DISPUTE_TIMEOUT > 7776000n))
  die(`DISPUTE_TIMEOUT_SECONDS 必须 0 或 [14d=1209600, 90d=7776000], 当前 ${DISPUTE_TIMEOUT}`)

const art = JSON.parse(fs.readFileSync(path.join(repoRoot, 'out/ItemTradeEscrow.sol/ItemTradeEscrow.json'), 'utf8'))
const abi = art.abi
const bytecode = art.bytecode.object || art.bytecode

const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: 'dbc' }, { staticNetwork: true })
const wallet = new ethers.Wallet(OWNER_KEY.startsWith('0x') ? OWNER_KEY : '0x' + OWNER_KEY, provider)
const sec = (t) => console.log('\n' + '='.repeat(68) + '\n' + t + '\n' + '='.repeat(68))
const legacy = async (gasLimit) => { const f = await provider.getFeeData(); return { gasPrice: f.gasPrice, type: 0, gasLimit } }

const esc = new ethers.Contract(PROXY, abi, provider)
async function snapshot() {
  const [version, owner, canUp, dlp, fee, arb, feeBps, autoConf] = await Promise.all([
    esc.version(), esc.owner(), esc.canUpgradeAddress(), esc.dlpToken(), esc.feeRecipient(),
    esc.arbiter(), esc.feeBps(), esc.autoConfirmPeriod(),
  ])
  let disputeTimeout = null
  try { disputeTimeout = await esc.disputeTimeout() } catch (_) { /* v1 无此字段 */ }
  return { version, owner, canUp, dlp, fee, arb, feeBps, autoConf, disputeTimeout }
}

async function main() {
  sec('ItemTradeEscrow v1→v2 升级 (claimDisputeTimeout 防恶意冻结)')
  console.log('RPC:', RPC_URL, '| chainId:', CHAIN_ID)
  console.log('Proxy:', PROXY)
  console.log('Signer(owner):', wallet.address)
  if (!eq(wallet.address, EXPECTED.owner)) die(`签名钱包 ${wallet.address} != 期望 owner ${EXPECTED.owner}`)

  const bal = await provider.getBalance(wallet.address)
  console.log('owner DBC balance:', ethers.formatEther(bal))
  if (bal < ethers.parseEther('0.5')) die(`owner 余额过低: ${ethers.formatEther(bal)}`)

  sec('Step 0: 升级前链上快照 + 硬断言')
  const pre = await snapshot()
  console.log('  version       =', pre.version.toString())
  console.log('  owner         =', pre.owner)
  console.log('  canUpgrade    =', pre.canUp)
  console.log('  dlpToken      =', pre.dlp)
  console.log('  feeRecipient  =', pre.fee)
  console.log('  arbiter       =', pre.arb)
  console.log('  feeBps        =', pre.feeBps.toString())
  console.log('  autoConfirm   =', pre.autoConf.toString())
  console.log('  disputeTimeout=', pre.disputeTimeout === null ? '(v1 无)' : pre.disputeTimeout.toString())
  if (pre.version !== 1n) die(`期望升级前 version==1, 实为 ${pre.version}`)
  if (!eq(pre.owner, EXPECTED.owner)) die('链上 owner 不符')
  if (!eq(pre.canUp, EXPECTED.owner)) die('链上 canUpgradeAddress 不符 (应==owner)')
  if (!eq(pre.dlp, EXPECTED.dlpToken)) die('dlpToken 不符')
  if (!eq(pre.fee, EXPECTED.feeRecipient)) die('feeRecipient 不符')
  if (!eq(pre.arb, EXPECTED.arbiter)) die('arbiter 不符')
  if (pre.feeBps !== 250n) die(`feeBps 应 250, 实 ${pre.feeBps}`)
  if (pre.autoConf !== 604800n) die(`autoConfirmPeriod 应 604800, 实 ${pre.autoConf}`)

  if (DRY_RUN) { console.log('\n[DRY_RUN] 快照+断言全过, 未上链。去掉 DRY_RUN=1 即正式升级。'); return }

  sec('Step 1: 部署 v2 implementation')
  const factory = new ethers.ContractFactory(abi, bytecode, wallet)
  const impl = await factory.deploy({ ...await legacy(9_000_000n) })
  await impl.waitForDeployment()
  const implAddr = await impl.getAddress()
  console.log('  new implementation:', implAddr)

  sec('Step 2: upgradeToAndCall(newImpl, 0x) — owner 签')
  const escW = new ethers.Contract(PROXY, abi, wallet)
  const tx1 = await escW.upgradeToAndCall(implAddr, '0x', { ...await legacy(2_500_000n) })
  console.log('  upgrade tx:', tx1.hash)
  const r1 = await tx1.wait()
  if (r1.status !== 1) die('upgradeToAndCall 交易失败 status=0')
  console.log('  upgrade 成功 block', r1.blockNumber)

  sec('Step 3: 升级后校验 (version==2 + config 不变 + disputeTimeout==0)')
  const mid = await snapshot()
  console.log('  version       =', mid.version.toString(), mid.version === 2n ? '✅' : '❌')
  console.log('  disputeTimeout=', mid.disputeTimeout?.toString(), mid.disputeTimeout === 0n ? '✅(出厂关闭)' : '❌')
  const cfgOk = mid.version === 2n && mid.disputeTimeout === 0n &&
    eq(mid.owner, pre.owner) && eq(mid.canUp, pre.canUp) && eq(mid.dlp, pre.dlp) &&
    eq(mid.fee, pre.fee) && eq(mid.arb, pre.arb) && mid.feeBps === pre.feeBps && mid.autoConf === pre.autoConf
  for (const [n, a, b] of [['owner', mid.owner, pre.owner], ['canUpgrade', mid.canUp, pre.canUp],
    ['dlpToken', mid.dlp, pre.dlp], ['feeRecipient', mid.fee, pre.fee], ['arbiter', mid.arb, pre.arb]])
    console.log(`  ${n} 不变:`, eq(a, b) ? '✅' : `❌ ${a} != ${b}`)
  console.log('  feeBps 不变:', mid.feeBps === pre.feeBps ? '✅' : '❌', '| autoConfirm 不变:', mid.autoConf === pre.autoConf ? '✅' : '❌')
  if (!cfgOk) die('升级后校验未通过 — 检查 ❌ 项 (升级已上链, 但状态异常需人工核查)')

  sec(`Step 4: setDisputeTimeout(${DISPUTE_TIMEOUT} 秒 = ${Number(DISPUTE_TIMEOUT) / 86400} 天) — owner 启用`)
  const tx2 = await escW.setDisputeTimeout(DISPUTE_TIMEOUT, { ...await legacy(1_000_000n) })
  console.log('  setDisputeTimeout tx:', tx2.hash)
  const r2 = await tx2.wait()
  if (r2.status !== 1) die('setDisputeTimeout 交易失败 status=0')
  console.log('  启用成功 block', r2.blockNumber)

  sec('Step 5: 最终校验')
  const post = await snapshot()
  console.log('  version       =', post.version.toString())
  console.log('  disputeTimeout=', post.disputeTimeout.toString(), post.disputeTimeout === DISPUTE_TIMEOUT ? '✅' : '❌')
  console.log('  owner/canUp/dlp/fee/arb/feeBps/autoConf 全不变:',
    (eq(post.owner, pre.owner) && eq(post.canUp, pre.canUp) && eq(post.dlp, pre.dlp) && eq(post.fee, pre.fee) &&
     eq(post.arb, pre.arb) && post.feeBps === pre.feeBps && post.autoConf === pre.autoConf) ? '✅' : '❌')
  if (post.version !== 2n || post.disputeTimeout !== DISPUTE_TIMEOUT) die('最终校验未通过')

  sec('升级完成 ✅')
  console.log(JSON.stringify({
    proxy: PROXY, newImplementation: implAddr, version: 2,
    disputeTimeoutSeconds: DISPUTE_TIMEOUT.toString(), disputeTimeoutDays: Number(DISPUTE_TIMEOUT) / 86400,
    upgradeTx: tx1.hash, setTimeoutTx: tx2.hash,
  }, null, 2))
}
main().catch((e) => { console.error('\n升级失败:', e.message || e); process.exit(1) })
