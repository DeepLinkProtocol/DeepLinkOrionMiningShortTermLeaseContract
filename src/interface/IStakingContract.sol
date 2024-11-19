pragma solidity ^0.8.20;

interface IStakingContract {
    function isStaking(string calldata machineId) external view returns (bool);
    function rentMachine(string calldata machineId, uint256 fee, uint8 rentedGPUCount) external;
    function endRentMachine(string calldata machineId, uint8 rentedGPUCount) external;
    function reportMachineFault(string calldata machineId, address[] memory renters) external;
    function getMachineHolder(string memory machineId) external view returns (address);
    function getMachinesInStaking(uint256 page, uint256 pageSize) external view returns (string[] memory);
    function getTotalGPUCountInStaking() external view returns (uint256);
    function getLeftGPUCountToStartReward() external view returns (uint256);
    function getTotalCalcPointAndReservedAmount() external view returns (uint256, uint256);
    function canRent(string calldata machineId) external view returns (bool);
    function getMachinePricePerHour(string memory machineId) external view returns (uint256);
}
