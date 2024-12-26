### Miner staking

- 1.call approve/setApprovalForAll function of the NFT(DLC NODE) contract to allow Staking contract to stake your NFT (this is Non-Fungible(ERC-721) Token Standard) 

- 2.call approve function of the Token(DLC) contract to allow Staking contract to stake your DLC token if you want to stake some (this is Fungible(ERC-20) Token Standard)
- 3.call stake(..) method on staking contract to stake your machine on staking contract

### Miner claim rewards
1. call claim(..) method  on staking contract

### exit staking
1. call unStakeAndClaim(..) method on staking contract
