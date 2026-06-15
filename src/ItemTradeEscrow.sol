// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ItemTradeEscrow
 * @notice DeepLink 道具交易托管合约（一期：LC + 冒险岛，标的 = 游戏币/道具）。
 *
 * 设计原则（boss 2026-06-13 拍板「走智能合约不走托管钱包」）：
 *   - 资金（DLP）锁在本合约，平台不托管用户资金、不持有可动用户钱的私钥。
 *   - 每笔订单链上独立完成：买家 approve → createOrder 把 DLP 拉进合约；
 *     买家确认收货 / 7 天超时 → 合约把 amount×(1-fee) 放给卖家，fee 给平台手续费地址。
 *   - 挂单（listing）在链下 DB，仅托管订单上链（省 gas）。
 *   - 纠纷由平台 arbiter 裁决（放卖家 or 全额退买家），其余流程去中心化。
 *
 * 安全：
 *   - 全部转账走 SafeERC20；所有改资金的外部函数 nonReentrant + 严格 CEI（先改状态后转账）。
 *   - orderId 由调用方提供（= 链下 DB 订单号的 bytes32），create 要求该 id 状态为 None，天然防重放/双花。
 *   - 终态（Released/Refunded/Cancelled）不可再变；金额与买卖双方在 create 时锁定，后续不可改。
 */
