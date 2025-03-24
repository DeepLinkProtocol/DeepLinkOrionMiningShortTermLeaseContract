import { BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  AddedStakeHours as AddedStakeHoursEvent,
  Claimed as ClaimedEvent,
  EndRentMachine as EndRentMachineEvent,
  Initialized as InitializedEvent,
  OwnershipTransferred as OwnershipTransferredEvent,
  PaySlash as PaySlashEvent,
  RentMachine as RentMachineEvent,
  ReportMachineFault as ReportMachineFaultEvent,
  ReserveDLC as ReserveDLCEvent,
  Staked as StakedEvent,
  Unstaked as UnstakedEvent,
  StakedGPUType as StakedGPUTypeEvent,
  MoveToReserveAmount as MoveToReserveAmountEvent,
  RenewRent as RenewRentEvent,

} from "../generated/NFTStaking/NFTStaking"
import {
  StateSummary,
  StakeHolder,
  MachineInfo, GpuTypeValue

} from "../generated/schema"


export function handleClaimed(event: ClaimedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()))
  if (stakeholder == null) {
    return
  }

  stakeholder.totalReleasedRewardAmount = stakeholder.totalReleasedRewardAmount.plus(event.params.moveToUserWalletAmount)
  stakeholder.totalClaimedRewardAmount = stakeholder.totalClaimedRewardAmount.plus(event.params.totalRewardAmount)
  // stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.plus(event.params.moveToReservedAmount)
  stakeholder.save()

}

export function handleMoveToReserveAmount(event : MoveToReserveAmountEvent): void{
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.plus(event.params.amount)
  machineInfo.save()

  let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()))
  if (stakeholder == null) {
    return
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.plus(event.params.amount)
  stakeholder.save()

  let stateSummary = StateSummary.load(Bytes.empty())
  if (stateSummary == null) {
    return
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.plus(event.params.amount)
  stateSummary.save()
}



export function handleEndRentMachine(event: EndRentMachineEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  machineInfo.nextCanRentTimestamp = event.params.nextCanRentTime
  machineInfo.isRented = false
  machineInfo.rentedGPUCount = BigInt.fromI32(0)

  const reducedCalcPoint = machineInfo.totalCalcPointWithNFT.times(BigInt.fromI32(3)).div(BigInt.fromI32(10))
  if (machineInfo.fullTotalCalcPoint > reducedCalcPoint) {
    machineInfo.fullTotalCalcPoint = machineInfo.fullTotalCalcPoint.minus(reducedCalcPoint)
  }
  machineInfo.nextCanRentTimestamp = event.params.nextCanRentTime
  machineInfo.nextCanRentTime = new Date(machineInfo.nextCanRentTimestamp.toU64() * 1000).toISOString();

  machineInfo.save()

  let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()))
  if (stakeholder == null) {
      return
  }


  stakeholder.rentedGPUCount = stakeholder.rentedGPUCount.minus(BigInt.fromI32(1))
  if (stakeholder.fullTotalCalcPoint > reducedCalcPoint){
    stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.minus(reducedCalcPoint)
  }

  stakeholder.save()

  let stateSummary = StateSummary.load(Bytes.empty())
  if (stateSummary == null) {
    return
  }
  stateSummary.totalRentedGPUCount = stateSummary.totalRentedGPUCount.minus(BigInt.fromI32(1))
  stateSummary.save()
}

export function handlePaySlash(event: PaySlashEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.minus(event.params.slashAmount)
  machineInfo.save()

  let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()))
  if (stakeholder == null) {
    return
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.minus(event.params.slashAmount)
  stakeholder.save()

  let stateSummary = StateSummary.load(Bytes.empty())
  if (stateSummary == null) {
    return
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.minus(event.params.slashAmount)
  stateSummary.save()
}


export function handleRentMachine(event: RentMachineEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString())
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  machineInfo.isRented = true
  const addedCalcPoint = machineInfo.totalCalcPointWithNFT.times(BigInt.fromI32(3)).div(BigInt.fromI32(10))
  machineInfo.fullTotalCalcPoint = machineInfo.fullTotalCalcPoint.plus(addedCalcPoint)
  machineInfo.burnedRentFee = machineInfo.burnedRentFee.plus(event.params.rentFee)
  machineInfo.save()

  let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()))
  if (stakeholder == null) {
    return
  }

  stakeholder.rentedGPUCount = stakeholder.rentedGPUCount.plus(BigInt.fromI32(1))
  stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.plus(addedCalcPoint)
  stakeholder.burnedRentFee = stakeholder.burnedRentFee.plus(event.params.rentFee)
  stakeholder.save()

  let stateSummary = StateSummary.load(Bytes.empty())
  if (stateSummary == null) {
    return
  }
  stateSummary.totalRentedGPUCount = stateSummary.totalRentedGPUCount.plus(BigInt.fromI32(1))
  stateSummary.totalBurnedRentFee = stateSummary.totalBurnedRentFee.plus(event.params.rentFee)
  stateSummary.save()
}

