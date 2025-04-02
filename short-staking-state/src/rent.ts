import {

  SlashMachineOnOffline as SlashMachineOnOfflineEvent,
  Upgraded as UpgradedEvent,
} from "../generated/Rent/Rent"
import {
  HolderPaidSlashRecord,
  LatestPaidSlashRecord,
  MachineSlashedRecord
} from "../generated/schema"
import {BigInt, Bytes} from "@graphprotocol/graph-ts";
export function handleSlashMachineOnOffline(event: SlashMachineOnOfflineEvent): void {
  let record = new MachineSlashedRecord(event.transaction.hash)

  record.machineId = event.params.machineId
  record.holder = event.params.stakeHolder
  record.renter = event.params.renter
  record.slashAmount = event.params.slashAmount
  record.slashType = BigInt.fromI32(event.params.slashType)
  record.rentStatTime = event.params.rentStartAt
  record.rentEndTime = event.params.rentEndAt
  record.blockTimestamp = event.block.timestamp
  record.blockNumber = event.block.number
  record.transactionHash = event.transaction.hash
  record.save()

  let latestRecord = LatestPaidSlashRecord.load(Bytes.fromHexString(record.holder.toHexString()))
  if (latestRecord == null){
    latestRecord = new LatestPaidSlashRecord(Bytes.fromHexString(record.holder.toHexString()))
    latestRecord.holder = event.params.stakeHolder
    latestRecord.paid = false
    latestRecord.blockNumber = event.block.number
    latestRecord.blockTimestamp = event.block.timestamp
    latestRecord.transactionHash = event.transaction.hash
  }else{
    latestRecord.paid = false
    latestRecord.blockNumber = event.block.number
    latestRecord.blockTimestamp = event.block.timestamp
    latestRecord.transactionHash = event.transaction.hash
  }

  latestRecord.save()
}