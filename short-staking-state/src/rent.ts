import {
  RentMachine as RentMachineEvent,
  RenewRent as RenewRentEvent,
  SlashMachineOnOffline as SlashMachineOnOfflineEvent,
  Upgraded as UpgradedEvent,
} from "../generated/Rent/Rent";
import {
  MachineInfo,
  MachineSlashedRecord,
  RentingRecord,
  RentMachineRecord,
  RentRenewal,
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
  machineInfo.save();
}