export function handleReserveDLC(event: ReserveDLCEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.plus(event.params.amount)
  machineInfo.save()

  let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()))
  if (stakeholder == null) {
    // never happen
    stakeholder = new StakeHolder(Bytes.fromHexString(machineInfo.holder.toHexString()))
    return
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.plus(event.params.amount)
  stakeholder.save()

  let stateSummary = StateSummary.load(Bytes.empty())
  if (stateSummary == null) {
    return
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.plus(event.params.amount)
  stateSummary.save()
}


export function handleStaked(event: StakedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  let isNewMachine: boolean = false
  if (machineInfo == null) {
    isNewMachine = true
    machineInfo = new MachineInfo(id)
    machineInfo.blockNumber = event.block.number
    machineInfo.blockTimestamp = event.block.timestamp
    machineInfo.machineId = event.params.machineId
    machineInfo.holder = event.params.stakeholder
    machineInfo.transactionHash = event.transaction.hash
    machineInfo.rentedGPUCount = BigInt.fromI32(0)
    machineInfo.totalReservedAmount = BigInt.fromI32(0)
    machineInfo.burnedRentFee = BigInt.fromI32(0)
    machineInfo.isRented = false
    machineInfo.gpuType = ""
  }

  machineInfo.totalGPUCount = BigInt.fromI32(1)
  machineInfo.totalCalcPoint = event.params.originCalcPoint
  machineInfo.totalCalcPointWithNFT = event.params.calcPoint
  machineInfo.fullTotalCalcPoint = event.params.calcPoint
  machineInfo.stakeEndTimestamp = event.block.timestamp.plus(event.params.stakeHours.times(BigInt.fromI32(3600)))
  machineInfo.nextCanRentTimestamp = event.block.timestamp.plus(event.params.stakeHours.times(BigInt.fromI32(3600)))
  machineInfo.stakeEndTime = new Date(machineInfo.stakeEndTimestamp.toU64() * 1000).toISOString();
  machineInfo.nextCanRentTime = new Date(machineInfo.nextCanRentTimestamp.toU64() * 1000).toISOString();
  machineInfo.isStaking = true
  machineInfo.online = true
  machineInfo.registered = true

  let stakeholder = StakeHolder.load(Bytes.fromHexString(event.params.stakeholder.toHexString()))
  if (stakeholder == null) {
    stakeholder = new StakeHolder(Bytes.fromHexString(event.params.stakeholder.toHexString()))
    stakeholder.holder = event.params.stakeholder
    stakeholder.blockNumber = event.block.number
    stakeholder.blockTimestamp = event.block.timestamp
    stakeholder.transactionHash = event.transaction.hash
    stakeholder.totalGPUCount = BigInt.fromI32(0)
    stakeholder.totalStakingGPUCount = BigInt.fromI32(0)
    stakeholder.rentedGPUCount = BigInt.fromI32(0)
    stakeholder.totalCalcPoint = BigInt.fromI32(0)
    stakeholder.fullTotalCalcPoint = BigInt.fromI32(0)
    stakeholder.totalReservedAmount = BigInt.fromI32(0)
    stakeholder.rentedGPUCount = BigInt.fromI32(0)
    stakeholder.burnedRentFee = BigInt.fromI32(0)
    stakeholder.totalReleasedRewardAmount = BigInt.fromI32(0)
    stakeholder.totalClaimedRewardAmount = BigInt.fromI32(0)
  }


  if (isNewMachine){
    stakeholder.totalGPUCount = stakeholder.totalGPUCount.plus(BigInt.fromI32(1))
  }
  stakeholder.totalStakingGPUCount = stakeholder.totalStakingGPUCount.plus(BigInt.fromI32(1))
  stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.plus(machineInfo.totalCalcPoint)
  stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.plus(machineInfo.fullTotalCalcPoint)
  stakeholder.save()

  machineInfo.holderRef = stakeholder.id
  machineInfo.save()


  let stateSummary = StateSummary.load(Bytes.empty())
  if (stateSummary == null) {
    stateSummary = new StateSummary(Bytes.empty())
    stateSummary.totalGPUCount = BigInt.fromI32(0)
    stateSummary.totalStakingGPUCount = BigInt.fromI32(0)
    stateSummary.totalCalcPointPoolCount = BigInt.fromI32(0)
    stateSummary.totalRentedGPUCount = BigInt.fromI32(0)
    stateSummary.totalBurnedRentFee = BigInt.fromI32(0)
    stateSummary.totalReservedAmount = BigInt.fromI32(0)
    stateSummary.totalCalcPoint = BigInt.fromI32(0)
  }
  if (isNewMachine){
    stateSummary.totalGPUCount = stateSummary.totalGPUCount.plus(BigInt.fromI32(1))
    stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.plus(machineInfo.totalCalcPoint)
  }
  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.plus(BigInt.fromI32(1))
  if (stakeholder.totalStakingGPUCount.toU32() == 1) {
    stateSummary.totalCalcPointPoolCount = stateSummary.totalCalcPointPoolCount.plus(BigInt.fromI32(1))
  }

  stateSummary.save()
  return
}

export function handleStakedGPUType(event: StakedGPUTypeEvent): void{
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }
  machineInfo.gpuType = event.params.gpuType
  machineInfo.save()

  let gpuTypeValue = GpuTypeValue.load(Bytes.fromUTF8(event.params.gpuType))
  if (gpuTypeValue == null) {
     gpuTypeValue = new GpuTypeValue(Bytes.fromUTF8(event.params.gpuType))
     gpuTypeValue.value = event.params.gpuType
     gpuTypeValue.count = BigInt.fromI32(1)
  }else{
     gpuTypeValue.count = gpuTypeValue.count.plus(BigInt.fromI32(1))
  }
  gpuTypeValue.save()
}

