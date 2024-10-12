// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStateContract {
    function addOrUpdateStakeHolder(
        address _holder,
        string memory _machineId,
        uint256 _calcPoint,
        uint256 _reservedAmount
    ) external;

    function removeMachine(address _holder, string memory _machineId) external;

    function getHolderMachineIds(address _holder) external view returns (string[] memory);

    function getRentedGPUCountOfStakeHolder(address _holder) external view returns (uint256);

    function getBurnedRentFeeOfStakeHolder(address _holder) external view returns (uint256);

    function getTopStakeHolders() external view returns (address[3] memory top3HoldersAddress,uint256[3] memory top3HoldersCalcPoint);
}
