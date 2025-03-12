// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interface/IRentContract.sol";

/// @custom:oz-upgrades-from OldNFTStakingState
contract NFTStakingState {
    IRentContract public rentContract;

    uint256 public totalReservedAmount;
    uint256 public totalGpuCount;
    uint256 public totalCalcPoint;
    uint256 public addressCountInStaking;
    string[] public machineIds;
    SimpleStakeHolder[] public topStakeHolders;

    mapping(address => uint8) public address2MachineCount;
    mapping(address => StakeHolderInfo) public stakeHolders;

    struct StateSummary {
        uint256 totalCalcPoint;
        uint256 totalGPUCount;
        uint256 totalCalcPointPoolCount;
        uint256 totalRentedGPUCount;
        uint256 totalBurnedRentFee;
        uint256 totalReservedAmount;
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

    modifier onlyRentAddress() {
        require(msg.sender == address(rentContract), "Only RentContractAddress can call this function");
        _;
    }

    function __State_Init(address _rentContract) internal {
        rentContract = IRentContract(_rentContract);
    }

    function _setRentContract(address _rentContract) internal {
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

    function removeStringValueOfArray(string memory addr, string[] storage arr) internal {
        uint256 index = findStringIndex(arr, addr);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function setBurnedRentFee(address _holder, string memory _machineId, uint256 fee) external onlyRentAddress {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        previousMachineInfo.burnedRentFee += fee;
        stakeHolderInfo.burnedRentFee += fee;
    }

    function addRentedGPUCount(address _holder, string memory _machineId) external onlyRentAddress {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        previousMachineInfo.rentedGPUCount += 1;
        stakeHolderInfo.rentedGPUCount += 1;
    }

    function subRentedGPUCount(address _holder, string memory _machineId) internal {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        if (previousMachineInfo.rentedGPUCount >= 1) {
            previousMachineInfo.rentedGPUCount -= 1;
            stakeHolderInfo.rentedGPUCount -= 1;
        }
    }

    function addReserveAmount(string memory _machineId, address _holder, uint256 _reserveAmount) internal {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];

        previousMachineInfo.reserveAmount += _reserveAmount;
        stakeHolderInfo.totalReservedAmount += _reserveAmount;
    }

    function subReserveAmount(address _holder, string memory _machineId, uint256 _reserveAmount) internal {
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
    ) internal {
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
        uint8 _gpuCount,
        bool isAdd
    ) internal {
        require(_holder != address(0), "Invalid holder address");
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
        }

        MachineInfo memory previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        stakeHolderInfo.machineId2Info[_machineId].calcPoint = _calcPoint;

        if (previousMachineInfo.calcPoint == 0) {
            stakeHolderInfo.machineIds.push(_machineId);
        }

        stakeHolderInfo.totalCalcPoint = stakeHolderInfo.totalCalcPoint + _calcPoint - previousMachineInfo.calcPoint;

        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
    }

    function removeMachine(address _holder, string memory _machineId) internal {
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

    function removeMachineIdByValueUnordered(string memory machineId) internal {
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

    function getMachinesInStaking(uint256 startIndex, uint256 pageSize)
        external
        view
        returns (string[] memory, uint256)
    {
        if (startIndex > machineIds.length) {
            return (new string[](0), machineIds.length);
        }

        uint256 endIndex = startIndex + pageSize;
        if (endIndex > machineIds.length) {
            endIndex = machineIds.length;
        }
        uint256 length = endIndex - startIndex;

        string[] memory pageItems = new string[](length);
        for (uint256 i = 0; i < length; i++) {
            pageItems[i] = machineIds[startIndex + i];
        }

        return (pageItems, machineIds.length);
    }

    function getRentedGPUCountInDlcNftStaking() external view returns (uint256) {
        return rentContract.getTotalRentedGPUCount();
    }

    function getTotalDlcNftStakingBurnedRentFee() external view returns (uint256) {
        return rentContract.getTotalBurnedRentFee();
    }

    function getStateSummary() public view returns (StateSummary memory) {
        return StateSummary({
            totalCalcPoint: totalCalcPoint,
            totalGPUCount: totalGpuCount,
            totalCalcPointPoolCount: addressCountInStaking,
            totalRentedGPUCount: rentContract.getTotalRentedGPUCount(),
            totalBurnedRentFee: rentContract.getTotalBurnedRentFee(),
            totalReservedAmount: totalReservedAmount
        });
    }

    function isRented(string calldata machineId) external view returns (bool) {
        return rentContract.isRented(machineId);
    }
}
