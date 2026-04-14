import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  MachineStateUpdate,
  NotifiedTargetContract,
  reportedStakingStatus,
  ContractRegister,
  ReportFailed,
} from "../generated/AI/AI";
import {
  MachineStateUpdateRecord,
  NotifiedTargetContractRecord,
  ReportedStakingStatusRecord,
  ContractRegisterRecord,
  ReportFailedRecord,
} from "../generated/schema";

// ── MachineStateUpdate（机器状态变更：注册/注销/上线/下线） ──
export function handleMachineStateUpdate(event: MachineStateUpdate): void {
  let record = new MachineStateUpdateRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.machineId = event.params.machineId;
  record.projectName = event.params.projectName;
  record.stakingType = BigInt.fromI32(event.params.stakingType);
  record.notifyType = BigInt.fromI32(event.params.tp);
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── NotifiedTargetContract（通知目标合约结果） ──
export function handleNotifiedTargetContract(event: NotifiedTargetContract): void {
  let record = new NotifiedTargetContractRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.targetContractAddress = event.params.targetContractAddress;
  record.notifyType = BigInt.fromI32(event.params.tp);
  record.machineId = event.params.machineId;
  record.result = event.params.result;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── reportedStakingStatus（上报质押状态到 DBC 合约） ──
export function handleReportedStakingStatus(event: reportedStakingStatus): void {
  let record = new ReportedStakingStatusRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.projectName = event.params.projectName;
  record.stakingType = BigInt.fromI32(event.params.tp);
  record.machineId = event.params.machineId;
  record.gpuNum = event.params.gpuNum;
  record.isStake = event.params.isStake;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── ContractRegister（项目质押合约注册） ──
export function handleContractRegister(event: ContractRegister): void {
  let record = new ContractRegisterRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.caller = event.params.caller;
  record.projectName = event.params.projectName;
  record.toBeNotified = event.params.toBeNotified;
  record.toReportStakingStatus = event.params.toReportStakingStatus;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}

// ── ReportFailed（上报失败记录） ──
export function handleReportFailed(event: ReportFailed): void {
  let record = new ReportFailedRecord(event.transaction.hash.concatI32(event.logIndex.toI32()));
  record.notifyType = BigInt.fromI32(event.params.tp);
  record.projectName = event.params.projectName;
  record.stakingType = BigInt.fromI32(event.params.stakingType);
  record.machineId = event.params.machineId;
  record.reason = event.params.reason;
  record.blockNumber = event.block.number;
  record.blockTimestamp = event.block.timestamp;
  record.transactionHash = event.transaction.hash;
  record.save();
}
