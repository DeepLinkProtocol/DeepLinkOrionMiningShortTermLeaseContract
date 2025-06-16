import { newMockEvent } from "matchstick-as"
import { ethereum, BigInt, Address } from "@graphprotocol/graph-ts"
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
  Upgraded
} from "../generated/Rent/Rent"

export function createAddBackCalcPointOnOnlineEvent(
  machineId: string,
  calcPoint: BigInt
): AddBackCalcPointOnOnline {
  let addBackCalcPointOnOnlineEvent =
    changetype<AddBackCalcPointOnOnline>(newMockEvent())

  addBackCalcPointOnOnlineEvent.parameters = new Array()

  addBackCalcPointOnOnlineEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  addBackCalcPointOnOnlineEvent.parameters.push(
    new ethereum.EventParam(
      "calcPoint",
      ethereum.Value.fromUnsignedBigInt(calcPoint)
    )
  )

  return addBackCalcPointOnOnlineEvent
}

export function createApprovedReportEvent(
  machineId: string,
  admin: Address
): ApprovedReport {
  let approvedReportEvent = changetype<ApprovedReport>(newMockEvent())

  approvedReportEvent.parameters = new Array()

  approvedReportEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  approvedReportEvent.parameters.push(
    new ethereum.EventParam("admin", ethereum.Value.fromAddress(admin))
  )

  return approvedReportEvent
}

export function createBurnedFeeEvent(
  machineId: string,
  rentId: BigInt,
  burnTime: BigInt,
  burnDLCAmount: BigInt,
  renter: Address,
  rentGpuCount: i32
): BurnedFee {
  let burnedFeeEvent = changetype<BurnedFee>(newMockEvent())

  burnedFeeEvent.parameters = new Array()

  burnedFeeEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  burnedFeeEvent.parameters.push(
    new ethereum.EventParam("rentId", ethereum.Value.fromUnsignedBigInt(rentId))
  )
  burnedFeeEvent.parameters.push(
    new ethereum.EventParam(
      "burnTime",
      ethereum.Value.fromUnsignedBigInt(burnTime)
    )
  )
  burnedFeeEvent.parameters.push(
    new ethereum.EventParam(
      "burnDLCAmount",
      ethereum.Value.fromUnsignedBigInt(burnDLCAmount)
    )
  )
  burnedFeeEvent.parameters.push(
    new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter))
  )
  burnedFeeEvent.parameters.push(
    new ethereum.EventParam(
      "rentGpuCount",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(rentGpuCount))
    )
  )

  return burnedFeeEvent
}

export function createEndRentMachineEvent(
  machineOnwer: Address,
  rentId: BigInt,
  machineId: string,
  rentEndTime: BigInt,
  renter: Address
): EndRentMachine {
  let endRentMachineEvent = changetype<EndRentMachine>(newMockEvent())

  endRentMachineEvent.parameters = new Array()

  endRentMachineEvent.parameters.push(
    new ethereum.EventParam(
      "machineOnwer",
      ethereum.Value.fromAddress(machineOnwer)
    )
  )
  endRentMachineEvent.parameters.push(
    new ethereum.EventParam("rentId", ethereum.Value.fromUnsignedBigInt(rentId))
  )
  endRentMachineEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  endRentMachineEvent.parameters.push(
    new ethereum.EventParam(
      "rentEndTime",
      ethereum.Value.fromUnsignedBigInt(rentEndTime)
    )
  )
  endRentMachineEvent.parameters.push(
    new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter))
  )

  return endRentMachineEvent
}

export function createExecuteReportEvent(
  machineId: string,
  vote: i32
): ExecuteReport {
  let executeReportEvent = changetype<ExecuteReport>(newMockEvent())

  executeReportEvent.parameters = new Array()

  executeReportEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  executeReportEvent.parameters.push(
    new ethereum.EventParam(
      "vote",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(vote))
    )
  )

  return executeReportEvent
}

export function createInitializedEvent(version: BigInt): Initialized {
  let initializedEvent = changetype<Initialized>(newMockEvent())

  initializedEvent.parameters = new Array()

  initializedEvent.parameters.push(
    new ethereum.EventParam(
      "version",
      ethereum.Value.fromUnsignedBigInt(version)
    )
  )

  return initializedEvent
}

export function createMachineRegisterEvent(
  machineId: string,
  calcPoint: BigInt
): MachineRegister {
  let machineRegisterEvent = changetype<MachineRegister>(newMockEvent())

  machineRegisterEvent.parameters = new Array()

  machineRegisterEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  machineRegisterEvent.parameters.push(
    new ethereum.EventParam(
      "calcPoint",
      ethereum.Value.fromUnsignedBigInt(calcPoint)
    )
  )

  return machineRegisterEvent
}

export function createMachineUnregisterEvent(
  machineId: string,
  calcPoint: BigInt
): MachineUnregister {
  let machineUnregisterEvent = changetype<MachineUnregister>(newMockEvent())

  machineUnregisterEvent.parameters = new Array()

  machineUnregisterEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  machineUnregisterEvent.parameters.push(
    new ethereum.EventParam(
      "calcPoint",
      ethereum.Value.fromUnsignedBigInt(calcPoint)
    )
  )

  return machineUnregisterEvent
}

export function createOwnershipTransferredEvent(
  previousOwner: Address,
  newOwner: Address
): OwnershipTransferred {
  let ownershipTransferredEvent =
    changetype<OwnershipTransferred>(newMockEvent())

  ownershipTransferredEvent.parameters = new Array()

  ownershipTransferredEvent.parameters.push(
    new ethereum.EventParam(
      "previousOwner",
      ethereum.Value.fromAddress(previousOwner)
    )
  )
  ownershipTransferredEvent.parameters.push(
    new ethereum.EventParam("newOwner", ethereum.Value.fromAddress(newOwner))
  )

  return ownershipTransferredEvent
}

