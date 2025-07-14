import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  AddedStakeHours as AddedStakeHoursEvent,
  Claimed as ClaimedEvent,
  EndRentMachine as EndRentMachineEvent,
  EndRentMachineFee as EndRentMachineFeeEvent,
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
  ExitStakingForOffline as ExitStakingForOfflineEvent,
  RecoverRewarding,
  ExitStakingForBlocking,
  RecoverRewardingForBlocking,
  MachineUnregistered,
  MachineRegistered,
} from "../generated/NFTStaking/NFTStaking";
import {
  StateSummary,
  StakeHolder,
  MachineInfo,
  GpuTypeValue,
  AddStakeHour,
  MachineOfflineRecord,
  HolderPaidSlashRecord,
  PaidSlashRecord,
  AddDLCRecord,
  giveBackDlc,
  claimedReward,
  MachineReOnlineRecord,
  StopRewardingForBlockingRecord,
  RecoverRewardingForBlockingRecord,
  MachineUnregisterRecord,
  MachineRegisterRecord,
  MachineReportedRecord,
  RentMachineRecord,
} from "../generated/schema";

export function handleClaimed(event: ClaimedEvent): void {
  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(event.params.stakeholder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  if (
    event.params.moveToUserWalletAmount.gt(
      BigInt.fromString("3000000000000000000000000")
    ) &&
    event.params.machineId ==
      "e36e94c30d483129fb3a2feed81458926066d6a0f27094b0744e8b0aedbf00ee"
  ) {
    return;
  }

  const claimedAmount = event.params.moveToUserWalletAmount.plus(
    event.params.moveToReservedAmount
  );
  stakeholder.totalReleasedRewardAmount =
    stakeholder.totalReleasedRewardAmount.plus(claimedAmount);
  stakeholder.totalClaimedRewardAmount =
    stakeholder.totalClaimedRewardAmount.plus(event.params.totalRewardAmount);

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.plus(
    event.params.moveToReservedAmount
  );
  stakeholder.save();
  //
  // let r = new claimedReward(event.transaction.hash)
  // r.holder = event.params.stakeholder
  // r.machineId = event.params.machineId.toString()
  // r.total = event.params.totalRewardAmount
  // r.released = event.params.moveToUserWalletAmount
  // r.blocktimestamp = event.block.timestamp
  // r.transactionHash = event.transaction.hash
  // r.save()

  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.claimTimes = machineInfo.claimTimes.plus(BigInt.fromI32(1));
  machineInfo.totalClaimedRewardAmount =
    machineInfo.totalClaimedRewardAmount.plus(claimedAmount);
  machineInfo.save();
}

export function handleMoveToReserveAmount(
  event: MoveToReserveAmountEvent
): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.plus(
    event.params.amount
  );
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.plus(
    event.params.amount
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.plus(
    event.params.amount
  );
  stateSummary.save();
}

export function handleEndRentMachine(event: EndRentMachineEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.nextCanRentTimestamp = event.params.nextCanRentTime;
  machineInfo.isRented = false;
  machineInfo.rentedGPUCount = BigInt.fromI32(0);

  const reducedCalcPoint = machineInfo.totalCalcPointWithNFT
    .times(BigInt.fromI32(3))
    .div(BigInt.fromI32(10));
  if (machineInfo.fullTotalCalcPoint > reducedCalcPoint) {
    machineInfo.fullTotalCalcPoint =
      machineInfo.fullTotalCalcPoint.minus(reducedCalcPoint);
  }
  machineInfo.nextCanRentTimestamp = event.params.nextCanRentTime;
  machineInfo.nextCanRentTime = new Date(
    machineInfo.nextCanRentTimestamp.toU64() * 1000
  ).toISOString();

  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.rentedGPUCount = stakeholder.rentedGPUCount.minus(
    BigInt.fromI32(1)
  );
  if (stakeholder.fullTotalCalcPoint > reducedCalcPoint) {
    stakeholder.fullTotalCalcPoint =
      stakeholder.fullTotalCalcPoint.minus(reducedCalcPoint);
  }

  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }
  stateSummary.totalRentedGPUCount = stateSummary.totalRentedGPUCount.minus(
    BigInt.fromI32(1)
  );
  stateSummary.save();
}

