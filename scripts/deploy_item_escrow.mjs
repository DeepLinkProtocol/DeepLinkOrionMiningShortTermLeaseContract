#!/usr/bin/env node
// ItemTradeEscrow 全新部署脚本 (UUPS proxy + initialize) — 道具交易链上托管合约
// 用法: cd 合约仓库目录, .env 设好下列变量, forge build, 然后 node scripts/deploy_item_escrow.mjs
//
//   DEPLOYER_KEY      部署者私钥 (付 gas, 可与 owner 不同; 用完即弃也行)
//   ESCROW_OWNER      合约 owner 地址 (治理: setFee/arbiter/upgrade, = canUpgradeAddress 初值) ★必填
//   DLP_TOKEN         结算代币地址, 默认 Point 0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6
//   FEE_RECIPIENT     2.5% 手续费收款地址, 默认 0xCAA5cB0983cd544283346c82f3870931a295365B (中央冷钱包)
//   ARBITER           纠纷裁决地址, 默认 0xB5A5ab31E5dEd47Cd61de1bbD62b1Dd161daA6f2 (中央, 部署后迁 KMS)
//   RPC_URL/CHAIN_ID  默认主网 rpc.dbcwallet.io / 19880818; 测试网改 19850818 + 对应 RPC
//
// ⚠️ 资金合约: 上主网前必须多专家审计 + boss 批准。本脚本只部署, 不碰任何已有合约。
// 用 ethers.js (DBC RPC 对 cast 有 "duplicate field" 兼容问题); 全部 type:0 legacy tx。

import { ethers } from 'ethers'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import dotenv from 'dotenv'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(__dirname, '..')
dotenv.config({ path: path.join(repoRoot, '.env') })

const RPC_URL = process.env.RPC_URL || 'https://rpc.dbcwallet.io'
const CHAIN_ID = parseInt(process.env.CHAIN_ID || '19880818')
const DEPLOYER_KEY = process.env.DEPLOYER_KEY || process.env.OWNER_KEY
const ESCROW_OWNER = process.env.ESCROW_OWNER
const DLP_TOKEN = process.env.DLP_TOKEN || '0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6'
const FEE_RECIPIENT = process.env.FEE_RECIPIENT || '0xCAA5cB0983cd544283346c82f3870931a295365B'
const ARBITER = process.env.ARBITER || '0xB5A5ab31E5dEd47Cd61de1bbD62b1Dd161daA6f2'
const DRY_RUN = process.env.DRY_RUN === '1'   // 只校验参数+链上探针, 不上链

// boss 2026-06-13 拍板的主网真值 — 硬断言, 防 .env 填错/大小写/粘错/残留 override (主网填错不可逆无救)
const MAINNET_CHAIN_ID = 19880818
const EXPECTED = {
  owner: '0x244f8191010a9C20aaE96DC4afa4E1D63983802E',
  dlpToken: '0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6',
  feeRecipient: '0xCAA5cB0983cd544283346c82f3870931a295365B',
  arbiter: '0xB5A5ab31E5dEd47Cd61de1bbD62b1Dd161daA6f2',
}
const eqAddr = (a, b) => !!a && !!b && a.toLowerCase() === b.toLowerCase()

function die(m) { console.error('FATAL:', m); process.exit(1) }
if (!DEPLOYER_KEY) die('DEPLOYER_KEY (或 OWNER_KEY) 未设')
if (!ESCROW_OWNER || !ethers.isAddress(ESCROW_OWNER)) die('ESCROW_OWNER 未设/非法 (合约 owner 地址)')
for (const [n, v] of [['DLP_TOKEN', DLP_TOKEN], ['FEE_RECIPIENT', FEE_RECIPIENT], ['ARBITER', ARBITER]])
  if (!ethers.isAddress(v)) die(`${n} 非法: ${v}`)
// [终审 BLOCKER] owner 硬断言: 任何网络都强制 = boss 拍板地址 (owner 填错=治理+升级权落错方, 主网真钱不可逆)
if (!eqAddr(ESCROW_OWNER, EXPECTED.owner)) die(`ESCROW_OWNER 必须 = ${EXPECTED.owner} (boss 2026-06-13 拍板), 当前=${ESCROW_OWNER}`)
// [终审 HIGH] 主网链路: 三地址必须 = 期望真值 (测试网才允许 override; 防 .env 残留测试网值静默覆盖默认)
if (CHAIN_ID === MAINNET_CHAIN_ID) {
  for (const [n, got, exp] of [['DLP_TOKEN', DLP_TOKEN, EXPECTED.dlpToken], ['FEE_RECIPIENT', FEE_RECIPIENT, EXPECTED.feeRecipient], ['ARBITER', ARBITER, EXPECTED.arbiter]])
    if (!eqAddr(got, exp)) die(`主网部署 ${n} 必须 = ${exp}, 当前=${got} (检查 .env 是否残留 override)`)
}

const escArt = JSON.parse(fs.readFileSync(path.join(repoRoot, 'out/ItemTradeEscrow.sol/ItemTradeEscrow.json'), 'utf8'))
const proxyArt = JSON.parse(fs.readFileSync(path.join(repoRoot, 'out/ERC1967Proxy.sol/ERC1967Proxy.json'), 'utf8'))
const escBytecode = escArt.bytecode.object || escArt.bytecode
const escAbi = escArt.abi
const proxyBytecode = proxyArt.bytecode.object || proxyArt.bytecode
const proxyAbi = proxyArt.abi

const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: 'dbc' }, { staticNetwork: true })
const dkey = DEPLOYER_KEY.startsWith('0x') ? DEPLOYER_KEY : '0x' + DEPLOYER_KEY
const wallet = new ethers.Wallet(dkey, provider)

