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
  ReportMachineFault,
  RewardsPerCalcPointUpdate,
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
  ReportMachineFaultLight,
  AfterAddHoursEndTime,
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
  RentingRecord,
  ReportMachineFaultLightRecord,
  AfterAddHoursEndTimeRecord,
  ReportMachineFaultRecord,
  RewardsPerCalcPointUpdateRecord,
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

  // Idempotency: only decrement if the machine was actually rented.
  // EndRentMachine can race with the rent.ts SlashMachineOnOffline path
  // (both decrement) and was the second drift source.
  let wasRented = machineInfo.isRented;

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
    machineInfo.nextCanRentTimestamp.toI64() * 1000
  ).toISOString();

  machineInfo.save();

  if (!wasRented) {
    return;
  }

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  if (stakeholder.rentedGPUCount.gt(BigInt.zero())) {
    stakeholder.rentedGPUCount = stakeholder.rentedGPUCount.minus(
      BigInt.fromI32(1)
    );
  }
  if (stakeholder.fullTotalCalcPoint > reducedCalcPoint) {
    stakeholder.fullTotalCalcPoint =
      stakeholder.fullTotalCalcPoint.minus(reducedCalcPoint);
  }

  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }
  if (stateSummary.totalRentedGPUCount.gt(BigInt.zero())) {
    stateSummary.totalRentedGPUCount = stateSummary.totalRentedGPUCount.minus(
      BigInt.fromI32(1)
    );
  }
  if (stateSummary.totalCalcPoint.gt(reducedCalcPoint)) {
    stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.minus(reducedCalcPoint);
  }
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
  machineInfo.extraRentFee = machineInfo.extraRentFee.plus(
    event.params.extraRentFee
  );

  machineInfo.save();

  let rentingRecord = RentingRecord.load(id);
  if (rentingRecord == null) {
    return;
  }

  const rid = rentingRecord.transactionHash;
  let record = RentMachineRecord.load(rid);
  if (record == null) {
    return;
  }
  record.extraRentFee = event.params.extraRentFee;
  record.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.burnedRentFee = stakeholder.burnedRentFee.plus(
    event.params.baseRentFee
  );
  stakeholder.extraRentFee = stakeholder.extraRentFee.plus(
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

  // Idempotency: bail if this machine is already flagged rented. Without
  // this guard a duplicate RentMachine emission (reorg, retry, edge case)
  // would double-increment the per-stakeholder and per-summary aggregates,
  // which is the root cause of historical drift seen on prod (rented count
  // exceeding total staking count).
  if (machineInfo.isRented) {
    return;
  }

  machineInfo.isRented = true;
  machineInfo.rentedGPUCount = BigInt.fromI32(1);
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
  stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.plus(addedCalcPoint);
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
  let wasAlreadyStaking: boolean = false;
  // Snapshot the previously-counted contributions before we overwrite the
  // per-machine fields. Used below when wasAlreadyStaking to delta-adjust
  // stakeholder/summary aggregates instead of skipping them entirely —
  // the contract's addDLCToStake / repricing flow can re-emit Staked with
  // a different calcPoint, in which case the aggregates need to follow.
  let priorTotalCalcPoint: BigInt = BigInt.zero();
  let priorFullTotalCalcPoint: BigInt = BigInt.zero();
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
  } else {
    // Track whether this is a re-stake (after Unstaked cleared isStaking)
    // versus a duplicate Staked while still staking (aggregates already
    // counted, must NOT increment again).
    wasAlreadyStaking = machineInfo.isStaking;
    if (wasAlreadyStaking) {
      priorTotalCalcPoint = machineInfo.totalCalcPoint;
      priorFullTotalCalcPoint = machineInfo.fullTotalCalcPoint;
    }
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
    machineInfo.stakeEndTimestamp.toI64() * 1000
  ).toISOString();
  machineInfo.nextCanRentTime = new Date(
    machineInfo.nextCanRentTimestamp.toI64() * 1000
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

  // Idempotency: when the machine was already counted as staking, we skip
  // the GPU-count increment but still need to delta-adjust calcPoint
  // aggregates if the new event carries a different value (the contract's
  // addDLCToStake / repricing path re-emits Staked with an updated calcPoint).
  // GPU count itself is binary per machine, so the .totalGPUCount and
  // .totalStakingGPUCount increments stay skipped.
  if (wasAlreadyStaking) {
    let newTotalCalcPoint = machineInfo.totalCalcPoint;
    let newFullCalcPoint = machineInfo.fullTotalCalcPoint;

    // stakeholder.totalCalcPoint += (new - prior)
    if (newTotalCalcPoint.gt(priorTotalCalcPoint)) {
      stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.plus(
        newTotalCalcPoint.minus(priorTotalCalcPoint)
      );
    } else if (priorTotalCalcPoint.gt(newTotalCalcPoint)) {
      let delta = priorTotalCalcPoint.minus(newTotalCalcPoint);
      stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.gt(delta)
        ? stakeholder.totalCalcPoint.minus(delta)
        : BigInt.zero();
    }

    // stakeholder.fullTotalCalcPoint += (new - prior)
    if (newFullCalcPoint.gt(priorFullTotalCalcPoint)) {
      stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.plus(
        newFullCalcPoint.minus(priorFullTotalCalcPoint)
      );
    } else if (priorFullTotalCalcPoint.gt(newFullCalcPoint)) {
      let delta = priorFullTotalCalcPoint.minus(newFullCalcPoint);
      stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.gt(delta)
        ? stakeholder.fullTotalCalcPoint.minus(delta)
        : BigInt.zero();
    }
    stakeholder.save();
    machineInfo.holderRef = stakeholder.id;
    machineInfo.save();

    // Mirror the same delta on stateSummary.totalCalcPoint (it's incremented
    // by fullTotalCalcPoint in the new-stake branch below, so use full delta).
    let stateSummary = StateSummary.load(Bytes.empty());
    if (stateSummary != null) {
      if (newFullCalcPoint.gt(priorFullTotalCalcPoint)) {
        stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.plus(
          newFullCalcPoint.minus(priorFullTotalCalcPoint)
        );
      } else if (priorFullTotalCalcPoint.gt(newFullCalcPoint)) {
        let delta = priorFullTotalCalcPoint.minus(newFullCalcPoint);
        stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.gt(delta)
          ? stateSummary.totalCalcPoint.minus(delta)
          : BigInt.zero();
      }
      stateSummary.save();
    }
    return;
  }

  stakeholder.totalGPUCount = stakeholder.totalGPUCount.plus(
    BigInt.fromI32(1)
  );
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
  stateSummary.totalGPUCount = stateSummary.totalGPUCount.plus(
    BigInt.fromI32(1)
  );
  stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.plus(
    machineInfo.fullTotalCalcPoint
  );
  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.plus(
    BigInt.fromI32(1)
  );
  if (stakeholder.totalStakingGPUCount.equals(BigInt.fromI32(1))) {
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

  // Idempotency: a duplicate Unstaked event would otherwise re-decrement
  // every aggregate counter and pull totals into negative territory.
  if (!machineInfo.isStaking) {
    return;
  }

  // If the machine is being unstaked while still flagged as rented (e.g.
  // operator pulls it out without the EndRentMachine path running first),
  // the rented aggregates would stay too high. Carry the cleanup here.
  let wasRented = machineInfo.isRented;

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(event.params.stakeholder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.gt(machineInfo.fullTotalCalcPoint)
    ? stakeholder.fullTotalCalcPoint.minus(machineInfo.fullTotalCalcPoint)
    : BigInt.zero();
  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.gt(machineInfo.totalReservedAmount)
    ? stakeholder.totalReservedAmount.minus(machineInfo.totalReservedAmount)
    : BigInt.zero();
  stakeholder.totalStakingGPUCount = stakeholder.totalStakingGPUCount.gt(BigInt.zero())
    ? stakeholder.totalStakingGPUCount.minus(BigInt.fromI32(1))
    : BigInt.zero();
  stakeholder.totalGPUCount = stakeholder.totalGPUCount.gt(BigInt.zero())
    ? stakeholder.totalGPUCount.minus(BigInt.fromI32(1))
    : BigInt.zero();
  stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.gt(machineInfo.totalCalcPoint)
    ? stakeholder.totalCalcPoint.minus(machineInfo.totalCalcPoint)
    : BigInt.zero();
  if (wasRented && stakeholder.rentedGPUCount.gt(BigInt.zero())) {
    stakeholder.rentedGPUCount = stakeholder.rentedGPUCount.minus(BigInt.fromI32(1));
  }
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  if (stateSummary.totalStakingGPUCount.gt(BigInt.zero())) {
    stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.minus(BigInt.fromI32(1));
  }
  if (stateSummary.totalGPUCount.gt(BigInt.zero())) {
    stateSummary.totalGPUCount = stateSummary.totalGPUCount.minus(BigInt.fromI32(1));
  }
  if (stateSummary.totalCalcPoint.gt(machineInfo.fullTotalCalcPoint)) {
    stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.minus(
      machineInfo.fullTotalCalcPoint
    );
  } else {
    stateSummary.totalCalcPoint = BigInt.zero();
  }
  if (stakeholder.totalStakingGPUCount.equals(BigInt.zero())
    && stateSummary.totalCalcPointPoolCount.gt(BigInt.zero())) {
    stateSummary.totalCalcPointPoolCount =
      stateSummary.totalCalcPointPoolCount.minus(BigInt.fromI32(1));
  }
  if (wasRented && stateSummary.totalRentedGPUCount.gt(BigInt.zero())) {
    stateSummary.totalRentedGPUCount = stateSummary.totalRentedGPUCount.minus(BigInt.fromI32(1));
  }
  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.gt(machineInfo.totalReservedAmount)
    ? stateSummary.totalReservedAmount.minus(machineInfo.totalReservedAmount)
    : BigInt.zero();
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
  machineInfo.isRented = false;

  machineInfo.save();

  let gpuTypeValue = GpuTypeValue.load(Bytes.fromUTF8(machineInfo.gpuType));
  if (gpuTypeValue == null) {
    return;
  }
  if (gpuTypeValue.count.gt(BigInt.zero())) {
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
    machineInfo.stakeEndTimestamp.toI64() * 1000
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

  // NOTE: burnedRentFee 不在这里累加，统一由 EndRentMachineFee 处理
  // RenewRent.rentFee = base+extra+platform（续租增量），
  // EndRentMachineFee.baseRentFee = 累计总额（含所有续租），在这里加会导致双重计费
  machineInfo.save();
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

  // Bug fix: same-tx RentMachine + ExitStakingForOffline could leave the
  // machine flagged isRented forever because the contract path that ends
  // rewards via _stopRewarding doesn't unwind the rent state on the
  // subgraph side. If the machine was being rented when rewards stopped,
  // clear isRented and decrement the rented aggregates here so the
  // counters stay consistent.
  let wasRented = machineInfo.isRented;
  if (wasRented) {
    machineInfo.isRented = false;
    machineInfo.rentedGPUCount = BigInt.zero();
  }

  // Bug fix: 同步减 calcPoint（合约 _stopRewarding → _joinStaking(0)）
  let calcPointToRemove = machineInfo.fullTotalCalcPoint;
  machineInfo.fullTotalCalcPoint = BigInt.zero();
  machineInfo.save();

  let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()));
  if (stakeholder != null) {
    if (stakeholder.fullTotalCalcPoint.gt(calcPointToRemove)) {
      stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.minus(calcPointToRemove);
    } else {
      stakeholder.fullTotalCalcPoint = BigInt.zero();
    }
    if (wasRented && stakeholder.rentedGPUCount.gt(BigInt.zero())) {
      stakeholder.rentedGPUCount = stakeholder.rentedGPUCount.minus(BigInt.fromI32(1));
    }
    stakeholder.save();
  }

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary != null) {
    if (stateSummary.totalCalcPoint.gt(calcPointToRemove)) {
      stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.minus(calcPointToRemove);
    } else {
      stateSummary.totalCalcPoint = BigInt.zero();
    }
    if (wasRented && stateSummary.totalRentedGPUCount.gt(BigInt.zero())) {
      stateSummary.totalRentedGPUCount = stateSummary.totalRentedGPUCount.minus(BigInt.fromI32(1));
    }
    stateSummary.save();
  }

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

  // Idempotency: mirror the contract guard `if (calcPoint != 0) return`.
  // A duplicate RecoverRewarding (reorg, retry) would otherwise add the
  // bonus to the aggregates twice while the per-machine field stays at the
  // same restored value. Only restore calcPoint when it was actually 0.
  let needsCalcPointRestore = machineInfo.fullTotalCalcPoint.equals(BigInt.zero());

  // Bug fix: 恢复 calcPoint（合约 _recoverRewarding → _joinStaking(calcPoint)）
  // 恢复到含 NFT 倍数的值（如果在租赁中还要加 30% 增幅）
  if (needsCalcPointRestore) {
    let restoredCalcPoint = machineInfo.totalCalcPointWithNFT;
    if (machineInfo.isRented) {
      let rentBonus = restoredCalcPoint.times(BigInt.fromI32(3)).div(BigInt.fromI32(10));
      restoredCalcPoint = restoredCalcPoint.plus(rentBonus);
    }
    machineInfo.fullTotalCalcPoint = restoredCalcPoint;
    machineInfo.save();

    let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()));
    if (stakeholder != null) {
      stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.plus(restoredCalcPoint);
      stakeholder.save();
    }

    let stateSummary = StateSummary.load(Bytes.empty());
    if (stateSummary != null) {
      stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.plus(restoredCalcPoint);
      stateSummary.save();
    }
  } else {
    machineInfo.save();
  }

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

  // Bug fix: 同步减 calcPoint（合约 _stopRewarding → _joinStaking(0)）
  // Bug fix: also flip online to false. The Blocking pathway is what
  // validateMachineIds() uses (the DLC client wallet's health check), so
  // 70%+ of real-world "machine went offline" transitions arrive here,
  // not via ExitStakingForOffline. Without this line, blocked machines
  // appear online=true forever and any UI relying on machineInfo.online
  // gets misleading data.
  // Bug fix: same-tx RentMachine + ExitStakingForBlocking could leave
  // the machine in `isRented=true / fullTotalCalcPoint=0` permanently —
  // ExitStakingForBlocking zeroed calcPoint but never unwound rent state.
  // Mirror the cleanup we do for ExitStakingForOffline.
  let machineInfo = MachineInfo.load(id);
  if (machineInfo != null) {
    let wasRented = machineInfo.isRented;
    let calcPointToRemove = machineInfo.fullTotalCalcPoint;
    machineInfo.fullTotalCalcPoint = BigInt.zero();
    machineInfo.online = false;
    if (wasRented) {
      machineInfo.isRented = false;
      machineInfo.rentedGPUCount = BigInt.zero();
    }
    machineInfo.save();

    let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()));
    if (stakeholder != null) {
      if (stakeholder.fullTotalCalcPoint.gt(calcPointToRemove)) {
        stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.minus(calcPointToRemove);
      } else {
        stakeholder.fullTotalCalcPoint = BigInt.zero();
      }
      if (wasRented && stakeholder.rentedGPUCount.gt(BigInt.zero())) {
        stakeholder.rentedGPUCount = stakeholder.rentedGPUCount.minus(BigInt.fromI32(1));
      }
      stakeholder.save();
    }

    let stateSummary = StateSummary.load(Bytes.empty());
    if (stateSummary != null) {
      if (stateSummary.totalCalcPoint.gt(calcPointToRemove)) {
        stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.minus(calcPointToRemove);
      } else {
        stateSummary.totalCalcPoint = BigInt.zero();
      }
      if (wasRented && stateSummary.totalRentedGPUCount.gt(BigInt.zero())) {
        stateSummary.totalRentedGPUCount = stateSummary.totalRentedGPUCount.minus(BigInt.fromI32(1));
      }
      stateSummary.save();
    }
  }

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

  // Bug fix: 恢复 calcPoint（合约 _recoverRewarding → _joinStaking(calcPoint)）
  // Bug fix: mirror the online=true flip its non-blocking sibling does.
  // Bug fix: idempotency — the contract has `if (calcPoint != 0) return`
  // so the on-chain effect of a duplicate RecoverRewardingForBlocking is
  // a no-op; mirror that here so the subgraph aggregates don't double up.
  let machineInfo = MachineInfo.load(id);
  if (machineInfo != null) {
    machineInfo.online = true;
    if (machineInfo.fullTotalCalcPoint.equals(BigInt.zero())) {
      let restoredCalcPoint = machineInfo.totalCalcPointWithNFT;
      if (machineInfo.isRented) {
        let rentBonus = restoredCalcPoint.times(BigInt.fromI32(3)).div(BigInt.fromI32(10));
        restoredCalcPoint = restoredCalcPoint.plus(rentBonus);
      }
      machineInfo.fullTotalCalcPoint = restoredCalcPoint;
      machineInfo.save();

      let stakeholder = StakeHolder.load(Bytes.fromHexString(machineInfo.holder.toHexString()));
      if (stakeholder != null) {
        stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.plus(restoredCalcPoint);
        stakeholder.save();
      }

      let stateSummary = StateSummary.load(Bytes.empty());
      if (stateSummary != null) {
        stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.plus(restoredCalcPoint);
        stateSummary.save();
      }
    } else {
      machineInfo.save();
    }
  }

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

