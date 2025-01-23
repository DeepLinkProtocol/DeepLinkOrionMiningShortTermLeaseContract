// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
//
//import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
//import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
//import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
//import "../interface/IStakingContract.sol";
//import "../interface/IRewardToken.sol";
//import "../interface/IRentContract.sol";
//import "../interface/IPrecompileContract.sol";
//import "../interface/IStateContract.sol";
//import "forge-std/console.sol";
//
///// @custom:oz-upgrades-from OldRent
//contract Rent is Initializable, OwnableUpgradeable, UUPSUpgradeable {
//    uint8 public constant SECONDS_PER_BLOCK = 6;
//    uint256 public constant REPORT_RESERVE_AMOUNT = 10000 * 1e18;
//    uint256 public constant SLASH_AMOUNT = 10000 * 1e18;
//
//    IRewardToken public feeToken;
//
//    IPrecompileContract public precompileContract;
//    IStakingContract public stakingContract;
//    IStateContract public stateContract;
//
//    uint256 public lastRentId;
//
//    struct RentInfo {
//        address stakeHolder;
//        string machineId;
//        uint256 rentStatTime;
//        uint256 rentEndTime;
//        address renter;
//    }
//
//    mapping(uint256 => RentInfo) public rentId2RentInfo;
//
//    mapping(string => uint256) public machineId2RentId;
//    mapping(address => uint256[]) public renter2RentIds;
//
//    uint256 public totalBurnedAmount;
//
//    struct BurnedDetail {
//        uint256 rentId;
//        uint256 burnTime;
//        uint256 burnDLCAmount;
//        address renter;
//    }
//
//    struct BurnedInfo {
//        BurnedDetail[] details;
//        uint256 totalBurnedAmount;
//    }
//
//    mapping(string => BurnedInfo) public machineId2BurnedInfo;
//
//    address[] public adminsToApprove;
//
//    uint8 public voteThreshold;
//    string[] public pendingSlashMachineIds;
//    mapping(string => SlashInfo) public machineId2SlashInfo;
//    mapping(address => SlashInfo[]) public stakeHolder2SlashInfos;
//
//    enum SlashType {
//        Offline,
//        RenterReport
//    }
//
//    struct SlashInfo {
//        address stakeHolder;
//        string machineId;
//        uint256 slashAmount;
//        uint256 rentStartAtTimestamp;
//        uint256 rentEndAtTimestamp;
//        uint256 rentedDurationSeconds;
//        address renter;
//        SlashType slashType;
//        uint256 createdAt;
//        bool paid;
//    }
//
//    bool registered;
//
//    enum NotifyType {
//        ContractRegister,
//        MachineRegister,
//        MachineUnregister,
//        MachineOnline,
//        MachineOffline
//    }
//
//    enum Vote {
//        None,
//        Yes,
//        No,
//        Finished
//    }
//
//    mapping(string => mapping(address => Vote))
//    public pendingSlashMachineId2ApprovedAdmins;
//    mapping(string => uint8) public pendingSlashMachineId2ApprovedCount;
//    mapping(string => uint8) public pendingSlashMachineId2RefuseCount;
//
//    mapping(address => uint256) public stakeHolder2RentFee;
//    struct RentGPUInfo {
//        uint256 rentedGPUCount;
//        uint256 rentingGPUCount;
//    }
//    RentGPUInfo public rentGPUInfo;
//    mapping(address => RentGPUInfo) public stakeHolder2RentGPUInfo;
//    mapping(string => uint256) public machineId2LastRentEndBlock;
//
//    event RentMachine(
//        uint256 rentId,
//        string machineId,
//        uint256 rentEndTime,
//        uint8 gpuCount,
//        address renter
//    );
//    event RenewRent(
//        uint256 rentId,
//        uint256 additionalRentSeconds,
//        uint256 additionalRentFee,
//        address renter
//    );
//    event EndRentMachine(
//        uint256 rentId,
//        string machineId,
//        uint256 rentEndTime,
//        address renter
//    );
//    event ReportMachineFault(
//        uint256 rentId,
//        string machineId,
//        address reporter
//    );
//    event BurnedFee(
//        string machineId,
//        uint256 rentId,
//        uint256 burnTime,
//        uint256 burnDLCAmount,
//        address renter,
//        uint8 rentGpuCount
//    );
//    event ApprovedReport(string machineId, address admin);
//    event RefusedReport(string machineId, address admin);
//    event ExecuteReport(string machineId, Vote vote);
//    event MachineRegister(string machineId, uint256 calcPoint);
//    event MachineUnregister(string machineId, uint256 calcPoint);
//    event PaidSlash(address indexed stakeHolder, string machineId);
//
//    modifier onlyAdmins() {
//        bool found = false;
//        for (uint8 i = 0; i < adminsToApprove.length; i++) {
//            if (msg.sender == adminsToApprove[i]) {
//                found = true;
//                break;
//            }
//        }
//        require(found, "not admin");
//        _;
//    }
//
//    modifier onlyStakingContract() {
//        require(msg.sender == address(stakingContract), "only staking contract");
//        _;
//    }
//
//    /// @custom:oz-upgrades-unsafe-allow constructor
//    constructor() {
//        _disableInitializers();
//    }
//
//    function initialize(
//        address _initialOwner,
//        address _precompileContract,
//        address _stakingContract,
//        address _stateContract,
//        address _feeToken
//    ) public initializer {
//        __Ownable_init(_initialOwner);
//        __UUPSUpgradeable_init();
//        feeToken = IRewardToken(_feeToken);
//        precompileContract = IPrecompileContract(_precompileContract);
//        stakingContract = IStakingContract(_stakingContract);
//        stateContract = IStateContract(_stateContract);
//
//        voteThreshold = 3;
//    }
//
//    function _authorizeUpgrade(
//        address newImplementation
//    ) internal override onlyOwner {}
//
//    function setAdminsToApproveMachineFaultReporting(
//        address[] calldata admins
//    ) external onlyOwner {
//        require(admins.length == 5, "admins length should be 5");
//        adminsToApprove = admins;
//    }
//
//    function setFeeToken(address _feeToken) external onlyOwner {
//        require(
//            _feeToken != address(0x0),
//            "fee token address should not be 0x0"
//        );
//        feeToken = IRewardToken(_feeToken);
//    }
//
//    function setStakingContract(address addr) external onlyOwner {
//        stakingContract = IStakingContract(addr);
//    }
//
//    function setPrecompileContract(
//        address _precompileContract
//    ) external onlyOwner {
//        require(
//            _precompileContract != address(0x0),
//            "precompile contract address should not be 0x0"
//        );
//        precompileContract = IPrecompileContract(_precompileContract);
//    }
//
//    function findUintIndex(
//        uint256[] memory arr,
//        uint256 v
//    ) internal pure returns (uint256) {
//        for (uint256 i = 0; i < arr.length; i++) {
//            if (arr[i] == v) {
//                return i;
//            }
//        }
//        revert("Element not found");
//    }
//
//    function removeValueOfUintArray(uint256 v, uint256[] storage arr) internal {
//        uint256 index = findUintIndex(arr, v);
//        arr[index] = arr[arr.length - 1];
//        arr.pop();
//    }
//
//    function findStringIndex(
//        string[] memory arr,
//        string memory v
//    ) internal pure returns (uint256) {
//        for (uint256 i = 0; i < arr.length; i++) {
//            if (
//                keccak256(abi.encodePacked(arr[i])) ==
//                keccak256(abi.encodePacked(v))
//            ) {
//                return i;
//            }
//        }
//        revert("Element not found");
//    }
//
//    function removeValueOfStringArray(
//        string memory addr,
//        string[] storage arr
//    ) internal {
//        uint256 index = findStringIndex(arr, addr);
//        arr[index] = arr[arr.length - 1];
//        arr.pop();
//    }
//
//    function getNextRentId() internal returns (uint256) {
//        require(lastRentId < type(uint256).max, "ID overflow");
//        lastRentId += 1;
//        return lastRentId;
//    }
//
//    function canRent(
//        string calldata machineId,
//        uint256 rentSeconds
//    ) public view returns (bool) {
//        console.log("00");
//
//        require(stakingContract.isStaking(machineId), "machine not staked");
//        console.log("11");
//
//        (
//            ,
//            ,
//            ,
//            uint256 endAtTimestamp,
//            uint256 nextRenterCanRentAt,
//            ,
//            bool isOnline,
//            bool isRegistered
//        ) = stakingContract.getMachineInfo(machineId);
//        if (!isOnline || !isRegistered) {
//            return false;
//        }
//        console.log("22");
//
//
//        if (nextRenterCanRentAt > block.timestamp) {
//            // not reach the start rent block number yet
//            return false;
//        }
//
//        uint256 _now = block.timestamp;
//        if ((_now < endAtTimestamp && endAtTimestamp - _now > 1 hours)) {
//            uint256 maxRentDuration = endAtTimestamp - _now;
//            return maxRentDuration >= rentSeconds;
//        }
//
//        // unLimit stake time
//        return endAtTimestamp == 0;
//    }
//
//    function getMachineInfo(
//        string memory machineId
//    )
//    public
//    view
//    returns (
//        uint256 availableRentHours,
//        uint256 reservedAmount,
//        uint256 rentFeePerHour
//    )
//    {
//        (, , , uint256 endAt, , uint256 _reservedAmount, , ) = stakingContract
//            .getMachineInfo(machineId);
//        uint256 rentFee = getMachinePrice(
//            machineId,
//            1 hours / SECONDS_PER_BLOCK
//        );
//
//        if (isRented(machineId)) {
//            return (0, _reservedAmount, rentFee);
//        }
//
//        return (endAt - block.timestamp / 1 hours, _reservedAmount, rentFee);
//    }
//
//    function getMachinePrice(
//        string memory machineId,
//        uint256 rentSeconds
//    ) public view returns (uint256) {
//        (, uint256 calcPoint) = getMachineHolderAndCalcPoint(machineId);
//        require(calcPoint > 0, "machine calcPoint is 0 now");
//        uint256 rentBlockNumbers = rentSeconds / SECONDS_PER_BLOCK;
//        uint256 rentFee = precompileContract.getDLCRentFeeByCalcPoint(
//            calcPoint,
//            rentBlockNumbers,
//            1,
//            1
//        );
//        return rentFee;
//    }
//
//    function rentMachine(
//        string calldata machineId,
//        uint256 rentSeconds,
//        uint256 rentFee
//    ) external {
//        require(rentSeconds > 0, "rent duration should be greater than 0");
//        require(canRent(machineId, rentSeconds), "machine can not rent");
//        console.log("machine can rent");
//        require(!isRented(machineId), "machine already rented");
//        require(
//            rentSeconds >= 10 minutes,
//            "rent duration should be greater than 10 minutes"
//        );
//        require(
//            rentSeconds <= 2 hours ,
//            "rent duration should be less than 2 hours"
//        );
//
//        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
//        if (lastRentEndBlock != 0) {
//            require(
//                block.number > lastRentEndBlock + 100,
//                "machine can not rent too frequently"
//            );
//        }
//
//        uint256 rentFeeInFact = getMachinePrice(machineId, rentSeconds);
//        require(rentFee >= rentFeeInFact, "rent fee not enough");
//
//        (address machineHolder, , , , , , , ) = stakingContract
//            .getMachineInfo(machineId);
//        // save rent info
//        uint256 _now = block.timestamp;
//        lastRentId = getNextRentId();
//        rentId2RentInfo[lastRentId] = RentInfo({
//            stakeHolder: machineHolder,
//            machineId: machineId,
//            rentStatTime: _now,
//            rentEndTime: _now + rentSeconds,
//            renter: msg.sender
//        });
//        machineId2RentId[machineId] = lastRentId;
//        renter2RentIds[msg.sender].push(lastRentId);
//
//        // burn rent fee
//        feeToken.burnFrom(msg.sender, rentFeeInFact);
//        emit BurnedFee(
//            machineId,
//            lastRentId,
//            block.timestamp,
//            rentFeeInFact,
//            msg.sender,
//            1
//        );
//
//        // add machine burn info
//        BurnedDetail memory burnedDetail = BurnedDetail({
//            rentId: lastRentId,
//            burnTime: block.timestamp,
//            burnDLCAmount: rentFeeInFact,
//            renter: msg.sender
//        });
//
//        stakeHolder2RentGPUInfo[machineHolder].rentedGPUCount += 1;
//        stakeHolder2RentGPUInfo[machineHolder].rentingGPUCount += 1;
//        rentGPUInfo.rentedGPUCount += 1;
//        rentGPUInfo.rentingGPUCount += 1;
//
//        stakeHolder2RentFee[machineHolder] += rentFeeInFact;
//        BurnedInfo storage burnedInfo = machineId2BurnedInfo[machineId];
//        burnedInfo.details.push(burnedDetail);
//        burnedInfo.totalBurnedAmount += rentFeeInFact;
//
//        // update total burned amount
//        totalBurnedAmount += rentFeeInFact;
//
//        // notify staking contract renting machine action happened
//        stakingContract.rentMachine(machineId, rentFee);
//
//        emit RentMachine(
//            lastRentId,
//            machineId,
//            block.timestamp + rentSeconds,
//            1,
//            msg.sender
//        );
//    }
//
//    function renewRent(
//        string memory machineId,
//        uint256 additionalRentSeconds,
//        uint256 additionalRentFee
//    ) external {
//        uint256 rentId = machineId2RentId[machineId];
//        require(additionalRentSeconds > 0, "additional rent duration should be greater than 0");
//        require(
//            rentId2RentInfo[rentId].rentEndTime > block.timestamp,
//            "rent end"
//        );
//        require(
//            rentId2RentInfo[rentId].renter == msg.sender,
//            "Only the renter can renew the rent"
//        );
//        require(isRented(machineId), "Machine is not currently rented");
//        require(
//            additionalRentSeconds >= 10 minutes ,
//            "Additional rent duration should be greater than 10 minutes"
//        );
//        require(
//            additionalRentSeconds <= 2 hours,
//            "Additional rent duration should be less than 2 hours"
//        );
//
//
//
//        uint256 additionalRentFeeInFact = getMachinePrice(
//            rentId2RentInfo[rentId].machineId,
//            additionalRentSeconds
//        );
//        require(
//            additionalRentFee >= additionalRentFeeInFact,
//            "Additional rent fee not enough"
//        );
//
//        // Update rent end time
//        rentId2RentInfo[rentId].rentEndTime += additionalRentSeconds;
//
//        // Burn additional rent fee
//        feeToken.burnFrom(msg.sender, additionalRentFeeInFact);
//
//        emit BurnedFee(
//            machineId,
//            rentId,
//            block.timestamp,
//            additionalRentFeeInFact,
//            msg.sender,
//            1
//        );
//
//        // add machine burn info
//        BurnedDetail memory burnedDetail = BurnedDetail({
//            rentId: rentId,
//            burnTime: block.timestamp,
//            burnDLCAmount: additionalRentFeeInFact,
//            renter: msg.sender
//        });
//
//        (address machineHolder, ) = getMachineHolderAndCalcPoint(machineId);
//
//        stakeHolder2RentFee[machineHolder] += additionalRentFeeInFact;
//        BurnedInfo storage burnedInfo = machineId2BurnedInfo[machineId];
//        burnedInfo.details.push(burnedDetail);
//        burnedInfo.totalBurnedAmount += additionalRentFeeInFact;
//
//        // update total burned amount
//        totalBurnedAmount += additionalRentFeeInFact;
//
//        stateContract.setBurnedRentFee(
//            machineHolder,
//            machineId,
//            additionalRentFee
//        );
//        emit RenewRent(
//            rentId,
//            additionalRentSeconds,
//            additionalRentFee,
//            msg.sender
//        );
//    }
//
//    function endRentMachine(string calldata machineId) external {
//        uint256  rentId = machineId2RentId[machineId];
//        RentInfo memory rentInfo = rentId2RentInfo[rentId];
//
//        (address machineHolder, ) = getMachineHolderAndCalcPoint(machineId);
//        require(machineHolder == msg.sender, "not machine owner");
//
//        removeValueOfUintArray(rentId, renter2RentIds[rentInfo.renter]);
//        delete rentId2RentInfo[rentId];
//        delete machineId2RentId[machineId];
//
//        stakeHolder2RentGPUInfo[machineHolder].rentingGPUCount -= 1;
//        rentGPUInfo.rentingGPUCount -= 1;
//
//        stakingContract.endRentMachine(machineId);
//        machineId2LastRentEndBlock[machineId] = block.number;
//        emit EndRentMachine(
//            rentId,
//            machineId,
//            rentInfo.rentEndTime,
//            rentInfo.renter
//        );
//    }
//
//    function getMachineHolderAndCalcPoint(
//        string memory machineId
//    ) internal view returns (address, uint256) {
//        (address holder, uint256 calcPoint, , , , , , ) = stakingContract
//            .getMachineInfo(machineId);
//        return (holder, calcPoint);
//    }
//
//    function reportMachineFault(
//        string calldata machineId,
//        uint256 reserveAmount
//    ) external {
//        require(
//            reserveAmount == REPORT_RESERVE_AMOUNT,
//            "reserve amount should be 10000"
//        );
//
//        uint256 rentId = machineId2RentId[machineId];
//        RentInfo memory rentInfo = rentId2RentInfo[rentId];
//        require(rentInfo.renter == msg.sender, "not rent owner");
//        require(rentInfo.rentEndTime >= block.timestamp, "rent end");
//
//        feeToken.transferFrom(msg.sender, address(this), REPORT_RESERVE_AMOUNT);
//
//        machineId2SlashInfo[rentInfo.machineId] = newSlashInfo(
//            rentInfo.stakeHolder,
//            rentInfo.machineId,
//            SLASH_AMOUNT,
//            rentInfo.rentStatTime,
//            rentInfo.rentEndTime,
//            block.timestamp - rentInfo.rentStatTime,
//            SlashType.RenterReport,
//            rentInfo.renter
//        );
//        pendingSlashMachineIds.push(rentInfo.machineId);
//        emit ReportMachineFault(rentId, rentInfo.machineId, msg.sender);
//    }
//
//    function newSlashInfo(
//        address slasher,
//        string memory machineId,
//        uint256 slashAmount,
//        uint256 rentStartAt,
//        uint256 rentEndAt,
//        uint256 rentDuration,
//        SlashType slashType,
//        address renter
//    ) internal view returns (SlashInfo memory) {
//        SlashInfo memory slashInfo = SlashInfo({
//            stakeHolder: slasher,
//            machineId: machineId,
//            slashAmount: slashAmount,
//            rentStartAtTimestamp: rentStartAt,
//            rentEndAtTimestamp: rentEndAt,
//            rentedDurationSeconds: rentDuration,
//            renter: renter,
//            slashType: slashType,
//            createdAt: block.timestamp,
//            paid: false
//        });
//        return slashInfo;
//    }
//
//    function addSlashInfoAndReport(SlashInfo memory slashInfo) internal {
//        stakeHolder2SlashInfos[slashInfo.stakeHolder].push(slashInfo);
//        stakingContract.reportMachineFault(
//            slashInfo.machineId,
//            slashInfo.renter
//        );
//    }
//
//    function approveMachineFaultReporting(
//        string calldata machineId
//    ) external onlyAdmins {
//        require(
//            machineId2SlashInfo[machineId].renter != address(0x0),
//            "not found reported machine"
//        );
//
//        require(
//            pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] !=
//            Vote.Finished,
//            "vote already finished"
//        );
//        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.Yes;
//        emit ApprovedReport(machineId, msg.sender);
//        pendingSlashMachineId2ApprovedCount[machineId] += 1;
//        if (pendingSlashMachineId2ApprovedCount[machineId] >= voteThreshold) {
//            SlashInfo memory slashInfo = machineId2SlashInfo[machineId];
//            addSlashInfoAndReport(slashInfo);
//
//            removeValueOfStringArray(machineId, pendingSlashMachineIds);
//            delete machineId2SlashInfo[machineId];
//            delete pendingSlashMachineId2ApprovedCount[machineId];
//
//            for (uint8 i = 0; i < adminsToApprove.length; i++) {
//                pendingSlashMachineId2ApprovedAdmins[machineId][
//                adminsToApprove[i]
//                ] = Vote.Finished;
//            }
//
//            feeToken.transfer(slashInfo.renter, REPORT_RESERVE_AMOUNT);
//            emit ExecuteReport(machineId, Vote.Yes);
//        }
//    }
//
//    function rejectMachineFaultReporting(
//        string calldata machineId
//    ) external onlyAdmins {
//        require(
//            machineId2SlashInfo[machineId].renter != address(0),
//            "not found reported machine"
//        );
//
//        require(
//            pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] !=
//            Vote.Finished,
//            "vote already finished"
//        );
//        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.No;
//        pendingSlashMachineId2RefuseCount[machineId] += 1;
//        emit RefusedReport(machineId, msg.sender);
//        if (pendingSlashMachineId2RefuseCount[machineId] >= voteThreshold) {
//            removeValueOfStringArray(machineId, pendingSlashMachineIds);
//            delete machineId2SlashInfo[machineId];
//            delete pendingSlashMachineId2ApprovedCount[machineId];
//
//            for (uint8 i = 0; i < adminsToApprove.length; i++) {
//                pendingSlashMachineId2ApprovedAdmins[machineId][
//                adminsToApprove[i]
//                ] = Vote.Finished;
//            }
//
//            uint256 amountPerAdmin = REPORT_RESERVE_AMOUNT /
//                            adminsToApprove.length;
//            for (uint256 i = 0; i < adminsToApprove.length; i++) {
//                feeToken.transferFrom(
//                    address(this),
//                    adminsToApprove[i],
//                    amountPerAdmin
//                );
//            }
//
//            SlashInfo memory slashInfo = machineId2SlashInfo[machineId];
//            feeToken.transfer(slashInfo.renter, REPORT_RESERVE_AMOUNT);
//            delete machineId2SlashInfo[machineId];
//
//            emit ExecuteReport(machineId, Vote.No);
//        }
//    }
//
//    function version() external pure returns (uint256) {
//        return 1;
//    }
//
//    function getBurnedRentFeeByStakeHolder(
//        address stakeHolder
//    ) public view returns (uint256) {
//        return stakeHolder2RentFee[stakeHolder];
//    }
//
//    function getTotalBurnedRentFee() public view returns (uint256) {
//        return totalBurnedAmount;
//    }
//
//    function getRentedGPUCountOfStakeHolder(
//        address stakeHolder
//    ) public view returns (uint256) {
//        return stakeHolder2RentGPUInfo[stakeHolder].rentedGPUCount;
//    }
//
//    function getTotalRentedGPUCount() public view returns (uint256) {
//        return rentGPUInfo.rentedGPUCount;
//    }
//
//    function isRented(string memory machineId) public view returns (bool) {
//        uint256 rentId = machineId2RentId[machineId];
//        RentInfo memory rentInfo = rentId2RentInfo[rentId];
//        if (rentInfo.renter != address(0)) {
//            return true;
//        }
//        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
//        if (lastRentEndBlock > 0) {
//            return block.number <= lastRentEndBlock + 100;
//        }
//        return false;
//    }
//
//    function getRenter(
//        string calldata machineId
//    ) public view returns (address) {
//        uint256 rentId = machineId2RentId[machineId];
//        address renter = rentId2RentInfo[rentId].renter;
//        return renter;
//    }
//
//    function notify(
//        NotifyType tp,
//        string calldata machineId
//    ) external onlyStakingContract returns (bool) {
//        (
//            ,
//            uint256 calcPoint,
//            uint256 stakeStartAtTimestamp,
//            ,
//            ,
//            uint256 reservedAmount,
//            ,
//            bool isRegistered
//        ) = stakingContract.getMachineInfo(machineId);
//
//        if (tp == NotifyType.ContractRegister) {
//            registered = true;
//        } else if (tp == NotifyType.MachineRegister) {
//            if (calcPoint == 0 && stakeStartAtTimestamp > 0) {
//                stakingContract.joinStaking(
//                    machineId,
//                    calcPoint,
//                    reservedAmount
//                );
//            }
//            emit MachineRegister(machineId, calcPoint);
//        } else if (tp == NotifyType.MachineUnregister) {
//            if (stakeStartAtTimestamp > 0) {
//                stakingContract.joinStaking(machineId, 0, reservedAmount);
//            }
//            emit MachineUnregister(machineId, calcPoint);
//        } else if (tp == NotifyType.MachineOffline) {
//            address renter = getRenter(machineId);
//            if (isRegistered && renter != address(0)) {
//                SlashInfo memory slashInfo = machineId2SlashInfo[machineId];
//                addSlashInfoAndReport(slashInfo);
//            }
//        }
//        return true;
//    }
//
//    function getSlashInfosByOwner(
//        address stakeHolder,
//        uint256 pageNumber,
//        uint256 pageSize
//    )
//    external
//    view
//    returns (SlashInfo[] memory paginatedSlashInfos, uint256 totalCount)
//    {
//        require(pageNumber > 0, "Page number must be greater than zero");
//        require(pageSize > 0, "Page size must be greater than zero");
//
//        // Get the total number of SlashInfo for the given machineOwner
//        totalCount = stakeHolder2SlashInfos[stakeHolder].length;
//        require(totalCount > 0, "No data available");
//
//        // Calculate the start index for the requested page
//        uint256 startIndex = (pageNumber - 1) * pageSize;
//
//        // Ensure startIndex is within bounds
//        if (startIndex >= totalCount) {
//            return (new SlashInfo[](0), totalCount);
//        }
//
//        // Calculate the end index for pagination
//        uint256 endIndex = startIndex + pageSize > totalCount
//            ? totalCount
//            : startIndex + pageSize;
//        uint256 resultSize = endIndex - startIndex;
//
//        // Create a new array for paginated results
//        paginatedSlashInfos = new SlashInfo[](resultSize);
//
//        // Populate the paginated array
//        for (uint256 i = 0; i < resultSize; i++) {
//            paginatedSlashInfos[i] = stakeHolder2SlashInfos[stakeHolder][
//                startIndex + i
//                ];
//        }
//    }
//
//    function paidSlash(address holder, string memory machineId) external onlyStakingContract {
//        SlashInfo[] memory slashInfos = stakeHolder2SlashInfos[holder];
//        for (uint256 i = 0; i < slashInfos.length; i++) {
//            if (keccak256(abi.encodePacked(slashInfos[i].machineId)) ==
//                keccak256(abi.encodePacked(machineId))) {
//                if (slashInfos[i].paid){
//                    return;
//                }
//                slashInfos[i].paid = true;
//                emit PaidSlash(holder, machineId);
//            }
//        }
//    }
//}
