pragma solidity ^0.8.20;

interface IRentContract {
    function getTotalBurnedRentFee(uint8 phaseLevel) external view returns (uint256);

    function getTotalRentedGPUCount(uint256 phaseLevel) external view returns (uint256);

    function isRented(string calldata machineId) external view returns (bool);
}
