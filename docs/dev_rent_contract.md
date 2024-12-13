### Contract:
    Rent: 0xe8fd234653518e34953e8f218c32d835e10893e8
      -- ABI: https://blockscout-testnet.dbcscan.io/address/0x85699b9BD0233E21c2520A92327800b969D31Edd?tab=contract

### Network : DeepBrainChain Testnet

#### Rent Contract Methods:

* getDLCMachineRentFee(string memory machineId, uint256 rentBlockNumbers, uint256 rentGpuNumbers) returns (uint256) - Get rent fee for given machine id, rent block numbers and rent gpu numbers.

* rentMachine(string  machineId, uint256 rentBlockNumbers, uint8 gpuCount, uint256 rentFee) - Rent machine with given rent fee and rent block numbers and gpu count.

* renewRent(uint256 rentId, uint256 additionalRentBlockNumbers, uint256 additionalRentFee) - Renew rent with given rent id, additional rent block numbers and additional rent fee.

* endRentMachine(uint256 rentId) - End rent machine with given rent id. only machine owner can call this function

* setAdminsToApproveMachineFaultReporting(address[] admins) - set admins to approve or reject machine fault reporting. only contract owner can call this function.

* reportMachineFault(uint256 rentId, uint256 reserveAmount) - report machine fault with given rent id and reserve amount.

* approveMachineFaultReporting(string machineId) - approve machine for reporting faults. only admin can call this function.

* rejectMachineFaultReporting(string machineId) - reject machine for reporting faults. only admin can call this function.