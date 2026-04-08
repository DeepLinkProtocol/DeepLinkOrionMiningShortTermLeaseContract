// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IDBCAIContract.sol";

/// @title FreeRental - 免质押 GPU 出租合约
/// @notice 不需要质押 DLC/NFT，机器注册后即可被租赁
/// @dev UUPS 代理模式，独立于 NFTStaking/Rent 合约
contract FreeRental is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant VERSION = 2;
    uint256 public constant PLATFORM_FEE_PCT = 25; // 平台提成 25%，机主得定价部分
    string public constant PROJECT_NAME = "DeepLinkEVM";

    // ── 代币 ──
    IERC20 public pointToken; // DLP Point Token（积分）

    // ── 外部合约 ──
    IDBCAIContract public dbcAIContract; // DDN 链上注册/在线状态

    // ── 权限 ──
    address public canUpgradeAddress;
    mapping(address => bool) public admins; // 管理员（注册/惩罚/定价）

    // ── 机器注册 ──
    struct MachineInfo {
        address owner;           // 机主钱包（收益接收方）
        uint256 pricePerHourUSD; // 机器定价（USD，6位精度，如 500000 = $0.5）
        bool registered;         // 是否已注册
        bool enabled;            // 是否启用（管理员可禁用）
    }
    mapping(string => MachineInfo) public machines;
    uint256 public machineCount;

    // ── 租赁 ──
    struct RentInfo {
        string machineId;
        address owner;           // 机主
        address renter;          // 租户
        uint256 rentStartTime;
        uint256 rentEndTime;
        uint256 totalPointPaid;  // 租户支付的总积分（含平台提成）
        uint256 ownerPoint;      // 机主应得积分（定价部分）
        uint256 platformPoint;   // 平台提成
        bool ended;              // 是否已结束
    }
    uint256 public lastRentId;
    mapping(uint256 => RentInfo) public rentId2RentInfo;
    mapping(string => uint256) public machineId2RentId; // 当前活跃租赁
    mapping(string => bool) public machineIsRented;

    // ── 惩罚 ──
    struct SlashInfo {
        string machineId;
        address renter;
        uint256 slashAmount;     // 罚扣积分（最多 24h 租金）
        uint256 refundAmount;    // 退还租户积分
        uint256 createdAt;
        bool executed;
    }
    mapping(string => SlashInfo) public machineId2SlashInfo;
    mapping(address => bool) public slashAdmins; // DDN 惩罚管理员

    // ── 收益 ──
    address public platformWallet; // 平台收款钱包
    mapping(address => uint256) public ownerPendingIncome; // 待领取收益
    mapping(address => uint256) public ownerTotalClaimed;  // 已领取总额

    // ── Events ──
    event MachineRegistered(string machineId, address indexed owner);
    event MachineRemoved(string machineId, address indexed owner);
    event MachineEnabled(string machineId, bool enabled);
    event PriceUpdated(string machineId, uint256 newPriceUSD);

    event RentStarted(uint256 indexed rentId, string machineId, address indexed renter, uint256 rentEndTime, uint256 totalPoint);
    event RentEnded(uint256 indexed rentId, string machineId, address indexed renter, uint256 ownerPoint, uint256 platformPoint);
    event RentEndedBySlash(uint256 indexed rentId, string machineId, address indexed renter, uint256 slashAmount, uint256 refundAmount);

    event IncomeClaimed(address indexed owner, uint256 amount);
    event SlashExecuted(string machineId, address indexed renter, uint256 slashAmount);

    // ── Modifiers ──
    modifier onlyAdmin() {
        require(admins[msg.sender] || msg.sender == owner(), "not admin");
        _;
    }

    modifier onlySlashAdmin() {
        require(slashAdmins[msg.sender] || msg.sender == owner(), "not slash admin");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _pointToken, address _platformWallet) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        pointToken = IERC20(_pointToken);
        platformWallet = _platformWallet;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == canUpgradeAddress || msg.sender == owner(), "not authorized to upgrade");
    }

    // ══════════════════════════════════════════════════════════════
    //  管理员设置
    // ══════════════════════════════════════════════════════════════

    function setCanUpgradeAddress(address addr) external onlyOwner {
        canUpgradeAddress = addr;
    }

    function setAdmins(address[] calldata addrs, bool enabled) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            admins[addrs[i]] = enabled;
        }
    }

    function setSlashAdmins(address[] calldata addrs, bool enabled) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            slashAdmins[addrs[i]] = enabled;
        }
    }

    function setPlatformWallet(address wallet) external onlyOwner {
        require(wallet != address(0), "zero address");
        platformWallet = wallet;
    }

    function setDbcAIContract(address addr) external onlyOwner {
        dbcAIContract = IDBCAIContract(addr);
    }

    // ══════════════════════════════════════════════════════════════
    //  机器注册/移除（管理员操作，机主通过后端 API 触发）
    // ══════════════════════════════════════════════════════════════

    /// @notice 注册免质押机器
    /// @param machineId 机器 ID（64位 hex）
    /// @param ownerWallet 机主钱包地址（收益接收方）
    /// @param pricePerHourUSD 每小时定价（USD，6位精度，500000 = $0.5）
    function registerMachine(
        string calldata machineId,
        address ownerWallet,
        uint256 pricePerHourUSD
    ) external onlyAdmin {
        require(!machines[machineId].registered, "already registered");
        require(ownerWallet != address(0), "zero owner");
        require(pricePerHourUSD > 0, "zero price");

        machines[machineId] = MachineInfo({
            owner: ownerWallet,
            pricePerHourUSD: pricePerHourUSD,
            registered: true,
            enabled: true
        });
        machineCount++;

        // 向 dbcAI 注册机器（DDN 检测节点通过此识别机器）
        if (address(dbcAIContract) != address(0)) {
            try dbcAIContract.reportStakingStatus(PROJECT_NAME, NFTStaking.StakingType.ShortTerm, machineId, 1, true) {} catch {}
        }

        emit MachineRegistered(machineId, ownerWallet);
    }

    /// @notice 批量注册
    function registerMachines(
        string[] calldata machineIds,
        address[] calldata owners,
        uint256 pricePerHourUSD
    ) external onlyAdmin {
        require(machineIds.length == owners.length, "length mismatch");
        for (uint256 i = 0; i < machineIds.length; i++) {
            if (!machines[machineIds[i]].registered && owners[i] != address(0)) {
                machines[machineIds[i]] = MachineInfo({
                    owner: owners[i],
                    pricePerHourUSD: pricePerHourUSD,
                    registered: true,
                    enabled: true
                });
                machineCount++;
                emit MachineRegistered(machineIds[i], owners[i]);
            }
        }
    }

    /// @notice 移除机器（需未在租赁中）
    function removeMachine(string calldata machineId) external onlyAdmin {
        MachineInfo storage m = machines[machineId];
        require(m.registered, "not registered");
        require(!machineIsRented[machineId], "currently rented");

        address prevOwner = m.owner;
        delete machines[machineId];
        if (machineCount > 0) machineCount--;

        // 从 dbcAI 注销
        if (address(dbcAIContract) != address(0)) {
            try dbcAIContract.reportStakingStatus(PROJECT_NAME, NFTStaking.StakingType.ShortTerm, machineId, 1, false) {} catch {}
        }

        emit MachineRemoved(machineId, prevOwner);
    }

    /// @notice 启用/禁用机器
    function setMachineEnabled(string calldata machineId, bool enabled) external onlyAdmin {
        require(machines[machineId].registered, "not registered");
        machines[machineId].enabled = enabled;
        emit MachineEnabled(machineId, enabled);
    }

    /// @notice 修改机器定价
    function setMachinePrice(string calldata machineId, uint256 pricePerHourUSD) external onlyAdmin {
        require(machines[machineId].registered, "not registered");
        require(pricePerHourUSD > 0, "zero price");
        machines[machineId].pricePerHourUSD = pricePerHourUSD;
        emit PriceUpdated(machineId, pricePerHourUSD);
    }

    // ══════════════════════════════════════════════════════════════
    //  租赁（由平台后端通过 admin 钱包调用）
    // ══════════════════════════════════════════════════════════════

    /// @notice 开始租赁
    /// @param machineId 机器 ID
    /// @param renter 租户地址
    /// @param durationSeconds 租赁时长（秒）
    /// @param totalPoint 租户支付的总积分（含平台提成）
    function rentMachine(
        string calldata machineId,
        address renter,
        uint256 durationSeconds,
        uint256 totalPoint
    ) external onlyAdmin nonReentrant {
        MachineInfo storage m = machines[machineId];
        require(m.registered && m.enabled, "machine not available");
        require(!machineIsRented[machineId], "already rented");
        require(renter != address(0), "zero renter");
        require(durationSeconds > 0, "zero duration");
        require(totalPoint > 0, "zero payment");

        // 计算分成：ownerPoint = totalPoint * 100 / 125 (去掉25%平台提成)
        uint256 ownerPoint = totalPoint * 100 / (100 + PLATFORM_FEE_PCT);
        uint256 platformPoint = totalPoint - ownerPoint;

        lastRentId++;
        uint256 rentId = lastRentId;

        rentId2RentInfo[rentId] = RentInfo({
            machineId: machineId,
            owner: m.owner,
            renter: renter,
            rentStartTime: block.timestamp,
            rentEndTime: block.timestamp + durationSeconds,
            totalPointPaid: totalPoint,
            ownerPoint: ownerPoint,
            platformPoint: platformPoint,
            ended: false
        });

        machineId2RentId[machineId] = rentId;
        machineIsRented[machineId] = true;

        // 转入积分到合约（后端先让用户 approve，再由 admin 调此函数）
        pointToken.safeTransferFrom(renter, address(this), totalPoint);

        emit RentStarted(rentId, machineId, renter, block.timestamp + durationSeconds, totalPoint);
    }

    /// @notice 正常结束租赁（到期或用户主动退租）
    function endRent(string calldata machineId) external onlyAdmin nonReentrant {
        uint256 rentId = machineId2RentId[machineId];
        require(rentId > 0, "no active rent");
        RentInfo storage r = rentId2RentInfo[rentId];
        require(!r.ended, "already ended");

        r.ended = true;
        machineIsRented[machineId] = false;
        delete machineId2RentId[machineId];

        // 如果提前退租，按实际使用时间计算
        uint256 actualDuration = block.timestamp >= r.rentEndTime
            ? r.rentEndTime - r.rentStartTime
            : block.timestamp - r.rentStartTime;
        uint256 totalDuration = r.rentEndTime - r.rentStartTime;

        if (actualDuration >= totalDuration) {
            // 正常到期：全额分配
            ownerPendingIncome[r.owner] += r.ownerPoint;
            pointToken.safeTransfer(platformWallet, r.platformPoint);
        } else {
            // 提前退租：按比例分配，剩余退给租户
            uint256 usedTotal = r.totalPointPaid * actualDuration / totalDuration;
            uint256 usedOwner = usedTotal * 100 / (100 + PLATFORM_FEE_PCT);
            uint256 usedPlatform = usedTotal - usedOwner;
            uint256 refund = r.totalPointPaid - usedTotal;

            ownerPendingIncome[r.owner] += usedOwner;
            pointToken.safeTransfer(platformWallet, usedPlatform);
            if (refund > 0) {
                pointToken.safeTransfer(r.renter, refund);
            }
        }

        emit RentEnded(rentId, machineId, r.renter, r.ownerPoint, r.platformPoint);
    }

    // ══════════════════════════════════════════════════════════════
    //  惩罚（DDN 检测离线后调用）
    // ══════════════════════════════════════════════════════════════

    /// @notice 惩罚免质押机器（离线等原因）— 管理员手动调用
    /// @dev 最多扣 24 小时租金，结束租赁，退还租户剩余积分
    function reportFault(string calldata machineId) external onlySlashAdmin nonReentrant {
        uint256 rentId = machineId2RentId[machineId];
        require(rentId > 0, "no active rent");
        RentInfo storage r = rentId2RentInfo[rentId];
        require(!r.ended, "already ended");

        _executeFault(machineId);
    }

    // ══════════════════════════════════════════════════════════════
    //  机主领取收益
    // ══════════════════════════════════════════════════════════════

    /// @notice 机主领取待结算收益
    function claimIncome() external nonReentrant {
        uint256 amount = ownerPendingIncome[msg.sender];
        require(amount > 0, "no pending income");

        ownerPendingIncome[msg.sender] = 0;
        ownerTotalClaimed[msg.sender] += amount;

        pointToken.safeTransfer(msg.sender, amount);

        emit IncomeClaimed(msg.sender, amount);
    }

    // ══════════════════════════════════════════════════════════════
    //  查询函数
    // ══════════════════════════════════════════════════════════════

    // ══════════════════════════════════════════════════════════════
    //  DDN 通知接口（dbcAI 合约调用）
    // ══════════════════════════════════════════════════════════════

    /// @notice DDN 检测节点通知机器离线，触发惩罚
    /// @dev 由 dbcAI 合约调用，与 Rent.notify() 同接口
    function notify(uint8 tp, string calldata machineId) external nonReentrant returns (bool) {
        require(msg.sender == address(dbcAIContract), "only dbcAI");

        // tp == 4 = MachineOffline
        if (tp != 4) return true;

        // 检查是否为免质押注册机器
        if (!machines[machineId].registered) return false;

        // 检查是否有活跃租赁
        uint256 rentId = machineId2RentId[machineId];
        if (rentId == 0) return true; // 未租赁，无需惩罚

        RentInfo storage r = rentId2RentInfo[rentId];
        if (r.ended) return true;
        if (block.timestamp > r.rentEndTime) return true; // 已过期

        // 执行惩罚（复用 reportFault 逻辑）
        _executeFault(machineId);
        return true;
    }

    /// @dev 内部惩罚执行（reportFault 和 notify 共用）
    function _executeFault(string calldata machineId) internal {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo storage r = rentId2RentInfo[rentId];

        uint256 actualDuration = block.timestamp > r.rentStartTime
            ? block.timestamp - r.rentStartTime
            : 0;
        uint256 totalDuration = r.rentEndTime - r.rentStartTime;

        uint256 usedTotal = r.totalPointPaid * actualDuration / totalDuration;
        if (usedTotal > r.totalPointPaid) usedTotal = r.totalPointPaid;

        uint256 maxSlash24h = r.ownerPoint * 24 * 3600 / totalDuration;
        uint256 usedOwner = usedTotal * 100 / (100 + PLATFORM_FEE_PCT);
        uint256 slashAmount = usedOwner < maxSlash24h ? usedOwner : maxSlash24h;

        uint256 refundAmount = r.totalPointPaid - usedTotal;

        r.ended = true;
        machineIsRented[machineId] = false;
        delete machineId2RentId[machineId];

        uint256 usedPlatform = usedTotal - usedOwner;
        if (usedPlatform > 0) {
            pointToken.safeTransfer(platformWallet, usedPlatform);
        }

        if (usedOwner > slashAmount) {
            ownerPendingIncome[r.owner] += (usedOwner - slashAmount);
        }
        if (slashAmount > 0) {
            pointToken.safeTransfer(platformWallet, slashAmount);
        }

        if (refundAmount > 0) {
            pointToken.safeTransfer(r.renter, refundAmount);
        }

        machineId2SlashInfo[machineId] = SlashInfo({
            machineId: machineId,
            renter: r.renter,
            slashAmount: slashAmount,
            refundAmount: refundAmount,
            createdAt: block.timestamp,
            executed: true
        });

        emit SlashExecuted(machineId, r.renter, slashAmount);
        emit RentEndedBySlash(rentId, machineId, r.renter, slashAmount, refundAmount);
    }

    /// @notice 查询机器信息
    function getMachineInfo(string calldata machineId) external view returns (
        address owner_,
        uint256 pricePerHourUSD_,
        bool registered_,
        bool enabled_,
        bool isRented_
    ) {
        MachineInfo storage m = machines[machineId];
        return (m.owner, m.pricePerHourUSD, m.registered, m.enabled, machineIsRented[machineId]);
    }

    /// @notice 查询租赁信息
    function getRentInfo(uint256 rentId) external view returns (
        string memory machineId_,
        address owner_,
        address renter_,
        uint256 startTime_,
        uint256 endTime_,
        uint256 totalPaid_,
        bool ended_
    ) {
        RentInfo storage r = rentId2RentInfo[rentId];
        return (r.machineId, r.owner, r.renter, r.rentStartTime, r.rentEndTime, r.totalPointPaid, r.ended);
    }

    /// @notice 查询机器是否可租赁
    function canRent(string calldata machineId) external view returns (bool) {
        MachineInfo storage m = machines[machineId];
        return m.registered && m.enabled && !machineIsRented[machineId];
    }

    /// @notice 查询机主待领取收益
    function getPendingIncome(address ownerAddr) external view returns (uint256) {
        return ownerPendingIncome[ownerAddr];
    }
}