contract ItemTradeEscrow is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ───────────────────────────── 常量 / 边界
    uint16 public constant MAX_FEE_BPS = 1000;            // 手续费上限 10%（防误设/治理滥用）
    uint256 public constant MIN_AUTO_CONFIRM = 1 days;    // 自动确认周期下限
    uint256 public constant MAX_AUTO_CONFIRM = 30 days;   // 自动确认周期上限
    uint256 public constant MIN_DISPUTE_TIMEOUT = 14 days; // disputeTimeout 下限（防过短导致仲裁来不及）
    uint256 public constant MAX_DISPUTE_TIMEOUT = 90 days; // disputeTimeout 上限

    // ───────────────────────────── 配置（owner 可调）
    IERC20 public dlpToken;          // 结算代币（DLP / Point）
    address public feeRecipient;     // 手续费（2.5%）收款地址
    address public arbiter;          // 纠纷裁决地址
    uint16 public feeBps;            // 手续费 basis points（250 = 2.5%）
    uint256 public autoConfirmPeriod; // 交付后自动确认时长（默认 7 天）
    address public canUpgradeAddress; // 升级权限地址（与平台其它合约一致的约定）

    // ───────────────────────────── 订单
    enum State {
        None,       // 不存在
        Paid,       // 已支付，DLP 锁在合约
        Delivered,  // 卖家已标记交付，开始自动确认计时
        Released,   // 已放款卖家（终态-成功）
        Refunded,   // 已退款买家（终态）
        Disputed,   // 纠纷中
        Cancelled   // 交付前取消（终态）
    }

    struct Order {
        address buyer;
        address seller;
        uint256 amount;     // 托管的 DLP 数量
        uint64 createdAt;
        uint64 deliveredAt; // 0 表示未交付；非 0 = 自动确认计时起点
        uint16 feeBps;      // 下单时锁定的手续费率（防 owner 事后改费率影响在途订单）
        State state;
    }

    mapping(bytes32 => Order) public orders;

    // ───────────────────────────── 灾难兜底（方向 B，append-only 存储；出厂默认关闭）
    // Disputed 状态超时自救窗口：从 deliveredAt 起算，超过 disputeTimeout 后卖家可单方放款。
    // 防「买家恶意 openDispute 永久冻结已交付订单的卖家货款」。0 = 关闭（kill-switch，出厂默认）。
    // 命门：仅对 deliveredAt != 0（确已交付）的订单生效；纯 Paid 期开的纠纷永不可超时放款，
    // 仍只能由 arbiter/owner 裁决，杜绝「未交付却被卖家超时拿钱」。
    uint256 public disputeTimeout;

    // 纠纷发起方（openDispute 调用者）。append-only 存储，紧随 disputeTimeout 之后。
    // 红队向量3 修复命门：claimDisputeTimeout 超时自救仅对**买家发起**的纠纷开放，
    // 杜绝骗子卖家自走「markDelivered(不真发货)→自己 openDispute→超时 claim 提走买家本金」。
    mapping(bytes32 => address) public disputeInitiator;

    // ───────────────────────────── 事件（后端索引器监听回写订单状态）
    event OrderCreated(bytes32 indexed orderId, address indexed buyer, address indexed seller, uint256 amount);
    event OrderDelivered(bytes32 indexed orderId, uint64 deliveredAt);
    event OrderReleased(bytes32 indexed orderId, address indexed seller, uint256 net, uint256 fee, address by);
    event OrderRefunded(bytes32 indexed orderId, address indexed buyer, uint256 amount, string reason);
    event OrderCancelled(bytes32 indexed orderId, address by);
    event OrderDisputed(bytes32 indexed orderId, address by);
    event DisputeResolved(bytes32 indexed orderId, bool releasedToSeller, address arbiter);

    event FeeRecipientUpdated(address indexed prev, address indexed next);
    event ArbiterUpdated(address indexed prev, address indexed next);
    event FeeBpsUpdated(uint16 prev, uint16 next);
    event AutoConfirmPeriodUpdated(uint256 prev, uint256 next);
    event CanUpgradeAddressUpdated(address indexed prev, address indexed next);
    event DisputeTimeoutUpdated(uint256 prev, uint256 next);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dlpToken,
        address _feeRecipient,
        address _arbiter,
        address _owner
    ) public initializer {
        require(_dlpToken != address(0), "dlp=0");
        require(_feeRecipient != address(0), "feeRecipient=0");
        require(_arbiter != address(0), "arbiter=0");
        require(_owner != address(0), "owner=0");

        __Ownable_init(_owner);
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        dlpToken = IERC20(_dlpToken);
        feeRecipient = _feeRecipient;
        arbiter = _arbiter;
        feeBps = 250;                 // 2.5%
        autoConfirmPeriod = 7 days;   // 与 ItemMania/ItemBay 一致
        canUpgradeAddress = _owner;
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    // ───────────────────────────── 修饰
    // 纠纷裁决者 = arbiter（日常）或 owner（兜底，防 arbiter 私钥丢失导致 Disputed 资金永久锁死）
    modifier onlyArbiterOrOwner() {
        require(msg.sender == arbiter || msg.sender == owner(), "not arbiter/owner");
        _;
    }

    // ───────────────────────────── 交易主流程

    /**
     * @notice 买家下单并把 DLP 锁进托管。买家须先 approve 本合约 >= amount。
     * @param orderId 链下 DB 订单号（bytes32）；必须此前未用过。
     */
    function createOrder(bytes32 orderId, address seller, uint256 amount) external nonReentrant {
        require(orderId != bytes32(0), "orderId=0");
        require(seller != address(0), "seller=0");
        require(seller != msg.sender, "self trade");
        require(amount > 0, "amount=0");
        Order storage o = orders[orderId];
        require(o.state == State.None, "order exists");

        // CEI：先写状态，再拉资金
        o.buyer = msg.sender;
        o.seller = seller;
        o.amount = amount;
        o.createdAt = uint64(block.timestamp);
        o.deliveredAt = 0;
        o.feeBps = feeBps;      // 锁定下单时费率
        o.state = State.Paid;

        dlpToken.safeTransferFrom(msg.sender, address(this), amount);

        emit OrderCreated(orderId, msg.sender, seller, amount);
    }

    /// @notice 卖家标记已交付，启动自动确认计时。
    function markDelivered(bytes32 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.state == State.Paid, "not paid");
        require(msg.sender == o.seller, "not seller");
        o.deliveredAt = uint64(block.timestamp);
        o.state = State.Delivered;
        emit OrderDelivered(orderId, o.deliveredAt);
    }

    /// @notice 买家确认收货 → 放款给卖家（可从 Paid 或 Delivered 直接确认）。
    function confirmReceived(bytes32 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.state == State.Paid || o.state == State.Delivered, "bad state");
        require(msg.sender == o.buyer, "not buyer");
        _release(orderId, o, msg.sender);
    }

    /// @notice 交付满 autoConfirmPeriod 后，任何人可触发自动放款（permissionless，最去中心化）。
    function claimAfterTimeout(bytes32 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.state == State.Delivered, "not delivered");
        require(block.timestamp >= uint256(o.deliveredAt) + autoConfirmPeriod, "too early");
        _release(orderId, o, msg.sender);
    }

    /// @notice 交付前取消 → 全额退买家。**仅卖家可调**（卖家谢绝订单）。
    ///   反诈关键(审计 F-1)：买家不能付款后单方退款——否则可"游戏内收货→抢在 markDelivered 前 cancel→拿货又退款"。
    ///   买家想付款后退出 → 走 openDispute 由 arbiter 裁决（卖家没交付则退款）。
    function cancel(bytes32 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.state == State.Paid, "not cancellable");
        require(msg.sender == o.seller, "not seller");
        uint256 amt = o.amount;
        address buyer = o.buyer;
        o.state = State.Cancelled;
        dlpToken.safeTransfer(buyer, amt);
        emit OrderCancelled(orderId, msg.sender);
        emit OrderRefunded(orderId, buyer, amt, "cancel");
    }

    /// @notice 开纠纷（买卖任一方），冻结自动流程，交 arbiter 裁决。
    function openDispute(bytes32 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.state == State.Paid || o.state == State.Delivered, "bad state");
        require(msg.sender == o.buyer || msg.sender == o.seller, "forbidden");
        o.state = State.Disputed;
        disputeInitiator[orderId] = msg.sender; // 记录发起方，供 claimDisputeTimeout 闸门校验
        emit OrderDisputed(orderId, msg.sender);
    }

    /// @notice arbiter（或 owner 兜底）裁决纠纷：releaseToSeller=true 放款卖家（扣 fee），否则全额退买家。
    function resolveDispute(bytes32 orderId, bool releaseToSeller) external nonReentrant onlyArbiterOrOwner {
        Order storage o = orders[orderId];
        require(o.state == State.Disputed, "not disputed");
        if (releaseToSeller) {
            _release(orderId, o, msg.sender);
        } else {
            uint256 amt = o.amount;
            address buyer = o.buyer;
            o.state = State.Refunded;
            dlpToken.safeTransfer(buyer, amt);
            emit OrderRefunded(orderId, buyer, amt, "dispute");
        }
        emit DisputeResolved(orderId, releaseToSeller, msg.sender);
    }

    /// @notice 灾难兜底（方向 B）：买家恶意 openDispute 永久冻结一笔**已交付**订单的卖家货款时，
    ///   卖家可在 disputeTimeout 之后单方触发放款自救。出厂 disputeTimeout==0=关闭（kill-switch）。
    ///   - 仅 Disputed 态；仅卖家可调。
    ///   - 命门：require deliveredAt != 0 —— 纯 Paid 期开的纠纷（卖家从未交付）永不可走此路径，
    ///     仍只能由 arbiter/owner 裁决，杜绝「没交货却超时拿钱」。
    ///   - 仲裁优先：窗口内 arbiter/owner 可随时 resolveDispute 终结，之后本函数因非 Disputed 而 revert。
    ///   - 计时锚点 = deliveredAt（不是 openDispute 时刻），与买家何时挑起纠纷无关，避免买家拖延起算点。
    ///   - 红队向量3 命门：require disputeInitiator == buyer —— 仅**买家发起**的纠纷才允许卖家超时自救。
    ///     杜绝骗子卖家自走「markDelivered(不真发货)→自己 openDispute→超时 claim 提走买家本金」；
    ///     卖家自开的纠纷只能由 arbiter/owner 裁决（或买家另行处理），不能走此路径。
    function claimDisputeTimeout(bytes32 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        require(o.state == State.Disputed, "not disputed");
        require(o.deliveredAt != 0, "never delivered");
        require(disputeInitiator[orderId] == o.buyer, "not buyer-initiated");
        require(disputeTimeout != 0, "timeout disabled");
        require(block.timestamp >= uint256(o.deliveredAt) + disputeTimeout, "too early");
        require(msg.sender == o.seller, "not seller");
        _release(orderId, o, msg.sender);
    }

    // ───────────────────────────── 内部：放款（CEI + SafeERC20）
    function _release(bytes32 orderId, Order storage o, address by) private {
        uint256 amt = o.amount;
        address seller = o.seller;
        uint256 fee = (amt * o.feeBps) / 10000;  // 用订单锁定的费率，不受事后 setFeeBps 影响
        uint256 net = amt - fee;

        o.state = State.Released; // 先置终态，杜绝重入/重复放款

        if (net > 0) dlpToken.safeTransfer(seller, net);
        if (fee > 0) dlpToken.safeTransfer(feeRecipient, fee);

        emit OrderReleased(orderId, seller, net, fee, by);
    }

    // ───────────────────────────── 只读
    function getOrder(bytes32 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    /// @notice 订单是否已可超时放款（前端/keeper 判断用）。
    function isClaimable(bytes32 orderId) external view returns (bool) {
        Order storage o = orders[orderId];
        return o.state == State.Delivered && block.timestamp >= uint256(o.deliveredAt) + autoConfirmPeriod;
    }

    // ───────────────────────────── 治理（onlyOwner）
    function setFeeRecipient(address next) external onlyOwner {
        require(next != address(0), "feeRecipient=0");
        emit FeeRecipientUpdated(feeRecipient, next);
        feeRecipient = next;
    }

    function setArbiter(address next) external onlyOwner {
        require(next != address(0), "arbiter=0");
        emit ArbiterUpdated(arbiter, next);
        arbiter = next;
    }

    function setFeeBps(uint16 next) external onlyOwner {
        require(next <= MAX_FEE_BPS, "fee too high");
        emit FeeBpsUpdated(feeBps, next);
        feeBps = next;
    }

    function setAutoConfirmPeriod(uint256 next) external onlyOwner {
        require(next >= MIN_AUTO_CONFIRM && next <= MAX_AUTO_CONFIRM, "out of range");
        emit AutoConfirmPeriodUpdated(autoConfirmPeriod, next);
        autoConfirmPeriod = next;
    }

    /// @notice 启用/调整/关闭 Disputed 超时自救窗口。next==0 = 关闭（kill-switch）；
    ///   否则必须落在 [MIN_DISPUTE_TIMEOUT, MAX_DISPUTE_TIMEOUT]。出厂默认 0（关闭，安全默认）。
    function setDisputeTimeout(uint256 next) external onlyOwner {
        require(next == 0 || (next >= MIN_DISPUTE_TIMEOUT && next <= MAX_DISPUTE_TIMEOUT), "out of range");
        emit DisputeTimeoutUpdated(disputeTimeout, next);
        disputeTimeout = next;
    }

    function setCanUpgradeAddress(address next) external onlyOwner {
        require(next != address(0), "canUpgrade=0");
        emit CanUpgradeAddressUpdated(canUpgradeAddress, next);
        canUpgradeAddress = next;
    }

    // ───────────────────────────── UUPS 升级授权
    // canUpgradeAddress 日常升级；owner 兜底，防 setCanUpgradeAddress 误设成坏地址导致升级权永久锁死。
    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == canUpgradeAddress || msg.sender == owner(), "not upgrader");
    }

    // __gap 从 44 → 42：v2 新增 2 个 storage slot（disputeTimeout + disputeInitiator，
    // 均 append 在 orders 之后、__gap 之前），总占用不变 → 升级安全。
    uint256[42] private __gap;
}
