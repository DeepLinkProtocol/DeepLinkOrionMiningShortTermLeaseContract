import {
  AddBackCalcPointOnOnline as AddBackCalcPointOnOnlineEvent,
  ApprovedReport as ApprovedReportEvent,
  BurnedFee as BurnedFeeEvent,
  EndRentMachine as EndRentMachineEvent,
  ExecuteReport as ExecuteReportEvent,
  Initialized as InitializedEvent,
  MachineRegister as MachineRegisterEvent,
  MachineUnregister as MachineUnregisterEvent,
  OwnershipTransferred as OwnershipTransferredEvent,
  PaidSlash as PaidSlashEvent,
  RefusedReport as RefusedReportEvent,
  RemoveCalcPointOnOffline as RemoveCalcPointOnOfflineEvent,
  RenewRent as RenewRentEvent,
  RentMachine as RentMachineEvent,
  ReportMachineFault as ReportMachineFaultEvent,
  SlashMachineOnOffline as SlashMachineOnOfflineEvent,
  Upgraded as UpgradedEvent,
} from "../generated/Rent/Rent"
import {
  AddBackCalcPointOnOnline,
  ApprovedReport,
  BurnedFee,
  EndRentMachine,
  ExecuteReport,
  Initialized,
  MachineRegister,
  MachineUnregister,
  OwnershipTransferred,
  PaidSlash,
  RefusedReport,
  RemoveCalcPointOnOffline,
  RenewRent,
  RentMachine,
  ReportMachineFault,
  SlashMachineOnOffline,
  Upgraded,
} from "../generated/schema"

export function handleAddBackCalcPointOnOnline(
  event: AddBackCalcPointOnOnlineEvent,
): void {
  let entity = new AddBackCalcPointOnOnline(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId
  entity.calcPoint = event.params.calcPoint

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleApprovedReport(event: ApprovedReportEvent): void {
  let entity = new ApprovedReport(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId
  entity.admin = event.params.admin

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleBurnedFee(event: BurnedFeeEvent): void {
  let entity = new BurnedFee(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId
  entity.rentId = event.params.rentId
  entity.burnTime = event.params.burnTime
  entity.burnDLCAmount = event.params.burnDLCAmount
  entity.renter = event.params.renter
  entity.rentGpuCount = event.params.rentGpuCount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleEndRentMachine(event: EndRentMachineEvent): void {
  let entity = new EndRentMachine(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineOnwer = event.params.machineOnwer
  entity.rentId = event.params.rentId
  entity.machineId = event.params.machineId
  entity.rentEndTime = event.params.rentEndTime
  entity.renter = event.params.renter

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleExecuteReport(event: ExecuteReportEvent): void {
  let entity = new ExecuteReport(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId
  entity.vote = event.params.vote

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleInitialized(event: InitializedEvent): void {
  let entity = new Initialized(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.version = event.params.version

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleMachineRegister(event: MachineRegisterEvent): void {
  let entity = new MachineRegister(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId
  entity.calcPoint = event.params.calcPoint

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleMachineUnregister(event: MachineUnregisterEvent): void {
  let entity = new MachineUnregister(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId
  entity.calcPoint = event.params.calcPoint

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleOwnershipTransferred(
  event: OwnershipTransferredEvent,
): void {
  let entity = new OwnershipTransferred(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.previousOwner = event.params.previousOwner
  entity.newOwner = event.params.newOwner

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handlePaidSlash(event: PaidSlashEvent): void {
  let entity = new PaidSlash(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRefusedReport(event: RefusedReportEvent): void {
  let entity = new RefusedReport(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId
  entity.admin = event.params.admin

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRemoveCalcPointOnOffline(
  event: RemoveCalcPointOnOfflineEvent,
): void {
  let entity = new RemoveCalcPointOnOffline(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineId = event.params.machineId

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRenewRent(event: RenewRentEvent): void {
  let entity = new RenewRent(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineOnwer = event.params.machineOnwer
  entity.machineId = event.params.machineId
  entity.rentId = event.params.rentId
  entity.additionalRentSeconds = event.params.additionalRentSeconds
  entity.additionalRentFee = event.params.additionalRentFee
  entity.renter = event.params.renter

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRentMachine(event: RentMachineEvent): void {
  let entity = new RentMachine(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.machineOnwer = event.params.machineOnwer
  entity.rentId = event.params.rentId
  entity.machineId = event.params.machineId
  entity.rentEndTime = event.params.rentEndTime
  entity.renter = event.params.renter
  entity.rentFee = event.params.rentFee

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleReportMachineFault(event: ReportMachineFaultEvent): void {
  let entity = new ReportMachineFault(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.rentId = event.params.rentId
  entity.machineId = event.params.machineId
  entity.reporter = event.params.reporter

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleSlashMachineOnOffline(
  event: SlashMachineOnOfflineEvent,
): void {
  let entity = new SlashMachineOnOffline(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.stakeHolder = event.params.stakeHolder
  entity.renter = event.params.renter
  entity.machineId = event.params.machineId
  entity.slashAmount = event.params.slashAmount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleUpgraded(event: UpgradedEvent): void {
  let entity = new Upgraded(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.implementation = event.params.implementation

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
