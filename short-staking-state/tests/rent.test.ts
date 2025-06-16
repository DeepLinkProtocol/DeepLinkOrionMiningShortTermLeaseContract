import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { BigInt, Address } from "@graphprotocol/graph-ts"
import { AddBackCalcPointOnOnline } from "../generated/schema"
import { AddBackCalcPointOnOnline as AddBackCalcPointOnOnlineEvent } from "../generated/Rent/Rent"
import { handleAddBackCalcPointOnOnline } from "../src/rent"
import { createAddBackCalcPointOnOnlineEvent } from "./rent-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let machineId = "Example string value"
    let calcPoint = BigInt.fromI32(234)
    let newAddBackCalcPointOnOnlineEvent = createAddBackCalcPointOnOnlineEvent(
      machineId,
      calcPoint
    )
    handleAddBackCalcPointOnOnline(newAddBackCalcPointOnOnlineEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("AddBackCalcPointOnOnline created and stored", () => {
    assert.entityCount("AddBackCalcPointOnOnline", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "AddBackCalcPointOnOnline",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "machineId",
      "Example string value"
    )
    assert.fieldEquals(
      "AddBackCalcPointOnOnline",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "calcPoint",
      "234"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