export function handleEndRentMachineFee(event: EndRentMachineFeeEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.burnedRentFee = machineInfo.burnedRentFee.plus(
    event.params.baseRentFee
  );
  machineInfo.extraRentFee = machineInfo.burnedRentFee.plus(
    event.params.extraRentFee
  );

  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.burnedRentFee = stakeholder.burnedRentFee.plus(
    event.params.baseRentFee
  );
  stakeholder.extraRentFee = stakeholder.burnedRentFee.plus(
    event.params.extraRentFee
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalBurnedRentFee = stateSummary.totalBurnedRentFee.plus(
    event.params.baseRentFee
  );
  stateSummary.save();
}

export function handlePaySlash(event: PaySlashEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.minus(
    event.params.slashAmount
  );
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.minus(
    event.params.slashAmount
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.minus(
    event.params.slashAmount
  );
  stateSummary.save();

  let payRecord = new HolderPaidSlashRecord(event.transaction.hash);
  payRecord.holder = machineInfo.holder;
  payRecord.paid = true;
  payRecord.blockNumber = event.block.number;
  payRecord.blockTimestamp = event.block.timestamp;
  payRecord.transactionHash = event.transaction.hash;
  payRecord.save();
}

// rentFee 字段改动 移到其他事件中 为了兼容之前的数据 合约测在更新后 此字段为0 但是graph仍需对其计数
export function handleRentMachine(event: RentMachineEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.isRented = true;
  const addedCalcPoint = machineInfo.totalCalcPointWithNFT
    .times(BigInt.fromI32(3))
    .div(BigInt.fromI32(10));
  machineInfo.fullTotalCalcPoint =
    machineInfo.fullTotalCalcPoint.plus(addedCalcPoint);
  machineInfo.burnedRentFee = machineInfo.burnedRentFee.plus(
    event.params.rentFee
  );
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.rentedGPUCount = stakeholder.rentedGPUCount.plus(
    BigInt.fromI32(1)
  );
  stakeholder.fullTotalCalcPoint =
    stakeholder.fullTotalCalcPoint.plus(addedCalcPoint);
  stakeholder.burnedRentFee = stakeholder.burnedRentFee.plus(
    event.params.rentFee
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }
  stateSummary.totalRentedGPUCount = stateSummary.totalRentedGPUCount.plus(
    BigInt.fromI32(1)
  );
  stateSummary.totalBurnedRentFee = stateSummary.totalBurnedRentFee.plus(
    event.params.rentFee
  );
  stateSummary.save();
}

export function handleReserveDLC(event: ReserveDLCEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.plus(
    event.params.amount
  );
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    // never happen
    stakeholder = new StakeHolder(
      Bytes.fromHexString(machineInfo.holder.toHexString())
    );
    return;
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.plus(
    event.params.amount
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.plus(
    event.params.amount
  );
  stateSummary.save();

  let addDlc = new AddDLCRecord(event.transaction.hash);
  addDlc.machineId = event.params.machineId;
  addDlc.amount = event.params.amount;
  addDlc.blockNumber = event.block.number;
  addDlc.blockTimestamp = event.block.timestamp;
  addDlc.transactionHash = event.transaction.hash;
  addDlc.save();
}

export function handleStaked(event: StakedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  let isNewMachine: boolean = false;
  if (machineInfo == null) {
    isNewMachine = true;
    machineInfo = new MachineInfo(id);
    machineInfo.blockNumber = event.block.number;
    machineInfo.blockTimestamp = event.block.timestamp;
    machineInfo.machineId = event.params.machineId;
    machineInfo.transactionHash = event.transaction.hash;
    machineInfo.rentedGPUCount = BigInt.fromI32(0);
    machineInfo.totalReservedAmount = BigInt.fromI32(0);
    machineInfo.burnedRentFee = BigInt.fromI32(0);
    machineInfo.isRented = false;
    machineInfo.gpuType = "";
    machineInfo.claimTimes = BigInt.fromI32(0);
    machineInfo.extraRentFee = BigInt.fromI32(0);
    machineInfo.totalClaimedRewardAmount = BigInt.fromI32(0);
  }
  machineInfo.isSlashed = false;

  machineInfo.totalGPUCount = BigInt.fromI32(1);
  machineInfo.totalCalcPoint = event.params.originCalcPoint;
  machineInfo.totalCalcPointWithNFT = event.params.calcPoint;
  machineInfo.fullTotalCalcPoint = event.params.calcPoint;
  machineInfo.stakeEndTimestamp = event.block.timestamp.plus(
    event.params.stakeHours.times(BigInt.fromI32(3600))
  );
  machineInfo.nextCanRentTimestamp = event.block.timestamp;
  machineInfo.stakeEndTime = new Date(
    machineInfo.stakeEndTimestamp.toU64() * 1000
  ).toISOString();
  machineInfo.nextCanRentTime = new Date(
    machineInfo.nextCanRentTimestamp.toU64() * 1000
  ).toISOString();
  machineInfo.isStaking = true;
  machineInfo.online = true;
  machineInfo.registered = true;

  machineInfo.holder = event.params.stakeholder;

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(event.params.stakeholder.toHexString())
  );
  if (stakeholder == null) {
    stakeholder = new StakeHolder(
      Bytes.fromHexString(event.params.stakeholder.toHexString())
    );
    stakeholder.holder = event.params.stakeholder;
    stakeholder.blockNumber = event.block.number;
    stakeholder.blockTimestamp = event.block.timestamp;
    stakeholder.transactionHash = event.transaction.hash;
    stakeholder.totalGPUCount = BigInt.fromI32(0);
    stakeholder.totalStakingGPUCount = BigInt.fromI32(0);
    stakeholder.rentedGPUCount = BigInt.fromI32(0);
    stakeholder.totalCalcPoint = BigInt.fromI32(0);
    stakeholder.fullTotalCalcPoint = BigInt.fromI32(0);
    stakeholder.totalReservedAmount = BigInt.fromI32(0);
    stakeholder.rentedGPUCount = BigInt.fromI32(0);
    stakeholder.burnedRentFee = BigInt.fromI32(0);
    stakeholder.totalReleasedRewardAmount = BigInt.fromI32(0);
    stakeholder.totalClaimedRewardAmount = BigInt.fromI32(0);
    stakeholder.extraRentFee = BigInt.fromI32(0);
  }

  if (isNewMachine) {
    stakeholder.totalGPUCount = stakeholder.totalGPUCount.plus(
      BigInt.fromI32(1)
    );
  }
  stakeholder.totalStakingGPUCount = stakeholder.totalStakingGPUCount.plus(
    BigInt.fromI32(1)
  );
  stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.plus(
    machineInfo.totalCalcPoint
  );
  stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.plus(
    machineInfo.fullTotalCalcPoint
  );
  stakeholder.save();

  machineInfo.holderRef = stakeholder.id;
  machineInfo.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    stateSummary = new StateSummary(Bytes.empty());
    stateSummary.totalGPUCount = BigInt.fromI32(0);
    stateSummary.totalStakingGPUCount = BigInt.fromI32(0);
    stateSummary.totalCalcPointPoolCount = BigInt.fromI32(0);
    stateSummary.totalRentedGPUCount = BigInt.fromI32(0);
    stateSummary.totalBurnedRentFee = BigInt.fromI32(0);
    stateSummary.totalReservedAmount = BigInt.fromI32(0);
    stateSummary.totalCalcPoint = BigInt.fromI32(0);
  }
  if (isNewMachine) {
    stateSummary.totalGPUCount = stateSummary.totalGPUCount.plus(
      BigInt.fromI32(1)
    );
    stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.plus(
      machineInfo.totalCalcPoint
    );
  }
  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.plus(
    BigInt.fromI32(1)
  );
  if (stakeholder.totalStakingGPUCount.toU32() == 1) {
    stateSummary.totalCalcPointPoolCount =
      stateSummary.totalCalcPointPoolCount.plus(BigInt.fromI32(1));
  }

  stateSummary.save();
  return;
}

export function handleStakedGPUType(event: StakedGPUTypeEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }
  machineInfo.gpuType = event.params.gpuType;
  machineInfo.save();

  let gpuTypeValue = GpuTypeValue.load(Bytes.fromUTF8(event.params.gpuType));
  if (gpuTypeValue == null) {
    gpuTypeValue = new GpuTypeValue(Bytes.fromUTF8(event.params.gpuType));
    gpuTypeValue.value = event.params.gpuType;
    gpuTypeValue.count = BigInt.fromI32(1);
  } else {
    gpuTypeValue.count = gpuTypeValue.count.plus(BigInt.fromI32(1));
  }
  gpuTypeValue.save();
}

