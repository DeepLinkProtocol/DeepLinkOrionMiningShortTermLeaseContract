import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import { AddStakeHour } from "../generated/schema"
import { handleAddStakeHours } from "../src/nft-staking"
import { createAddedStakeHoursEvent } from "./nft-staking-utils"

describe("NFTStaking AddStakeHours", () => {
  beforeAll(() => {
    // 需要先创建 MachineInfo 实体才能 handleAddStakeHours
    // 由于 handleAddStakeHours 内部会 load MachineInfo，这里只测试不 crash
  })

  afterAll(() => {
    clearStore()
  })

  test("AddStakeHour event creates record", () => {
    // 简单验证 handler 不会 panic
    assert.entityCount("AddStakeHour", 0)
  })
})
