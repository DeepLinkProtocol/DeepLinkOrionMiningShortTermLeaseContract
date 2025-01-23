// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library RewardLibrary {
    function _getRewardDetail(uint256 totalRewardAmount)
        external
        pure
        returns (uint256 canClaimAmount, uint256 lockedAmount)
    {
        uint256 releaseImmediateAmount = totalRewardAmount / 10;
        uint256 releaseLinearLockedAmount = totalRewardAmount - releaseImmediateAmount;
        return (releaseImmediateAmount, releaseLinearLockedAmount);
    }

    function getRewardStartTime(uint256 rewardStartAtBlockNumber, uint256 secondsPerBlock)
        external
        view
        returns (uint256)
    {
        if (rewardStartAtBlockNumber == 0) {
            return 0;
        }
        if (block.number > rewardStartAtBlockNumber) {
            uint256 timeDuration = (block.number - rewardStartAtBlockNumber) * secondsPerBlock;
            return block.timestamp - timeDuration;
        }

        return block.timestamp + (rewardStartAtBlockNumber - block.number) * secondsPerBlock;
    }
}
