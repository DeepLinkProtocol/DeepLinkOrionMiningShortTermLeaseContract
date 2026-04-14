import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { BigInt, Address } from "@graphprotocol/graph-ts"
import { RentFeeRecord } from "../generated/schema"

describe("Rent contract tests", () => {
  afterAll(() => {
    clearStore()
  })

  test("RentFeeRecord entity can be loaded", () => {
    assert.entityCount("RentFeeRecord", 0)
  })

  test("PayBackFeeRecord entity can be loaded", () => {
    assert.entityCount("PayBackFeeRecord", 0)
  })

  test("RentPaidSlashRecord entity can be loaded", () => {
    assert.entityCount("RentPaidSlashRecord", 0)
  })
})
