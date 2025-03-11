pragma solidity ^0.8.20;

interface ILongStakeContract {
    function isStaking(string calldata machineId) external view returns (bool);
}
