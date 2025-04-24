// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

library RewardCalculatorLib {
    uint256 private constant PRECISION_FACTOR = 1 ether;

    struct RewardsPerShare {
        uint256 accumulatedPerShare; // accumulated rewards per share
        uint256 lastUpdated; // accumulated rewards per share last updated time
    }

    struct UserRewards {
        uint256 accumulated; // user accumulated rewards
        uint256 lastAccumulatedPerShare; // last accumulated rewards per share of user
    }

    function getUpdateRewardsPerShare(
        RewardsPerShare memory rewardsPerShareIn,
        uint256 totalShares,
        uint256 rewardsRate,
        uint256 rewardsStart,
        uint256 rewardsEnd
    ) internal view returns (RewardsPerShare memory) {
        RewardsPerShare memory rewardsPerTokenOut =
            RewardsPerShare(rewardsPerShareIn.accumulatedPerShare, rewardsPerShareIn.lastUpdated);

        if (block.timestamp < rewardsStart) return rewardsPerTokenOut;

        uint256 updateTime = block.timestamp < rewardsEnd ? block.timestamp : rewardsEnd;
        uint256 elapsed = updateTime > rewardsPerShareIn.lastUpdated ? updateTime - rewardsPerShareIn.lastUpdated : 0;

        if (elapsed == 0) return rewardsPerTokenOut;
        rewardsPerTokenOut.lastUpdated = updateTime;

        if (totalShares == 0) return rewardsPerTokenOut;

        rewardsPerTokenOut.accumulatedPerShare =
            rewardsPerShareIn.accumulatedPerShare + PRECISION_FACTOR * elapsed * rewardsRate / totalShares;

        return rewardsPerTokenOut;
    }

    function getUpdateUserRewards(
        UserRewards memory userRewardsIn,
        uint256 userShares,
        RewardsPerShare memory rewardsPerToken_
    ) internal pure returns (UserRewards memory) {
        if (userRewardsIn.lastAccumulatedPerShare == rewardsPerToken_.lastUpdated) return userRewardsIn;

        UserRewards memory userRewardsOut = UserRewards(userRewardsIn.accumulated, rewardsPerToken_.accumulatedPerShare);
        userRewardsOut.accumulated = calculatePendingUserRewards(
            userShares, userRewardsIn.lastAccumulatedPerShare, rewardsPerToken_.accumulatedPerShare
        ) + userRewardsIn.accumulated;
        userRewardsOut.lastAccumulatedPerShare = rewardsPerToken_.accumulatedPerShare;

        return userRewardsOut;
    }

    function calculatePendingUserRewards(
        uint256 userShares,
        uint256 earlierAccumulatedPerShare,
        uint256 latterAccumulatedPerShare
    ) internal pure returns (uint256) {
        return userShares * (latterAccumulatedPerShare - earlierAccumulatedPerShare) / PRECISION_FACTOR;
    }
}
