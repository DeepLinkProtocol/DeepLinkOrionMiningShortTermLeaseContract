pragma solidity ^0.8.20;

interface IRentContract {
    function getTotalBurnedRentFee() external view returns (uint256);

    function getTotalRentedGPUCount() external view returns (uint256);

    function isRented(string calldata machineId) external view returns (bool);

    function getRenter(string calldata machineId) external view returns (address);

    function paidSlash(string memory machineId) external;
}
