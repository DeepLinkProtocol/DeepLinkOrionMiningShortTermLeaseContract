pragma solidity ^0.8.20;

interface IStakingContract {
    function isStaking(string calldata machineId) external view returns (bool);
    function rentMachine(string calldata machineId) external;
    function endRentMachine(string calldata machineId, uint256 baseRentFee, uint256 extraRentFee) external;
    function renewRentMachine(string memory machineId, uint256 rentFee) external;
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
    function getLeftGPUCountToStartReward() external view returns (uint256);
    function getGlobalState() external view returns (uint256, uint256, uint256);

    function getMachinesInStaking(uint256 page, uint256 pageSize) external view returns (string[] memory, uint256);

    function removeMachine(address _holder, string memory _machineId) external;

    function unStake(string calldata machineId) external;

    function stopRewarding(string memory machineId) external;
    function recoverRewarding(string memory machineId) external;
    function isStakingButOffline(string calldata machineId) external view returns (bool);
    function getRewardDuration() external view returns (uint256);
    function getMachineExtraRentFee(string memory machineId) external view returns (uint256);
    function machineIsBlocked(string memory machineId) external view returns (bool);
    function getaCalcPoint(string memory machineId) external view returns (uint256);
    function getMachineConfig(string memory machineId)
        external
        view
        returns (address[] memory beneficiaries, uint256[] memory rates, uint256 palateFormFeeRate);

    function isPersonalMachine(string memory machineId) external view returns (bool);
    function updateMachineRegisterStatus(string memory machineId,bool registered ) external;
}
