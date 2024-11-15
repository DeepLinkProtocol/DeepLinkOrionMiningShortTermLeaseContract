// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/IPrecompileContract.sol";
import "../interface/IRentContract.sol";
import "../interface/IStakingContract.sol";

/// @custom:oz-upgrades-from OldNFTStakingState
contract NFTStakingState is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    IPrecompileContract public precompileContract;
    IRentContract public rentContract;
    IStakingContract public stakingContract;

    uint8 public phaseLevel;

    string[] public machineIds;
    uint256 public addressCountInStaking;
    mapping(address => uint8) public address2MachineCount;

    struct StateSummary {
        uint256 totalCalcPoint;
        uint256 totalGPUCount;
        uint256 totalCalcPointPoolCount;
        uint256 totalRentedGPUCount;
        uint256 totalBurnedRentFee;
        uint256 totalReservedAmount;
        uint256 leftGPUCountBeforeRewardStart;
    }

    struct MachineInfo {
        uint256 calcPoint;
        uint8 gpuCount;
        uint256 reserveAmount;
        uint256 burnedRentFee;
        uint8 rentedGPUCount;
        uint256 totalClaimedRewardAmount;
        uint256 releasedRewardAmount;
    }

    struct StakeHolderInfo {
        address holder;
        uint256 totalCalcPoint;
        uint256 totalGPUCount;
        uint256 rentedGPUCount;
        uint256 totalReservedAmount;
        uint256 burnedRentFee;
        uint256 totalClaimedRewardAmount;
        uint256 releasedRewardAmount;
        string[] machineIds;
        mapping(string => MachineInfo) machineId2Info;
    }

    struct SimpleStakeHolder {
        address holder;
        uint256 totalCalcPoint;
    }

    SimpleStakeHolder[] public topStakeHolders;

    mapping(address => StakeHolderInfo) public stakeHolders;

    struct StakeHolder {
        address holder;
        uint256 totalCalcPoint;
        uint256 totalGPUCount;
        uint256 rentedGPUCount;
        uint256 totalReservedAmount;
        uint256 burnedRentFee;
        uint256 totalClaimedRewardAmount;
        uint256 releasedRewardAmount;
    }

    modifier onlyNftStakingAddress() {
        require(msg.sender == address(stakingContract), "Only NFTStakingAddress can call this function");
        _;
    }

    function initialize(
        address _initialOwner,
        address _precompileContract,
        address _rentContract,
        address _stakingContract,
        uint8 _phase_level
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        precompileContract = IPrecompileContract(_precompileContract);
        rentContract = IRentContract(_rentContract);
        stakingContract = IStakingContract(_stakingContract);
        phaseLevel = _phase_level;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setStakingContract(address caller) external onlyOwner {
        stakingContract = IStakingContract(caller);
    }

    function setPrecompileContract(address _precompileContract) external onlyOwner {
        precompileContract = IPrecompileContract(_precompileContract);
    }

    function setRentContract(address _rentContract) external onlyOwner {
        rentContract = IRentContract(_rentContract);
    }

    function findStringIndex(string[] memory arr, string memory v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (keccak256(abi.encodePacked(arr[i])) == keccak256(abi.encodePacked(v))) {
                return i;
            }
        }
        revert("Element not found");
    }

    function getMachineCalcPoint(string memory machineId) public view returns (uint256) {
        return precompileContract.getMachineCalcPoint(machineId);
    }

    function getMachineGPUCount(string memory machineId) public view returns (uint8) {
        return precompileContract.getMachineGPUCount(machineId);
    }

    function removeStringValueOfArray(string memory addr, string[] storage arr) internal {
        uint256 index = findStringIndex(arr, addr);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function setBurnedRentFee(address _holder, string memory _machineId, uint256 fee) external onlyNftStakingAddress {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        previousMachineInfo.burnedRentFee += fee;
        stakeHolderInfo.burnedRentFee += fee;
    }

    function addRentedGPUCount(address _holder, string memory _machineId, uint8 rentedGPUCount)
        external
        onlyNftStakingAddress
    {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        previousMachineInfo.rentedGPUCount += rentedGPUCount;
        stakeHolderInfo.rentedGPUCount += rentedGPUCount;
    }

    function subRentedGPUCount(address _holder, string memory _machineId, uint8 rentedGPUCount)
        external
        onlyNftStakingAddress
    {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        if (previousMachineInfo.rentedGPUCount >= rentedGPUCount) {
            previousMachineInfo.rentedGPUCount -= rentedGPUCount;
            stakeHolderInfo.rentedGPUCount -= rentedGPUCount;
        }
    }

    function addReserveAmount(address _holder, string memory _machineId, uint256 _reserveAmount)
        external
        onlyNftStakingAddress
    {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];

        previousMachineInfo.reserveAmount += _reserveAmount;
        stakeHolderInfo.totalReservedAmount += _reserveAmount;
    }

    function subReserveAmount(address _holder, string memory _machineId, uint256 _reserveAmount)
        external
        onlyNftStakingAddress
    {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];

        if (previousMachineInfo.reserveAmount > _reserveAmount) {
            previousMachineInfo.reserveAmount -= _reserveAmount;
        } else {
            previousMachineInfo.reserveAmount = 0;
        }

        if (stakeHolderInfo.totalReservedAmount > _reserveAmount) {
            stakeHolderInfo.totalReservedAmount -= _reserveAmount;
        } else {
            stakeHolderInfo.totalReservedAmount = 0;
        }
    }

    function addClaimedRewardAmount(
        address _holder,
        string memory _machineId,
        uint256 totalClaimedAmount,
        uint256 releasedAmount
    ) external onlyNftStakingAddress {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];

        previousMachineInfo.totalClaimedRewardAmount += totalClaimedAmount;
        previousMachineInfo.releasedRewardAmount += releasedAmount;
        stakeHolderInfo.totalClaimedRewardAmount += totalClaimedAmount;
        stakeHolderInfo.releasedRewardAmount += releasedAmount;
    }

    function addOrUpdateStakeHolder(
        address _holder,
        string memory _machineId,
        uint256 _calcPoint,
        uint256 _reservedAmount,
        uint8 _gpuCount,
        bool isAdd
    ) external onlyNftStakingAddress {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        if (isAdd) {
            machineIds.push(_machineId);
            uint256 stakedMachineCount = address2MachineCount[_holder];
            if (stakedMachineCount == 0) {
                addressCountInStaking += 1;
            }
            address2MachineCount[_holder] += 1;

            stakeHolderInfo.totalGPUCount += _gpuCount;
            stakeHolderInfo.machineId2Info[_machineId].gpuCount = _gpuCount;

            stakeHolderInfo.totalReservedAmount += _reservedAmount;
            stakeHolderInfo.machineId2Info[_machineId].reserveAmount = _reservedAmount;
        }

        MachineInfo memory previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        stakeHolderInfo.machineId2Info[_machineId].calcPoint = _calcPoint;

        if (previousMachineInfo.calcPoint == 0) {
            stakeHolderInfo.machineIds.push(_machineId);
        }

        stakeHolderInfo.totalCalcPoint = stakeHolderInfo.totalCalcPoint + _calcPoint - previousMachineInfo.calcPoint;

        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
    }

    function removeMachine(address _holder, string memory _machineId) external onlyNftStakingAddress {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        MachineInfo memory stakeInfoToRemove = stakeHolderInfo.machineId2Info[_machineId];
        require(stakeInfoToRemove.calcPoint > 0, "Machine not found");

        stakeHolderInfo.totalCalcPoint -= stakeInfoToRemove.calcPoint;
        stakeHolderInfo.totalGPUCount -= stakeInfoToRemove.gpuCount;
        stakeHolderInfo.totalReservedAmount -= stakeInfoToRemove.reserveAmount;
        stakeHolderInfo.rentedGPUCount -= stakeInfoToRemove.rentedGPUCount;
        removeStringValueOfArray(_machineId, stakeHolderInfo.machineIds);
        delete stakeHolderInfo.machineId2Info[_machineId];
        removeMachineIdByValueUnordered(_machineId);

        uint256 stakedMachineCount = address2MachineCount[_holder];
        if (stakedMachineCount > 0) {
            if (stakedMachineCount == 1) {
                addressCountInStaking -= 1;
            }
            address2MachineCount[_holder] -= 1;
        }

        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
    }

    function updateTopStakeHolders(address _holder, uint256 newCalcPoint) internal {
        bool exists = false;
        uint256 index;

        for (uint256 i = 0; i < topStakeHolders.length; i++) {
            if (topStakeHolders[i].holder == _holder) {
                exists = true;
                index = i;
                break;
            }
        }

        if (exists) {
            topStakeHolders[index].totalCalcPoint = newCalcPoint;
        } else {
            topStakeHolders.push(SimpleStakeHolder(_holder, newCalcPoint));
            index = topStakeHolders.length - 1;
        }
    }

    function getHolderMachineIds(address _holder) external view returns (string[] memory) {
        return stakeHolders[_holder].machineIds;
    }

    function getTotalGPUCountOfStakeHolder(address _holder) public view returns (uint256) {
        uint256 totalGpuCount = 0;
        for (uint256 i = 0; i < stakeHolders[_holder].machineIds.length; i++) {
            string memory machineId = stakeHolders[_holder].machineIds[i];
            uint256 gpuCount = precompileContract.getMachineGPUCount(machineId);
            totalGpuCount += gpuCount;
        }
        return totalGpuCount;
    }

    function getCalcPointOfStakeHolders(address _holder) external view returns (uint256) {
        uint256 totalCalcPoint = 0;
        for (uint256 i = 0; i < stakeHolders[_holder].machineIds.length; i++) {
            string memory machineId = stakeHolders[_holder].machineIds[i];
            uint256 calcPoint = getMachineCalcPoint(machineId);
            totalCalcPoint += calcPoint;
        }
        return totalCalcPoint;
    }

    function getTopStakeHolders(uint256 offset, uint256 limit)
        external
        view
        returns (StakeHolder[] memory, uint256 total)
    {
        uint256 totalItems = topStakeHolders.length;

        if (offset >= totalItems) {
            StakeHolder[] memory empty = new StakeHolder[](0);
            return (empty, totalItems);
        }

        uint256 end = offset + limit;
        if (end > totalItems) {
            end = totalItems;
        }

        uint256 size = end - offset;

        SimpleStakeHolder[] memory sortedStakeHolders = new SimpleStakeHolder[](totalItems);

        for (uint256 i = 0; i < totalItems; i++) {
            sortedStakeHolders[i] = topStakeHolders[i];
        }

        selectionSort(sortedStakeHolders);

        StakeHolder[] memory result = new StakeHolder[](size);

        for (uint256 i = 0; i < size; i++) {
            SimpleStakeHolder memory simpleHolder = sortedStakeHolders[offset + i];
            StakeHolderInfo storage stakeHolderInfo = stakeHolders[simpleHolder.holder];

            result[i] = StakeHolder({
                holder: simpleHolder.holder,
                totalCalcPoint: simpleHolder.totalCalcPoint,
                totalGPUCount: stakeHolderInfo.totalGPUCount,
                totalReservedAmount: stakeHolderInfo.totalReservedAmount,
                rentedGPUCount: stakeHolderInfo.rentedGPUCount,
                burnedRentFee: stakeHolderInfo.burnedRentFee,
                totalClaimedRewardAmount: stakeHolderInfo.totalClaimedRewardAmount,
                releasedRewardAmount: stakeHolderInfo.releasedRewardAmount
            });
        }

        return (result, totalItems);
    }

    function selectionSort(SimpleStakeHolder[] memory arr) internal pure {
        uint256 len = arr.length;
        for (uint256 i = 0; i < len - 1; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < len; j++) {
                if (arr[j].totalCalcPoint > arr[maxIndex].totalCalcPoint) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                SimpleStakeHolder memory temp = arr[i];
                arr[i] = arr[maxIndex];
                arr[maxIndex] = temp;
            }
        }
    }

    function removeMachineIdByValueUnordered(string memory machineId) public {
        uint256 index = findMachineIdIndex(machineId);

        machineIds[index] = machineIds[machineIds.length - 1];

        machineIds.pop();
    }

    function findMachineIdIndex(string memory machineId) internal view returns (uint256) {
        for (uint256 i = 0; i < machineIds.length; i++) {
            if (keccak256(abi.encodePacked(machineIds[i])) == keccak256(abi.encodePacked(machineId))) {
                return i;
            }
        }
        revert("Element not found");
    }

    function getMachinesInStaking(uint256 startIndex, uint256 pageSize) external view returns (string[] memory) {
        require(startIndex < machineIds.length, "Start index out of bounds");

        // 计算返回的数组大小
        uint256 endIndex = startIndex + pageSize;
        if (endIndex > machineIds.length) {
            endIndex = machineIds.length;
        }
        uint256 length = endIndex - startIndex;

        string[] memory pageItems = new string[](length);
        for (uint256 i = 0; i < length; i++) {
            pageItems[i] = machineIds[startIndex + i];
        }

        return pageItems;
    }

    function getRentedGPUCountInDlcNftStaking() external view returns (uint256) {
        return rentContract.getTotalRentedGPUCount(phaseLevel);
    }

    function getTotalDlcNftStakingBurnedRentFee() external view returns (uint256) {
        return rentContract.getTotalBurnedRentFee(phaseLevel);
    }

    function getTotalGPUCountInStaking() public view returns (uint256) {
        return stakingContract.getTotalGPUCountInStaking();
    }

    function getLeftGPUCountToStartReward() public view returns (uint256) {
        return stakingContract.getLeftGPUCountToStartReward();
    }

    function getStateSummary() public view returns (StateSummary memory) {
        uint256 totalGPUCount = stakingContract.getTotalGPUCountInStaking();
        uint256 _leftGPUCountBeforeRewardStart = stakingContract.getLeftGPUCountToStartReward();
        (uint256 totalCalcPoint, uint256 totalReservedAmount) = stakingContract.getTotalCalcPointAndReservedAmount();

        return StateSummary({
            totalCalcPoint: totalCalcPoint,
            totalGPUCount: totalGPUCount,
            totalCalcPointPoolCount: addressCountInStaking,
            totalRentedGPUCount: rentContract.getTotalRentedGPUCount(phaseLevel),
            totalBurnedRentFee: rentContract.getTotalBurnedRentFee(phaseLevel),
            totalReservedAmount: totalReservedAmount,
            leftGPUCountBeforeRewardStart: _leftGPUCountBeforeRewardStart
        });
    }

    function isRented(string calldata machineId) external view returns (bool) {
        return rentContract.isRented(machineId);
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
