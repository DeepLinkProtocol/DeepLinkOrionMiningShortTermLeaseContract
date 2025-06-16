import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts"
import {
  AddedStakeHours,
  Claimed,
  EndRentMachine,
  Initialized,
  OwnershipTransferred,
  PaySlash,
  RentMachine,
  ReportMachineFault,
  ReserveDLC,
  RewardsPerCalcPointUpdate,
  Staked,
  Unstaked,
  Upgraded
} from "../generated/NFTStaking/NFTStaking"

export function createAddedStakeHoursEvent(
  stakeholder: Address,
  machineId: string,
  stakeHours: BigInt
): AddedStakeHours {
  let addedStakeHoursEvent = changetype<AddedStakeHours>(newMockEvent())

  addedStakeHoursEvent.parameters = new Array()

  addedStakeHoursEvent.parameters.push(
    new ethereum.EventParam(
      "stakeholder",
      ethereum.Value.fromAddress(stakeholder)
    )
  )
  addedStakeHoursEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  addedStakeHoursEvent.parameters.push(
    new ethereum.EventParam(
      "stakeHours",
      ethereum.Value.fromUnsignedBigInt(stakeHours)
    )
  )

  return addedStakeHoursEvent
}

export function createClaimedEvent(
  stakeholder: Address,
  machineId: string,
  totalRewardAmount: BigInt,
  moveToUserWalletAmount: BigInt,
  moveToReservedAmount: BigInt,
  paidSlash: boolean
): Claimed {
  let claimedEvent = changetype<Claimed>(newMockEvent())

  claimedEvent.parameters = new Array()

  claimedEvent.parameters.push(
    new ethereum.EventParam(
      "stakeholder",
      ethereum.Value.fromAddress(stakeholder)
    )
  )
  claimedEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  claimedEvent.parameters.push(
    new ethereum.EventParam(
      "totalRewardAmount",
      ethereum.Value.fromUnsignedBigInt(totalRewardAmount)
    )
  )
  claimedEvent.parameters.push(
    new ethereum.EventParam(
      "moveToUserWalletAmount",
      ethereum.Value.fromUnsignedBigInt(moveToUserWalletAmount)
    )
  )
  claimedEvent.parameters.push(
    new ethereum.EventParam(
      "moveToReservedAmount",
      ethereum.Value.fromUnsignedBigInt(moveToReservedAmount)
    )
  )
  claimedEvent.parameters.push(
    new ethereum.EventParam("paidSlash", ethereum.Value.fromBoolean(paidSlash))
  )

  return claimedEvent
}

export function createEndRentMachineEvent(
  machineOwner: Address,
  machineId: string
): EndRentMachine {
  let endRentMachineEvent = changetype<EndRentMachine>(newMockEvent())

  endRentMachineEvent.parameters = new Array()

  endRentMachineEvent.parameters.push(
    new ethereum.EventParam(
      "machineOwner",
      ethereum.Value.fromAddress(machineOwner)
    )
  )
  endRentMachineEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )

  return endRentMachineEvent
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

export function createPaySlashEvent(
  machineId: string,
  renter: Address,
  slashAmount: BigInt
): PaySlash {
  let paySlashEvent = changetype<PaySlash>(newMockEvent())

  paySlashEvent.parameters = new Array()

  paySlashEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  paySlashEvent.parameters.push(
    new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter))
  )
  paySlashEvent.parameters.push(
    new ethereum.EventParam(
      "slashAmount",
      ethereum.Value.fromUnsignedBigInt(slashAmount)
    )
  )

  return paySlashEvent
}

export function createRentMachineEvent(
  machineOwner: Address,
  machineId: string
): RentMachine {
  let rentMachineEvent = changetype<RentMachine>(newMockEvent())

  rentMachineEvent.parameters = new Array()

  rentMachineEvent.parameters.push(
    new ethereum.EventParam(
      "machineOwner",
      ethereum.Value.fromAddress(machineOwner)
    )
  )
  rentMachineEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )

  return rentMachineEvent
}

export function createReportMachineFaultEvent(
  machineId: string,
  renter: Address
): ReportMachineFault {
  let reportMachineFaultEvent = changetype<ReportMachineFault>(newMockEvent())

  reportMachineFaultEvent.parameters = new Array()

  reportMachineFaultEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  reportMachineFaultEvent.parameters.push(
    new ethereum.EventParam("renter", ethereum.Value.fromAddress(renter))
  )

  return reportMachineFaultEvent
}

export function createReserveDLCEvent(
  machineId: string,
  amount: BigInt
): ReserveDLC {
  let reserveDlcEvent = changetype<ReserveDLC>(newMockEvent())

  reserveDlcEvent.parameters = new Array()

  reserveDlcEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  reserveDlcEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return reserveDlcEvent
}

export function createRewardsPerCalcPointUpdateEvent(
  accumulatedPerShareBefore: BigInt,
  accumulatedPerShareAfter: BigInt
): RewardsPerCalcPointUpdate {
  let rewardsPerCalcPointUpdateEvent =
    changetype<RewardsPerCalcPointUpdate>(newMockEvent())

  rewardsPerCalcPointUpdateEvent.parameters = new Array()

  rewardsPerCalcPointUpdateEvent.parameters.push(
    new ethereum.EventParam(
      "accumulatedPerShareBefore",
      ethereum.Value.fromUnsignedBigInt(accumulatedPerShareBefore)
    )
  )
  rewardsPerCalcPointUpdateEvent.parameters.push(
    new ethereum.EventParam(
      "accumulatedPerShareAfter",
      ethereum.Value.fromUnsignedBigInt(accumulatedPerShareAfter)
    )
  )

  return rewardsPerCalcPointUpdateEvent
}

export function createStakedEvent(
  stakeholder: Address,
  machineId: string,
  calcPoint: BigInt,
  stakeSeconds: BigInt
): Staked {
  let stakedEvent = changetype<Staked>(newMockEvent())

  stakedEvent.parameters = new Array()

  stakedEvent.parameters.push(
    new ethereum.EventParam(
      "stakeholder",
      ethereum.Value.fromAddress(stakeholder)
    )
  )
  stakedEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )
  stakedEvent.parameters.push(
    new ethereum.EventParam(
      "calcPoint",
      ethereum.Value.fromUnsignedBigInt(calcPoint)
    )
  )
  stakedEvent.parameters.push(
    new ethereum.EventParam(
      "stakeSeconds",
      ethereum.Value.fromUnsignedBigInt(stakeSeconds)
    )
  )

  return stakedEvent
}

export function createUnstakedEvent(
  stakeholder: Address,
  machineId: string
): Unstaked {
  let unstakedEvent = changetype<Unstaked>(newMockEvent())

  unstakedEvent.parameters = new Array()

  unstakedEvent.parameters.push(
    new ethereum.EventParam(
      "stakeholder",
      ethereum.Value.fromAddress(stakeholder)
    )
  )
  unstakedEvent.parameters.push(
    new ethereum.EventParam("machineId", ethereum.Value.fromString(machineId))
  )

  return unstakedEvent
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
