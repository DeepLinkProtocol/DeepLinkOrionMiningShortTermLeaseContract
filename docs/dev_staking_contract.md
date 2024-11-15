### Contract:
    Staking: 
      -- Address: 0xc51fc01886bff07bb02454709a7f64189ae7a95b
      -- ABI: https://blockscout-testnet.dbcscan.io/address/0x91Ae136414F45056e1A3303E1AABCB4BE806669a?tab=contract

### Network : DeepBrainChain Testnet

#### Staking Contract Methods:

* stake(string  machineId, uint256 amount, uint256[] nftTokenIds, uint256 rentId) - Stake machine with given machine id, amount, nft token ids and rent id.

* claim(string memory machineId) - Claim rewards for given machine id.

* unStakeAndClaim(string  machineId) - end stake and claim rewards for given machine id.
