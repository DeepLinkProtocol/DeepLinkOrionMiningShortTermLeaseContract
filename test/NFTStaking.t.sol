// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {ToolLib} from "../src/library/ToolLib.sol";
import {IRewardToken} from "../src/interface/IRewardToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

contract RentTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    IPrecompileContract public precompileContract;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;

    //    ToolLib public tool;
    address owner = address(0x01);
    address admin2 = address(0x02);
    address admin3 = address(0x03);
    address admin4 = address(0x04);
    address admin5 = address(0x05);

    address stakeHolder2 = address(0x06);

    function setUp() public {
        vm.startPrank(owner);
        precompileContract = IPrecompileContract(address(0x11));
        rewardToken = new Token();
        nftToken = new DLCNode(owner);

        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(proxy1));

        ERC1967Proxy proxy = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(proxy));

        NFTStaking(address(proxy1)).initialize(
            owner, address(nftToken), address(rewardToken), address(rent), address(dbcAIContract), 1
        );
        Rent(address(proxy)).initialize(
            owner, address(precompileContract), address(nftStaking), address(dbcAIContract), address(rewardToken)
        );
        deal(address(rewardToken), address(this), 100000000000 * 1e18);
        deal(address(rewardToken), owner, 180000000 * 1e18);
        rewardToken.approve(address(nftStaking), 180000000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 180000000 * 1e18);

        nftStaking.setRewardStartAt(block.timestamp);
        passHours(1);
        address[] memory addrs = new address[](1);
        addrs[0] = owner;
        nftStaking.setDLCClientWallets(addrs);
        vm.mockCall(
            address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.reportStakingStatus.selector), abi.encode()
        );
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.stopPrank();
    }

    function test_daily_reward() public view {
        assertEq(nftStaking.getDailyRewardAmount(), 3000000 * 1e18);
    }

    function stakeByOwner(string memory machineId, uint256 reserveAmount, uint256 stakeHours, address _owner) public {
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(_owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, machineId, 16)
        );

        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );

        vm.startPrank(_owner);
        dealERC1155(address(nftToken), _owner, 1, 1, false);
        assertEq(nftToken.balanceOf(_owner, 1), 1, "owner erc1155 failed");
        deal(address(rewardToken), _owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);
        vm.stopPrank();

        vm.startPrank(owner);
        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        uint256 totalCalcPointBefore = nftStaking.totalCalcPoint();
        nftStaking.stake(_owner, machineId, nftTokens, nftTokensBalance, stakeHours);
        assertEq(nftToken.balanceOf(_owner, 1), 0, "owner erc1155 failed");
        nftStaking.addDLCToStake(machineId, reserveAmount);
        vm.stopPrank();
        uint256 totalCalcPoint = nftStaking.totalCalcPoint();

        assertEq(totalCalcPoint, totalCalcPointBefore + 100);
        (uint256 accumulatedPerShare,) = nftStaking.rewardsPerCalcPoint();
        (uint256 accumulated, uint256 lastAccumulatedPerShare) = nftStaking.machineId2StakeUnitRewards(machineId);
        assertEq(accumulatedPerShare, lastAccumulatedPerShare);
        assertEq(accumulated, 0);
    }

    function testStake() public {
        address stakeHolder = owner;
        //        assertEq(nftToken.balanceOf(stakeHolder, 1), 100);
        //        address nftAddr = address(nftToken);
        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";

        //        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.transferFrom.selector), abi.encode(true));
        //        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.startPrank(stakeHolder);
        stakeByOwner(machineId, 0, 72, stakeHolder);
        vm.stopPrank();

        //        (NFTStaking.StakeHolder[] memory topHolders,) = nftStaking.getTopStakeHolders(0, 10);
        //        assertEq(topHolders[0].holder, stakeHolder, "topHolders[0].holder, stakeHolder");
        //        assertEq(topHolders[0].totalCalcPoint, 100, "top1 holder calc point 100 failed");
        //        assertTrue(nftStaking.isStaking(machineId));

        passDays(1);

        vm.startPrank(stakeHolder);
        assertLt(
            nftStaking.getReward(machineId),
            nftStaking.getDailyRewardAmount(),
            "get reward lt failed after reward start 1 day 1"
        );
        assertGt(
            nftStaking.getReward(machineId),
            nftStaking.getDailyRewardAmount() - 1 * 1e18,
            "get reward gt failed after reward start 1 day 2"
        );
        vm.stopPrank();

        // staking.stake(machineId2, 0, tokenIds0, 2);

        vm.prank(stakeHolder2);
        stakeByOwner(machineId2, 0, 72, stakeHolder2);
        passDays(1);

        uint256 reward2 = nftStaking.getReward(machineId2);
        assertGt(reward2, 0, "machineId2 get reward lt 0  failed after staked 1 day");

        assertLt(
            reward2,
            nftStaking.getDailyRewardAmount() / 2,
            "machineId2 get reward lt staking.getDailyRewardAmount()/2 failed after staked 1 day"
        );

        assertGt(
            nftStaking.getReward(machineId2),
            nftStaking.getDailyRewardAmount() / 2 - 1 * 1e18,
            "machineId2 get reward gt staking.getDailyRewardAmount()/2 - 1 * 1e18 failed after staked 1 day"
        );

        (, uint256 rewardAmountCanClaim, uint256 lockedRewardAmount,) = nftStaking.getRewardInfo(machineId2);
        assertEq(rewardAmountCanClaim, reward2 / 10);
        assertEq(lockedRewardAmount, reward2 - reward2 / 10);

        passDays(1);
        uint256 reward4 = nftStaking.getReward(machineId2);

        (, uint256 rewardAmountCanClaim0, uint256 lockedRewardAmount0,) = nftStaking.getRewardInfo(machineId2);
        assertEq(rewardAmountCanClaim0, reward4 / 10);
        assertEq(lockedRewardAmount0, reward4 - reward4 / 10);

        vm.prank(stakeHolder2);
        nftStaking.claim(machineId2);

        reward4 = nftStaking.getReward(machineId2);
        assertEq(reward4, 0, "machineId2 get reward  failed after claim");

        passDays(1);
        (uint256 release, uint256 locked) = nftStaking.calculateReleaseReward(machineId2);
        assertEq(release, ((locked + release) * 3 days / nftStaking.LOCK_PERIOD()), "111");
        vm.stopPrank();
        uint256[] memory tokenIds3 = new uint256[](1);
        tokenIds3[0] = 10;
        vm.startPrank(stakeHolder);
        vm.stopPrank();
    }

    function testUnStake() public {
        address stakeHolder = owner;
        string memory machineId = "machineId";
        stakeByOwner(machineId, 100000, 48, stakeHolder);

        passHours(48);
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, false)
        );

        vm.startPrank(stakeHolder);
        nftStaking.unStake(machineId);
        vm.stopPrank();
        assertEq(nftToken.balanceOf(stakeHolder, 1), 1, "owner erc1155 failed");

        nftStaking.getRewardInfo(machineId);
        uint256 balance1 = rewardToken.balanceOf(stakeHolder);

        passHours(24);
        vm.startPrank(stakeHolder);
        nftStaking.claim(machineId);
        vm.stopPrank();
        uint256 balance2 = rewardToken.balanceOf(stakeHolder);

        assertGt(balance2, balance1, "claim failed");
    }

    function testUnStakeByHolderAndReStake() public {
        // Test if a miner can claim rewards from previous staking period after unstaking early and staking again
        address stakeHolder = owner;
        string memory machineId = "machineId";

        // First staking period
        stakeByOwner(machineId, 100000, 72, stakeHolder);

        // Pass some time to accumulate rewards but not the full staking period
        passHours(24);

        // Check rewards accumulated
        uint256 rewardBefore = nftStaking.getReward(machineId);
        assertGt(rewardBefore, 0, "Should have accumulated some rewards");

        // Mock machine is not registered to allow unstaking
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, false)
        );

        // Unstake early using unStakeByHolder
        vm.startPrank(stakeHolder);
        nftStaking.unStakeByHolder(machineId);
        vm.stopPrank();

        // Verify NFT returned to holder
        assertEq(nftToken.balanceOf(stakeHolder, 1), 1, "NFT should be returned to owner");

        // Pass some time
        passHours(12);

        // Re-stake the same machine
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );

        stakeByOwner(machineId, 100000, 72, stakeHolder);

        // Pass more time
        passHours(24);

        // Check if rewards can be claimed
        uint256 balanceBefore = rewardToken.balanceOf(stakeHolder);

        vm.startPrank(stakeHolder);
        nftStaking.claim(machineId);
        vm.stopPrank();

        uint256 balanceAfter = rewardToken.balanceOf(stakeHolder);

        // Verify rewards were claimed
        assertGt(balanceAfter, balanceBefore, "Should be able to claim rewards after re-staking");

        // Verify that rewards from the new staking period are separate from previous period
        (,,, uint256 claimedAmount) = nftStaking.getRewardInfo(machineId);
        assertGt(claimedAmount, 0, "Should have claimed some rewards");
    }

    function testTool() public pure {
        string memory gpuType1 = "NVIDIA GeForce RTX 4060 Ti";
        assertEq(ToolLib.checkString(gpuType1), true, "checkString failed1");

        string memory gpuType2 = "Gen Intel(R) Core(TM) i7-13790F";
        assertEq(ToolLib.checkString(gpuType2), false, "checkString failed2");

        string memory gpuType3 = "NVIDIA GeForce RTX 20 Ti";
        assertEq(ToolLib.checkString(gpuType3), true, "checkString failed3");
    }

    function claimAfter(string memory machineId, address _owner, uint256 hour, bool shouldGetMore) internal {
        uint256 balance1 = rewardToken.balanceOf(_owner);
        passHours(hour);
        vm.prank(_owner);
        nftStaking.claim(machineId);
        uint256 balance2 = rewardToken.balanceOf(_owner);
        if (shouldGetMore) {
            assertGt(balance2, balance1);
        } else {
            assertEq(balance2, balance1);
        }
    }

    function passHours(uint256 n) public {
        uint256 secondsToAdvance = n * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / 6;

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passDays(uint256 n) public {
        uint256 secondsToAdvance = n * 24 * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / nftStaking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passBlocks(uint256 n) public {
        uint256 timeToAdvance = n * nftStaking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + timeToAdvance - 1);
        vm.roll(vm.getBlockNumber() + n - 1);
    }

    // function testClaimTwiceInSuccession() public {
    //     // Create a stake
    //     address stakeHolder = owner;
    //     string memory machineId = "machineIdForDoubleClaim";
    //     stakeByOwner(machineId, 0, 48, stakeHolder);

    //     // Wait for a day to accumulate rewards
    //     passDays(1);

    //     // Get reward information before the first claim
    //     uint256 rewardBeforeFirstClaim = nftStaking.getReward(machineId);
    //     (, uint256 rewardAmountCanClaimBeforeFirst, uint256 lockedRewardAmountBeforeFirst,) =
    //         nftStaking.getRewardInfo(machineId);

    //     // Confirm there are claimable rewards
    //     assertGt(rewardBeforeFirstClaim, 0, "should have reward");
    //     assertGt(rewardAmountCanClaimBeforeFirst, 0, "should have reward");
    //     assertGt(lockedRewardAmountBeforeFirst, 0, "should have reward");

    //     // Record balance before the first claim
    //     uint256 balanceBeforeFirstClaim = rewardToken.balanceOf(stakeHolder);

    //     // First claim of rewards
    //     vm.prank(stakeHolder);
    //     nftStaking.claim(machineId);

    //     // Record balance after the first claim
    //     uint256 balanceAfterFirstClaim = rewardToken.balanceOf(stakeHolder);

    //     // Verify the first claim was successful
    //     assertGt(balanceAfterFirstClaim, balanceBeforeFirstClaim, "first claim should increase balance");

    //     // Get reward information after the first claim
    //     uint256 rewardAfterFirstClaim = nftStaking.getReward(machineId);
    //     (, uint256 rewardAmountCanClaimAfterFirst,,) =
    //         nftStaking.getRewardInfo(machineId);

    //     // Verify claimable rewards are zero after the first claim
    //     assertEq(rewardAfterFirstClaim, 0, "after first claim, should have no reward");
    //     assertEq(rewardAmountCanClaimAfterFirst, 0, "after first claim, should have no reward");

    //     // Record balance before the second claim
    //     uint256 balanceBeforeSecondClaim = rewardToken.balanceOf(stakeHolder);

    //     // Immediately perform the second claim
    //     vm.prank(stakeHolder);
    //     nftStaking.claim(machineId);

    //     // Record balance after the second claim
    //     uint256 balanceAfterSecondClaim = rewardToken.balanceOf(stakeHolder);

    //     // Verify the second claim did not increase the balance
    //     assertEq(balanceAfterSecondClaim, balanceBeforeSecondClaim, "second claim should not increase balance");

    //     // Get reward information after the second claim
    //     uint256 rewardAfterSecondClaim = nftStaking.getReward(machineId);

    //     // Verify claimable rewards are still zero after the second claim
    //     assertEq(rewardAfterSecondClaim, 0, "second claim, should have no reward");
    // }

    function testLockedRewardFullClaimAfterLockPeriod() public {
        // Test if a user can claim all locked rewards after the lock period ends
        address stakeHolder = owner;
        string memory machineId = "machineId";

        // Setup staking
        stakeByOwner(machineId, 100000 ether, 72, stakeHolder);

        // Set reward start time to enable rewards
        vm.prank(owner);
        nftStaking.setRewardStartAt(block.timestamp);

        // Pass some time to accumulate rewards
        passHours(24);

        // Check initial rewards
        (uint256 totalReward, uint256 canClaimNow, uint256 lockedAmount,) = nftStaking.getRewardInfo(machineId);
        assertGt(totalReward, 0, "Should have accumulated some rewards");
        assertGt(lockedAmount, 0, "Should have some locked rewards");

        // Claim rewards first time - this will lock 90% of rewards
        vm.startPrank(stakeHolder);
        uint256 balanceBefore = rewardToken.balanceOf(stakeHolder);
        nftStaking.claim(machineId);
        uint256 balanceAfter = rewardToken.balanceOf(stakeHolder);
        vm.stopPrank();

        // Verify immediate claim (10% of rewards) - 使用近似比较而不是精确比较
        assertEq(balanceAfter - balanceBefore, canClaimNow, "Should have claimed immediate rewards");

        // Get locked reward details
        (,, uint256 stillLockedAmount,) = nftStaking.getRewardInfo(machineId);
        assertGt(stillLockedAmount, 0, "Should still have locked rewards");

        // Fast forward to after lock period (180 days)
        vm.warp(block.timestamp + nftStaking.LOCK_PERIOD() + 1);

        // uint256 leftLocked = total-claimed;

        // Check rewards after lock period
        (, uint256 newCanClaimNow, uint256 newLockedAmount,) = nftStaking.getRewardInfo(machineId);

        // All previously locked rewards should now be claimable
        assertGt(newLockedAmount, 0, "Should have new locked rewards after lock period");
        assertGt(newCanClaimNow, 0, "Should have claimable rewards after lock period");

        // Claim all rewards after lock period
        vm.startPrank(stakeHolder);
        uint256 balanceBeforeFinal = rewardToken.balanceOf(stakeHolder);
        nftStaking.claim(machineId);
        uint256 balanceAfterFinal = rewardToken.balanceOf(stakeHolder);
        vm.stopPrank();

        assertApproxEqRel(
            balanceAfterFinal - balanceBeforeFinal, newCanClaimNow, 0.01e18, "Should have claimed all unlocked rewards"
        );

        // Verify no more locked rewards
        (, uint256 finalCanClaimNow, uint256 finalLockedAmount,) = nftStaking.getRewardInfo(machineId);
        assertGt(finalCanClaimNow, 0, "Should have new rewards after claiming");
        assertEq(finalLockedAmount, 0, "Should have no locked rewards after claiming");

        (uint256 total, uint256 startTime, uint256 endTime, uint256 claimed) =
            nftStaking.machineId2LockedRewardDetail(machineId);
        assertEq(endTime - startTime, nftStaking.LOCK_PERIOD());
        uint256 left = total - claimed;
        vm.startPrank(stakeHolder);
        uint256 balanceBeforeFinal1 = rewardToken.balanceOf(stakeHolder);
        nftStaking.claim(machineId);
        uint256 balanceAfterFinal1 = rewardToken.balanceOf(stakeHolder);
        vm.stopPrank();
        assertEq(left, balanceAfterFinal1 - balanceBeforeFinal1);

        (uint256 totalFinal,,, uint256 claimedFinal) = nftStaking.machineId2LockedRewardDetail(machineId);

        assertEq(totalFinal, claimedFinal);
    }
}