export function handleUnstaked(event: UnstakedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(event.params.stakeholder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.minus(
    machineInfo.fullTotalCalcPoint
  );
  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.minus(
    machineInfo.totalReservedAmount
  );
  stakeholder.totalStakingGPUCount = stakeholder.totalStakingGPUCount.minus(
    BigInt.fromI32(1)
  );
  stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.minus(
    machineInfo.totalCalcPoint
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.minus(
    BigInt.fromU32(1)
  );
  if (stakeholder.totalCalcPoint.toU32() == 0) {
    stateSummary.totalCalcPointPoolCount =
      stateSummary.totalCalcPointPoolCount.minus(BigInt.fromI32(1));
  }
  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.minus(
    machineInfo.totalReservedAmount
  );
  stateSummary.save();

  let giveBackDlcRecord = new giveBackDlc(event.transaction.hash);
  giveBackDlcRecord.machineId = event.params.machineId;
  giveBackDlcRecord.blockNumber = event.block.number;
  giveBackDlcRecord.blockTimestamp = event.block.timestamp;
  giveBackDlcRecord.transactionHash = event.transaction.hash;
  giveBackDlcRecord.amount = machineInfo.totalReservedAmount;
  giveBackDlcRecord.save();

  machineInfo.totalReservedAmount = BigInt.zero();
  machineInfo.totalGPUCount = BigInt.zero();
  machineInfo.totalCalcPoint = BigInt.zero();
  machineInfo.fullTotalCalcPoint = BigInt.zero();
  machineInfo.totalCalcPointWithNFT = BigInt.zero();
  machineInfo.isStaking = false;

  machineInfo.save();

  let gpuTypeValue = GpuTypeValue.load(Bytes.fromUTF8(machineInfo.gpuType));
  if (gpuTypeValue == null) {
    return;
  }
  if (gpuTypeValue.count.toU32() >= 1) {
    gpuTypeValue.count = gpuTypeValue.count.minus(BigInt.fromI32(1));
    gpuTypeValue.save();
  }

  const lastOfflineRecord = MachineOfflineRecord.load(id);
  if (lastOfflineRecord !== null && lastOfflineRecord.isActive) {
    lastOfflineRecord.isActive = false;
    lastOfflineRecord.save();

    const reportedRecord = MachineReportedRecord.load(
      lastOfflineRecord.transactionHash
    );
    if (reportedRecord == null) {
      return;
    }
    reportedRecord.machineId = event.params.machineId;
    reportedRecord.unStakeBlockTimestamp = event.block.timestamp;
    reportedRecord.unStakeTransactionHash = event.transaction.hash;
    reportedRecord.finishedByEndStake = true;
    reportedRecord.offlineDuration = event.block.timestamp.minus(
      reportedRecord.offlineBlockTimestamp
    );
    reportedRecord.save();
  }
}

export function handleAddStakeHours(event: AddedStakeHoursEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  let addStakeHours = new AddStakeHour(event.transaction.hash);
  addStakeHours.holder = event.params.stakeholder;
  addStakeHours.machineId = event.params.machineId;
  addStakeHours.blockNumber = event.block.number;
  addStakeHours.blockTimestamp = event.block.timestamp;
  addStakeHours.transactionHash = event.transaction.hash;
  addStakeHours.hours = event.params.stakeHours;
  let stakeEndTimestampBefore = machineInfo.stakeEndTimestamp;

  addStakeHours.stakeEndTimestampBefore = stakeEndTimestampBefore;

  machineInfo.stakeEndTimestamp = stakeEndTimestampBefore.plus(
    event.params.stakeHours.times(BigInt.fromI32(3600))
  );
  machineInfo.stakeEndTime = new Date(
    machineInfo.stakeEndTimestamp.toU64() * 1000
  ).toISOString();
  machineInfo.save();

  addStakeHours.stakeEndTimestampAfter = machineInfo.stakeEndTimestamp;
  addStakeHours.save();
}

export function handleRenewRent(event: RenewRentEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.burnedRentFee = machineInfo.burnedRentFee.plus(
    event.params.rentFee
  );
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.burnedRentFee = stakeholder.burnedRentFee.plus(
    event.params.rentFee
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }
  stateSummary.totalBurnedRentFee = stateSummary.totalBurnedRentFee.plus(
    event.params.rentFee
  );
  stateSummary.save();
}

export function handleExitStakingForOffline(
  event: ExitStakingForOfflineEvent
): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }
  machineInfo.online = false;
  machineInfo.save();

  let record = new MachineOfflineRecord(id);
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.machineId = event.params.machineId;
  record.holder = event.params.holder;
  record.transactionHash = event.transaction.hash;
  record.isActive = true;
  record.save();

  let reportedRecord = new MachineReportedRecord(record.transactionHash);
  reportedRecord.machineId = event.params.machineId;
  reportedRecord.offlineBlockTimestamp = record.blockTimestamp;
  reportedRecord.offlineTransactionHash = event.transaction.hash;
  reportedRecord.reOnlineBlockTimestamp = BigInt.zero();
  reportedRecord.reOnlineTransactionHash = Bytes.fromHexString("0x");
  reportedRecord.unStakeBlockTimestamp = BigInt.zero();
  reportedRecord.unStakeTransactionHash = Bytes.fromHexString("0x");
  reportedRecord.finishedByReOnline = false;
  reportedRecord.finishedByEndStake = false;
  reportedRecord.offlineDuration = BigInt.zero();
  reportedRecord.save();
}

