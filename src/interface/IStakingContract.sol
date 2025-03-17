pragma solidity ^0.8.20;

interface IStakingContract {
    function isStaking(string calldata machineId) external view returns (bool);
    function rentMachine(string calldata machineId, uint256 rentFee) external;
    function endRentMachine(string calldata machineId) external;
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
    function getTotalGPUCountInStaking() external view returns (uint256);
    function getLeftGPUCountToStartReward() external view returns (uint256);
    function getGlobalState() external view returns (uint256, uint256, uint256);

    function getMachinesInStaking(uint256 page, uint256 pageSize) external view returns (string[] memory, uint256);
    function addReserveAmount(string memory _machineId, address _holder, uint256 _reservedAmount) external;
    function addOrUpdateStakeHolder(
        address _holder,
        string memory _machineId,
        uint256 _calcPoint,
        uint8 _gpuCount,
        bool isAdd
    ) external;

    function removeMachine(address _holder, string memory _machineId) external;
    function setBurnedRentFee(address _holder, string memory _machineId, uint256 fee) external;
    function addRentedGPUCount(address _holder, string memory _machineId) external;
    function subRentedGPUCount(address _holder, string memory _machineId) external;
    function addReserveAmount(address _holder, string memory _machineId, uint256 _reserveAmount) external;
    function subReserveAmount(address _holder, string memory _machineId, uint256 _reserveAmount) external;

    function addClaimedRewardAmount(
        address _holder,
        string memory _machineId,
        uint256 totalClaimedAmount,
        uint256 releasedAmount
    ) external;

    function unStake(string calldata machineId) external;
}
