// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interface/IRewardToken.sol";
import "../interface/IDBCAIContract.sol";
import "../interface/IOracle.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice 主链 RentBridge precompile 接口（hash(2052)=0x…0804）。RentDBC 租出/退租时通知主链
/// online-profile 标记机器被 DeepLink 租用，使其享受原生挖矿 +30% 被租加成。
interface IRentBonusBridge {
    function setMachineRentedForDeepLink(string calldata machineId, bool isRented) external;
}

/// @title RentDBC — DBC 支付版短租合约（面向中国矿工机器）
/// @notice 与 DLC `Rent.sol` 完全独立、零耦合。功能对标 DLC 租赁，但：
///   - 支付/销毁币种 = DBC（ERC20 gas 币，带 burnFrom），租金 base 部分按比例销毁；
///   - 不依赖 NFTStaking：机器算力(calcPoint)从 dbcAI 合约读，质押生命周期/slash/白名单/在线检查全部去掉；
///   - 矿工挖矿走 Substrate 主链原生 DBC 挖矿（不在本合约），矿工的 DLP 积分租金收益在退租时结算；
///   - 国家判定(中国机器) + 10 个代付钱包 = DeepLink 后端职责，本合约只限制发起人为授权后端钱包（防绕过）；
///   - 矿工收 DLP 租金的地址由矿工在 DeepLink 自行指定，后端下单时以 `minerPayout` 参数传入。
/// @dev 资金模型（对标 DLC V2）：
///   payer(代付钱包) 转入 DBC(baseFee + platformFee) + DLP 积分(extraFee) →
///   退租按已用时长比例结算：已用 baseFee 的 DBC burnFrom 销毁 / platformFee 给平台 / 已用 extraFee 的 DLP 给矿工 /
///   未用部分 DBC + DLP 退还 payer。
contract RentDBC is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint8 public constant SECONDS_PER_BLOCK = 6;
    uint256 public constant ONE_CALC_POINT_USD_VALUE_PER_MONTH = 5_080;
    uint256 public constant FACTOR = 10_000;
    uint256 public constant USD_DECIMALS = 1_000_000;

    IRewardToken public feeToken; // DBC
    IDBCAIContract public dbcAIContract; // 机器算力/owner 数据源（不依赖 NFTStaking）
    IOracle public oracle; // DBC/USD 兜底价格源
    /// @notice DLP 积分代币（与 DLC 版同一个 Point Token 0x9b09…，矿工租金收益）。initialize 设入，可 owner 调整。
    IERC20 public pointToken;

    address public canUpgradeAddress;
    address public platformFeeRecipient; // 平台费收款地址
    uint256 public lastRentId;
    uint256 public totalBurnedAmount;

    uint256 public platformFeeRate; // 平台费率（百分比，如 10 = 10%）
    uint256 public extraRentFeePerMinuteUSD; // 每分钟额外租金（USD，6 位小数 USD_DECIMALS 口径），矿工 DLP 租金来源
    uint256 public dbcPriceMarkupBps; // DBC 价格加成（basis points，FACTOR=不涨；0 视为 FACTOR 安全兜底）

    struct RentInfo {
        address minerPayout; // 矿工自定义收 DLP 租金地址
        string machineId;
        uint256 rentStartTime;
        uint256 rentEndTime;
        address renter;
        address payer; // 代付钱包（退款回到这里）
    }

    struct FeeInfo {
        uint256 baseFee; // DBC，退租销毁已用部分
        uint256 extraFee; // DLP 积分，退租给矿工
        uint256 platformFee; // DBC，给平台
    }

    struct TokenPriceInfo {
        uint256 price;
        uint256 timestamp;
    }

    TokenPriceInfo public tokenPriceInfo;

    mapping(uint256 => RentInfo) public rentId2RentInfo;
    mapping(uint256 => FeeInfo) public rentId2FeeInfo;
    mapping(string => uint256) public machineId2RentId;
    mapping(address => uint256[]) public renter2RentIds;
    mapping(string => uint256) public machineId2LastRentEndBlock;
    mapping(address => bool) public rentAdmins; // 授权后端代付/发起钱包
    address public priceSetter; // 允许推送 DBC 价格的地址（同 DLC oracle 钱包模式）

    // ── 审计修复新增 storage（append-only，无 __gap）──
    uint256 public activeRentalCount; // 当前活跃租约数；token 不可在有活跃租约时切换（防 escrow/结算币种错配）
    uint256 public maxRentDuration; // 单租约总时长上限（秒）；0 = 不限。防 renewRent 无限延长锁死矿工机器
    // [HIGH 修复] 矿工 payout 转账失败时转入 pending，矿工自行 claim；保证 endRent 永不因恶意 minerPayout 卡死
    mapping(address => uint256) public pendingPointPayout;
    // [R2 HIGH 修复] pending 总额。pending 故意比活跃租约存活更久，故 setPointToken 必须同时 require 此值为 0，
    // 否则换币后旧 DLP 被困、矿工 claim 取不出 / 新币 escrow 被挪用。
    uint256 public totalPendingPointPayout;
    // [R3 HIGH] dbcAI.getMachineInfo 的 isDeepLink 命名空间参数，owner 可调（默认 false=主链原生 DBC 挖矿机器）。
    // ⚠️ 上线前必须用真实 dbcAI(0xa7B9…) fork 验证：对中国 DBC 机器传 false/true 哪个返回正确 calcPoint/owner。
    bool public dbcAIQueryIsDeepLink;
    // [R3 MED] DBC 价格最大有效期（秒），0=不限。>0 时 tokenPriceInfo 超龄则回退 oracle，防喂价 cron 死后用陈旧价。
    uint256 public maxPriceAge;
    // [+30% 桥] 主链 RentBridge precompile 地址（0=禁用）。租出/退租时通知主链标记被租，享受原生挖矿 +30% 加成。
    address public rentBonusBridge;

    event RentMachine(
        address indexed minerPayout,
        uint256 rentId,
        string machineId,
        uint256 rentEndTime,
        address renter,
        uint256 baseFee
    );
    event EndRentMachine(
        address indexed minerPayout, uint256 rentId, string machineId, uint256 rentEndTime, address renter
    );
    event RenewRent(
        address indexed minerPayout,
        string machineId,
        uint256 rentId,
        uint256 additionalRentSeconds,
        uint256 additionalRentFee,
        address renter
    );
    event RentFee(uint256 rentId, address payer, uint256 baseRentFee, uint256 extraRentFee, uint256 platformFee);
    event BurnedFee(string machineId, uint256 rentId, uint256 burnTime, uint256 burnDBCAmount, address renter);
    event ExtraRentFeeTransfer(address indexed minerPayout, uint256 rentId, uint256 amount);
    event PlatformFeeTransfer(address indexed recipient, uint256 rentId, uint256 amount);
    event PayBackFee(string machineId, uint256 rentId, address payer, uint256 amount);
    event PayBackPointFee(string machineId, uint256 rentId, address payer, uint256 amount);
    event RentTime(uint256 totalRentSeconds, uint256 usedRentSeconds);
    event TokenPriceUpdated(uint256 oldPrice, uint256 newPrice, uint256 timestamp);
    event DbcPriceMarkupUpdated(uint256 oldBps, uint256 newBps);
    event PayBackPointFeeShortfall(string machineId, uint256 rentId, uint256 owed, uint256 actual);
    event PointPayoutDeferred(address indexed minerPayout, uint256 rentId, uint256 amount); // 直转失败转 pending
    event PointPayoutClaimed(address indexed minerPayout, uint256 amount);
    event MaxRentDurationUpdated(uint256 oldValue, uint256 newValue);
    event RentBonusBridgeUpdated(address oldBridge, address newBridge);
    event RentBonusNotified(string machineId, bool isRented, bool ok); // 桥调用结果（ok=false 表示桥失败但租用不受影响）

    error ZeroAddress();
    error ZeroCalcPoint();
    error CanNotUpgrade(address);
    error NotRentAdmin();
    error InvalidRentDuration(uint256 rentDuration);
    error RenterAndPayerIsSame();
    error MachineAlreadyRented();
    error MachineCanNotRentWithin30BlocksAfterLastRent();
    error BalanceNotEnough();
    error PointNotEnough();
    error RentEnd();
    error RentNotEnd();
    error NotRenter();
    error RentingNotExist();
    error MachineNotRented();
    error uint256Overflow();
    error TokenLockedWhileRentalsActive();
    error RentDurationCapExceeded(uint256 total, uint256 cap);
    error NotOriginalPayer();
    error NothingToClaim();
    error PendingPayoutsOutstanding();
    error HasObligations();

    modifier onlyRentAdmin() {
        require(rentAdmins[msg.sender], NotRentAdmin());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _dbcAIContract,
        address _feeToken,
        address _pointToken,
        address _platformFeeRecipient
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        require(
            _dbcAIContract != address(0) && _feeToken != address(0) && _pointToken != address(0)
                && _platformFeeRecipient != address(0),
            ZeroAddress()
        );
        feeToken = IRewardToken(_feeToken);
        dbcAIContract = IDBCAIContract(_dbcAIContract);
        pointToken = IERC20(_pointToken);
        platformFeeRecipient = _platformFeeRecipient;
        // [审计修 MED] 升级权默认给 _initialOwner(治理/多签)而非 msg.sender(部署 EOA)——非原子部署/脚本部署时
        //   deployer 热钱包不应静默拿到升级全权(_authorizeUpgrade 只认 canUpgradeAddress,泄露=可升级到恶意 impl 盗全部 escrow)。
        //   部署后仍应 setCanUpgradeAddress 指向多签/timelock 并链上读回确认。
        canUpgradeAddress = _initialOwner;
        platformFeeRate = 10; // 默认 10%
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(newImplementation != address(0), ZeroAddress());
        require(msg.sender == canUpgradeAddress, CanNotUpgrade(msg.sender));
    }

    // ----------------------------- admin setters -----------------------------

    function setCanUpgradeAddress(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        canUpgradeAddress = addr;
    }

    /// @dev [MED 修复] 有活跃租约时禁止切换支付/积分币种，否则托管的旧币种结算时读到新指针会卡死/冻结资金
    function setFeeToken(address _feeToken) external onlyOwner {
        require(_feeToken != address(0), ZeroAddress());
        require(activeRentalCount == 0, TokenLockedWhileRentalsActive());
        feeToken = IRewardToken(_feeToken);
    }

    function setDBCAIContract(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        dbcAIContract = IDBCAIContract(addr);
    }

    /// @dev token-swap 守卫追踪的是"在途义务"(活跃 escrow + 未领 pending)，不是 isRented 的冷却窗口。
    ///      pending 比活跃租约存活更久，故必须同时 require 二者为 0，否则换币会困住旧 DLP。
    function setPointToken(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        require(activeRentalCount == 0, TokenLockedWhileRentalsActive());
        require(totalPendingPointPayout == 0, PendingPayoutsOutstanding());
        pointToken = IERC20(addr);
    }

    function setOracle(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        oracle = IOracle(addr);
    }

    function setPlatformFeeRecipient(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        platformFeeRecipient = addr;
    }

    function setPlatformFeeRate(uint256 rate) external onlyOwner {
        require(rate <= 100, "rate out of range");
        platformFeeRate = rate;
    }

    function setExtraRentFeePerMinuteUSD(uint256 v) external onlyOwner {
        extraRentFeePerMinuteUSD = v;
    }

    /// @notice 单租约总时长上限（秒）。0 = 不限。防 renewRent 把矿工机器无限期锁住。
    function setMaxRentDuration(uint256 v) external onlyOwner {
        uint256 old = maxRentDuration;
        maxRentDuration = v;
        emit MaxRentDurationUpdated(old, v);
    }

    /// @notice [R3] dbcAI 查询命名空间。上线前须 fork 真实 dbcAI 验证再定值。
    function setDbcAIQueryIsDeepLink(bool v) external onlyOwner {
        dbcAIQueryIsDeepLink = v;
    }

    /// @notice [R3] DBC 价格最大有效期（秒）。0=不限；>0 时超龄回退 oracle。
    function setMaxPriceAge(uint256 v) external onlyOwner {
        maxPriceAge = v;
    }

    /// @notice [+30% 桥] 设主链 RentBridge precompile 地址（0=禁用，主链未上桥前保持 0）。
    function setRentBonusBridge(address addr) external onlyOwner {
        emit RentBonusBridgeUpdated(rentBonusBridge, addr);
        rentBonusBridge = addr;
    }

    function setPriceSetter(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        priceSetter = addr;
    }

    function setRentAdmins(address[] calldata admins, bool isAdd) external onlyOwner {
        for (uint256 i = 0; i < admins.length; i++) {
            rentAdmins[admins[i]] = isAdd;
        }
    }

    /// @notice DBC 价格加成（basis points）。FACTOR(10000)=不涨，10600=+6%。范围 [FACTOR, FACTOR*2]。
    function setDbcPriceMarkupBps(uint256 bps) external onlyOwner {
        require(bps >= FACTOR && bps <= FACTOR * 2, "markup out of range");
        uint256 oldBps = dbcPriceMarkupBps;
        dbcPriceMarkupBps = bps;
        emit DbcPriceMarkupUpdated(oldBps, bps);
    }

    function setTokenPriceInUSD(uint256 price) external {
        require(price > 0, "invalid price");
        require(msg.sender == priceSetter, "has no permission");
        uint256 oldPrice = tokenPriceInfo.price;
        tokenPriceInfo.price = price;
        tokenPriceInfo.timestamp = block.timestamp;
        emit TokenPriceUpdated(oldPrice, price, block.timestamp);
    }

    // ----------------------------- pricing -----------------------------

    function getTokenPrice() internal view returns (uint256) {
        if (tokenPriceInfo.timestamp > 0 && tokenPriceInfo.price > 0) {
            // [R3 MED] 配置了 maxPriceAge 且推送价超龄 → 回退 oracle（喂价 cron 死后不再用陈旧价烧错钱）
            if (maxPriceAge != 0 && block.timestamp - tokenPriceInfo.timestamp > maxPriceAge
                && address(oracle) != address(0)) {
                return oracle.getTokenPriceInUSD(10, address(feeToken));
            }
            return tokenPriceInfo.price;
        }
        return oracle.getTokenPriceInUSD(10, address(feeToken));
    }

    /// @notice 基础租金（USD，6 位小数口径），按机器算力计价，对标 DLC getBaseMachinePriceInUSD
    function getBaseMachinePriceInUSD(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        (, uint256 calcPoint,,,,,,,) = dbcAIContract.getMachineInfo(machineId, dbcAIQueryIsDeepLink);
        require(calcPoint > 0, ZeroCalcPoint());

        uint256 totalFactor = FACTOR * FACTOR;
        uint256 rentFeeUSD = USD_DECIMALS * rentSeconds * calcPoint * ONE_CALC_POINT_USD_VALUE_PER_MONTH / 30 / 24
            / 60 / 60 / totalFactor;
        rentFeeUSD = rentFeeUSD * 6 / 10; // 60%
        return rentFeeUSD;
    }

    /// @notice 基础租金（DBC），= USD 价值 / DBC价 × 加成
    function getBaseMachinePrice(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        uint256 rentFeeUSD = getBaseMachinePriceInUSD(machineId, rentSeconds);
        uint256 dbcUSDPrice = getTokenPrice();
        uint256 baseRentFeeDBC = 1e18 * rentFeeUSD / dbcUSDPrice;
        uint256 markup = dbcPriceMarkupBps == 0 ? FACTOR : dbcPriceMarkupBps;
        return baseRentFeeDBC * markup / FACTOR;
    }

    /// @notice 额外租金（USD，6 位小数），矿工 DLP 租金来源（owner 全局配置，替代 NFTStaking 每机配置）
    function getExtraRentFeeInUSD(uint256 rentSeconds) public view returns (uint256) {
        if (extraRentFeePerMinuteUSD == 0) {
            return 0;
        }
        return extraRentFeePerMinuteUSD * (rentSeconds / 60);
    }

    /// @notice 额外租金（DLP 积分），= USD × 1e15（对标 DLC getExtraRentFeeInPoint）
    function getExtraRentFeeInPoint(uint256 rentSeconds) public view returns (uint256) {
        return getExtraRentFeeInUSD(rentSeconds) * 1e15;
    }

    /// @notice 报价：返回总价(DBC) + 各部分。base/platform 为 DBC，extra 为 DLP 积分
    function getRentFees(string memory machineId, uint256 rentSeconds)
        public
        view
        returns (uint256 baseFeeDBC, uint256 platformFeeDBC, uint256 extraFeePoint)
    {
        baseFeeDBC = getBaseMachinePrice(machineId, rentSeconds);
        extraFeePoint = getExtraRentFeeInPoint(rentSeconds);
        uint256 extraFeeDBC = 0;
        {
            uint256 extraUSD = getExtraRentFeeInUSD(rentSeconds);
            if (extraUSD > 0) {
                extraFeeDBC = 1e18 * extraUSD / getTokenPrice();
            }
        }
        platformFeeDBC = (baseFeeDBC + extraFeeDBC) * platformFeeRate / 100;
    }

    /// @notice 平台代付总成本，全部折算成 DLP 积分(point)口径，供后端按「租客付 = 成本 × 加价」定价(B 方案)，
    ///   结构上保证 revenue ≥ cost、不依赖链下价格源。base+platform 的 DBC 按当前 DBC 价折 USD(6dec) 再按
    ///   1e15/USD(与 getExtraRentFeeInPoint 同口径)折积分，加上 extra 积分。
    /// @dev DBC(1e18) × dbcUSDPrice(USD 6dec/DBC) / 1e18 = USD(6dec)；× 1e15 = point。整数除法向下取整(亚单位)，
    ///   后端在 ×加价后 Math.ceil 吸收，绝不令平台少收。
    function getRentCostInPoint(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        (uint256 baseFeeDBC, uint256 platformFeeDBC, uint256 extraFeePoint) = getRentFees(machineId, rentSeconds);
        uint256 dbcCostPoint = (baseFeeDBC + platformFeeDBC) * getTokenPrice() * 1e15 / 1e18;
        return dbcCostPoint + extraFeePoint;
    }

    // ----------------------------- rent -----------------------------

    function isRented(string memory machineId) public view returns (bool) {
        uint256 rentId = machineId2RentId[machineId];
        if (rentId2RentInfo[rentId].renter != address(0)) {
            return true;
        }
        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock > 0) {
            return block.number <= lastRentEndBlock + 30;
        }
        return false;
    }

    function getNextRentId() internal returns (uint256) {
        require(lastRentId < type(uint256).max, uint256Overflow());
        lastRentId += 1;
        return lastRentId;
    }

    /// @notice 代付租用（后端代付钱包调用）。country 门在后端，本合约只允许授权发起人。
    /// @param renter 实际租客
    /// @param minerPayout 矿工自定义收 DLP 租金地址
    /// @param machineId 机器 ID
    /// @param rentSeconds 租用时长
    function rentProxy(address renter, address minerPayout, string calldata machineId, uint256 rentSeconds)
        external
        onlyRentAdmin
        nonReentrant
    {
        require(msg.sender != renter, RenterAndPayerIsSame());
        // [审计修 HIGH] renter 必须非零：isRented() 用 rentId2RentInfo.renter!=address(0) 当活跃哨兵，
        //   若后端误传 renter=0 → 租约建立但 isRented 返 false → 同机可被双租 + 第一笔 escrow 成孤儿永久锁死
        //   + activeRentalCount 卡住(setFeeToken/rescueToken 永久锁)。renter 是后端参数,不能信,合约层兜底。
        require(renter != address(0), ZeroAddress());
        require(minerPayout != address(0), ZeroAddress());
        require(rentSeconds >= 10 minutes && rentSeconds <= 10 hours, InvalidRentDuration(rentSeconds));
        require(!isRented(machineId), MachineAlreadyRented());

        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock != 0) {
            require(block.number > lastRentEndBlock + 30, MachineCanNotRentWithin30BlocksAfterLastRent());
        }

        (uint256 baseRentFee, uint256 platformFee, uint256 extraRentFeeInPoint) = getRentFees(machineId, rentSeconds);
        uint256 totalDBC = baseRentFee + platformFee;

        address payer = msg.sender;
        require(feeToken.balanceOf(payer) >= totalDBC, BalanceNotEnough());
        require(pointToken.balanceOf(payer) >= extraRentFeeInPoint, PointNotEnough());

        uint256 _now = block.timestamp;
        uint256 rentId = getNextRentId();
        rentId2RentInfo[rentId] = RentInfo({
            minerPayout: minerPayout,
            machineId: machineId,
            rentStartTime: _now,
            rentEndTime: _now + rentSeconds,
            renter: renter,
            payer: payer
        });
        rentId2FeeInfo[rentId] = FeeInfo({baseFee: baseRentFee, extraFee: extraRentFeeInPoint, platformFee: platformFee});
        machineId2RentId[machineId] = rentId;
        renter2RentIds[renter].push(rentId);
        activeRentalCount += 1;

        SafeERC20.safeTransferFrom(feeToken, payer, address(this), totalDBC);
        if (extraRentFeeInPoint > 0) {
            SafeERC20.safeTransferFrom(pointToken, payer, address(this), extraRentFeeInPoint);
        }

        emit RentFee(rentId, payer, baseRentFee, extraRentFeeInPoint, platformFee);
        emit RentMachine(minerPayout, rentId, machineId, _now + rentSeconds, renter, baseRentFee);

        // [+30% 桥] 通知主链该机被 DeepLink 租用（享受原生挖矿 +30% 加成）。失败不影响租用。
        _notifyRentBonus(machineId, true);
    }

    function renewRent(string calldata machineId, uint256 additionalRentSeconds) external onlyRentAdmin nonReentrant {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo storage rentInfo = rentId2RentInfo[rentId];
        require(rentInfo.rentEndTime > block.timestamp, RentEnd());
        require(isRented(machineId), MachineNotRented());
        require(
            additionalRentSeconds >= 10 minutes && additionalRentSeconds <= 10 hours,
            InvalidRentDuration(additionalRentSeconds)
        );
        // [MED-HIGH 修复] 续租必须由原 payer 钱包发起：续租资金从 msg.sender 扣、退款回 rentInfo.payer，
        // 若允许其他 admin 钱包续租会导致 10 钱包池间资金错配（B 出钱、A 收退款）。
        require(msg.sender == rentInfo.payer, NotOriginalPayer());
        // [LOW→MED 修复] 总时长上限，防无限续租锁死矿工机器
        if (maxRentDuration != 0) {
            uint256 newTotal = (rentInfo.rentEndTime + additionalRentSeconds) - rentInfo.rentStartTime;
            require(newTotal <= maxRentDuration, RentDurationCapExceeded(newTotal, maxRentDuration));
        }

        (uint256 baseRentFee, uint256 platformFee, uint256 extraRentFeeInPoint) =
            getRentFees(machineId, additionalRentSeconds);
        uint256 totalDBC = baseRentFee + platformFee;

        require(feeToken.balanceOf(msg.sender) >= totalDBC, BalanceNotEnough());
        require(pointToken.balanceOf(msg.sender) >= extraRentFeeInPoint, PointNotEnough());

        rentInfo.rentEndTime += additionalRentSeconds;

        FeeInfo storage feeInfo = rentId2FeeInfo[rentId];
        feeInfo.baseFee += baseRentFee;
        feeInfo.extraFee += extraRentFeeInPoint;
        feeInfo.platformFee += platformFee;

        SafeERC20.safeTransferFrom(feeToken, msg.sender, address(this), totalDBC);
        if (extraRentFeeInPoint > 0) {
            SafeERC20.safeTransferFrom(pointToken, msg.sender, address(this), extraRentFeeInPoint);
        }

        emit RenewRent(rentInfo.minerPayout, machineId, rentId, additionalRentSeconds, totalDBC, rentInfo.renter);
    }

    /// @notice 退租结算。仅租客或原 payer 可提前退（按已用时长比例）；其他人需等租期结束。
    function endRentMachine(string calldata machineId) external nonReentrant {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        require(rentInfo.rentEndTime > 0, RentingNotExist());

        address payer = rentInfo.payer;
        // [HIGH 修复] 去掉 rentAdmin 提前退租豁免：仅租客/原 payer 可提前结束（防单个热钱包踢掉任意租客）；
        // 其余（含其他 admin）需等到期后才能结束（清理用途）。
        if (msg.sender != rentInfo.renter && msg.sender != payer) {
            require(rentInfo.rentEndTime <= block.timestamp, RentNotEnd());
        }

        FeeInfo memory feeInfo = rentId2FeeInfo[rentId];
        uint256 pointBalance = pointToken.balanceOf(address(this));
        uint256 availablePoint = feeInfo.extraFee > pointBalance ? pointBalance : feeInfo.extraFee;
        // [MED 观测] DLP 余额不足以覆盖本租约记录额 → emit shortfall 供后端对账（对标 DLC PayBackExtraFeeShortfall）
        if (availablePoint < feeInfo.extraFee) {
            emit PayBackPointFeeShortfall(machineId, rentId, feeInfo.extraFee, availablePoint);
        }

        uint256 _now = block.timestamp;
        uint256 burnAmount;
        uint256 platformAmount;
        uint256 minerAmount;
        uint256 paybackDBC;
        uint256 paybackPoint;
        uint256 rentDuration = rentInfo.rentEndTime - rentInfo.rentStartTime;

        if (_now < rentInfo.rentEndTime) {
            uint256 usedDuration = _now - rentInfo.rentStartTime;
            burnAmount = (feeInfo.baseFee * usedDuration) / rentDuration;
            minerAmount = (availablePoint * usedDuration) / rentDuration;
            platformAmount = (feeInfo.platformFee * usedDuration) / rentDuration;
            // payback = 精确补集，保证每个币池 in==out，无 wei 创造/滞留
            paybackDBC = (feeInfo.baseFee - burnAmount) + (feeInfo.platformFee - platformAmount);
            paybackPoint = availablePoint - minerAmount;
            emit RentTime(rentDuration, usedDuration);
        } else {
            burnAmount = feeInfo.baseFee;
            platformAmount = feeInfo.platformFee;
            minerAmount = availablePoint;
        }

        // ── CEI：先清状态 + 计数，再做外部调用 ──
        machineId2LastRentEndBlock[machineId] = block.number;
        delete rentId2RentInfo[rentId];
        delete rentId2FeeInfo[rentId];
        delete machineId2RentId[machineId];
        if (activeRentalCount > 0) {
            activeRentalCount -= 1;
        }

        // 退款给 payer
        if (paybackDBC > 0) {
            SafeERC20.safeTransfer(feeToken, payer, paybackDBC);
            emit PayBackFee(machineId, rentId, payer, paybackDBC);
        }
        if (paybackPoint > 0) {
            SafeERC20.safeTransfer(pointToken, payer, paybackPoint);
            emit PayBackPointFee(machineId, rentId, payer, paybackPoint);
        }
        // 已用 baseFee 的 DBC 销毁
        if (burnAmount > 0) {
            feeToken.approve(address(this), burnAmount);
            feeToken.burnFrom(address(this), burnAmount);
            emit BurnedFee(machineId, rentId, block.timestamp, burnAmount, rentInfo.renter);
            totalBurnedAmount += burnAmount;
        }
        // [HIGH 修复] 矿工 DLP payout 用 try/catch：失败（黑名单/合约 revert）转 pending 由矿工自行 claim，
        // 保证 endRent 永不因恶意/失效 minerPayout 卡死（机器解锁 + 本金结算照常完成）。
        if (minerAmount > 0) {
            try pointToken.transfer(rentInfo.minerPayout, minerAmount) returns (bool ok) {
                if (ok) {
                    emit ExtraRentFeeTransfer(rentInfo.minerPayout, rentId, minerAmount);
                } else {
                    _deferPayout(rentInfo.minerPayout, rentId, minerAmount);
                }
            } catch {
                _deferPayout(rentInfo.minerPayout, rentId, minerAmount);
            }
        }
        // platformFee 给平台
        if (platformAmount > 0) {
            SafeERC20.safeTransfer(feeToken, platformFeeRecipient, platformAmount);
            emit PlatformFeeTransfer(platformFeeRecipient, rentId, platformAmount);
        }

        emit EndRentMachine(rentInfo.minerPayout, rentId, machineId, rentInfo.rentEndTime, rentInfo.renter);

        // [+30% 桥] 通知主链取消被租标记（恢复无加成）。失败不影响退租。
        _notifyRentBonus(machineId, false);
    }

    /// @dev DLP payout 直转失败时转 pending，并累计总额（setPointToken 守卫依赖此值）
    function _deferPayout(address minerPayout, uint256 rentId, uint256 amount) internal {
        pendingPointPayout[minerPayout] += amount;
        totalPendingPointPayout += amount;
        emit PointPayoutDeferred(minerPayout, rentId, amount);
    }

    /// @dev [+30% 桥] 通知主链 RentBridge 标记机器被租/退租。try/catch 包裹：桥未配置(0)或失败都不阻塞
    ///      租用/退租（+30% 是 bonus，非关键路径）。仅在 CEI 状态更新完成后调用。
    function _notifyRentBonus(string memory machineId, bool rented) internal {
        address bridge = rentBonusBridge;
        if (bridge == address(0)) {
            return;
        }
        try IRentBonusBridge(bridge).setMachineRentedForDeepLink(machineId, rented) {
            emit RentBonusNotified(machineId, rented, true);
        } catch {
            emit RentBonusNotified(machineId, rented, false);
        }
    }

    /// @notice 矿工领取因 payout 直转失败（黑名单/合约 revert）而暂存的 DLP 租金
    function claimPointPayout() external nonReentrant {
        uint256 amount = pendingPointPayout[msg.sender];
        require(amount > 0, NothingToClaim());
        pendingPointPayout[msg.sender] = 0;
        totalPendingPointPayout -= amount;
        SafeERC20.safeTransfer(pointToken, msg.sender, amount);
        emit PointPayoutClaimed(msg.sender, amount);
    }

    /// @notice owner 救援被困/误转入的代币（仅在无活跃租约且无未领 pending 时；此时合约无任何在途义务）。
    /// @dev 解决审计 LOW：误转入/shortfall 残留/旧币种残留的 DLP/DBC 否则永久冻结。
    function rescueToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), ZeroAddress());
        require(activeRentalCount == 0 && totalPendingPointPayout == 0, HasObligations());
        SafeERC20.safeTransfer(IERC20(token), to, amount);
    }

    /// @notice [R3 MED] owner 强制清理卡死的租约状态（对标 DLC forceCleanupRentInfoByOwner）。
    /// @dev 仅用于 endRentMachine 因外部原因（token 暂停/平台收款方 revert 等）反复 revert 导致机器永久卡 rented
    ///      时的应急恢复。清状态 + 解 activeRentalCount，escrow 残留之后可经 rescueToken 取回（须先无义务）。
    function forceCleanupRentInfoByOwner(string calldata machineId) external onlyOwner {
        uint256 rentId = machineId2RentId[machineId];
        require(rentId2RentInfo[rentId].rentEndTime > 0, RentingNotExist());
        delete rentId2RentInfo[rentId];
        delete rentId2FeeInfo[rentId];
        delete machineId2RentId[machineId];
        machineId2LastRentEndBlock[machineId] = block.number;
        if (activeRentalCount > 0) {
            activeRentalCount -= 1;
        }
        emit EndRentMachine(address(0), rentId, machineId, 0, address(0));
        // [+30% 桥] 卡死机器强制清理后也取消被租标记
        _notifyRentBonus(machineId, false);
    }

    function getRentInfo(string calldata machineId) external view returns (RentInfo memory) {
        return rentId2RentInfo[machineId2RentId[machineId]];
    }

    function getRenter(string calldata machineId) external view returns (address) {
        return rentId2RentInfo[machineId2RentId[machineId]].renter;
    }

    function version() external pure returns (uint256) {
        // v5: +30% 被租挖矿加成桥（rentProxy/endRent 通知主链 RentBridge，guarded try/catch 不阻塞）
        return 5;
    }
}
