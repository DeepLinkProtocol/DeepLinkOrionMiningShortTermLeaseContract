// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
//
//import {OwnerManager} from "./OwnerManager.sol";
////import "./library/Ln.sol";
//import "./interface/ITool.sol";
//
//contract RewardManager is OwnerManager {
//
//    uint8 public constant SECONDS_PER_BLOCK = 6;
//    uint256 public constant BASE_RESERVE_AMOUNT = 1000 * 1e18;
//    uint256 public constant REWARD_DURATION = 60 days;
//
//    uint256 public totalAdjustUnit;
//    uint256 public dailyRewardAmount;
//    uint256 public rewardPerUnit;
//    uint256 public lastUpdateTime;
//
//    uint256 public totalReservedAmount;
//    uint256 public totalCalcPoint;
//
//    struct StakeInfo {
//        address holder;
//        uint256 startAtTimestamp;
//        uint256 lastClaimAtTimestamp;
//        uint256 endAtTimestamp;
//        uint256 calcPoint;
//        uint256 reservedAmount;
//        uint256[] nftTokenIds;
//        uint256 claimedAmount;
//        uint256 pendingRewards;
//        uint256 userRewardDebt;
//        bool isRentedByUser;
//        uint256 gpuCount;
//        uint256 nextRenterCanRentAt;
//    }
//
//    mapping(string => StakeInfo) public machineId2StakeInfos;
//
//    function _getRewardDetail(uint256 totalRewardAmount)
//        internal
//        pure
//        returns (uint256 canClaimAmount, uint256 lockedAmount)
//    {
//        uint256 releaseImmediateAmount = totalRewardAmount / 10;
//        uint256 releaseLinearLockedAmount = totalRewardAmount - releaseImmediateAmount;
//        return (releaseImmediateAmount, releaseLinearLockedAmount);
//    }
//
//    function getReward(string memory machineId) external view returns (uint256) {
//        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
//        uint256 currentRewardPerUnit = getCurrentRewardRate(getRewardEndAtTimestamp(stakeInfo.endAtTimestamp));
//        return calculateRewards(machineId, currentRewardPerUnit);
//    }
//
//    function getDailyRewardAmount() public view returns (uint256) {
//        return dailyRewardAmount;
//    }
//
//    function rewardStart() internal view returns (bool) {
//        return rewardStartAtTimestamp > 0 && block.timestamp >= rewardStartAtTimestamp;
//    }
//
//    function updateRewardPerCalcPoint() internal {
//        if (totalAdjustUnit > 0) {
//            uint256 timeDelta = rewardStart() ? block.timestamp - lastUpdateTime : 0;
//            uint256 periodReward = (dailyRewardAmount * timeDelta) / 1 days;
//            rewardPerUnit += toolContract.safeDiv(periodReward, totalAdjustUnit);
//        }
//        lastUpdateTime = block.timestamp;
//    }
//
//    function _joinStaking(string memory machineId, uint256 calcPoint, uint256 reserveAmount) internal {
//        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
//
//        // update global reward rate
//        updateRewardPerCalcPoint();
//
//        uint256 lnReserveAmount = toolContract.LnUint256(
//            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
//        );
//
//        // update pending rewards of the machine
//        stakeInfo.pendingRewards += ((rewardPerUnit - stakeInfo.userRewardDebt) * stakeInfo.calcPoint * lnReserveAmount)
//            / toolContract.getDecimals();
//
//        stakeInfo.userRewardDebt = rewardPerUnit;
//
//        uint256 oldLnReserved = toolContract.LnUint256(
//            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
//        );
//
//        uint256 newLnReserved =
//            toolContract.LnUint256(reserveAmount > BASE_RESERVE_AMOUNT ? reserveAmount : BASE_RESERVE_AMOUNT);
//
//        totalAdjustUnit -= stakeInfo.calcPoint * oldLnReserved;
//        totalAdjustUnit += calcPoint * newLnReserved;
//        totalCalcPoint = totalCalcPoint - stakeInfo.calcPoint + calcPoint;
//
//        stakeInfo.calcPoint = calcPoint;
//        if (reserveAmount > stakeInfo.reservedAmount) {
//            totalReservedAmount += reserveAmount - stakeInfo.reservedAmount;
//            stakeInfo.reservedAmount = reserveAmount;
//            rewardToken.transferFrom(stakeInfo.holder, address(this), reserveAmount);
//        }
//    }
//
//    function getCurrentRewardRate(uint256 endAtTimestamp) internal view returns (uint256) {
//        uint256 tempRewardPerUnit = rewardPerUnit;
//
//        uint256 rewardStartTime = getRewardStartTime(rewardStartAtTimestamp);
//
//        uint256 _lastUpdateTime = rewardStartTime < lastUpdateTime ? lastUpdateTime : rewardStartTime;
//        uint256 timeDelta = endAtTimestamp - _lastUpdateTime;
//
//        if (totalAdjustUnit > 0) {
//            uint256 periodReward = (dailyRewardAmount * timeDelta) / 1 days;
//            tempRewardPerUnit += toolContract.safeDiv(periodReward, totalAdjustUnit);
//        }
//
//        return tempRewardPerUnit;
//    }
//
//    function calculateRewards(string memory machineId, uint256 currentRewardPerUnit) public view returns (uint256) {
//        if (currentRewardPerUnit == 0) {
//            return 0;
//        }
//        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
//
//        uint256 lnReserveAmount = toolContract.LnUint256(
//            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
//        );
//
//        uint256 accumulatedReward = (
//            (currentRewardPerUnit - stakeInfo.userRewardDebt) * stakeInfo.calcPoint * lnReserveAmount
//        ) / toolContract.getDecimals();
//        uint256 rewardAmount = stakeInfo.pendingRewards + accumulatedReward;
//
//        return rewardAmount;
//    }
//
//    function getRewardEndAtTimestamp(uint256 stakeEndAtTimestamp) internal view returns (uint256) {
//        uint256 rewardEndAt = rewardStartAtTimestamp + REWARD_DURATION;
//        uint256 endAt = block.timestamp < rewardEndAt ? block.timestamp : rewardEndAt;
//        if (stakeEndAtTimestamp > endAt) {
//            if (stakeEndAtTimestamp - endAt <= 1 hours) {
//                return stakeEndAtTimestamp - 1 hours;
//            }
//            return endAt;
//        }
//        return stakeEndAtTimestamp;
//    }
//
//    function getRewardsAndUpdateGlobalRewardRate(string memory machineId) public returns (uint256) {
//        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
//
//        uint256 currentRewardPerUnit = getCurrentRewardRate(getRewardEndAtTimestamp(stakeInfo.endAtTimestamp));
//
//        uint256 rewards = calculateRewards(machineId, currentRewardPerUnit);
//
//        stakeInfo.userRewardDebt = currentRewardPerUnit;
//        stakeInfo.pendingRewards = 0;
//        lastUpdateTime = block.timestamp;
//        rewardPerUnit = currentRewardPerUnit;
//        return rewards;
//    }
//
//    function getRewardStartTime(uint256 rewardStartAtTimestamp) public view returns (uint256) {
//        if (rewardStartAtTimestamp == 0) {
//            return 0;
//        }
//        if (block.timestamp > rewardStartAtTimestamp) {
//            uint256 timeDuration = block.timestamp - rewardStartAtTimestamp;
//            return block.timestamp - timeDuration;
//        }
//
//        return block.timestamp + (rewardStartAtTimestamp - block.timestamp);
//    }
//}
