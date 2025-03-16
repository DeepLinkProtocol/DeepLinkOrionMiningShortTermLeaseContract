import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, BigInt } from "@graphprotocol/graph-ts"
import { AddedStakeHours } from "../generated/schema"
import { AddedStakeHours as AddedStakeHoursEvent } from "../generated/NFTStaking/NFTStaking"
import { handleAddedStakeHours } from "../src/nft-staking"
import { createAddedStakeHoursEvent } from "./nft-staking-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let stakeholder = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let machineId = "Example string value"
    let stakeHours = BigInt.fromI32(234)
    let newAddedStakeHoursEvent = createAddedStakeHoursEvent(
      stakeholder,
      machineId,
      stakeHours
    )
    handleAddedStakeHours(newAddedStakeHoursEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("AddedStakeHours created and stored", () => {
    assert.entityCount("AddedStakeHours", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "AddedStakeHours",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "stakeholder",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "AddedStakeHours",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "machineId",
      "Example string value"
    )
    assert.fieldEquals(
      "AddedStakeHours",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "stakeHours",
      "234"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