export function handleUnstaked(event: UnstakedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  let stakeholder = StakeHolder.load(Bytes.fromHexString(event.params.stakeholder.toHexString()))
  if (stakeholder == null) {
    return
  }

  stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.minus(machineInfo.fullTotalCalcPoint)
  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.minus(machineInfo.totalReservedAmount)
  stakeholder.totalStakingGPUCount = stakeholder.totalStakingGPUCount.minus(BigInt.fromI32(1))
  stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.minus(machineInfo.totalCalcPoint)
  stakeholder.save()

  let stateSummary = StateSummary.load(Bytes.empty())
  if (stateSummary == null) {
    return
  }

  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.minus(BigInt.fromU32(1))
  if (stakeholder.totalCalcPoint.toU32() == 0) {
    stateSummary.totalCalcPointPoolCount = stateSummary.totalCalcPointPoolCount.minus(BigInt.fromI32(1))
  }
  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.minus(machineInfo.totalReservedAmount)
  stateSummary.save()

  machineInfo.totalReservedAmount = BigInt.zero()
  machineInfo.totalGPUCount = BigInt.zero()
  machineInfo.totalCalcPoint = BigInt.zero()
  machineInfo.fullTotalCalcPoint = BigInt.zero()
  machineInfo.totalCalcPointWithNFT = BigInt.zero()
  machineInfo.isStaking = false
  machineInfo.online = false
  machineInfo.registered = false
  machineInfo.save()

  let gpuTypeValue = GpuTypeValue.load(Bytes.fromUTF8(machineInfo.gpuType))
  if (gpuTypeValue == null) {
    return
  }
  if (gpuTypeValue.count.toU32() >=1 ){
    gpuTypeValue.count = gpuTypeValue.count.minus(BigInt.fromI32(1))
    gpuTypeValue.save()
  }

}

export function handleAddStakeHours(event: AddedStakeHoursEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  machineInfo.stakeEndTimestamp = machineInfo.stakeEndTimestamp.plus(event.params.stakeHours.times(BigInt.fromI32(3600)))
  machineInfo.stakeEndTime = new Date(machineInfo.stakeEndTimestamp.toU64() * 1000).toISOString();
  machineInfo.save()
}


export function handleRenewRent(event: RenewRentEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString())
  let machineInfo = MachineInfo.load(id)
  if (machineInfo == null) {
    return
  }

  machineInfo.burnedRentFee = machineInfo.burnedRentFee.plus(event.params.rentFee)
  machineInfo.save()

  let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()))
  if (stakeholder == null) {
    return
  }


  stakeholder.burnedRentFee = stakeholder.burnedRentFee.plus(event.params.rentFee)
  stakeholder.save()

  let stateSummary = StateSummary.load(Bytes.empty())
  if (stateSummary == null) {
    return
  }
  stateSummary.totalBurnedRentFee = stateSummary.totalBurnedRentFee.plus(event.params.rentFee)
  stateSummary.save()
}