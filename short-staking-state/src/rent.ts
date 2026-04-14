import {
  RentMachine as RentMachineEvent,
  RenewRent as RenewRentEvent,
  SlashMachineOnOffline as SlashMachineOnOfflineEvent,
  Upgraded as UpgradedEvent,
  RentFee as RentFeeEvent,
  PayBackFee as PayBackFeeEvent,
  PayBackExtraFee as PayBackExtraFeeEvent,
  PayBackPointFee as PayBackPointFeeEvent,
  PaidSlash as PaidSlashEvent,
  MachineRegister as MachineRegisterEvent,
  MachineUnregister as MachineUnregisterEvent,
} from "../generated/Rent/Rent";
import {
  MachineInfo,
  MachineSlashedRecord,
  RentingRecord,
  RentMachineRecord,
  RentRenewal,
  RentFeeRecord,
  PayBackFeeRecord,
  RentPaidSlashRecord,
  RentMachineRegisterRecord,
  RentMachineUnregisterRecord,
} from "../generated/schema";
import { BigInt, Bytes } from "@graphprotocol/graph-ts";

export function handleRentMachine(event: RentMachineEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());

  let rentingRecord = RentingRecord.load(id);
  if (rentingRecord == null) {
    rentingRecord = new RentingRecord(id);
  }
  rentingRecord.machineOwner = event.params.machineOnwer;
  rentingRecord.rentId = event.params.rentId;
  rentingRecord.isActive = true;
  rentingRecord.transactionHash = event.transaction.hash;
  rentingRecord.machineId = event.params.machineId;
  rentingRecord.save();

  const rid = rentingRecord.transactionHash;
  let record = new RentMachineRecord(rid);

  record.machineOwner = event.params.machineOnwer;
  record.rentId = event.params.rentId;
  record.machineId = event.params.machineId;
  record.rentEndTime = event.params.rentEndTime;
  record.renter = event.params.renter;
  record.gogoing = true;
  record.rentBlockTimestamp = event.block.timestamp;
  record.rentTransactionHash = event.transaction.hash;
  record.endRentBlockTimestamp = BigInt.zero();
  record.endRentTransactionHash = Bytes.fromHexString("0x");
  record.extraRentFee = BigInt.zero();
  record.save();
}

export function handleEndRentMachine(event: RentMachineEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());

  // Fix: Rent 合约的 forceCleanupRentInfo/forceCleanupRentInfoByOwner 只 emit Rent 的 EndRentMachine，
  // 不会触发 NFTStaking 的 handler，需要在这里同步更新 MachineInfo.isRented
  let machineInfo = MachineInfo.load(id);
  if (machineInfo != null) {
    machineInfo.isRented = false;
    machineInfo.save();
  }

  let rentingRecord = RentingRecord.load(id);
  if (rentingRecord == null) {
    return;
  }
  rentingRecord.isActive = false;
  rentingRecord.save();

  const rid = rentingRecord.transactionHash;
  let record = RentMachineRecord.load(rid);
  if (record == null) {
    return;
  }

  record.gogoing = false;
  record.endRentBlockTimestamp = event.block.timestamp;
  record.endRentTransactionHash = event.transaction.hash;
  record.rentEndTime = event.params.rentEndTime;
  record.save();
}

export function handleRenewRent(event: RenewRentEvent): void {
  let record = new RentRenewal(event.transaction.hash);

  record.machineOwner = event.params.machineOnwer;
  record.machineId = event.params.machineId;
  record.rentId = event.params.rentId;
  record.additionalRentSeconds = event.params.additionalRentSeconds;
  record.additionalRentFee = event.params.additionalRentFee;
  record.renter = event.params.renter;
  record.blockTimestamp = event.block.timestamp;
  record.blockNumber = event.block.number;
  record.transactionHash = event.transaction.hash;
  record.save();
}

export function handleSlashMachineOnOffline(
  event: SlashMachineOnOfflineEvent
): void {
  let record = new MachineSlashedRecord(event.transaction.hash);

  record.machineId = event.params.machineId;
  record.holder = event.params.stakeHolder;
  record.renter = event.params.renter;
  record.slashAmount = event.params.slashAmount;
  record.slashType = BigInt.fromI32(event.params.slashType);
  record.rentStatTime = event.params.rentStartAt;
  record.rentEndTime = event.params.rentEndAt;
  record.blockTimestamp = event.block.timestamp;
  record.blockNumber = event.block.number;
  record.transactionHash = event.transaction.hash;
  record.save();

  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }
  machineInfo.isSlashed = true;
  machineInfo.isRented = false;
  machineInfo.save();
}

// ── 补全事件: RentFee（租赁费用详情） ──
export function handleRentFee(event: RentFeeEvent): void {
  let record = new RentFeeRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.rentId = event.params.rentId;
  record.renter = event.params.renter;
  record.baseRentFee = event.params.baseRentFee;
  record.extraRentFee = event.params.extraRentFee;
  record.platformFee = event.params.platformFee;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── 补全事件: PayBackFee（退还基础费） ──
export function handlePayBackFee(event: PayBackFeeEvent): void {
  let record = new PayBackFeeRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.rentId = event.params.rentId;
  record.renter = event.params.renter;
  record.amount = event.params.amount;
  record.feeType = "base";
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── 补全事件: PayBackExtraFee（退还额外费） ──
export function handlePayBackExtraFee(event: PayBackExtraFeeEvent): void {
  let record = new PayBackFeeRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.rentId = event.params.rentId;
  record.renter = event.params.renter;
  record.amount = event.params.amount;
  record.feeType = "extra";
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── 补全事件: PayBackPointFee（退还积分费） ──
export function handlePayBackPointFee(event: PayBackPointFeeEvent): void {
  let record = new PayBackFeeRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.rentId = event.params.rentId;
  record.renter = event.params.renter;
  record.amount = event.params.amount;
  record.feeType = "point";
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── 补全事件: PaidSlash（Rent 合约罚款已支付） ──
export function handleRentPaidSlash(event: PaidSlashEvent): void {
  let record = new RentPaidSlashRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── 补全事件: MachineRegister（Rent 合约机器注册） ──
export function handleRentMachineRegister(event: MachineRegisterEvent): void {
  let record = new RentMachineRegisterRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.calcPoint = event.params.calcPoint;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── 补全事件: MachineUnregister（Rent 合约机器注销） ──
export function handleRentMachineUnregister(event: MachineUnregisterEvent): void {
  let record = new RentMachineUnregisterRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.calcPoint = event.params.calcPoint;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}
