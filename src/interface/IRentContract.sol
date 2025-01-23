pragma solidity ^0.8.20;

interface IRentContract {
    enum NotifyType {
        ContractRegister,
        MachineRegister,
        MachineUnregister,
        MachineOnline,
        MachineOffline
    }

    function notify(NotifyType tp, string calldata machineId) external returns (bool);

    function getTotalBurnedRentFee() external view returns (uint256);

    function getTotalRentedGPUCount() external view returns (uint256);

    function isRented(string calldata machineId) external view returns (bool);

    function getRenter(string calldata machineId) external view returns (address);

    function paidSlash(address holder, string memory machineId) external;
}
