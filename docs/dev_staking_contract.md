### Contract:
    Staking: 
      -- Address: 0x2add61b9c3e98672ee0abe3f14241b8673d2c1e3
### Network : DeepBrainChain Testnet

#### Staking Contract Methods:

* stake(string  machineId, uint256 amount, uint256[] nftTokenIds, uint256 rentId) - Stake machine with given machine id, amount, nft token ids and rent id.

* claim(string memory machineId) - Claim rewards for given machine id.

* unStakeAndClaim(string  machineId) - end stake and claim rewards for given machine id.

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
