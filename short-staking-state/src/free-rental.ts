import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  MachineRegistered as MachineRegisteredEvent,
  MachineRemoved as MachineRemovedEvent,
  MachineEnabled as MachineEnabledEvent,
  PriceUpdated as PriceUpdatedEvent,
  RentStarted as RentStartedEvent,
  RentEnded as RentEndedEvent,
  RentEndedBySlash as RentEndedBySlashEvent,
  IncomeClaimed as IncomeClaimedEvent,
  SlashExecuted as SlashExecutedEvent,
} from "../generated/FreeRental/FreeRental";
import {
  FreeRentalSummary,
  FreeRentalMachine,
  FreeRentalRecord,
  FreeRentalSlashRecord,
  FreeRentalIncomeClaimedRecord,
} from "../generated/schema";

function getOrCreateSummary(): FreeRentalSummary {
  let summary = FreeRentalSummary.load(Bytes.fromI32(0));
  if (summary == null) {
    summary = new FreeRentalSummary(Bytes.fromI32(0));
    summary.totalMachines = BigInt.zero();
    summary.totalActiveRentals = BigInt.zero();
    summary.totalCompletedRentals = BigInt.zero();
    summary.totalPointPaid = BigInt.zero();
    summary.totalOwnerIncome = BigInt.zero();
    summary.totalPlatformIncome = BigInt.zero();
    summary.totalSlashAmount = BigInt.zero();
  }
  return summary;
}

// ── 机器注册 ──
export function handleFreeRentalMachineRegistered(event: MachineRegisteredEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId);
  let machine = new FreeRentalMachine(id);
  machine.machineId = event.params.machineId;
  machine.owner = event.params.owner;
  machine.registered = true;
  machine.enabled = true;
  machine.isRented = false;
  machine.pricePerHourUSD = BigInt.zero();
  machine.blockNumber = event.block.number;
  machine.blockTimestamp = event.block.timestamp;
  machine.transactionHash = event.transaction.hash;
  machine.save();

  let summary = getOrCreateSummary();
  summary.totalMachines = summary.totalMachines.plus(BigInt.fromI32(1));
  summary.save();
}

// ── 机器移除 ──
export function handleFreeRentalMachineRemoved(event: MachineRemovedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId);
  let machine = FreeRentalMachine.load(id);
  if (machine == null) return;

  machine.registered = false;
  machine.enabled = false;
  machine.save();

  let summary = getOrCreateSummary();
  if (summary.totalMachines.gt(BigInt.zero())) {
    summary.totalMachines = summary.totalMachines.minus(BigInt.fromI32(1));
  }
  summary.save();
}

// ── 机器启用/禁用 ──
export function handleFreeRentalMachineEnabled(event: MachineEnabledEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId);
  let machine = FreeRentalMachine.load(id);
  if (machine == null) return;

  machine.enabled = event.params.enabled;
  machine.save();
}

// ── 价格更新 ──
export function handleFreeRentalPriceUpdated(event: PriceUpdatedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId);
  let machine = FreeRentalMachine.load(id);
  if (machine == null) return;

  machine.pricePerHourUSD = event.params.newPriceUSD;
  machine.save();
}

// ── 租赁开始 ──
export function handleFreeRentalRentStarted(event: RentStartedEvent): void {
  let machineId = Bytes.fromUTF8(event.params.machineId);
  let machine = FreeRentalMachine.load(machineId);
  if (machine != null) {
    machine.isRented = true;
    machine.save();
  }

  let record = new FreeRentalRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.rentId = event.params.rentId;
  record.machine = machineId;
  record.machineId = event.params.machineId;
  record.owner = machine != null ? machine.owner : Bytes.fromI32(0);
  record.renter = event.params.renter;
  record.rentStartTime = event.block.timestamp;
  record.rentEndTime = event.params.rentEndTime;
  record.totalPointPaid = event.params.totalPoint;
  record.ownerPoint = BigInt.zero();
  record.platformPoint = BigInt.zero();
  record.ended = false;
  record.endedBySlash = false;
  record.slashAmount = BigInt.zero();
  record.refundAmount = BigInt.zero();
  record.rentTransactionHash = event.transaction.hash;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.save();

  let summary = getOrCreateSummary();
  summary.totalActiveRentals = summary.totalActiveRentals.plus(BigInt.fromI32(1));
  summary.totalPointPaid = summary.totalPointPaid.plus(event.params.totalPoint);
  summary.save();
}

// ── 租赁正常结束 ──
export function handleFreeRentalRentEnded(event: RentEndedEvent): void {
  let machineId = Bytes.fromUTF8(event.params.machineId);
  let machine = FreeRentalMachine.load(machineId);
  if (machine != null) {
    machine.isRented = false;
    machine.save();
  }

  let summary = getOrCreateSummary();
  if (summary.totalActiveRentals.gt(BigInt.zero())) {
    summary.totalActiveRentals = summary.totalActiveRentals.minus(BigInt.fromI32(1));
  }
  summary.totalCompletedRentals = summary.totalCompletedRentals.plus(BigInt.fromI32(1));
  summary.totalOwnerIncome = summary.totalOwnerIncome.plus(event.params.ownerPoint);
  summary.totalPlatformIncome = summary.totalPlatformIncome.plus(event.params.platformPoint);
  summary.save();
}

// ── 租赁因惩罚结束 ──
export function handleFreeRentalRentEndedBySlash(event: RentEndedBySlashEvent): void {
  let machineId = Bytes.fromUTF8(event.params.machineId);
  let machine = FreeRentalMachine.load(machineId);
  if (machine != null) {
    machine.isRented = false;
    machine.save();
  }

  let summary = getOrCreateSummary();
  if (summary.totalActiveRentals.gt(BigInt.zero())) {
    summary.totalActiveRentals = summary.totalActiveRentals.minus(BigInt.fromI32(1));
  }
  summary.totalCompletedRentals = summary.totalCompletedRentals.plus(BigInt.fromI32(1));
  summary.totalSlashAmount = summary.totalSlashAmount.plus(event.params.slashAmount);
  summary.save();
}

// ── 机主领取收益 ──
export function handleFreeRentalIncomeClaimed(event: IncomeClaimedEvent): void {
  let record = new FreeRentalIncomeClaimedRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.owner = event.params.owner;
  record.amount = event.params.amount;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── 惩罚执行 ──
export function handleFreeRentalSlashExecuted(event: SlashExecutedEvent): void {
  let record = new FreeRentalSlashRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.renter = event.params.renter;
  record.slashAmount = event.params.slashAmount;
  record.refundAmount = BigInt.zero();
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}
