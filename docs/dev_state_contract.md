### Contract:
    State:
      -- Address:0x5f8bf45dd6d87494814bcd8f3c321bd1ce4d0391
### Network : DeepBrainChain Testnet

#### State Contract Methods:

* getMachinesInStaking(uint256 page, uint256 pageSize) returns (string[]) - Get Machine In staking

* function getStateSummary() returns (StateSummary memory) - Get state summary info. contains following fields:
  ```struct StateSummary {
       uint256 totalCalcPoint;  // Total calculation point in staking.
       uint256 totalGPUCount;  // Total GPU count in staking.
       uint256 totalCalcPointPoolCount;    // Total calculation point pool count in staking.
       uint256 totalRentedGPUCount;  // Total rented GPU count in staking.
       uint256 totalBurnedRentFee;  // Total rent fee burned in staking.
       uint256 totalReservedAmount;  // Total reserved amount in staking.
       uint256 leftGPUCountBeforeRewardStart;  // Left GPU count before reward start.
    }
  
* getTopStakeHolders(uint256 offset, uint256 limit) returns (StakeHolder[] memory, uint256 total) - Get top stakeholders info ordered by their machines calculation point. 'offset' column start from 0
  ```struct StakeHolder {
       address holder;   // Address of stakeholder.
       uint256 totalCalcPoint; // Total calculation point of machines of stakeholder.
       uint256 totalGPUCount; // Total GPU count of machines of stakeholder.
       uint256 rentedGPUCount; // Rented GPU count of machines of stakeholder.
       uint256 totalReservedAmount; // Total reserved amount of machines of stakeholder.
       uint256 burnedRentFee; // Burned rent fee of machines of stakeholder.
       uint256 totalClaimedRewardAmount; // Total claimed reward amount of machines of stakeholder.
       uint256 releasedRewardAmount; // Released reward amount of machines of stakeholder.
  }

* isRented(string machineId) returns (bool) - Check if machine is rented or not.

* getMachineUploadInfo(string machineId)  returns (MachineUploadInfo) - get machine info
``` 
struct MachineUploadInfo {
        string gpuType;  // gpu type 
        uint256 gpuMem;  // memory in GB
        uint256 cpuRate; // cpu rate in MHz
        string cpuType;  // cpu type
        uint256 pricePerHour; // price(DLC) per hour in wei
        uint256 reserveAmount; // reserve amount in wei
        uint256 nextRenterCanRentAt; // next renter can rent at
        uint64 east; // east longitude of the machine location
        uint64 west; // west longitude of the machine location
        uint64 south; // south latitude of the machine location
        uint64 north; // north latitude of the machine location
}
```