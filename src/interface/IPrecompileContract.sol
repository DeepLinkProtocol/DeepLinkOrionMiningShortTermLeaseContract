// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPrecompileContract {
    function getDLCRentFeeByCalcPoint(
        uint256 calcPoint,
        uint256 rentBlocks,
        uint256 rentGpuCount,
        uint256 totalGpuCount
    ) external view returns (uint256);
}
