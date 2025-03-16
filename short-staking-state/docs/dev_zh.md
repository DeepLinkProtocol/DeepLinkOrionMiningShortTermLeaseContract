## Development

## 主网url：http://8.214.55.62:8032/subgraphs/name/short-staking-state 
  - 查询列：http://8.214.55.62:8032/subgraphs/name/short-staking-state/graphql?query=%7B%0A++stateSummaries%28first%3A+1%29+%7B%0A++++id%0A++++totalGPUCount%0A++++totalCalcPointPoolCount%0A++++totalRentedGPUCount%0A++++totalBurnedRentFee%0A++++totalReservedAmount%0A++%7D%0A++stakeHolders%28first%3A+5%29+%7B%0A++++id%0A++++holder%0A++++totalCalcPoint%0A++++fullTotalCalcPoint%0A++++totalGPUCount%0A++++totalReservedAmount%0A++++machineInfos%7B%0A++++++id%0A++++++holder%0A++++++totalGPUCount%0A++++++stakeEndTimestamp%0A++++++totalCalcPoint%0A++++++fullTotalCalcPoint%0A++++++isStaking%0A++++++online%0A++++++registered%0A++++%7D%0A++%7D%0A++machineInfos+%28first%3A10%2Cskip%3A0%2Cwhere%3A%7B%0A+++++gpuType%3A+%22NVIDIA+GeForce+RTX+4060%22%0A+++++isStaking%3A+true%0A+++++isRented%3A+false%0A+++++online%3A+true%0A+++++registered%3A+true%0A+++%7D%29%7B%0A++++id%0A++++holder%0A++++totalGPUCount%0A++++stakeEndTimestamp%0A++++totalCalcPoint%0A++++fullTotalCalcPoint%0A++++nextCanRentTimestamp%0A++++isRented%0A++++isStaking%0A++++online%0A++++registered%0A++++gpuType%0A++++totalReservedAmount%0A++%7D%0A%7D
    按需求调整查询条件 查询字段 排序条件，查询数量等, 
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
        
        stakeEndTimestamp: BigInt! # uint256 质押结束时间戳（秒）
        nextCanRentTimestamp: BigInt! # uint256 下次可租用时间戳（秒）
        isStaking: Boolean! # 是否处于质押状态
        online: Boolean! # 是否在线
        registered: Boolean! # 是否注册
        gpuType: String! # string gpu类型
    }
```