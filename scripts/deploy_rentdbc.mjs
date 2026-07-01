// RentDBC 部署脚本 (2026-07-01) —— DeepLink × DBC 短租结算合约首次部署
// 用法: node scripts/deploy_rentdbc.mjs        (DRY: 校验 + 估算 + 打印计划, 不上链)
//       node scripts/deploy_rentdbc.mjs EXEC   (真部署上链)
//
// 参数照 DLC Rent 镜像 + boss 确认 (2026-06-30/07-01):
//   feeToken=WDBC / pointToken=DLP / oracle/priceSetter/maxPriceAge 同 DLC Rent / owner 最终=0x244f8191 / 升级权=0xa7b0FA65
//   平台费/代付/销毁地址 = 中央新建冷钱包. 部署+配置用 0xa7b0FA65(有 key+gas), 最后 transferOwnership 给 0x244f8191.
import { ethers } from 'ethers'
import fs from 'fs'
import { fileURLToPath } from 'url'
import path from 'path'
const __dir = path.dirname(fileURLToPath(import.meta.url))

const EXEC = process.argv[2] === 'EXEC'
const RPC = 'https://rpc.dbcwallet.io'

// ── 部署参数 (全部已链上验证) ──
const P = {
  dbcAI: '0xa7B9f404653841227AF204a561455113F36d8EC8',          // getMachineInfo calcPoint 已验(两 flag 同值)
  feeToken_WDBC: '0xD7EA4Da7794c7d09bceab4A21a6910D9114Bc936',  // Wrapped DBC, decimals=18 已验
  pointToken_DLP: '0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6', // DLP, decimals=18 已验
  oracle: '0x4bb48d5821cb668B663f74111D06D6B0060d2950',         // 同 DLC Rent
  priceSetter: '0xf050e9C7425A9f6F7496F5dd287F9A3575751Fc6',    // DBCPriceService
  maxPriceAge: 1800,                                             // 同 DLC Rent
  maxRentDuration: 30 * 24 * 3600,                              // boss: 30 天
  platformFeeRecipient: '0x9Da00260B54f65f0e3A13e80462b98DdF7CdeA2A', // 新建
  rentAdmin: '0x1773Ca7dfff081136fc8b8B939cD169442a28b38',            // 新建
  burnAddress: '0x6c8fBDD39A56428cE82eae974fBa2153F10BFCac',          // 新建
  finalOwner: '0x244f8191010a9C20aaE96DC4afa4E1D63983802E',           // 最终 owner = 同 DLC Rent
  // dbcPriceMarkupBps: 默认 0(=不加成, boss), dbcAIQueryIsDeepLink: 默认 false(已验), rentBonusBridge: 0(待白名单)
}

