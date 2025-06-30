// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/IStakingContract.sol";
import "../interface/IRewardToken.sol";
import "../interface/IRentContract.sol";
import "../interface/IPrecompileContract.sol";
import "forge-std/console.sol";
import "../interface/IDBCAIContract.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IOracle.sol";

/// @custom:oz-upgrades-from OldRent
contract Rent is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint8 public constant SECONDS_PER_BLOCK = 6;
    uint256 public constant REPORT_RESERVE_AMOUNT = 10_000 ether;
    uint256 public constant SLASH_AMOUNT = 10_000 ether;
    uint256 public constant ONE_CALC_POINT_USD_VALUE_PER_MONTH = 5_080;
    uint256 public constant FACTOR = 10_000;
    uint256 public constant USD_DECIMALS = 1_000_000;

    IRewardToken public feeToken;
    IPrecompileContract public precompileContract;
    IStakingContract public stakingContract;
    IDBCAIContract public dbcAIContract;

    address public canUpgradeAddress;
    uint256 public lastRentId;
    uint256 public totalBurnedAmount;
    uint8 public voteThreshold;
    bool public registered;
    RentGPUInfo public rentGPUInfo;

    enum SlashType {
        Offline,
        RenterReport
    }

    enum NotifyType {
        ContractRegister,
        MachineRegister,
        MachineUnregister,
        MachineOnline,
        MachineOffline
    }

    enum Vote {
        None,
        Yes,
        No,
        Finished
    }

    struct RentInfo {
        address stakeHolder;
        string machineId;
        uint256 rentStatTime;
        uint256 rentEndTime;
        address renter;
    }

    struct BurnedDetail {
        uint256 rentId;
        uint256 burnTime;
        uint256 burnDLCAmount;
        address renter;
    }

    struct BurnedInfo {
        BurnedDetail[] details;
        uint256 totalBurnedAmount;
    }

    struct SlashInfo {
        address stakeHolder;
        string machineId;
        uint256 slashAmount;
        uint256 rentStartAtTimestamp;
        uint256 rentEndAtTimestamp;
        uint256 rentedDurationSeconds;
        address renter;
        SlashType slashType;
        uint256 createdAt;
        bool paid;
    }

    struct RentGPUInfo {
        uint256 rentedGPUCount;
        uint256 rentingGPUCount;
    }

    address[] public adminsToApprove;
    string[] public pendingSlashMachineIds;

    mapping(uint256 => RentInfo) public rentId2RentInfo;
    mapping(string => uint256) public machineId2RentId;
    mapping(address => uint256[]) public renter2RentIds;
    mapping(string => BurnedInfo) public machineId2BurnedInfo;
    mapping(string => SlashInfo) public machineId2SlashInfo;
    mapping(string => mapping(address => Vote)) public pendingSlashMachineId2ApprovedAdmins;
    mapping(string => uint8) public pendingSlashMachineId2ApprovedCount;
    mapping(string => uint8) public pendingSlashMachineId2RefuseCount;
    mapping(address => uint256) public stakeHolder2RentFee;
    mapping(address => RentGPUInfo) public stakeHolder2RentGPUInfo;
    mapping(string => uint256) public machineId2LastRentEndBlock;
    mapping(string => SlashInfo[]) public machineId2SlashInfos;

    struct FeeInfo {
        uint256 baseFee;
        uint256 extraFee;
        uint256 platformFee;
    }

    IOracle public oracle;
    mapping(uint256 => FeeInfo) public rentId2FeeInfoInDLC;
    mapping(string => bool) public rentWhitelist;
    mapping(address => bool) public adminsToSetRentWhiteList;
    mapping(string => bool) public machine2ProxyRented;

    event RentMachine(
        address indexed machineOnwer,
        uint256 rentId,
        string machineId,
        uint256 rentEndTime,
        address renter,
        uint256 rentFee
    );
    event RenewRent(
        address indexed machineOnwer,
        string machineId,
        uint256 rentId,
        uint256 additionalRentSeconds,
        uint256 additionalRentFee,
        address renter
    );
    event ExtraRentFeeTransfer(address indexed machineOnwer, uint256 rentId, uint256 amount);
    event EndRentMachine(address machineOnwer, uint256 rentId, string machineId, uint256 rentEndTime, address renter);
    event ReportMachineFault(uint256 rentId, string machineId, address reporter);
    event BurnedFee(
        string machineId, uint256 rentId, uint256 burnTime, uint256 burnDLCAmount, address renter, uint8 rentGpuCount
    );
    event PayBackFee(string machineId, uint256 rentId, address renter, uint256 amount);
    event PayToContractOnRent(uint256 rentId, address renter, uint256 totalRentFee);
    event RentFee(uint256 rentId, address renter, uint256 baseRentFee, uint256 extraRentFee, uint256 platformFee);

    event RenterPayExtraRentFee(uint256 rentId, address renter, uint256 amount);
    event ApprovedReport(string machineId, address admin);
    event RefusedReport(string machineId, address admin);
    event ExecuteReport(string machineId, Vote vote);
    event MachineRegister(string machineId, uint256 calcPoint);
    event MachineUnregister(string machineId, uint256 calcPoint);
    event PaidSlash(string machineId);
    event SlashMachineOnOffline(
        address indexed stakeHolder,
        string machineId,
        address indexed renter,
        uint256 slashAmount,
        uint256 rentStartAt,
        uint256 rentEndAt,
        SlashType slashType
    );
    event RemoveCalcPointOnOffline(string machineId);
    event AddCalcPointOnline(string machineId);

    event AddBackCalcPointOnOnline(string machineId, uint256 calcPoint);
    event PlatformFeeTransfer(address indexed machineOnwer, uint256 rentId, uint256 amount);

    error NotApproveAdmin();
    error ZeroCalcPoint();
    error CallerNotStakingContract();
    error ZeroAddress();
    error CanNotUpgrade(address);
    error CountOfApproveAdminsShouldBeFive();
    error ElementNotFound();
    error uint256Overflow();
    error InvalidRentDuration(uint256 rentDuration);
    error MachineCanNotRent();
    error RentDurationTooLong(uint256 rentDuration, uint256 maxRentDuration);
    error RenTimeCannotOverMachineUnstakeTime();
    error MachineCanNotRentWithin100BlocksAfterLastRent();
    error BalanceNotEnough();
    error RentEnd();
    error RentNotEnd();
    error NotRenter();
    error RentingNotExist();
    error MachineNotRented();
    error ReserveAmountForReportShouldBe10000();
    error ReportedMachineNotFound();
    error VoteFinished();
    error NotDBCAIContract();
    error RewardNotStart();
    error NotValidMachineId();
    error RenterAndPayerIsSame();
    error ProxyRentCanNotEndByRenter();
    error NotProxyRentingMachine();

    modifier onlyApproveAdmins() {
        bool found = false;
        for (uint8 i = 0; i < adminsToApprove.length; i++) {
            if (msg.sender == adminsToApprove[i]) {
                found = true;
                break;
            }
        }
        require(found, NotApproveAdmin());
        _;
    }

    modifier onlyStakingContract() {
        require(msg.sender == address(stakingContract), CallerNotStakingContract());
        _;
    }

    modifier onlyDBCAIContract() {
        require(msg.sender == address(dbcAIContract), NotDBCAIContract());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _precompileContract,
        address _stakingContract,
        address _dbcAIContract,
        address _feeToken
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
        feeToken = IRewardToken(_feeToken);
        precompileContract = IPrecompileContract(_precompileContract);
        stakingContract = IStakingContract(_stakingContract);
        dbcAIContract = IDBCAIContract(_dbcAIContract);
        voteThreshold = 3;
        canUpgradeAddress = msg.sender;
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(newImplementation != address(0), ZeroAddress());
        require(msg.sender == canUpgradeAddress, CanNotUpgrade(msg.sender));
    }

    function setCanUpgradeAddress(address addr) external onlyOwner {
        canUpgradeAddress = addr;
    }

    function setDBCAIContract(address addr) external onlyOwner {
        dbcAIContract = IDBCAIContract(addr);
    }

    function setOracle(address addr) external onlyOwner {
        oracle = IOracle(addr);
    }

    function setAdminsToApproveMachineFaultReporting(address[] calldata admins) external onlyOwner {
        require(admins.length == 5, CountOfApproveAdminsShouldBeFive());
        adminsToApprove = admins;
    }

    function setFeeToken(address _feeToken) external onlyOwner {
        require(_feeToken != address(0x0), ZeroAddress());
        feeToken = IRewardToken(_feeToken);
    }

    function setStakingContract(address addr) external onlyOwner {
        stakingContract = IStakingContract(addr);
    }

    function setPrecompileContract(address _precompileContract) external onlyOwner {
        require(_precompileContract != address(0x0), ZeroAddress());
        precompileContract = IPrecompileContract(_precompileContract);
    }

    function findUintIndex(uint256[] memory arr, uint256 v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == v) {
                return i;
            }
        }
        revert ElementNotFound();
    }

    function removeValueOfUintArray(uint256 v, uint256[] storage arr) internal {
        uint256 index = findUintIndex(arr, v);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function findStringIndex(string[] memory arr, string memory v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (keccak256(abi.encodePacked(arr[i])) == keccak256(abi.encodePacked(v))) {
                return i;
            }
        }
        revert ElementNotFound();
    }

    function removeValueOfStringArray(string memory addr, string[] storage arr) internal {
        uint256 index = findStringIndex(arr, addr);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function getNextRentId() internal returns (uint256) {
        require(lastRentId < type(uint256).max, uint256Overflow());
        lastRentId += 1;
        return lastRentId;
    }

    function canRent(string calldata machineId) public view returns (bool) {
        if (!inRentWhiteList(machineId)) {
            return false;
        }
        if (isRented(machineId)) {
            return false;
        }
        if (!stakingContract.isStaking(machineId)) {
            return false;
        }

        if (stakingContract.machineIsBlocked(machineId)) {
            return false;
        }

        if (stakingContract.isStakingButOffline(machineId)) {
            return false;
        }

        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        if (rewardEndAt == stakingContract.getRewardDuration()) {
            return false;
        }

        (, uint256 calcPoint,, uint256 endAtTimestamp, uint256 nextRenterCanRentAt,, bool isOnline, bool isRegistered) =
            stakingContract.getMachineInfo(machineId);
        if (!isOnline || !isRegistered || isRented(machineId) || calcPoint == 0) {
            return false;
        }

        if (nextRenterCanRentAt > block.timestamp || nextRenterCanRentAt == 0) {
            // not reach the start rent block number yet
            return false;
        }
        if (endAtTimestamp > 0) {
            return endAtTimestamp > block.timestamp && endAtTimestamp - block.timestamp > 1 hours;
        }

        return endAtTimestamp == 0;
    }

    function getMachineInfo(string memory machineId)
        public
        view
        returns (uint256 availableRentHours, uint256 reservedAmount, uint256 rentFeePerHour)
    {
        (,,, uint256 endAt,, uint256 _reservedAmount,,) = stakingContract.getMachineInfo(machineId);
        uint256 rentFee = getMachinePrice(machineId, 1 hours / SECONDS_PER_BLOCK);
        if (isRented(machineId)) {
            return (0, _reservedAmount, rentFee);
        }

        return (endAt - block.timestamp / 1 hours, _reservedAmount, rentFee);
    }

    function getMachinePrice(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        uint256 baseMachinePrice = getBaseMachinePrice(machineId, rentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, rentSeconds);
        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);
        uint256 platformFee = (baseMachinePrice + extraRentFee) * platformFeeRate / 100;
        return baseMachinePrice + extraRentFee + platformFee;
    }

    function getBaseMachinePrice(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        (, uint256 calcPointInFact,,,,,,,) = dbcAIContract.getMachineInfo(machineId, true);
        require(calcPointInFact > 0, ZeroCalcPoint());

        // calcPont factor : 10000 ; ONE_CALC_POINT_USD_VALUE_PER_MONTH factor: 10000
        uint256 totalFactor = FACTOR * FACTOR;
        uint256 dlcUSDPrice = oracle.getTokenPriceInUSD(10, address(feeToken));

        uint256 rentFeeUSD = USD_DECIMALS * rentSeconds * calcPointInFact * ONE_CALC_POINT_USD_VALUE_PER_MONTH / 30 / 24
            / 60 / 60 / totalFactor;
        rentFeeUSD = rentFeeUSD * 6 / 10; // 60% of the total rent fee
        uint256 baseRentFeeUSD = 1e18 * rentFeeUSD / dlcUSDPrice;
        return baseRentFeeUSD;
    }

    function getExtraRentFee(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        uint256 rentMinutes = rentSeconds / 60;

        uint256 fee = stakingContract.getMachineExtraRentFee(machineId) * rentMinutes;
        if (fee == 0) {
            return 0;
        }
        uint256 dlcUSDPrice = oracle.getTokenPriceInUSD(10, address(feeToken));
        uint256 baseRentFeeUSD = 1e18 * fee / dlcUSDPrice;
        return baseRentFeeUSD;
    }

    function inRentWhiteList(string calldata machineId) public view returns (bool) {
        if (stakingContract.isPersonalMachine(machineId)) {
            return true;
        }
        return rentWhitelist[machineId];
    }

    function setRentingWhitelist(string[] calldata machineIds, bool isAdd) external {
        require(adminsToSetRentWhiteList[msg.sender], "has no permission to set renting whitelist");
        for (uint256 i = 0; i < machineIds.length; i++) {
            rentWhitelist[machineIds[i]] = isAdd;
        }
    }

    function setAdminsToAddRentWhiteList(address[] calldata admins) external onlyOwner {
        for (uint256 i = 0; i < admins.length; i++) {
            adminsToSetRentWhiteList[admins[i]] = true;
        }
    }

    function rentMachine(string calldata machineId, uint256 rentSeconds) external {
        _rentMachine(msg.sender, msg.sender, machineId, rentSeconds);
    }

    function rentProxyMachine(address renter, string calldata machineId, uint256 rentSeconds) external {
        require(msg.sender != renter, RenterAndPayerIsSame());
        _rentMachine(msg.sender, renter, machineId, rentSeconds);
    }

    function _rentMachine(address payer, address renter, string calldata machineId, uint256 rentSeconds) internal {
        require(inRentWhiteList(machineId), NotValidMachineId());
        require(rentSeconds >= 10 minutes && rentSeconds <= 2 hours, InvalidRentDuration(rentSeconds));
        require(canRent(machineId), MachineCanNotRent());

        (address machineHolder,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        require(block.timestamp + rentSeconds < endAtTimestamp, RenTimeCannotOverMachineUnstakeTime());
        uint256 rewardDuration = stakingContract.getRewardDuration();
        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        require(rewardEndAt > rewardDuration, RewardNotStart());
        uint256 maxRentDuration = Math.min(Math.min(endAtTimestamp, rewardEndAt) - block.timestamp, rewardDuration);
        require(rentSeconds <= maxRentDuration, RentDurationTooLong(rentSeconds, maxRentDuration));
        machine2ProxyRented[machineId] = msg.sender != renter;

        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock != 0) {
            require(block.number > lastRentEndBlock + 30, MachineCanNotRentWithin100BlocksAfterLastRent());
        }

        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);

        uint256 baseRentFee = getBaseMachinePrice(machineId, rentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, rentSeconds);
        uint256 platformFee = (baseRentFee + extraRentFee) * platformFeeRate / 100;
        uint256 totalRentFee = baseRentFee + extraRentFee + platformFee;
        require(feeToken.balanceOf(payer) >= totalRentFee, BalanceNotEnough());

        uint256 _now = block.timestamp;

        // save rent info
        lastRentId = getNextRentId();
        rentId2RentInfo[lastRentId] = RentInfo({
            stakeHolder: machineHolder,
            machineId: machineId,
            rentStatTime: _now,
            rentEndTime: _now + rentSeconds,
            renter: renter
        });
        machineId2RentId[machineId] = lastRentId;
        renter2RentIds[renter].push(lastRentId);

        FeeInfo memory feeInfo;
        feeInfo.baseFee = baseRentFee;
        feeInfo.extraFee = extraRentFee;
        feeInfo.platformFee = platformFee;
        rentId2FeeInfoInDLC[lastRentId] = feeInfo;

        feeToken.transferFrom(msg.sender, address(this), totalRentFee);
        emit RentFee(lastRentId, msg.sender, baseRentFee, extraRentFee, platformFee);
        emit PayToContractOnRent(lastRentId, msg.sender, totalRentFee);

        // burn rent fee
        //        feeToken.burnFrom(payer, baseRentFee);
        //        emit BurnedFee(machineId, lastRentId, block.timestamp, baseRentFee, renter, 1);
        //        totalBurnedAmount += baseRentFee;

        // add machine burn info
        //        BurnedDetail memory burnedDetail =
        //            BurnedDetail({rentId: lastRentId, burnTime: block.timestamp, burnDLCAmount: baseRentFee, renter: renter});

        stakeHolder2RentGPUInfo[machineHolder].rentedGPUCount += 1;
        stakeHolder2RentGPUInfo[machineHolder].rentingGPUCount += 1;
        rentGPUInfo.rentedGPUCount += 1;
        rentGPUInfo.rentingGPUCount += 1;

        stakeHolder2RentFee[machineHolder] += baseRentFee;
        //        BurnedInfo storage burnedInfo = machineId2BurnedInfo[machineId];
        //        burnedInfo.details.push(burnedDetail);
        //        burnedInfo.totalBurnedAmount += baseRentFee;

        // notify staking contract renting machine action happened
        stakingContract.rentMachine(machineId);

        emit RentMachine(machineHolder, lastRentId, machineId, block.timestamp + rentSeconds, renter, baseRentFee);
    }

    function proxyRenewRent(address renter, string memory machineId, uint256 additionalRentSeconds) external {
        _renewRent(renter, machineId, additionalRentSeconds);
    }

    function renewRent(string memory machineId, uint256 additionalRentSeconds) external {
        _renewRent(msg.sender, machineId, additionalRentSeconds);
    }

    function _renewRent(address renter, string memory machineId, uint256 additionalRentSeconds) internal {
        uint256 rentId = machineId2RentId[machineId];
        require(rentId2RentInfo[rentId].rentEndTime > block.timestamp, RentEnd());
        require(rentId2RentInfo[rentId].renter == renter, NotRenter());
        require(isRented(machineId), MachineNotRented());
        require(
            additionalRentSeconds >= 10 minutes && additionalRentSeconds <= 2 hours,
            InvalidRentDuration(additionalRentSeconds)
        );

        (,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        uint256 maxRentDuration =
            Math.min(Math.min(endAtTimestamp, rewardEndAt) - block.timestamp, stakingContract.getRewardDuration());

        require(
            rentId2RentInfo[rentId].rentEndTime + additionalRentSeconds < endAtTimestamp,
            RenTimeCannotOverMachineUnstakeTime()
        );

        if (msg.sender != renter) {
            require(machine2ProxyRented[machineId] == true, NotProxyRentingMachine());
        }

        uint256 newRentDuration = rentId2RentInfo[rentId].rentEndTime - block.timestamp + additionalRentSeconds;
        require(newRentDuration <= maxRentDuration, RentDurationTooLong(newRentDuration, maxRentDuration));

        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);

        uint256 baseRentFee = getBaseMachinePrice(machineId, additionalRentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, additionalRentSeconds);
        uint256 platformFee = (baseRentFee + extraRentFee) * platformFeeRate / 100;
        uint256 additionalRentFeeInFact = baseRentFee + extraRentFee + platformFee;
        require(feeToken.balanceOf(msg.sender) >= additionalRentFeeInFact, BalanceNotEnough());

        // Update rent end time
        rentId2RentInfo[rentId].rentEndTime += additionalRentSeconds;

        FeeInfo storage feeInfo = rentId2FeeInfoInDLC[lastRentId];
        feeInfo.baseFee += baseRentFee;
        feeInfo.extraFee += extraRentFee;
        feeInfo.platformFee += platformFee;

        feeToken.transferFrom(msg.sender, address(this), platformFee + extraRentFee + baseRentFee);

        // add machine burn info
        BurnedDetail memory burnedDetail = BurnedDetail({
            rentId: rentId,
            burnTime: block.timestamp,
            burnDLCAmount: additionalRentFeeInFact,
            renter: renter
        });

        (address machineHolder,) = getMachineHolderAndCalcPoint(machineId);

        stakeHolder2RentFee[machineHolder] += additionalRentFeeInFact;
        BurnedInfo storage burnedInfo = machineId2BurnedInfo[machineId];
        burnedInfo.details.push(burnedDetail);
        burnedInfo.totalBurnedAmount += additionalRentFeeInFact;

        // update total burned amount
        totalBurnedAmount += additionalRentFeeInFact;
        stakingContract.renewRentMachine(machineId, additionalRentFeeInFact);
        emit RenewRent(machineHolder, machineId, rentId, additionalRentSeconds, additionalRentFeeInFact, renter);
    }

    function endRentMachine(string calldata machineId) external {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        if (msg.sender != rentInfo.renter) {
            require(rentInfo.rentEndTime <= block.timestamp, RentNotEnd());
        } else {
            require(machine2ProxyRented[machineId] == false, ProxyRentCanNotEndByRenter());
        }
        machine2ProxyRented[machineId] == false;
        require(rentInfo.rentEndTime > 0, RentingNotExist());

        (address machineHolder,) = getMachineHolderAndCalcPoint(machineId);

        FeeInfo memory feeInfo = rentId2FeeInfoInDLC[rentId];
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];

        uint256 _now = block.timestamp;
        if (_now < rentInfo.rentEndTime) {
            uint256 rentDuration = rentInfo.rentEndTime - rentInfo.rentStatTime;
            uint256 usdDuration = _now - rentInfo.rentStatTime;

            uint256 totalRentFee = feeInfo.baseFee + feeInfo.extraFee + feeInfo.platformFee;

            feeInfo.baseFee = feeInfo.baseFee * usdDuration / rentDuration;
            feeInfo.extraFee = feeInfo.extraFee * usdDuration / rentDuration;
            feeInfo.platformFee = feeInfo.platformFee * usdDuration / rentDuration;

            uint256 payBackFee = totalRentFee - feeInfo.baseFee - feeInfo.extraFee - feeInfo.platformFee;
            if (payBackFee > 0) {
                feeToken.transfer(rentInfo.renter, payBackFee);
                emit PayBackFee(machineId, rentId, rentInfo.renter, payBackFee);
            }
        }

        if (feeInfo.baseFee > 0) {
            feeToken.approve(address(this), feeInfo.baseFee);
            feeToken.burnFrom(address(this), feeInfo.baseFee);
            emit BurnedFee(machineId, lastRentId, block.timestamp, feeInfo.baseFee, rentInfo.renter, 1);
            totalBurnedAmount += feeInfo.baseFee;
        }

        if (feeInfo.extraFee > 0) {
            feeToken.transfer(machineHolder, feeInfo.extraFee);
            emit ExtraRentFeeTransfer(machineHolder, lastRentId, feeInfo.extraFee);
        }
        if (feeInfo.platformFee > 0) {
            distributePlatformFee(rentId, machineId, feeInfo.platformFee);
        }

        stakingContract.endRentMachine(machineId, feeInfo.baseFee, feeInfo.platformFee);
        machineId2LastRentEndBlock[machineId] = block.number;
        delete rentId2FeeInfoInDLC[rentId];
        emit EndRentMachine(machineHolder, rentId, machineId, rentInfo.rentEndTime, rentInfo.renter);
    }

    function getMachineHolderAndCalcPoint(string memory machineId) public view returns (address, uint256) {
        (address holder, uint256 calcPoint,,,,,,) = stakingContract.getMachineInfo(machineId);
        return (holder, calcPoint);
    }

    function reportMachineFault(string calldata machineId, uint256 reserveAmount) external {
        require(reserveAmount == REPORT_RESERVE_AMOUNT, ReserveAmountForReportShouldBe10000());

        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        require(rentInfo.renter == msg.sender, NotRenter());
        require(rentInfo.rentEndTime >= block.timestamp, RentEnd());

        SafeERC20.safeTransferFrom(feeToken, msg.sender, address(this), REPORT_RESERVE_AMOUNT);
        machineId2SlashInfo[rentInfo.machineId] = newSlashInfo(
            rentInfo.stakeHolder,
            rentInfo.machineId,
            SLASH_AMOUNT,
            rentInfo.rentStatTime,
            rentInfo.rentEndTime,
            block.timestamp - rentInfo.rentStatTime,
            SlashType.RenterReport,
            rentInfo.renter
        );
        pendingSlashMachineIds.push(rentInfo.machineId);
        emit ReportMachineFault(rentId, rentInfo.machineId, msg.sender);
    }

    function newSlashInfo(
        address slasher,
        string memory machineId,
        uint256 slashAmount,
        uint256 rentStartAt,
        uint256 rentEndAt,
        uint256 rentDuration,
        SlashType slashType,
        address renter
    ) internal view returns (SlashInfo memory) {
        SlashInfo memory slashInfo = SlashInfo({
            stakeHolder: slasher,
            machineId: machineId,
            slashAmount: slashAmount,
            rentStartAtTimestamp: rentStartAt,
            rentEndAtTimestamp: rentEndAt,
            rentedDurationSeconds: rentDuration,
            renter: renter,
            slashType: slashType,
            createdAt: block.timestamp,
            paid: false
        });
        return slashInfo;
    }

    function addSlashInfoAndReport(SlashInfo memory slashInfo) internal {
        machineId2SlashInfos[slashInfo.machineId].push(slashInfo);
        stakingContract.reportMachineFault(slashInfo.machineId, slashInfo.renter);
    }

    function approveMachineFaultReporting(string calldata machineId) external onlyApproveAdmins {
        require(machineId2SlashInfo[machineId].renter != address(0x0), ReportedMachineNotFound());

        require(pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] != Vote.Finished, VoteFinished());
        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.Yes;
        emit ApprovedReport(machineId, msg.sender);
        pendingSlashMachineId2ApprovedCount[machineId] += 1;
        if (pendingSlashMachineId2ApprovedCount[machineId] >= voteThreshold) {
            SlashInfo memory slashInfo = machineId2SlashInfo[machineId];
            addSlashInfoAndReport(slashInfo);

            removeValueOfStringArray(machineId, pendingSlashMachineIds);
            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2ApprovedCount[machineId];

            for (uint8 i = 0; i < adminsToApprove.length; i++) {
                pendingSlashMachineId2ApprovedAdmins[machineId][adminsToApprove[i]] = Vote.Finished;
            }

            SafeERC20.safeTransfer(feeToken, slashInfo.renter, REPORT_RESERVE_AMOUNT);
            emit ExecuteReport(machineId, Vote.Yes);
        }
    }

    function rejectMachineFaultReporting(string calldata machineId) external onlyApproveAdmins {
        require(machineId2SlashInfo[machineId].renter != address(0), ReportedMachineNotFound());

        require(pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] != Vote.Finished, VoteFinished());
        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.No;
        pendingSlashMachineId2RefuseCount[machineId] += 1;
        emit RefusedReport(machineId, msg.sender);
        if (pendingSlashMachineId2RefuseCount[machineId] >= voteThreshold) {
            removeValueOfStringArray(machineId, pendingSlashMachineIds);
            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2ApprovedCount[machineId];

            for (uint8 i = 0; i < adminsToApprove.length; i++) {
                pendingSlashMachineId2ApprovedAdmins[machineId][adminsToApprove[i]] = Vote.Finished;
            }

            uint256 amountPerAdmin = REPORT_RESERVE_AMOUNT / adminsToApprove.length;
            for (uint256 i = 0; i < adminsToApprove.length; i++) {
                if (adminsToApprove[i] == address(0)) {
                    continue;
                }
                SafeERC20.safeTransfer(feeToken, adminsToApprove[i], amountPerAdmin);
            }

            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2RefuseCount[machineId];

            emit ExecuteReport(machineId, Vote.No);
        }
    }

    function version() external pure returns (uint256) {
        return 0;
    }

    function getBurnedRentFeeByStakeHolder(address stakeHolder) public view returns (uint256) {
        return stakeHolder2RentFee[stakeHolder];
    }

    function getTotalBurnedRentFee() public view returns (uint256) {
        return totalBurnedAmount;
    }

    function getRentedGPUCountOfStakeHolder(address stakeHolder) public view returns (uint256) {
        return stakeHolder2RentGPUInfo[stakeHolder].rentedGPUCount;
    }

    function getTotalRentedGPUCount() public view returns (uint256) {
        return rentGPUInfo.rentedGPUCount;
    }

    function isRented(string memory machineId) public view returns (bool) {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        if (rentInfo.renter != address(0)) {
            return true;
        }
        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock > 0) {
            return block.number <= lastRentEndBlock + 30;
        }
        return false;
    }

    function getRenter(string calldata machineId) public view returns (address) {
        uint256 rentId = machineId2RentId[machineId];
        address renter = rentId2RentInfo[rentId].renter;
        return renter;
    }

    function notify(NotifyType tp, string calldata machineId) external onlyDBCAIContract returns (bool) {
        if (tp == NotifyType.ContractRegister) {
            registered = true;
            return true;
        }

        bool isStaking = stakingContract.isStaking(machineId);
        if (!isStaking) {
            return false;
        }

        if (tp == NotifyType.MachineOffline) {
            uint256 rentId = machineId2RentId[machineId];
            RentInfo memory rentInfo = rentId2RentInfo[rentId];
            if (
                rentInfo.renter != address(0) && block.timestamp <= rentInfo.rentEndTime
                    && block.timestamp > rentInfo.rentStatTime
            ) {
                SlashInfo memory slashInfo = newSlashInfo(
                    rentInfo.stakeHolder,
                    rentInfo.machineId,
                    SLASH_AMOUNT,
                    rentInfo.rentStatTime,
                    rentInfo.rentEndTime,
                    block.timestamp - rentInfo.rentStatTime,
                    SlashType.Offline,
                    rentInfo.renter
                );
                addSlashInfoAndReport(slashInfo);
                emit SlashMachineOnOffline(
                    rentInfo.stakeHolder,
                    rentInfo.machineId,
                    rentInfo.renter,
                    SLASH_AMOUNT,
                    rentInfo.rentStatTime,
                    rentInfo.rentEndTime,
                    SlashType.Offline
                );
            } else {
                stakingContract.stopRewarding(machineId);
                emit RemoveCalcPointOnOffline(machineId);
            }
        } else if (tp == NotifyType.MachineOnline && stakingContract.isStakingButOffline(machineId)) {
            stakingContract.recoverRewarding(machineId);
            emit AddCalcPointOnline(machineId);
        }
        return true;
    }

    function getSlashInfosByMachineId(string memory machineId, uint256 pageNumber, uint256 pageSize)
        external
        view
        returns (SlashInfo[] memory paginatedSlashInfos, uint256 totalCount)
    {
        totalCount = machineId2SlashInfos[machineId].length;

        if (pageNumber == 0 || pageSize == 0 || totalCount == 0) {
            return (new SlashInfo[](0), 0);
        }

        // Calculate the start index for the requested page
        uint256 startIndex = (pageNumber - 1) * pageSize;

        // Ensure startIndex is within bounds
        if (startIndex >= totalCount) {
            return (new SlashInfo[](0), totalCount);
        }

        // Calculate the end index for pagination
        uint256 endIndex = startIndex + pageSize > totalCount ? totalCount : startIndex + pageSize;
        uint256 resultSize = endIndex - startIndex;

        // Create a new array for paginated results
        paginatedSlashInfos = new SlashInfo[](resultSize);

        // Populate the paginated array
        for (uint256 i = 0; i < resultSize; i++) {
            paginatedSlashInfos[i] = machineId2SlashInfos[machineId][startIndex + i];
        }
    }

    function paidSlash(string memory machineId) external onlyStakingContract {
        SlashInfo[] storage slashInfos = machineId2SlashInfos[machineId];
        for (uint256 i = 0; i < slashInfos.length; i++) {
            if (slashInfos[i].paid) {
                return;
            }
            if (keccak256(abi.encodePacked(slashInfos[i].machineId)) == keccak256(abi.encodePacked(machineId))) {
                slashInfos[i].paid = true;
                emit PaidSlash(machineId);
            }
        }
    }

    function isInSlashing(string memory machineId) public view returns (bool) {
        return machineId2SlashInfo[machineId].paid == false;
    }

    function distributePlatformFee(uint256 rentId, string memory machineId, uint256 platformFee) internal {
        (address[] memory beneficiaries, uint256[] memory rates,) = stakingContract.getMachineConfig(machineId);
        for (uint8 i = 0; i < beneficiaries.length; i++) {
            feeToken.transfer(beneficiaries[i], platformFee * rates[i] / 100);
            emit PlatformFeeTransfer(beneficiaries[i], rentId, platformFee * rates[i] / 100);
        }
    }
}
