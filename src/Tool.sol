// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "abdk-libraries-solidity/ABDKMathQuad.sol";
import "./OwnerManager.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @custom:oz-upgrades-from OldTool
contract Tool is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 private constant DECIMALS = 1e18;
    uint256 public constant SECONDS_PER_BLOCK = 6;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function LnUint256(uint256 value) public pure returns (uint256) {
        bytes16 v = ABDKMathQuad.ln(ABDKMathQuad.fromUInt(value));
        return getLnValue(v);
    }

    function getLnValue(bytes16 value) public pure returns (uint256) {
        return ABDKMathQuad.toUInt(ABDKMathQuad.mul(value, ABDKMathQuad.fromUInt(DECIMALS)));
    }

    function safeDiv(uint256 a, uint256 b) public pure returns (uint256) {
        require(b > 0, "Division by zero");

        bytes16 scaledA = ABDKMathQuad.fromUInt(a * DECIMALS);

        bytes16 result = ABDKMathQuad.div(scaledA, ABDKMathQuad.fromUInt(b));

        return ABDKMathQuad.toUInt(result);
    }

    function getDecimals() public pure returns (uint256) {
        return DECIMALS;
    }

    function _getRewardDetail(uint256 totalRewardAmount)
        internal
        pure
        returns (uint256 canClaimAmount, uint256 lockedAmount)
    {
        uint256 releaseImmediateAmount = totalRewardAmount / 10;
        uint256 releaseLinearLockedAmount = totalRewardAmount - releaseImmediateAmount;
        return (releaseImmediateAmount, releaseLinearLockedAmount);
    }

    function getRewardStartTime(uint256 rewardStartAtBlockNumber) public view returns (uint256) {
        if (rewardStartAtBlockNumber == 0) {
            return 0;
        }
        if (block.number > rewardStartAtBlockNumber) {
            uint256 timeDuration = (block.number - rewardStartAtBlockNumber) * SECONDS_PER_BLOCK;
            return block.timestamp - timeDuration;
        }

        return block.timestamp + (rewardStartAtBlockNumber - block.number) * SECONDS_PER_BLOCK;
    }

    function getCurrentRewardRate(
        uint256 rewardStartAtBlockNumber,
        uint256 lastUpdateTime,
        uint256 totalAdjustUnit,
        uint256 rewardPerUnit,
        uint256 dailyRewardAmount
    ) internal view returns (uint256) {
        uint256 tempRewardPerUnit = rewardPerUnit;

        uint256 rewardStartTime = getRewardStartTime(rewardStartAtBlockNumber);

        uint256 _lastUpdateTime = rewardStartTime < lastUpdateTime ? lastUpdateTime : rewardStartTime;
        uint256 timeDelta = block.timestamp - _lastUpdateTime;

        if (totalAdjustUnit > 0) {
            uint256 periodReward =
                (getDailyRewardAmount(rewardStartAtBlockNumber, dailyRewardAmount) * timeDelta) / 1 days;
            tempRewardPerUnit += safeDiv(periodReward, totalAdjustUnit);
        }

        return tempRewardPerUnit;
    }

    function getDailyRewardAmount(uint256 rewardStartAtBlockNumber, uint256 dailyRewardAmount)
        public
        pure
        returns (uint256)
    {
        if (rewardStartAtBlockNumber > 0) {
            return dailyRewardAmount;
        }
        return 0;
    }
}