export function createPaidSlashEvent(machineId: string): PaidSlash {
  let paidSlashEvent = changetype<PaidSlash>(newMockEvent())

  paidSlashEvent.parameters = new Array()

  paidSlashEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )

  return paidSlashEvent
}

export function createRefusedReportEvent(
  machineId: string,
  admin: Address
): RefusedReport {
  let refusedReportEvent = changetype<RefusedReport>(newMockEvent())

  refusedReportEvent.parameters = new Array()

  refusedReportEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  refusedReportEvent.parameters.push(
    new ethereum.EventParam("admin", ethereum.Value.fromAddress(admin))
  )

  return refusedReportEvent
}

export function createRemoveCalcPointOnOfflineEvent(
  machineId: string
): RemoveCalcPointOnOffline {
  let removeCalcPointOnOfflineEvent =
    changetype<RemoveCalcPointOnOffline>(newMockEvent())

  removeCalcPointOnOfflineEvent.parameters = new Array()

  removeCalcPointOnOfflineEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )

  return removeCalcPointOnOfflineEvent
}

export function createRenewRentEvent(
  machineOnwer: Address,
  machineId: string,
  rentId: BigInt,
  additionalRentSeconds: BigInt,
  additionalRentFee: BigInt,
  renter: Address
): RenewRent {
  let renewRentEvent = changetype<RenewRent>(newMockEvent())

  renewRentEvent.parameters = new Array()

  renewRentEvent.parameters.push(
    new ethereum.EventParam(
      "machineOnwer",
      ethereum.Value.fromAddress(machineOnwer)
    )
  )
  renewRentEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  renewRentEvent.parameters.push(
    new ethereum.EventParam("rentId", ethereum.Value.fromUnsignedBigInt(rentId))
  )
  renewRentEvent.parameters.push(
    new ethereum.EventParam(
      "additionalRentSeconds",
      ethereum.Value.fromUnsignedBigInt(additionalRentSeconds)
    )
  )
  renewRentEvent.parameters.push(
    new ethereum.EventParam(
      "additionalRentFee",
      ethereum.Value.fromUnsignedBigInt(additionalRentFee)
    )
  )
  renewRentEvent.parameters.push(
    new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter))
  )

  return renewRentEvent
}

export function createRentMachineEvent(
  machineOnwer: Address,
  rentId: BigInt,
  machineId: string,
  rentEndTime: BigInt,
  renter: Address,
  rentFee: BigInt
): RentMachine {
  let rentMachineEvent = changetype<RentMachine>(newMockEvent())

  rentMachineEvent.parameters = new Array()

  rentMachineEvent.parameters.push(
    new ethereum.EventParam(
      "machineOnwer",
      ethereum.Value.fromAddress(machineOnwer)
    )
  )
  rentMachineEvent.parameters.push(
    new ethereum.EventParam("rentId", ethereum.Value.fromUnsignedBigInt(rentId))
  )
  rentMachineEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  rentMachineEvent.parameters.push(
    new ethereum.EventParam(
      "rentEndTime",
      ethereum.Value.fromUnsignedBigInt(rentEndTime)
    )
  )
  rentMachineEvent.parameters.push(
    new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter))
  )
  rentMachineEvent.parameters.push(
    new ethereum.EventParam(
      "rentFee",
      ethereum.Value.fromUnsignedBigInt(rentFee)
    )
  )

  return rentMachineEvent
}

export function createReportMachineFaultEvent(
  rentId: BigInt,
  machineId: string,
  reporter: Address
): ReportMachineFault {
  let reportMachineFaultEvent = changetype<ReportMachineFault>(newMockEvent())

  reportMachineFaultEvent.parameters = new Array()

  reportMachineFaultEvent.parameters.push(
    new ethereum.EventParam("rentId", ethereum.Value.fromUnsignedBigInt(rentId))
  )
  reportMachineFaultEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  reportMachineFaultEvent.parameters.push(
    new ethereum.EventParam("reporter", ethereum.Value.fromAddress(reporter))
  )

  return reportMachineFaultEvent
}

export function createSlashMachineOnOfflineEvent(
  stakeHolder: Address,
  renter: Address,
  machineId: string,
  slashAmount: BigInt
): SlashMachineOnOffline {
  let slashMachineOnOfflineEvent =
    changetype<SlashMachineOnOffline>(newMockEvent())

  slashMachineOnOfflineEvent.parameters = new Array()

  slashMachineOnOfflineEvent.parameters.push(
    new ethereum.EventParam(
      "stakeHolder",
      ethereum.Value.fromAddress(stakeHolder)
    )
  )
  slashMachineOnOfflineEvent.parameters.push(
    new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter))
  )
  slashMachineOnOfflineEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  slashMachineOnOfflineEvent.parameters.push(
    new ethereum.EventParam(
      "slashAmount",
      ethereum.Value.fromUnsignedBigInt(slashAmount)
    )
  )

  return slashMachineOnOfflineEvent
}

export function createUpgradedEvent(implementation: Address): Upgraded {
  let upgradedEvent = changetype<Upgraded>(newMockEvent())

  upgradedEvent.parameters = new Array()

  upgradedEvent.parameters.push(
    new ethereum.EventParam(
      "implementation",
      ethereum.Value.fromAddress(implementation)
    )
  )

  return upgradedEvent
}