function loadArtifact(rel) { return JSON.parse(fs.readFileSync(path.join(__dir, '..', rel), 'utf8')) }
function bytecode(a) { return (a.bytecode && a.bytecode.object) || a.bytecode }

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC)
  // 部署 key = 升级权钱包 0xa7b0FA65 (中央 NEW_WALLETS_2026-06-13_SECRET.json D.upgrade_key_NEW), 不打印
  const secret = JSON.parse(fs.readFileSync('C:/Project/Fengxia/deeplink2/NEW_WALLETS_2026-06-13_SECRET.json', 'utf8'))
  const kobj = secret.D.upgrade_key_NEW
  const KEY = kobj.private_key || kobj.privateKey || kobj.key || kobj.seed
  const deployer = new ethers.Wallet(KEY, provider)
  const DEPLOYER_ADDR = '0xa7b0FA657331DE35D31b6c91e7EadcB3399c12eB'
  if (deployer.address.toLowerCase() !== DEPLOYER_ADDR.toLowerCase()) throw new Error('deployer key mismatch: ' + deployer.address)

  const rentArt = loadArtifact('out/RentDBC.sol/RentDBC.json')
  const proxyArt = loadArtifact('out/ERC1967Proxy.sol/ERC1967Proxy.json')
  const rentIface = new ethers.Interface(rentArt.abi)

  const bal = await provider.getBalance(deployer.address)
  const fee = await provider.getFeeData()
  const gasPrice = fee.gasPrice || 10000000000n

  console.log('=== RentDBC 部署计划 ===')
  console.log('mode:', EXEC ? 'EXEC (真上链)' : 'DRY (仅校验)')
  console.log('deployer(临时owner+配置):', deployer.address, '| balance:', ethers.formatEther(bal), 'DBC | gasPrice:', gasPrice.toString())
  console.log('finalOwner:', P.finalOwner, '| canUpgradeAddress(initialize默认=deployer):', deployer.address, '→ 同 DLC Rent')
  for (const [k, v] of Object.entries(P)) console.log('  ', k, '=', v)

  // 地址校验
  for (const [k, v] of Object.entries(P)) {
    if (typeof v === 'string' && v.startsWith('0x') && !ethers.isAddress(v)) throw new Error('bad address ' + k + ': ' + v)
  }
  if (bal < ethers.parseEther('5')) throw new Error('deployer DBC gas 不足(<5): ' + ethers.formatEther(bal))

  // initialize calldata: _initialOwner=deployer(临时), dbcAI, feeToken, pointToken, platformFeeRecipient
  const initData = rentIface.encodeFunctionData('initialize', [deployer.address, P.dbcAI, P.feeToken_WDBC, P.pointToken_DLP, P.platformFeeRecipient])
  console.log('\ninitialize calldata:', initData.slice(0, 42), '...')

  if (!EXEC) {
    console.log('\n[DRY] 校验通过。加 EXEC 参数真部署。将执行:')
    console.log('  1) deploy RentDBC impl')
    console.log('  2) deploy ERC1967Proxy(impl, initData) —— owner+canUpgrade=deployer 临时')
    console.log('  3) setOracle/setPriceSetter/setMaxPriceAge(1800)/setMaxRentDuration(30d)/setRentAdmins([payer])/setBurnAddress')
    console.log('  4) transferOwnership(0x244f8191) —— 最终 owner, canUpgrade 留 0xa7b0FA65 (镜像 DLC Rent)')
    return
  }

  const tx0 = { type: 0, gasPrice }
  // 1) impl
  console.log('\n[1/4] 部署 RentDBC impl...')
  const implFactory = new ethers.ContractFactory(rentArt.abi, bytecode(rentArt), deployer)
  const impl = await implFactory.deploy({ ...tx0, gasLimit: 8000000n })
  await impl.waitForDeployment()
  const implAddr = await impl.getAddress()
  console.log('   impl =', implAddr)

  // 2) proxy
  console.log('[2/4] 部署 ERC1967Proxy + initialize...')
  const proxyFactory = new ethers.ContractFactory(proxyArt.abi, bytecode(proxyArt), deployer)
  const proxy = await proxyFactory.deploy(implAddr, initData, { ...tx0, gasLimit: 2000000n })
  await proxy.waitForDeployment()
  const proxyAddr = await proxy.getAddress()
  console.log('   PROXY =', proxyAddr, '  ★ RentDBC 合约地址')

  const c = new ethers.Contract(proxyAddr, rentArt.abi, deployer)
  // 3) setters
  console.log('[3/4] 配置 setters...')
  const setters = [
    ['setOracle', [P.oracle]],
    ['setPriceSetter', [P.priceSetter]],
    ['setMaxPriceAge', [P.maxPriceAge]],
    ['setMaxRentDuration', [P.maxRentDuration]],
    ['setRentAdmins', [[P.rentAdmin], true]],
    ['setBurnAddress', [P.burnAddress]],
  ]
  for (const [fn, args] of setters) {
    const tx = await c[fn](...args, { ...tx0, gasLimit: 300000n })
    await tx.wait()
    console.log('   ', fn, '✓', tx.hash)
  }
  // 4) transfer ownership
  console.log('[4/4] transferOwnership →', P.finalOwner)
  const tt = await c.transferOwnership(P.finalOwner, { ...tx0, gasLimit: 200000n })
  await tt.wait()
  console.log('   ✓', tt.hash)

  // 核验
  console.log('\n=== 链上核验 ===')
  console.log('owner        =', await c.owner(), '(期望', P.finalOwner + ')')
  console.log('canUpgrade   =', await c.canUpgradeAddress(), '(期望 0xa7b0FA65)')
  console.log('feeToken     =', await c.feeToken())
  console.log('pointToken   =', await c.pointToken())
  console.log('oracle       =', await c.oracle())
  console.log('priceSetter  =', await c.priceSetter())
  console.log('maxPriceAge  =', (await c.maxPriceAge()).toString())
  console.log('maxRentDur   =', (await c.maxRentDuration()).toString())
  console.log('platformFee  =', await c.platformFeeRecipient())
  console.log('burnAddress  =', await c.burnAddress())
  console.log('rentAdmin ok =', await c.rentAdmins(P.rentAdmin))
  console.log('version      =', (await c.version()).toString())
  console.log('\n★★ RentDBC PROXY 地址:', proxyAddr, '(填入后端 DBC_RENT_ADDRESS + WDBC 到 DBC_ERC20_ADDRESS)')
}
main().catch(e => { console.error('ERR', e.shortMessage || e.message); process.exit(1) })
