pragma solidity ^0.8.20;

interface IStakingContract {
    function isStaking(string calldata machineId) external view returns (bool);
    function rentMachine(string calldata machineId, uint256 fee, uint8 rentedGPUCount) external;
    function renewRentMachine(string calldata machineId, uint256 fee) external;
    function endRentMachine(string calldata machineId, uint8 rentedGPUCount) external;
    function reportMachineFault(string calldata machineId, address renter) external;
    function getMachineHolder(string memory machineId) external view returns (address);
    function getMachinesInStaking(uint256 page, uint256 pageSize) external view returns (string[] memory);
    function getTotalGPUCountInStaking() external view returns (uint256);
    function getLeftGPUCountToStartReward() external view returns (uint256);
    function getTotalCalcPointAndReservedAmount() external view returns (uint256, uint256);
    function canRent(string calldata machineId, uint256 rentBlockNumbers) external view returns (bool);
    function getMachinePricePerHour(string memory machineId) external view returns (uint256);

    struct MachineUploadInfo {
        string gpuType;
        uint256 gpuMem;
        uint256 cpuRate;
        string cpuType;
        uint256 pricePerHour;
        uint256 reserveAmount;
        uint256 nextRenterCanRentAt;
        uint64 east;
        uint64 west;
        uint64 south;
        uint64 north;
    }

    function getMachineUploadInfo(string memory machineId) external view returns (MachineUploadInfo memory);
}
