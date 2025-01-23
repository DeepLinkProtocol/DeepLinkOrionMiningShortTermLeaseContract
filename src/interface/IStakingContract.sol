pragma solidity ^0.8.20;

interface IStakingContract {
    enum NotifyType {
        ContractRegister,
        MachineRegister,
        MachineUnregister,
        MachineOnline,
        MachineOffline
    }

    function notify(NotifyType tp, string calldata machineId) external returns (bool);

    function isStaking(string calldata machineId) external view returns (bool);
    function rentMachine(string calldata machineId) external;
    function endRentMachine(string calldata machineId) external;
    function reportMachineFault(string calldata machineId, address renter) external;
    function getMachineInfo(string memory machineId)
        external
        view
        returns (
            address holder,
            uint256 calcPoint,
            uint256 startAtTimestamp,
            uint256 endAtTimestamp,
            uint256 nextRenterCanRentAt,
            uint256 reservedAmount,
            bool isOnline,
            bool isRegistered
        );
    function getTotalGPUCountInStaking() external view returns (uint256);
    function getLeftGPUCountToStartReward() external view returns (uint256);
    function getTotalCalcPointAndReservedAmount() external view returns (uint256, uint256);
    function joinStaking(string memory machineId, uint256 calcPoint, uint256 reserveAmount) external;
}