function sectionLog(t) { console.log('\n' + '='.repeat(70) + '\n' + t + '\n' + '='.repeat(70)) }
async function legacy(gasLimit) { const f = await provider.getFeeData(); return { gasPrice: f.gasPrice, type: 0, gasLimit } }

async function main() {
  sectionLog('ItemTradeEscrow 全新部署 (UUPS)')
  console.log('RPC:', RPC_URL, '| chainId:', CHAIN_ID)
  console.log('Deployer:', wallet.address)
  console.log('ESCROW_OWNER:', ESCROW_OWNER)
  console.log('DLP_TOKEN:', DLP_TOKEN)
  console.log('FEE_RECIPIENT:', FEE_RECIPIENT)
  console.log('ARBITER:', ARBITER)

  const bal = await provider.getBalance(wallet.address)
  console.log('Deployer DBC balance:', ethers.formatEther(bal))
  if (bal < ethers.parseEther('0.5')) throw new Error(`Deployer 余额过低: ${ethers.formatEther(bal)} DBC`)

  // [终审 HIGH] DLP_TOKEN 链上探针: 确认确实是 ERC20 合约 (防填成 EOA/错合约/测试网空地址)
  const code = await provider.getCode(DLP_TOKEN)
  if (!code || code === '0x') throw new Error(`DLP_TOKEN ${DLP_TOKEN} 链上无合约代码 — 地址错或网络错`)
  try {
    const erc = new ethers.Contract(DLP_TOKEN, ['function symbol() view returns (string)', 'function decimals() view returns (uint8)'], provider)
    const [sym, dec] = await Promise.all([erc.symbol(), erc.decimals()])
    console.log(`DLP_TOKEN 探针: symbol=${sym} decimals=${dec} (人工核对: 应是 DLP/Point, decimals=18)`)
    if (Number(dec) !== 18) throw new Error(`DLP_TOKEN decimals=${dec} != 18 — 金额单位会算错, 中止`)
  } catch (e) { throw new Error(`DLP_TOKEN ${DLP_TOKEN} symbol()/decimals() 失败, 可能不是 ERC20: ${e.message}`) }
  // [终审 MED] deployer 不应是 owner/治理私钥
  if (eqAddr(wallet.address, ESCROW_OWNER)) console.warn('⚠️ deployer == owner: 建议用独立一次性 deployer, 勿用 owner/治理私钥当部署者')
  if (DRY_RUN) { console.log('\n[DRY_RUN] 参数 + 链上探针校验全通过, 未上链。去掉 DRY_RUN=1 即正式部署。'); return }

  // 1. 部署 implementation
  sectionLog('Step 1: 部署 implementation')
  const implFactory = new ethers.ContractFactory(escAbi, escBytecode, wallet)
  const impl = await implFactory.deploy({ ...await legacy(8_000_000n) })
  await impl.waitForDeployment()
  const implAddr = await impl.getAddress()
  console.log('implementation:', implAddr)

  // 2. 构造 initialize calldata + 部署 ERC1967Proxy
  sectionLog('Step 2: 部署 ERC1967Proxy (initialize 原子执行)')
  const iface = new ethers.Interface(escAbi)
  const initData = iface.encodeFunctionData('initialize', [DLP_TOKEN, FEE_RECIPIENT, ARBITER, ESCROW_OWNER])
  const proxyFactory = new ethers.ContractFactory(proxyAbi, proxyBytecode, wallet)
  const proxy = await proxyFactory.deploy(implAddr, initData, { ...await legacy(2_000_000n) })
  await proxy.waitForDeployment()
  const proxyAddr = await proxy.getAddress()
  console.log('★ PROXY (合约地址, 前后端用这个):', proxyAddr)

  // 3. 验证
  sectionLog('Step 3: 验证链上状态')
  const esc = new ethers.Contract(proxyAddr, escAbi, provider)
  const [ver, dlp, fee, arb, owner, feeBps, autoConf, canUp] = await Promise.all([
    esc.version(), esc.dlpToken(), esc.feeRecipient(), esc.arbiter(),
    esc.owner(), esc.feeBps(), esc.autoConfirmPeriod(), esc.canUpgradeAddress(),
  ])
  const eq = (a, b) => a.toLowerCase() === b.toLowerCase()
  const checks = [
    ['version==1', ver === 1n],
    ['dlpToken', eq(dlp, DLP_TOKEN)],
    ['feeRecipient', eq(fee, FEE_RECIPIENT)],
    ['arbiter', eq(arb, ARBITER)],
    ['owner', eq(owner, ESCROW_OWNER)],
    ['feeBps==250', feeBps === 250n],
    ['autoConfirmPeriod==7d', autoConf === 604800n],
    ['canUpgradeAddress==owner', eq(canUp, ESCROW_OWNER)],
  ]
  let allOk = true
  for (const [n, ok] of checks) { console.log(ok ? '  ✅' : '  ❌', n); if (!ok) allOk = false }
  if (!allOk) throw new Error('链上验证未全通过 — 检查上方 ❌ 项')

  sectionLog('部署完成 ✅')
  console.log(JSON.stringify({ proxy: proxyAddr, implementation: implAddr, chainId: CHAIN_ID,
    dlpToken: DLP_TOKEN, feeRecipient: FEE_RECIPIENT, arbiter: ARBITER, owner: ESCROW_OWNER }, null, 2))
  console.log('\n下一步: ① 记录 proxy 地址到前后端 config ② arbiter 私钥迁 KMS ③ 前端/后端接 proxy')
}

main().catch((e) => { console.error('\n部署失败:', e.message || e); process.exit(1) })
