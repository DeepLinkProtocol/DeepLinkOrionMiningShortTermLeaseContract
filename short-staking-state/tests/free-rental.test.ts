import {
  assert,
  describe,
  test,
  clearStore,
  beforeEach,
} from "matchstick-as/assembly/index"
import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  handleFreeRentalMachineRegistered,
  handleFreeRentalMachineRemoved,
  handleFreeRentalMachineEnabled,
  handleFreeRentalPriceUpdated,
  handleFreeRentalRentStarted,
  handleFreeRentalRentEnded,
  handleFreeRentalRentEndedBySlash,
  handleFreeRentalIncomeClaimed,
  handleFreeRentalSlashExecuted,
} from "../src/free-rental"
import {
  createMachineRegisteredEvent,
  createMachineRemovedEvent,
  createMachineEnabledEvent,
  createPriceUpdatedEvent,
  createRentStartedEvent,
  createRentEndedEvent,
  createRentEndedBySlashEvent,
  createIncomeClaimedEvent,
  createSlashExecutedEvent,
} from "./free-rental-utils"

const MACHINE_ID = "abc123def456"
const OWNER = Address.fromString("0x0000000000000000000000000000000000000010")
const RENTER = Address.fromString("0x0000000000000000000000000000000000000020")

describe("FreeRental Machine Lifecycle", () => {
  beforeEach(() => {
    clearStore()
  })

  test("Machine registration creates FreeRentalMachine and updates summary", () => {
    let event = createMachineRegisteredEvent(MACHINE_ID, OWNER)
    handleFreeRentalMachineRegistered(event)

    let id = Bytes.fromUTF8(MACHINE_ID).toHexString()
    assert.entityCount("FreeRentalMachine", 1)
    assert.fieldEquals("FreeRentalMachine", id, "machineId", MACHINE_ID)
    assert.fieldEquals("FreeRentalMachine", id, "registered", "true")
    assert.fieldEquals("FreeRentalMachine", id, "enabled", "true")
    assert.fieldEquals("FreeRentalMachine", id, "isRented", "false")

    assert.entityCount("FreeRentalSummary", 1)
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalMachines", "1")
  })

  test("Machine removal updates state and decrements summary", () => {
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent(MACHINE_ID, OWNER))
    handleFreeRentalMachineRemoved(createMachineRemovedEvent(MACHINE_ID, OWNER))

    let id = Bytes.fromUTF8(MACHINE_ID).toHexString()
    assert.fieldEquals("FreeRentalMachine", id, "registered", "false")
    assert.fieldEquals("FreeRentalMachine", id, "enabled", "false")
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalMachines", "0")
  })

  test("Machine enable/disable toggle", () => {
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent(MACHINE_ID, OWNER))

    handleFreeRentalMachineEnabled(createMachineEnabledEvent(MACHINE_ID, false))
    let id = Bytes.fromUTF8(MACHINE_ID).toHexString()
    assert.fieldEquals("FreeRentalMachine", id, "enabled", "false")

    handleFreeRentalMachineEnabled(createMachineEnabledEvent(MACHINE_ID, true))
    assert.fieldEquals("FreeRentalMachine", id, "enabled", "true")
  })

  test("Price update", () => {
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent(MACHINE_ID, OWNER))
    handleFreeRentalPriceUpdated(createPriceUpdatedEvent(MACHINE_ID, BigInt.fromI32(500000)))

    let id = Bytes.fromUTF8(MACHINE_ID).toHexString()
    assert.fieldEquals("FreeRentalMachine", id, "pricePerHourUSD", "500000")
  })
})

describe("FreeRental Rent Flow", () => {
  beforeEach(() => {
    clearStore()
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent(MACHINE_ID, OWNER))
  })

  test("Rent started marks machine as rented and creates record", () => {
    let event = createRentStartedEvent(
      BigInt.fromI32(1), MACHINE_ID, RENTER,
      BigInt.fromI32(1700000000), BigInt.fromI32(1250)
    )
    handleFreeRentalRentStarted(event)

    let machineHex = Bytes.fromUTF8(MACHINE_ID).toHexString()
    assert.fieldEquals("FreeRentalMachine", machineHex, "isRented", "true")
    assert.entityCount("FreeRentalRecord", 1)
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalActiveRentals", "1")
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalPointPaid", "1250")
  })

  test("Rent ended marks machine as not rented and updates summary", () => {
    handleFreeRentalRentStarted(createRentStartedEvent(
      BigInt.fromI32(1), MACHINE_ID, RENTER,
      BigInt.fromI32(1700000000), BigInt.fromI32(1250)
    ))
    handleFreeRentalRentEnded(createRentEndedEvent(
      BigInt.fromI32(1), MACHINE_ID, RENTER,
      BigInt.fromI32(1000), BigInt.fromI32(250)
    ))

    let machineHex = Bytes.fromUTF8(MACHINE_ID).toHexString()
    assert.fieldEquals("FreeRentalMachine", machineHex, "isRented", "false")
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalActiveRentals", "0")
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalCompletedRentals", "1")
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalOwnerIncome", "1000")
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalPlatformIncome", "250")
  })

  test("Rent ended by slash updates slash stats", () => {
    handleFreeRentalRentStarted(createRentStartedEvent(
      BigInt.fromI32(1), MACHINE_ID, RENTER,
      BigInt.fromI32(1700000000), BigInt.fromI32(1250)
    ))
    handleFreeRentalRentEndedBySlash(createRentEndedBySlashEvent(
      BigInt.fromI32(1), MACHINE_ID, RENTER,
      BigInt.fromI32(200), BigInt.fromI32(800)
    ))

    let machineHex = Bytes.fromUTF8(MACHINE_ID).toHexString()
    assert.fieldEquals("FreeRentalMachine", machineHex, "isRented", "false")
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalSlashAmount", "200")
    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalCompletedRentals", "1")
  })
})

describe("FreeRental Income and Slash", () => {
  beforeEach(() => {
    clearStore()
  })

  test("Income claimed creates record", () => {
    handleFreeRentalIncomeClaimed(createIncomeClaimedEvent(OWNER, BigInt.fromI32(5000)))
    assert.entityCount("FreeRentalIncomeClaimedRecord", 1)
  })

  test("Slash executed creates record", () => {
    handleFreeRentalSlashExecuted(createSlashExecutedEvent(MACHINE_ID, RENTER, BigInt.fromI32(300)))
    assert.entityCount("FreeRentalSlashRecord", 1)
  })
})

describe("FreeRental Multiple Machines", () => {
  beforeEach(() => {
    clearStore()
  })

  test("Register multiple machines increments summary correctly", () => {
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent("machine_1", OWNER))
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent("machine_2", OWNER))
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent("machine_3", OWNER))

    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalMachines", "3")
    assert.entityCount("FreeRentalMachine", 3)
  })

  test("Remove one machine decrements correctly", () => {
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent("machine_1", OWNER))
    handleFreeRentalMachineRegistered(createMachineRegisteredEvent("machine_2", OWNER))
    handleFreeRentalMachineRemoved(createMachineRemovedEvent("machine_1", OWNER))

    assert.fieldEquals("FreeRentalSummary", "0x00000000", "totalMachines", "1")
  })
})