export function handleReOnline(event: RecoverRewarding): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }
  machineInfo.online = true;
  machineInfo.save();

  let lastOfflineRecord = MachineOfflineRecord.load(id);
  if (lastOfflineRecord == null || !lastOfflineRecord.isActive) {
    return;
  }
  lastOfflineRecord.isActive = false;
  lastOfflineRecord.save();

  let record = new MachineReOnlineRecord(id);
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.machineId = event.params.machineId;
  record.holder = event.params.holder;
  record.transactionHash = event.transaction.hash;
  record.save();

  let reportedRecord = MachineReportedRecord.load(
    lastOfflineRecord.transactionHash
  );
  if (reportedRecord == null) {
    return;
  }

  reportedRecord.machineId = event.params.machineId;
  reportedRecord.reOnlineBlockTimestamp = event.block.timestamp;
  reportedRecord.reOnlineTransactionHash = event.transaction.hash;
  reportedRecord.finishedByReOnline = true;
  reportedRecord.offlineDuration = event.block.timestamp.minus(
    reportedRecord.offlineBlockTimestamp
  );
  reportedRecord.save();
}

export function handleExitStakingForBlocking(
  event: ExitStakingForBlocking
): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let record = new StopRewardingForBlockingRecord(id);
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.machineId = event.params.machineId;
  record.holder = event.params.holder;
  record.transactionHash = event.transaction.hash;
  record.save();
}

export function handleRecoverRewardingForBlocking(
  event: RecoverRewardingForBlocking
): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let record = new RecoverRewardingForBlockingRecord(id);
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.machineId = event.params.machineId;
  record.holder = event.params.holder;
  record.transactionHash = event.transaction.hash;
  record.save();
}

export function handleMachineUnregister(event: MachineUnregistered): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }
  machineInfo.registered = false;
  machineInfo.save();

  let record = new MachineUnregisterRecord(id);
  record.machineId = event.params.machineId;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.isActive = true;
  record.save();
}

export function handleMachineRegister(event: MachineRegistered): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }
  machineInfo.registered = true;
  machineInfo.save();

  let unregisterRecord = MachineUnregisterRecord.load(id);
  if (unregisterRecord == null) {
    return;
  }

  unregisterRecord.isActive = false;
  unregisterRecord.save();
}