// ── 补全事件: ReportMachineFaultLight（轻量惩罚） ──
export function handleReportMachineFaultLight(event: ReportMachineFaultLight): void {
  let record = new ReportMachineFaultLightRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.renter = event.params.renter;
  record.nextCanRentTime = event.params.nextCanRentTime;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();

  // 更新 MachineInfo 状态
  let id = Bytes.fromUTF8(event.params.machineId);
  let machineInfo = MachineInfo.load(id);
  if (machineInfo != null) {
    machineInfo.isSlashed = true;
    machineInfo.nextCanRentTimestamp = event.params.nextCanRentTime;
    machineInfo.nextCanRentTime = new Date(event.params.nextCanRentTime.toI64() * 1000).toISOString();
    machineInfo.save();
  }
}

// ── 补全事件: AfterAddHoursEndTime（延长质押后的新结束时间） ──
export function handleAfterAddHoursEndTime(event: AfterAddHoursEndTime): void {
  let record = new AfterAddHoursEndTimeRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.endTimestamp = event.params.endTimestamp;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();

  // 更新 MachineInfo 的质押结束时间
  let id = Bytes.fromUTF8(event.params.machineId);
  let machineInfo = MachineInfo.load(id);
  if (machineInfo != null) {
    machineInfo.stakeEndTimestamp = event.params.endTimestamp;
    machineInfo.stakeEndTime = new Date(event.params.endTimestamp.toI64() * 1000).toISOString();
    machineInfo.save();
  }
}

// ── 补全事件: ReportMachineFault（重度惩罚） ──
export function handleReportMachineFault(event: ReportMachineFault): void {
  let record = new ReportMachineFaultRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.renter = event.params.renter;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();

  // 重度罚款会调 _unStake()，emit Unstaked 事件 → handleUnstaked 会处理 GPU 计数和 calcPoint 的减操作
  // 这里只标记 isSlashed，不减计数（避免与 handleUnstaked 重复减）
  let id = Bytes.fromUTF8(event.params.machineId);
  let machineInfo = MachineInfo.load(id);
  if (machineInfo != null) {
    machineInfo.isSlashed = true;
    machineInfo.save();
  }
}

// ── 补全事件: RewardsPerCalcPointUpdate（每算力点奖励更新） ──
export function handleRewardsPerCalcPointUpdate(event: RewardsPerCalcPointUpdate): void {
  let record = new RewardsPerCalcPointUpdateRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.accumulatedPerShareBefore = event.params.accumulatedPerShareBefore;
  record.accumulatedPerShareAfter = event.params.accumulatedPerShareAfter;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}
