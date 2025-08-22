## Development

## 主网url：https://dbcswap.io/subgraph/name/short-staking-state/graphql
  
## 对象实体定义:

```graphql
    type StateSummary @entity {
        id: Bytes!
        totalGPUCount: BigInt! # uint256
        totalStakingGPUCount: BigInt! # uint256
        totalCalcPointPoolCount: BigInt! # uint256
        totalRentedGPUCount: BigInt! # uint256
        totalBurnedRentFee: BigInt! # uint256
        totalReservedAmount: BigInt! # uint256
    }

```

```graphql
    type StakeHolder @entity {
    id: Bytes!
    holder: Bytes! # address 矿工地址
    totalCalcPoint: BigInt! # uint256  总的机器原始算力 (不包含质押nft/租用等行为 对算力的增幅)
    fullTotalCalcPoint: BigInt! # uint256 总的机器膨胀算力 (包含质押nft/租用等行为 对算力的增幅)
    totalGPUCount: BigInt! # uint256 总的参与过质押的gpu个数
    totalStakingGPUCount: BigInt! # uint256 总的处于质押中的gpu个数
    rentedGPUCount: BigInt! # uint256 被租用中的gpu个数
    totalReservedAmount: BigInt! # uint256 质押的总金额
    burnedRentFee: BigInt! # uint256 已销毁的租用费用
    totalClaimedRewardAmount: BigInt! # uint256 已领取的奖励金额
    totalReleasedRewardAmount: BigInt! # uint256 已释放的奖励金额
    blockNumber: BigInt!
    blockTimestamp: BigInt!
    transactionHash: Bytes!
```

```graphql
    type MachineInfo @entity {
        id: Bytes!
        holder: Bytes! # address 矿工地址
        holderRef: StakeHolder! @belongsTo(field: "holder")  # 关联的矿工对象
        machineId: String! # string 机器id
        totalCalcPoint: BigInt! # uint256  总的机器原始算力 (不包含质押nft/租用等行为 对算力的增幅)
        totalCalcPointWithNFT: BigInt! # uint256  总的机器算力 (包含质押nft 对算力的增幅)
        fullTotalCalcPoint: BigInt! # uint256 总的机器算力 (包含质押nft/租用等行为 对算力的增幅)
        totalGPUCount: BigInt! # uint256 gpu数量
        rentedGPUCount: BigInt! # uint256 被租用的gpu数量
        totalReservedAmount: BigInt! # uint256 质押的总金额
        burnedRentFee: BigInt! # uint256 已销毁的租用费用
        blockNumber: BigInt!
        blockTimestamp: BigInt!
        transactionHash: Bytes!
        totalClaimedRewardAmount: BigInt! # 已领取奖励
        extraRentFee: BigInt! # 额外租金
        stakeEndTimestamp: BigInt! # uint256 质押结束时间戳（秒）
        nextCanRentTimestamp: BigInt! # uint256 下次可租用时间戳（秒）
        isStaking: Boolean! # 是否处于质押状态
        online: Boolean! # 是否在线
        registered: Boolean! # 是否注册
        gpuType: String! # string gpu类型
    }
```

```graphql
    type GpuTypeValue @entity {
      id: Bytes!
      value: String! # string  gpu类型值
      count: BigInt! # uint256  该cpu类型的机器 处于质押状态的数量

}
```