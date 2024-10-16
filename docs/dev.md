### Contract Name: IDCMachineNFTStaking

### Contract Address: todo.

### Network : DeepBrainChain Testnet

#### Methods:

 * `getTotalGPUCountInStaking()public view returns (uint256)` - Get GPU count in staking.

 * `getLeftGPUCountToStartReward() public view returns (uint256)`- Get left GPU count for starting the staking reward.

 * `totalCalcPoint() public view returns (uint256)`- Get total machine calculation point in staking.

 * `addressInStaking() public view returns (uint256)` - Get address count in staking.

 * `getRentedGPUCountInDlcNftStaking() external view returns (uint256)` - Get rented GPU count in staking for now.

 * `getTotalDlcNftStakingBurnedRentFee() external view returns (uint256)` - Get total dlc rent fee in staking(All rent fee burned for now).

 * `totalReservedAmount() public view returns (uint256)` - Get total reserved amount in staking.

 * `getTopStakeHolders() public view returns (address[3] memory top3HoldersAddress, uint256[3] memory top3HoldersCalcPoint)` - Get top 3 stakeholders address and their machines calculation point.

 * `getCalcPointOfStakeHolders(address _holder) public view returns (uint256)` - Get machines calculation point of a stakeholder.

 * `getTotalGPUCountOfStakeHolder(address _holder) public view returns (uint256)` - Get total GPU count of a stakeholder.

 * `getRentedGPUCountOfStakeHolder(address _holder) external view returns (uint256)` Get rented GPU count of a stakeholder for now.

 * `getBurnedRentFeeOfStakeHolder(address _holder) public view returns (uint256)` Get dlc rent fee of a stakeholder in staking(All rent fee burned for now)

 * `getTotalRewardAmountOfStakeHolder(address _holder) public returns (uint256 releasedAmount, uint256 totalAmount)` - Get released reward amount and total reward amount of a stakeholder.