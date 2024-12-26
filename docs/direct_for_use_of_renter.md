### rent machine
- 1. call getMachinesInStaking(..) method on state contract.
- 2. chose a machine and call isRented(..) method to check if it is rented or not.
- 3. if not rented you can call getDLCMachineRentFee(..) to get the rent fee for the machine.
- 4. call approve function of the Token(DLC) contract to allow Rent contract to control your DLC tokens(rent fee) (this is Fungible(ERC-20) Token Standard)
- 5. rent it by calling rentMachine(..) method on rent contract and you will get a rent id.


### report fault machine
- 1. call reportMachineFault(..) method on rent contract this action require reserve 10000 DLC.
- 2. waiting for admins to check the report, if the report is valid the reserved 10000 DLC will be returned to the reporter.