import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  MachineRegistered,
  MachineRemoved,
  MachineEnabled,
  PriceUpdated,
  RentStarted,
  RentEnded,
  RentEndedBySlash,
  IncomeClaimed,
  SlashExecuted,
} from "../generated/FreeRental/FreeRental"

export function createMachineRegisteredEvent(machineId: string, owner: Address): MachineRegistered {
  let event = changetype<MachineRegistered>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId)))
  event.parameters.push(new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner)))
  return event
}

export function createMachineRemovedEvent(machineId: string, owner: Address): MachineRemoved {
  let event = changetype<MachineRemoved>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId)))
  event.parameters.push(new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner)))
  return event
}

export function createMachineEnabledEvent(machineId: string, enabled: boolean): MachineEnabled {
  let event = changetype<MachineEnabled>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId)))
  event.parameters.push(new ethereum.EventParam("enabled", ethereum.Value.fromBoolean(enabled)))
  return event
}

export function createPriceUpdatedEvent(machineId: string, newPriceUSD: BigInt): PriceUpdated {
  let event = changetype<PriceUpdated>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId)))
  event.parameters.push(new ethereum.EventParam("newPriceUSD", ethereum.Value.fromUnsignedBigInt(newPriceUSD)))
  return event
}

export function createRentStartedEvent(
  rentId: BigInt, machineId: string, renter: Address, rentEndTime: BigInt, totalPoint: BigInt
): RentStarted {
  let event = changetype<RentStarted>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("rentId", ethereum.Value.fromUnsignedBigInt(rentId)))
  event.parameters.push(new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId)))
  event.parameters.push(new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter)))
  event.parameters.push(new ethereum.EventParam("rentEndTime", ethereum.Value.fromUnsignedBigInt(rentEndTime)))
  event.parameters.push(new ethereum.EventParam("totalPoint", ethereum.Value.fromUnsignedBigInt(totalPoint)))
  return event
}

export function createRentEndedEvent(
  rentId: BigInt, machineId: string, renter: Address, ownerPoint: BigInt, platformPoint: BigInt
): RentEnded {
  let event = changetype<RentEnded>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("rentId", ethereum.Value.fromUnsignedBigInt(rentId)))
  event.parameters.push(new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId)))
  event.parameters.push(new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter)))
  event.parameters.push(new ethereum.EventParam("ownerPoint", ethereum.Value.fromUnsignedBigInt(ownerPoint)))
  event.parameters.push(new ethereum.EventParam("platformPoint", ethereum.Value.fromUnsignedBigInt(platformPoint)))
  return event
}

export function createRentEndedBySlashEvent(
  rentId: BigInt, machineId: string, renter: Address, slashAmount: BigInt, refundAmount: BigInt
): RentEndedBySlash {
  let event = changetype<RentEndedBySlash>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("rentId", ethereum.Value.fromUnsignedBigInt(rentId)))
  event.parameters.push(new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId)))
  event.parameters.push(new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter)))
  event.parameters.push(new ethereum.EventParam("slashAmount", ethereum.Value.fromUnsignedBigInt(slashAmount)))
  event.parameters.push(new ethereum.EventParam("refundAmount", ethereum.Value.fromUnsignedBigInt(refundAmount)))
  return event
}

export function createIncomeClaimedEvent(owner: Address, amount: BigInt): IncomeClaimed {
  let event = changetype<IncomeClaimed>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner)))
  event.parameters.push(new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount)))
  return event
}

export function createSlashExecutedEvent(machineId: string, renter: Address, slashAmount: BigInt): SlashExecuted {
  let event = changetype<SlashExecuted>(newMockEvent())
  event.parameters = new Array()
  event.parameters.push(new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId)))
  event.parameters.push(new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter)))
  event.parameters.push(new ethereum.EventParam("slashAmount", ethereum.Value.fromUnsignedBigInt(slashAmount)))
  return event
}
