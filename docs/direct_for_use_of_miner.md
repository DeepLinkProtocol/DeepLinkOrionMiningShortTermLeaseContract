### Miner staking
1. rent a machine which owner by yourself on DBC
2. bond evm address to a machine with owner substrate address on DBC![](./img.png)
3. call approve/setApprovalForAll function of the NFT(DLC NODE) contract to allow Staking contract to stake your NFT (this is Non-Fungible(ERC-721) Token Standard) 
4. call approve function of the Token(DLC) contract to allow Staking contract to stake your DLC token if you want to stake some (this is Fungible(ERC-20) Token Standard)
5.call stake(..) method to stake your machine on staking contract

### Miner claim rewards
1. call claim(..) method  on staking contract

### exit staking
1. call unStakeAndClaim(..) method on staking contract
