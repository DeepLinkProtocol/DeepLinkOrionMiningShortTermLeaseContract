### review the fault machine report
 - The following action is required by admins which set by setAdminsToApproveMachineFaultReporting(..)
1. check pendingSlashMachineIds on rent contract to get the machine id which reported.
2. call approve function of the Token(DLC) contract to allow contract to reserve your 10000 DLC tokens (this is Fungible(ERC-20) Token Standard)
3. call approveMachineFaultReporting(..) or rejectMachineFaultReporting(..) on rent contract to approve or reject the report.
4. if 3/5 admins approve the report, approve the machine by calling approveMachineFaultReporting(..) on rent contract. the slash will be executed, your reserved 10000 tokens will back to your address. the machine  will be remove from staking contract  and  if the reserve amount or unclaimed reward more than 10000, the reserve amount will be slashed to reporter. 