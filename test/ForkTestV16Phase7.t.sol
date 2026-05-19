// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/NFTStaking.sol";

interface IProxy {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

contract ForkTestV16Phase7 is Test {
    address constant STAKING_PROXY = 0x6268Aba94D0d0e4FB917cC02765f631f309a7388;
    address constant UPGRADE_ADDR = 0x36Ede4Fe3CD9F270747f07c15D8098F10dF6D8e8;

    NFTStaking staking;
    uint256 rewardStartAtTimestamp;
    uint256 phase6End;

    function setUp() public {
        staking = NFTStaking(STAKING_PROXY);
        rewardStartAtTimestamp = staking.rewardStartAtTimestamp();
        phase6End = rewardStartAtTimestamp + 420 days;
        console.log("rewardStartAtTimestamp:", rewardStartAtTimestamp);
        console.log("phase6End (5/21 cliff):", phase6End);
    }

    function _upgradeToV16() internal {
        vm.startPrank(UPGRADE_ADDR);
        NFTStaking newImpl = new NFTStaking();
        IProxy(STAKING_PROXY).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
        assertEq(staking.version(), 16, "version should be 16 post-upgrade");
    }

    function test_v16_preUpgradeVersionIs13() public view {
        uint256 v = staking.version();
        console.log("Pre-upgrade version:", v);
        assertEq(v, 13, "Pre-upgrade should be v13");
    }

    function test_v16_upgradeWorks() public {
        uint256 oldVer = staking.version();
        _upgradeToV16();
        uint256 newVer = staking.version();
        console.log("upgrade", oldVer, "->", newVer);
    }

    function test_v16_dailyReward_atPhase6End_minus1() public {
        _upgradeToV16();
        vm.warp(phase6End - 1);
        uint256 daily = staking.getDailyRewardAmount();
        uint256 ph = staking.getCurrentMiningPhase();
        console.log("Just before phase6End: daily=", daily, "phase=", ph);
        assertGt(daily, 9_000_000 ether, "Should still be phase 6 high rate");
        assertEq(ph, 6, "Should still be phase 6");
    }

    function _expectedDaily(uint256 totalAlloc) internal pure returns (uint256) {
        return (totalAlloc * 1 ether) / 1460;
    }

    function test_v16_dailyReward_atPhase6End_exact() public {
        _upgradeToV16();
        vm.warp(phase6End);
        uint256 daily = staking.getDailyRewardAmount();
        uint256 ph = staking.getCurrentMiningPhase();
        console.log("At phase6End: daily=", daily, "phase=", ph);
        assertEq(daily, _expectedDaily(8_000_000_000), "Should be phase 7 = 8B/1460");
        assertEq(ph, 7, "Should be phase 7");
    }

    function test_v16_dailyReward_at_plus4y() public {
        _upgradeToV16();
        vm.warp(phase6End + 4 * 365 days);
        uint256 daily = staking.getDailyRewardAmount();
        uint256 ph = staking.getCurrentMiningPhase();
        console.log("At +4y: daily=", daily, "phase=", ph);
        assertEq(daily, _expectedDaily(4_000_000_000), "Should be phase 8 = 4B/1460");
        assertEq(ph, 8, "Should be phase 8");
    }

    function test_v16_dailyReward_at_plus24y() public {
        _upgradeToV16();
        vm.warp(phase6End + 24 * 365 days);
        uint256 daily = staking.getDailyRewardAmount();
        uint256 ph = staking.getCurrentMiningPhase();
        console.log("At +24y: daily=", daily, "phase=", ph);
        assertEq(daily, 0, "Should be 0 - mining stopped");
        assertEq(ph, 13, "Should be phase 13 (ended)");
    }

    function test_v16_rewardEndAt_extends_to_2050() public {
        _upgradeToV16();
        (,, uint256 rewardEndAt) = staking.getGlobalState();
        uint256 expected = rewardStartAtTimestamp + 9180 days;
        console.log("rewardEndAt:", rewardEndAt, "expected:", expected);
        assertEq(rewardEndAt, expected, "rewardEndAt should extend to 2050-05-21");
    }

    function test_v16_phase7_to_phase8_boundary() public {
        _upgradeToV16();
        uint256 phase7End = phase6End + 4 * 365 days;

        vm.warp(phase7End - 1);
        assertEq(staking.getCurrentMiningPhase(), 7, "1 sec before phase 8 = still 7");

        vm.warp(phase7End);
        assertEq(staking.getCurrentMiningPhase(), 8, "At phase7End boundary = phase 8");
    }

    function test_v16_allHalvings() public {
        _upgradeToV16();

        uint256[6] memory allocs = [
            uint256(8_000_000_000),
            uint256(4_000_000_000),
            uint256(2_000_000_000),
            uint256(1_000_000_000),
            uint256(500_000_000),
            uint256(250_000_000)
        ];

        for (uint256 i = 0; i < 6; i++) {
            uint256 t = phase6End + i * 4 * 365 days + 1 days;
            vm.warp(t);
            uint256 daily = staking.getDailyRewardAmount();
            uint256 ph = staking.getCurrentMiningPhase();
            console.log("phase", 7 + i, "daily=", daily);
            assertEq(daily, _expectedDaily(allocs[i]), "halving rate mismatch");
            assertEq(ph, 7 + i, "phase mismatch");
        }
    }
}
