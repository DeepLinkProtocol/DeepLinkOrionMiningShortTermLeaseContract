// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/IPrecompileContract.sol";
import "../interface/IStakingContract.sol";
import "../interface/IRewardToken.sol";
import "../interface/IRentContract.sol";

contract OldRent is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint8 public constant SECONDS_PER_BLOCK = 6;
    uint256 public constant REPORT_RESERVE_AMOUNT = 10000 * 1e18;

    IRewardToken public feeToken;
    IPrecompileContract public precompileContract;

    IStakingContract public phaseOneOrionStakingContract;
    IStakingContract public phaseTwoOrionStakingContract;
    IStakingContract public phaseThreeOrionStakingContract;

    IStakingContract public currentStakingContract;

    enum StakingType {
        Unknown,
        phaseOne,
        phaseTwo,
        phaseThree,
        commonStaking
    }

    StakingType public currentStakingType;

    uint256 public lastRentId;

    mapping(string => address) public machineId2Reporter;

    struct RentInfo {
        string machineId;
        uint256 rentEndTime;
        uint8 gpuCount;
        address renter;
    }

    mapping(uint256 => RentInfo) public rentInfos;

    mapping(string => uint256[]) public machineId2RentIds;
    mapping(address => uint256[]) public user2RentIds;

    mapping(string => uint8) public machineId2RentedGpuCount;

    struct BurnedSummary {
        uint256 phaseOneOrionTotalBurnedAmount;
        uint256 phaseTwoOrionTotalBurnedAmount;
        uint256 phaseThreeOrionTotalBurnedAmount;
        uint256 commonStakingTotalBurnedAmount;
        uint256 totalBurnedAmount;
    }

    BurnedSummary public burnedSummary;

    struct BurnedDetail {
        uint256 rentId;
        uint256 burnTime;
        uint256 burnDLCAmount;
        address renter;
        uint8 rentGpuCount;
    }

    struct BurnedInfo {
        BurnedDetail[] details;
        uint256 totalBurnedAmount;
    }

    mapping(string => BurnedInfo) public machineId2BurnedInfo;

    address[] public adminsToApprove;

    uint8 public voteThreshold;
    string[] public pendingSlashMachineIds;
    mapping(string => address[]) public pendingSlashMachineId2Renters;

    enum Vote {
        None,
        Yes,
        No,
        Finished
    }

    mapping(string => mapping(address => Vote)) public pendingSlashMachineId2ApprovedAdmins;
    mapping(string => uint8) public pendingSlashMachineId2ApprovedCount;
    mapping(string => uint8) public pendingSlashMachineId2RefuseCount;

    mapping(StakingType => mapping(address => uint256)) public stakeHolder2RentFeeOfStakingType;
    mapping(StakingType => mapping(address => uint256)) public stakeHolder2RentedGPUCountOfStakingType;
    mapping(StakingType => uint256) public stakingType2totalRentedGPUCount;

    event RentMachine(uint256 rentId, string machineId, uint256 rentEndTime, uint8 gpuCount, address renter);
    event EndRentMachine(uint256 rentId, string machineId, uint256 rentEndTime, uint8 gpuCount, address renter);
    event ReportMachineFault(uint256 rentId, string machineId, address reporter);
    event BurnedFee(
        string machineId, uint256 rentId, uint256 burnTime, uint256 burnDLCAmount, address renter, uint8 rentGpuCount
    );
    event ApprovedReport(string machineId, address admin);
    event RefusedReport(string machineId, address admin);
    event ExecuteReport(string machineId, Vote vote);

    modifier onlyAdmins() {
        bool found = false;
        for (uint8 i = 0; i < adminsToApprove.length; i++) {
            if (msg.sender == adminsToApprove[i]) {
                found = true;
                break;
            }
        }
        require(found, "not admin");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _precompileContract,
        address _feeToken,
        address _phaseOneOrionStakingContract,
        address _phaseTwoOrionStakingContract,
        address _phaseThreeOrionStakingContract
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
        feeToken = IRewardToken(_feeToken);
        voteThreshold = 2;
        if (_precompileContract != address(0x0)) {
            precompileContract = IPrecompileContract(_precompileContract);
        }

        if (_phaseOneOrionStakingContract != address(0x0)) {
            phaseOneOrionStakingContract = IStakingContract(_phaseOneOrionStakingContract);
            currentStakingType = StakingType.phaseOne;
        }

        if (_phaseTwoOrionStakingContract != address(0x0)) {
            phaseTwoOrionStakingContract = IStakingContract(_phaseTwoOrionStakingContract);
            currentStakingType = StakingType.phaseTwo;
        }

        if (_phaseThreeOrionStakingContract != address(0x0)) {
            phaseThreeOrionStakingContract = IStakingContract(_phaseThreeOrionStakingContract);
            currentStakingType = StakingType.phaseThree;
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAdminsToApproveMachineFaultReporting(address[] calldata admins) external onlyOwner {
        adminsToApprove = admins;
    }

    function setPrecompileContract(address _precompileContract) external onlyOwner {
        precompileContract = IPrecompileContract(_precompileContract);
    }

    function setFeeToken(address _feeToken) external onlyOwner {
        feeToken = IRewardToken(_feeToken);
    }

    function setCurrentStakingContract(StakingType _stakingType, address addr) external onlyOwner {
        require(_stakingType != StakingType.Unknown, "staking type not found");
        currentStakingType = _stakingType;
        currentStakingContract = IStakingContract(addr);
    }

    function findUintIndex(uint256[] memory arr, uint256 v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == v) {
                return i;
            }
        }
        revert("Element not found");
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
        revert("Element not found");
    }

    function removeValueOfStringArray(string memory addr, string[] storage arr) internal {
        uint256 index = findStringIndex(arr, addr);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function getNextRentId() internal returns (uint256) {
        require(lastRentId < type(uint256).max, "ID overflow");
        lastRentId += 1;
        return lastRentId;
    }

    function getDLCMachineRentFee(string memory machineId, uint256 rentBlockNumbers, uint256 rentGpuNumbers)
        public
        view
        returns (uint256)
    {
        return precompileContract.getDLCMachineRentFee(machineId, rentBlockNumbers, rentGpuNumbers);
    }

    function rentMachine(string calldata machineId, uint256 rentBlockNumbers, uint8 gpuCount, uint256 rentFee)
        external
    {
        require(rentBlockNumbers % (10 * 30) == 0, "rent duration should be a multiple of 30 minutes");

        uint256 rentDuration = rentBlockNumbers * SECONDS_PER_BLOCK;
        require(rentDuration > 0, "rent duration should be greater than 0");

        StakingType stakingType = currentStakingType;
        require(currentStakingType != StakingType.Unknown, "machine not found");

        uint8 rentedGpuCount = machineId2RentedGpuCount[machineId];
        require(rentedGpuCount + gpuCount <= precompileContract.getMachineGPUCount(machineId), "gpu count not enough");

        uint256 rentFeeInFact = getDLCMachineRentFee(machineId, rentBlockNumbers, uint256(gpuCount));
        require(rentFee >= rentFeeInFact, "rent fee not enough");
        machineId2RentedGpuCount[machineId] += gpuCount;

        // save rent info
        lastRentId = getNextRentId();
        rentInfos[lastRentId] = RentInfo({
            machineId: machineId,
            rentEndTime: block.timestamp + rentDuration,
            gpuCount: gpuCount,
            renter: msg.sender
        });
        machineId2RentIds[machineId].push(lastRentId);
        user2RentIds[msg.sender].push(lastRentId);

        // burn rent fee
        feeToken.burnFrom(msg.sender, rentFeeInFact);
        emit BurnedFee(machineId, lastRentId, block.timestamp, rentFeeInFact, msg.sender, gpuCount);

        // add machine burn info
        BurnedDetail memory burnedDetail = BurnedDetail({
            rentId: lastRentId,
            burnTime: block.timestamp,
            burnDLCAmount: rentFeeInFact,
            renter: msg.sender,
            rentGpuCount: gpuCount
        });

        address machineHolder = getMachineHolder(machineId);
        stakeHolder2RentedGPUCountOfStakingType[currentStakingType][machineHolder] += gpuCount;
        stakingType2totalRentedGPUCount[currentStakingType] += gpuCount;

        stakeHolder2RentFeeOfStakingType[currentStakingType][machineHolder] += rentFeeInFact;
        BurnedInfo storage burnedInfo = machineId2BurnedInfo[machineId];
        burnedInfo.details.push(burnedDetail);
        burnedInfo.totalBurnedAmount += rentFeeInFact;

        // update total burned amount
        if (stakingType == StakingType.phaseOne) {
            burnedSummary.phaseOneOrionTotalBurnedAmount += rentFeeInFact;
        } else if (stakingType == StakingType.phaseTwo) {
            burnedSummary.phaseTwoOrionTotalBurnedAmount += rentFeeInFact;
        } else if (stakingType == StakingType.phaseThree) {
            burnedSummary.phaseThreeOrionTotalBurnedAmount += rentFeeInFact;
        } else if (stakingType == StakingType.commonStaking) {
            burnedSummary.commonStakingTotalBurnedAmount += rentFeeInFact;
        }
        burnedSummary.totalBurnedAmount += rentFeeInFact;

        // notify staking contract renting machine action happened
        currentStakingContract.rentMachine(machineId, rentFee, gpuCount);

        emit RentMachine(lastRentId, machineId, block.timestamp + rentDuration, gpuCount, msg.sender);
    }

    function endRentMachine(uint256 rentId) external {
        RentInfo memory rentInfo = rentInfos[rentId];
        require(getMachineHolder(rentInfo.machineId) == msg.sender, "not machine owner");
        string memory machineId = rentInfo.machineId;

        uint8 rentedGPUCount = rentInfos[rentId].gpuCount;
        if (machineId2RentedGpuCount[machineId] >= rentedGPUCount) {
            machineId2RentedGpuCount[machineId] -= rentedGPUCount;
        } else {
            machineId2RentedGpuCount[machineId] = 0;
        }
        removeValueOfUintArray(rentId, user2RentIds[rentInfo.renter]);
        delete rentInfos[rentId];
        removeValueOfUintArray(rentId, machineId2RentIds[machineId]);

        address machineHolder = getMachineHolder(machineId);
        stakeHolder2RentedGPUCountOfStakingType[currentStakingType][machineHolder] -= rentInfo.gpuCount;
        stakingType2totalRentedGPUCount[currentStakingType] += rentInfo.gpuCount;

        currentStakingContract.endRentMachine(machineId, rentedGPUCount);

        emit EndRentMachine(rentId, machineId, rentInfo.rentEndTime, rentInfo.gpuCount, rentInfo.renter);
    }

    function getMachineHolder(string memory machineId) internal view returns (address) {
        return currentStakingContract.getMachineHolder(machineId);
    }

    function getMachineGPUCount(string memory machineId) external view returns (uint8) {
        return precompileContract.getMachineGPUCount(machineId);
    }

    function reportMachineFault(uint256 rentId, uint256 reserveAmount) external {
        require(reserveAmount == REPORT_RESERVE_AMOUNT, "reserve amount should be 10000");
        require(currentStakingType != StakingType.Unknown, "machine not found");
        RentInfo memory rentInfo = rentInfos[rentId];
        require(rentInfo.renter == msg.sender, "not rent owner");
        require(rentInfo.rentEndTime >= block.timestamp, "rent end");

        feeToken.transferFrom(msg.sender, address(this), REPORT_RESERVE_AMOUNT);
        machineId2Reporter[rentInfo.machineId] = msg.sender;

        uint256[] memory rentIds = machineId2RentIds[rentInfo.machineId];
        for (uint8 i = 0; i < rentIds.length; i++) {
            uint256 _rentId = rentIds[i];
            RentInfo memory _rentInfo = rentInfos[_rentId];
            pendingSlashMachineId2Renters[rentInfo.machineId].push(_rentInfo.renter);
        }
        pendingSlashMachineIds.push(rentInfo.machineId);
        emit ReportMachineFault(rentId, rentInfo.machineId, msg.sender);
    }

    function approveMachineFaultReporting(string calldata machineId) external onlyAdmins {
        require(pendingSlashMachineId2Renters[machineId].length > 0, "not found reported machine");

        require(pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] != Vote.Finished, "vote already finished");
        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.Yes;
        emit ApprovedReport(machineId, msg.sender);
        pendingSlashMachineId2ApprovedCount[machineId] += 1;
        if (pendingSlashMachineId2ApprovedCount[machineId] >= voteThreshold) {
            address[] memory renters = pendingSlashMachineId2Renters[machineId];
            currentStakingContract.reportMachineFault(machineId, renters);

            removeValueOfStringArray(machineId, pendingSlashMachineIds);
            delete pendingSlashMachineId2Renters[machineId];
            delete pendingSlashMachineId2ApprovedCount[machineId];

            for (uint8 i = 0; i < adminsToApprove.length; i++) {
                pendingSlashMachineId2ApprovedAdmins[machineId][adminsToApprove[i]] = Vote.Finished;
            }

            address reporter = machineId2Reporter[machineId];
            feeToken.transfer(reporter, REPORT_RESERVE_AMOUNT);
            delete machineId2Reporter[machineId];
            emit ExecuteReport(machineId, Vote.Yes);
        }
    }

    function refuseMachineFaultReporting(string calldata machineId) external onlyAdmins {
        require(pendingSlashMachineId2Renters[machineId].length > 0, "not found reported machine");

        require(pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] != Vote.Finished, "vote already finished");
        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.No;
        pendingSlashMachineId2RefuseCount[machineId] += 1;
        emit RefusedReport(machineId, msg.sender);
        if (pendingSlashMachineId2RefuseCount[machineId] >= voteThreshold) {
            removeValueOfStringArray(machineId, pendingSlashMachineIds);
            delete pendingSlashMachineId2Renters[machineId];
            delete pendingSlashMachineId2ApprovedCount[machineId];

            for (uint8 i = 0; i < adminsToApprove.length; i++) {
                pendingSlashMachineId2ApprovedAdmins[machineId][adminsToApprove[i]] = Vote.Finished;
            }

            uint256 amountPerAdmin = REPORT_RESERVE_AMOUNT / adminsToApprove.length;
            for (uint256 i = 0; i < adminsToApprove.length; i++) {
                feeToken.transferFrom(address(this), adminsToApprove[i], amountPerAdmin);
            }

            address reporter = machineId2Reporter[machineId];
            feeToken.transfer(reporter, REPORT_RESERVE_AMOUNT);
            delete machineId2Reporter[machineId];

            emit ExecuteReport(machineId, Vote.No);
        }
    }

    function version() external pure returns (uint256) {
        return 6;
    }

    function getBurnedRentFeeByStakeHolder(uint8 phaseLevel, address stakeHolder) public view returns (uint256) {
        if (phaseLevel == 1) {
            return stakeHolder2RentFeeOfStakingType[StakingType.phaseOne][stakeHolder];
        }
        if (phaseLevel == 2) {
            return stakeHolder2RentFeeOfStakingType[StakingType.phaseTwo][stakeHolder];
        }
        if (phaseLevel == 3) {
            return stakeHolder2RentFeeOfStakingType[StakingType.phaseThree][stakeHolder];
        }
        return stakeHolder2RentFeeOfStakingType[StakingType.commonStaking][stakeHolder];
    }

    function getTotalBurnedRentFee(uint8 phaseLevel) public view returns (uint256) {
        if (phaseLevel == 1) {
            return burnedSummary.phaseOneOrionTotalBurnedAmount;
        }
        if (phaseLevel == 2) {
            return burnedSummary.phaseTwoOrionTotalBurnedAmount;
        }
        if (phaseLevel == 3) {
            return burnedSummary.phaseThreeOrionTotalBurnedAmount;
        }
        return burnedSummary.commonStakingTotalBurnedAmount;
    }

    function getRentedGPUCountOfStakeHolder(address stakeHolder) public view returns (uint256) {
        return stakeHolder2RentedGPUCountOfStakingType[currentStakingType][stakeHolder];
    }

    function getTotalRentedGPUCount(uint256 phaseLevel) public view returns (uint256) {
        if (phaseLevel == 1) {
            return stakingType2totalRentedGPUCount[StakingType.phaseOne];
        }
        if (phaseLevel == 2) {
            return stakingType2totalRentedGPUCount[StakingType.phaseTwo];
        }
        if (phaseLevel == 3) {
            return stakingType2totalRentedGPUCount[StakingType.phaseThree];
        }
        return stakingType2totalRentedGPUCount[StakingType.commonStaking];
    }

    function isRented(string calldata machineId) external view returns (bool) {
        return machineId2RentedGpuCount[machineId] > 0;
    }
}
