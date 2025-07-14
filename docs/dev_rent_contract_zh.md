Rent 合约接口文档
================

## 测试网合约地址
0xaa5b045b8b8d19e78c0244301046d57c122388ca
## 概述
Rent 合约是一个基于 Solidity 的智能合约，用于管理租赁机器的逻辑。它提供了租赁机器、续租、结束租赁、报告机器故障等功能。

## 函数接口
### `getMachinePrice(string memory machineId, uint256 rentSeconds) public view returns (uint256)`
- 描述: 获取租赁一台机器的价格
- 参数:
    - `machineId`: 机器 ID
    - `rentSeconds`: 租赁时长（秒）
- 返回信息: uint256 租赁价格

### `rentMachine(string calldata machineId, uint256 rentSeconds, uint256 rentFee)`
- 描述: 租赁一台机器
- 参数:
    - `machineId`: 机器 ID
    - `rentSeconds`: 租赁时长（秒）
    - `rentFee`: 租赁费用
-事件:
  - `RentMachine`: 租赁机器事件
  
### `renewRent(string memory machineId, uint256 additionalRentSeconds, uint256 additionalRentFee)`
- 描述: 续租一台机器
- 参数:
    - `machineId`: 机器 ID
    - `additionalRentSeconds`: 续租时长（秒）
    - `additionalRentFee`: 续租费用
- 事件:
   - `RenewRent`: 续租机器事件
   - 
### `endRentMachine(string calldata machineId)`
- 描述: 结束租赁一台机器
- 参数:
    - `machineId`: 机器 ID
- 事件:
   - `EndRentMachine`: 结束租赁机器事件
   - 
### `reportMachineFault(string calldata machineId, uint256 reserveAmount)`
- 描述: 报告一台机器故障 只能被租用人调用
- 参数:
    - `machineId`: 机器 ID
    - `reserveAmount`: 质押金额
- 事件:
    - `ReportMachineFault`: 报告机器故障事件
### `approveMachineFaultReporting(string calldata machineId)`
- 描述: 审批一台机器故障报告 只能被管理员调用
- 参数: 
    - `machineId`: 机器 ID
- 事件:
    - `ApprovedReport`: 审批机器故障报告事件
### `rejectMachineFaultReporting(string calldata machineId)`
- 描述: 拒绝一台机器故障报告 只能被管理员调用

- 参数:
    - `machineId`: 机器 ID
- 事件:
    - `RefusedReport`: 拒绝机器故障报告事件
### `notify(NotifyType tp, string calldata machineId)`
- 描述: 通知机器状态变化 只能被dbc ai合约调用
- 参数:
    - `tp`: 通知类型
    - `machineId`: 机器 ID
- 事件:
    - `MachineRegister`: 机器注册事件
    - `MachineUnregister`: 机器注销事件

### `isRented(string memory machineId) public view returns (bool)`
- 描述: 检查机器是否被租赁
- 参数:
    - `machineId`: 机器 ID
- 返回信息: bool

### `canRent(string calldata machineId) public view returns (bool)`
- 描述: 检查机器是否可以被租赁
- 参数:
    - `machineId`: 机器 ID
- 返回信息: bool 是否可以被租赁

### `getRenter(string calldata machineId) public view returns (address)`
- 描述: 获取机器的租赁者
- 参数:
    - `machineId`: 机器 ID
- 返回信息: address 租用人地址

### `function isInSlashing(string memory machineId) public view returns(bool)`
- 描述: 获取机器是否处于惩罚状态
- 参数:
  - `machineId`: 机器 ID
- 返回信息: bool 是否处于触发状态


### `getSlashInfosByMachineId(string memory machineId, uint256 pageNumber, uint256 pageSize) public view returns (SlashInfo[] memory, uint256)`
- 描述: 获取 stake holder 的 slash 信息
- 参数:
    - `stakeHolder`: stake holder 地址
    - `pageNumber`: 页码
    - `pageSize`: 页大小
- 返回信息: (SlashInfo[] memory, uint256)
```solidity

   enum SlashType {
     Offline,
     RenterReport
   }

    struct SlashInfo {
        address stakeHolder;   // 机器所有者
        string machineId;  // 被 slash 的机器 ID
        uint256 slashAmount;  // slash 金额
        uint256 rentStartAtTimestamp;  // 租赁开始时间戳
        uint256 rentEndAtTimestamp;  // 租赁结束时间戳
        uint256 rentedDurationSeconds;  // 租赁时长（秒）
        address renter;  // 租赁者
        SlashType slashType;  // slash 类型 0: 离线， slash 1: 租用人报告
        uint256 createdAt;  // slash 创建时间戳
        bool paid;  // slash 是否已缴纳
    }
```

### `rentProxyMachine(address renter, string calldata machineId, uint256 rentSeconds, uint256 rentFee)`
- 描述: 租赁一台机器
- 参数:
- `renter`: 租用人地址
- `machineId`: 机器 ID
- `rentSeconds`: 租赁时长（秒）
- `rentFee`: 租赁费用
-事件:
- `RentMachine`: 租赁机器事件


