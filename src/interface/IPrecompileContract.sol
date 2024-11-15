// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPrecompileContract {
    function getMachineCalcPoint(string memory machineId) external view returns (uint256 calcPoint);

    function getMachineGPUCount(string memory machineId) external view returns (uint8);

    function getOwnerRentEndAt(string memory machineId, uint256 rentId) external view returns (uint256);

    function getDLCMachineRentFee(string memory machineId, uint256 rentBlocks, uint256 rentGpuCount)
        external
        view
        returns (uint256);

    function isMachineOwner(string memory machineId, address evmAddress) external view returns (bool);
}
