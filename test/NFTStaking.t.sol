// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {NFTStakingState} from "../src/state/NFTStakingState.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/interface/IPrecompileContract.sol";
import {Deploy} from "../script/DeployForTest.s.sol";
import {DeployState} from "../script/state/DeployForTest.s.sol";
import {DeployRent} from "../script/rent/DeployForTest.s.sol";

import {DLCNode} from "./MockERC721.t.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {MockERC721} from "forge-std/mocks/MockERC721.sol";

import {Token} from "./MockRewardToken.sol";
import "../src/interface/IRewardToken.sol";
import "../src/state/NFTStakingState.sol";
import "../src/rent/Rent.sol";

contract StakingTest is Test {
    NFTStaking public staking;
    NFTStakingState public state;
    Rent public rent;

    address public rewardTokenAddr = address(0x0);
    address public precompileContractAddr = address(0x1);
    address public nftAddr;
    address public stakeHolder = address(0x1);
    address public stakeHolder2 = address(0x2);

    function setUp() public {
        deal(stakeHolder, 1 ether);

        vm.prank(address(this));
        nftAddr = address(new DLCNode());
        DLCNode(nftAddr).initialize(address(this));
        assertEq(DLCNode(nftAddr).owner(), address(this));

        Deploy deploy = new Deploy();
        address proxy = deploy.deploy();
        staking = NFTStaking(proxy);

        DeployState stateDeploy = new DeployState();
        address stateProxy = stateDeploy.deploy();
        state = NFTStakingState(stateProxy);
        state.setStakingContract(address(staking));

        assertEq(staking.owner(), address(this));
        rewardTokenAddr = address(new Token());
        Token(rewardTokenAddr).initialize(address(this));

        DeployRent rentDeploy = new DeployRent();
        address rentProxy = rentDeploy.deploy();
        rent = Rent(rentProxy);
        rent.setFeeToken(rewardTokenAddr);
        address[] memory cs = new address[](1);
        cs[0] = address(staking);
        rent.setCurrentStakingContract(Rent.StakingType.phaseOne, address(staking));

        staking.setRewardToken(rewardTokenAddr);
        staking.setNftToken(nftAddr);
        staking.setStateContract(address(state));
        staking.setRentContract(address(rent));

        deal(rewardTokenAddr, stakeHolder, 1000000 * 1e18);
        vm.prank(stakeHolder);
        IRewardToken(rewardTokenAddr).approve(proxy, 100000 * 1e18);
        DLCNode(nftAddr).safeBatchMint(address(stakeHolder), 1, 1);
        deal(rewardTokenAddr, stakeHolder2, 1000000 * 1e18);
        vm.prank(stakeHolder2);
        IRewardToken(rewardTokenAddr).approve(proxy, 100000 * 1e18);
        assertEq(IRewardToken(rewardTokenAddr).balanceOf(stakeHolder2), 1000000 * 1e18);
        IRewardToken(rewardTokenAddr).setMinter(address(staking), 2000000000 * 1e18);
    }

    function test_mock_contract() public {
        vm.mockCall(rewardTokenAddr, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(100000 * 10 ** 18));
        assertEq(staking.rewardToken().balanceOf(msg.sender), 100000 * 10 ** 18);
    }

    function test_daily_reward() public {
        assertEq(staking.getDailyRewardAmount(), 0);

        staking.setRewardStartAt(1);

        assertEq(staking.getDailyRewardAmount(), 3000000 * 1e18);
    }

    function test_stake() public {
        assertEq(DLCNode(nftAddr).ownerOf(1), address(stakeHolder));

        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";
        string memory machineId3 = "machineId3";

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getOwnerRentEndAt.selector),
            abi.encode(14400 * 65)
        );

        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.transferFrom.selector), abi.encode(true));
        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.startPrank(stakeHolder);
        // staking.stake(machineId, 0, tokenIds, 1);
        staking.stake(
            machineId,
            0,
            tokenIds,
            "gpu_type",
            100,
            3600,
            "cpu_type",
            100,
            2 hours / staking.SECONDS_PER_BLOCK(),
            0,
            100,
            0,
            0,
            0,
            0
        );
        vm.stopPrank();

        //        (address[] memory topHolders, uint256[] memory topCalcPoints) = state.getTopStakeHolders();
        //        assertEq(topHolders[0], stakeHolder);
        //        assertEq(topCalcPoints[0], 100);

        (NFTStakingState.StakeHolder[] memory topHolders,) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders[0].holder, stakeHolder, "topHolders[0].holder, stakeHolder");
        assertEq(topHolders[0].totalCalcPoint, 100, "top1 holder calc point 100 failed");

        assertTrue(staking.isStaking(machineId));

        // {
        //     console.log("other user stake the same machine should fail");
        //     // other user stake the same machine should fail
        //     vm.startPrank(stakeHolder2);
        //     vm.expectRevert("machine already staked");
        //     // staking.stake("machineId", 0, tokenIds, 1);

        //     staking.stake(
        //         machineId,
        //         0,
        //         tokenIds,
        //         "gpu_type",
        //         100,
        //         3600,
        //         "cpu_type",
        //         100,
        //         2 hours / staking.SECONDS_PER_BLOCK(),
        //         10000000 * 1e18,
        //         0,
        //         100,
        //         0,
        //         0,
        //         0,
        //         0
        //     );
        //     console.log(
        //         "staking.isStaking(machineId)",
        //         staking.isStaking(machineId)
        //     );
        //     vm.stopPrank();
        //     assertTrue(staking.isStaking(machineId));
        // }

        // should be 0 since reward not start
        vm.startPrank(stakeHolder);
        assertEq(staking.getReward(machineId), 0, "get reward before reward start failed");
        vm.stopPrank();
        uint256 rewardStartAtBlockNumber = 10;
        staking.setRewardStartAt(rewardStartAtBlockNumber);

        passBlocks(rewardStartAtBlockNumber);
        passDays(1);

        vm.startPrank(stakeHolder);
        assertLt(
            staking.getReward(machineId),
            staking.getDailyRewardAmount(),
            "get reward gt failed after reward start 1 day 1"
        );
        assertGt(
            staking.getReward(machineId),
            staking.getDailyRewardAmount() - 1 * 1e18,
            "get reward lt failed after reward start 1 day 2"
        );
        vm.stopPrank();
        uint256[] memory tokenIds0 = new uint256[](1);
        tokenIds0[0] = 2;

        vm.prank(stakeHolder2);
        // staking.stake(machineId2, 0, tokenIds0, 2);
        staking.stake(
            machineId2,
            0,
            tokenIds0,
            "gpu_type",
            100,
            3600,
            "cpu_type",
            100,
            2 hours / staking.SECONDS_PER_BLOCK(),
            0,
            100,
            0,
            0,
            0,
            0
        );
        passDays(1);

        uint256 reward2 = staking.getReward(machineId2);
        assertGt(reward2, 0, "machineId2 get reward lt 0  failed after staked 1 day");
        console.log("reward2", reward2);

        assertLt(
            reward2,
            staking.getDailyRewardAmount() / 2,
            "machineId2 get reward lt staking.getDailyRewardAmount()/2 failed after staked 1 day"
        );

        console.log("reward2  ", staking.getReward(machineId2));

        assertGt(
            staking.getReward(machineId2),
            staking.getDailyRewardAmount() / 2 - 1 * 1e18,
            "machineId2 get reward gt staking.getDailyRewardAmount()/2 - 1 * 1e18 failed after staked 1 day"
        );

        (uint256 rewardAmountCanClaim, uint256 lockedRewardAmount) = staking.getRewardAmountCanClaim(machineId2);
        assertEq(rewardAmountCanClaim, (reward2 * 1) / 10);
        assertEq(lockedRewardAmount, reward2 - (reward2 * 1) / 10);

        uint256[] memory tokenIds2 = new uint256[](1);
        tokenIds2[0] = 3;

        staking.addNFTs(machineId2, tokenIds2);

        uint256 reward3 = staking.getReward(machineId2);
        assertEq(reward3, reward2, "machineId2 get reward  failed after add nft");

        passDays(1);

        uint256 reward4 = staking.getReward(machineId2);
        assertGt(reward4 - reward2, reward2, "machineId2 get reward  failed after add nft");

        (uint256 rewardAmountCanClaim0, uint256 lockedRewardAmount0) = staking.getRewardAmountCanClaim(machineId2);
        assertEq(rewardAmountCanClaim0, (reward4 * 1) / 10);
        assertEq(lockedRewardAmount0, reward4 - (reward4 * 1) / 10);

        staking.claim(machineId2);

        reward4 = staking.getReward(machineId2);
        assertEq(reward4, 0, "machineId2 get reward  failed after claim");

        (uint256 rewardAmountCanClaim1, uint256 lockedRewardAmount1) = staking.getRewardAmountCanClaim(machineId2);
        assertEq(rewardAmountCanClaim1, (lockedRewardAmount0 * staking.DAILY_UNLOCK_RATE()) / 1000, "111");
        assertEq(
            lockedRewardAmount1, lockedRewardAmount0 - (lockedRewardAmount0 * staking.DAILY_UNLOCK_RATE()) / 1000, "222"
        );
        vm.stopPrank();

        uint256[] memory tokenIds1 = new uint256[](1);
        tokenIds2[0] = 3;
        vm.startPrank(stakeHolder);
        // staking.stake(machineId3, 10 * 1e18, tokenIds2, 3);
        staking.stake(
            machineId3,
            10 * 1e18,
            tokenIds2,
            "gpu_type",
            100,
            3600,
            "cpu_type",
            100,
            2 hours / staking.SECONDS_PER_BLOCK(),
            0,
            200,
            0,
            0,
            0,
            0
        );
        (NFTStakingState.StakeHolder[] memory topHolders1, uint256 total) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders1.length, 2, "topHolders1.length");
        assertEq(total, 2, "total");
        assertEq(topHolders1[0].holder, stakeHolder, "topHolders1[0].holder, stakeHolder");
        assertEq(topHolders1[0].totalCalcPoint, 300, "top holder calc point 300 failed");

        (address holder, uint256 calcPoint, uint256 gpuCount,, uint256 totalReservedAmount,,,) =
            state.stakeHolders(stakeHolder);

        assertEq(holder, stakeHolder, "");
        assertEq(calcPoint, 300);

        assertEq(gpuCount, 2, "gpuCount");

        // *****
        assertEq(totalReservedAmount, 10 * 1e18);
        vm.stopPrank();
    }

    function test_stake_with_reserve_token() public {
        assertEq(DLCNode(nftAddr).ownerOf(1), address(stakeHolder));

        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";
        string memory machineId3 = "machineId3";
        string memory machineId4 = "machineId4";

        deal(rewardTokenAddr, stakeHolder, 100000000 * 1e18);

        vm.startPrank(stakeHolder);
        MockERC20(rewardTokenAddr).approve(address(staking), 100000000 * 1e18);
        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.transferFrom.selector), abi.encode(true));

        vm.stopPrank();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.startPrank(stakeHolder2);
        // staking.stake(machineId, 0, tokenIds, 1);
        staking.stake(
            machineId,
            0,
            tokenIds,
            "gpu_type",
            100,
            3600,
            "cpu_type",
            100,
            2 hours / staking.SECONDS_PER_BLOCK(),
            0,
            100,
            0,
            0,
            0,
            0
        );
        vm.stopPrank();
        (NFTStakingState.StakeHolder[] memory topHolders1, uint256 total) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders1.length, 1);
        assertEq(total, 1);
        assertEq(topHolders1[0].holder, stakeHolder2);

        uint256 rewardStartAtBlockNumber = 10;
        staking.setRewardStartAt(rewardStartAtBlockNumber);
        passBlocks(10);

        passDays(1);

        vm.startPrank(stakeHolder2);
        uint256 reward1 = staking.getReward(machineId);
        console.log("1 machine staking reward1", reward1);
        assertLt(reward1, staking.getDailyRewardAmount());
        assertGt(reward1, staking.getDailyRewardAmount() - 1 * 1e18);

        staking.claim(machineId);
        vm.stopPrank();
        uint256[] memory tokenIds1 = new uint256[](1);
        tokenIds1[0] = 2;
        vm.startPrank(stakeHolder);
        // staking.stake(machineId2, 100000 * 1e18, tokenIds1, 1);
        staking.stake(
            machineId2,
            100000 * 1e18,
            tokenIds1,
            "gpu_type",
            100,
            3600,
            "cpu_type",
            100,
            2 hours / staking.SECONDS_PER_BLOCK(),
            0,
            100,
            0,
            0,
            0,
            0
        );
        vm.stopPrank();
        passDays(1);

        vm.startPrank(stakeHolder2);
        reward1 = staking.getReward(machineId);
        console.log("2 machine staking reward1", reward1);
        vm.stopPrank();
        vm.prank(stakeHolder);
        uint256 reward2 = staking.getReward(machineId2);
        console.log("2 machine staking reward2", reward2);

        assertLe(reward1 + reward2, staking.getDailyRewardAmount());
        vm.stopPrank();
        vm.startPrank(stakeHolder2);
        staking.claim(machineId);
        vm.stopPrank();
        vm.startPrank(stakeHolder);
        staking.claim(machineId2);

        uint256[] memory tokenIds2 = new uint256[](1);
        tokenIds2[0] = 3;
        // staking.stake(machineId3, 1000000 * 1e18, tokenIds2, 1);
        staking.stake(
            machineId3,
            1000000 * 1e18,
            tokenIds2,
            "gpu_type",
            100,
            3600,
            "cpu_type",
            100,
            2 hours / staking.SECONDS_PER_BLOCK(),
            0,
            100,
            0,
            0,
            0,
            0
        );
        (NFTStakingState.StakeHolder[] memory topHolders2, uint256 total2) = state.getTopStakeHolders(0, 10);
        assertEq(total2, 2);
        assertEq(topHolders2.length, 2);
        assertEq(topHolders2[0].holder, stakeHolder, "topHolders2[0].holder, stakeHolder");
        assertEq(topHolders2[0].totalCalcPoint, 200);
        assertEq(topHolders2[1].holder, stakeHolder2, "topHolders2[1].holder, stakeHolder2");
        assertEq(topHolders2[1].totalCalcPoint, 100);

        passDays(1);
        vm.stopPrank();
        vm.startPrank(stakeHolder2);
        reward1 = staking.getReward(machineId);
        console.log("3 machine staking reward1", reward1);
        vm.stopPrank();
        vm.startPrank(stakeHolder);
        reward2 = staking.getReward(machineId2);
        console.log("3 machine staking reward2", reward2);

        uint256 reward3 = staking.getReward(machineId3);
        console.log("3 machine staking reward3", reward3);

        assertLe(reward1 + reward2 + reward3, staking.getDailyRewardAmount());
        vm.stopPrank();
        vm.startPrank(stakeHolder2);
        staking.claim(machineId);
        vm.stopPrank();
        vm.startPrank(stakeHolder);
        staking.claim(machineId2);
        staking.claim(machineId3);

        uint256[] memory tokenIds3 = new uint256[](1);
        tokenIds3[0] = 4;
        // staking.stake(machineId4, 10000000 * 1e18, tokenIds3, 1);
        staking.stake(
            machineId4,
            10000000 * 1e18,
            tokenIds3,
            "gpu_type",
            100,
            3600,
            "cpu_type",
            100,
            2 hours / staking.SECONDS_PER_BLOCK(),
            0,
            100,
            0,
            0,
            0,
            0
        );
        vm.stopPrank();
        passDays(1);

        vm.startPrank(stakeHolder2);
        reward1 = staking.getReward(machineId);
        console.log("4 machine staking reward1", reward1);

        vm.startPrank(stakeHolder);
        reward2 = staking.getReward(machineId2);
        console.log("4 machine staking reward2", reward2);
        vm.stopPrank();
        vm.startPrank(stakeHolder);
        reward3 = staking.getReward(machineId3);
        console.log("4 machine staking reward3", reward3);

        uint256 reward4 = staking.getReward(machineId4);
        console.log("4 machine staking reward4", reward4);

        assertLe(reward1 + reward2 + reward3 + reward4, staking.getDailyRewardAmount());
        vm.stopPrank();
    }

    function passDays(uint256 n) public {
        uint256 secondsToAdvance = n * 24 * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / staking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passHours(uint256 n) public {
        uint256 secondsToAdvance = n * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / staking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passBlocks(uint256 n) public {
        uint256 timeToAdvance = n * staking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + timeToAdvance - 1);
        vm.roll(vm.getBlockNumber() + n - 1);
    }

    function test_rent() public {
        assertEq(DLCNode(nftAddr).ownerOf(1), address(stakeHolder));

        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";

        address renter = address(0x10);
        deal(rewardTokenAddr, renter, 1000000 * 1e18);
        assertEq(IRewardToken(rewardTokenAddr).balanceOf(renter), 1000000 * 1e18);
        vm.prank(renter);
        IRewardToken(rewardTokenAddr).approve(address(rent), 100000 * 1e18);
        console.log("rewardTokenAddr", rewardTokenAddr);
        assertEq(address(rent.feeToken()), rewardTokenAddr, "???");

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getOwnerRentEndAt.selector),
            abi.encode(14400 * 65)
        );

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getMachineGPUCount.selector),
            abi.encode(1)
        );
        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.transferFrom.selector), abi.encode(true));
        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1));

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getMachineGPUCount.selector),
            abi.encode(1)
        );

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.startPrank(stakeHolder);
        staking.stake(
            machineId,
            0,
            tokenIds,
            "gpu_type",
            100,
            3600,
            "cpu_type",
            100,
            2 hours / staking.SECONDS_PER_BLOCK(),
            0,
            100,
            0,
            0,
            0,
            0
        );
        vm.stopPrank();

        (NFTStakingState.StakeHolder[] memory topHolders,) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders[0].holder, stakeHolder, "topHolders[0].holder, stakeHolder111");
        assertEq(topHolders[0].totalCalcPoint, 100, "top1 holder calc point 100 failed");

        assertTrue(staking.isStaking(machineId));

        uint256 rewardStartAtBlockNumber = 10;
        staking.setRewardStartAt(rewardStartAtBlockNumber);

        passBlocks(rewardStartAtBlockNumber);

        passDays(1);

        vm.startPrank(stakeHolder);
        assertLt(
            staking.getReward(machineId),
            staking.getDailyRewardAmount(),
            "get reward gt failed after reward start 1 day"
        );
        assertGt(
            staking.getReward(machineId),
            staking.getDailyRewardAmount() - 1 * 1e18,
            "get reward lt failed after reward start 1 day"
        );
        vm.stopPrank();

        uint256[] memory tokenIds0 = new uint256[](1);
        tokenIds0[0] = 2;

        vm.startPrank(stakeHolder2);
        staking.stake(machineId2, 0, tokenIds0, "gpu_type", 100, 3600, "cpu_type", 100, 0, 0, 100, 0, 0, 0, 0);
        passHours(1);

        uint256 reward2 = staking.getReward(machineId2);
        assertGt(reward2, 0, "machineId2 get reward lt 0  failed after staked 1 day");
        vm.stopPrank();

        (NFTStakingState.StakeHolder[] memory topHolders1,) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders1[0].holder, stakeHolder, "topHolders1[0].holder, stakeHolder");
        assertEq(topHolders1[0].totalCalcPoint, 100, "top1 holder calc point 100 failed");

        assertTrue(staking.isStaking(machineId));

        uint256 tokenSupplyBeforeRent = Token(rewardTokenAddr).totalSupply();

        uint256 fee = rent.getMachinePrice(machineId2, 600);
        vm.startPrank(renter);
        rent.rentMachine(machineId2, 600, fee);
        vm.stopPrank();
        uint256 tokenSupplyAfterRent = Token(rewardTokenAddr).totalSupply();
        assertEq(tokenSupplyBeforeRent - tokenSupplyAfterRent, fee, "total supply after rent failed");

        (uint256 phaseOneBurnAmount,,,, uint256 totalBurnAmount) = rent.burnedSummary();

        assertEq(phaseOneBurnAmount, fee, "phase one burned amount failed");
        assertEq(totalBurnAmount, fee, "total burned amount failed");

        uint256 amount = rent.stakeHolder2RentFeeOfStakingType(Rent.StakingType.phaseOne, stakeHolder2);

        assertEq(amount, fee, "stakeHolder2RentFeeOfStakingType burned amount failed");

        (NFTStakingState.StakeHolder[] memory topHolders2,) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders2[0].holder, stakeHolder2);
        assertEq(topHolders2[0].totalCalcPoint, 130);
        assertEq(topHolders2[1].holder, stakeHolder, "topHolders2[1].holder, stakeHolder");
        assertEq(topHolders2[1].totalCalcPoint, 100);

        (NFTStakingState.StakeHolder[] memory topHolders3, uint256 count) = state.getTopStakeHolders(0, 1);
        assertEq(topHolders3[0].holder, stakeHolder2);
        assertEq(topHolders3[0].totalCalcPoint, 130);
        assertEq(count, 2);
        assertEq(topHolders3.length, 1);

        passHours(1);

        vm.startPrank(stakeHolder2);
        uint256 reward3 = staking.getReward(machineId2);
        uint256 reward4 = reward3 / 2;
        assertGt(reward4, reward2);

        assertEq(rent.machineId2RentedGpuCount(machineId2), 1);
        rent.endRentMachine(1);
        assertEq(rent.machineId2RentedGpuCount(machineId2), 0);

        passHours(1);

        uint256 reward5 = staking.getReward(machineId2);
        assertGt(reward5, reward2);

        (NFTStakingState.StakeHolder[] memory topHolders4,) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders4[0].totalCalcPoint, 100);
        vm.stopPrank();
    }

    function test_report_fault_machine() public {
        assertEq(DLCNode(nftAddr).ownerOf(1), address(stakeHolder));

        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";

        address admin1 = address(0x20);
        address admin2 = address(0x21);
        address admin3 = address(0x22);
        address admin4 = address(0x23);
        address admin5 = address(0x24);

        address renter = address(0x10);
        deal(rewardTokenAddr, renter, 1000000 * 1e18);
        assertEq(IRewardToken(rewardTokenAddr).balanceOf(renter), 1000000 * 1e18);
        vm.startPrank(renter);
        IRewardToken(rewardTokenAddr).approve(address(rent), 100000 * 1e18);
        console.log("rewardTokenAddr", rewardTokenAddr);
        assertEq(address(rent.feeToken()), rewardTokenAddr, "???");

        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.transferFrom.selector), abi.encode(true));
        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1));

        uint256[] memory tokenIds = new uint256[](1);
        vm.stopPrank();
        tokenIds[0] = 1;
        vm.startPrank(stakeHolder);
        staking.stake(machineId, 0, tokenIds, "gpu_type", 100, 3600, "cpu_type", 100, 0, 0, 100, 0, 0, 0, 0);

        (NFTStakingState.StakeHolder[] memory topHolders,) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders[0].holder, stakeHolder, "topHolders[0].holder, stakeHolder");
        assertEq(topHolders[0].totalCalcPoint, 100, "top1 holder calc point 100 failed");

        assertTrue(staking.isStaking(machineId));
        vm.stopPrank();

        uint256 rewardStartAtBlockNumber = 10;
        staking.setRewardStartAt(rewardStartAtBlockNumber);

        passBlocks(rewardStartAtBlockNumber);

        passHours(1);
        vm.startPrank(stakeHolder);

        assertLt(
            staking.getReward(machineId),
            staking.getDailyRewardAmount(),
            "get reward gt failed after reward start 1 day"
        );
        assertGt(
            staking.getReward(machineId),
            staking.getDailyRewardAmount() / 24 - 1 * 1e18,
            "get reward lt failed after reward start 1 day"
        );
        vm.stopPrank();

        uint256[] memory tokenIds0 = new uint256[](1);
        tokenIds0[0] = 2;
        vm.startPrank(stakeHolder2);
        staking.stake(machineId2, 0, tokenIds0, "gpu_type", 100, 3600, "cpu_type", 100, 0, 0, 100, 0, 0, 0, 0);

        passHours(1);

        uint256 reward2 = staking.getReward(machineId2);
        assertGt(reward2, 0, "machineId2 get reward lt 0  failed after staked 1 day");
        vm.stopPrank();

        (NFTStakingState.StakeHolder[] memory topHolders1,) = state.getTopStakeHolders(0, 10);
        assertEq(topHolders1[0].holder, stakeHolder, "topHolders1[0].holder, stakeHolder");
        assertEq(topHolders1[0].totalCalcPoint, 100, "top1 holder calc point 100 failed");

        assertTrue(staking.isStaking(machineId));

        uint256 fee = rent.getMachinePrice(machineId2, 1200);
        vm.startPrank(renter);
        rent.rentMachine(machineId2, 1200, fee);
        return passHours(1);
        vm.stopPrank();

        vm.startPrank(stakeHolder2);
        uint256 reward3 = staking.getReward(machineId2);
        uint256 reward4 = reward3 / 2;
        assertGt(reward4, reward2);

        uint256 renterBalanceBeforeSlash = Token(rewardTokenAddr).balanceOf(renter);
        vm.stopPrank();
        vm.startPrank(renter);
        rent.reportMachineFault(1, 10000 * 1e18);
        vm.stopPrank();

        address[] memory admins = new address[](5);
        admins[0] = admin1;
        admins[1] = admin2;
        admins[2] = admin3;
        admins[3] = admin4;
        admins[4] = admin5;
        rent.setAdminsToApproveMachineFaultReporting(admins);
        vm.startPrank(admin1);
        rent.approveMachineFaultReporting(machineId2);

        uint256 holderBalanceBeforeSlashAndClaim = Token(rewardTokenAddr).balanceOf(stakeHolder2);
        vm.stopPrank();
        vm.startPrank(admin2);
        rent.approveMachineFaultReporting(machineId2);
        vm.stopPrank();
        vm.startPrank(admin3);
        rent.approveMachineFaultReporting(machineId2);

        //
        //        vm.prank(stakeHolder2);
        //        staking.claim(machineId2);
        assertEq(staking.isStaking(machineId2), false);

        uint256 renterBalanceAfterSlash = Token(rewardTokenAddr).balanceOf(renter);
        uint256 holderBalanceAfterSlashAndClaim = Token(rewardTokenAddr).balanceOf(stakeHolder2);

        assertEq(
            renterBalanceAfterSlash - renterBalanceBeforeSlash, staking.BASE_RESERVE_AMOUNT(), "slash amount failed"
        );
        assertGt(holderBalanceAfterSlashAndClaim, holderBalanceBeforeSlashAndClaim);
        (,,,, uint256 _totalReservedAmount,,,) = state.stakeHolders(stakeHolder2);
        assertEq(_totalReservedAmount, 0, "holder2 reserved amount failed");

        assertEq(staking.totalReservedAmount(), 0, "reserved amount failed");
        vm.stopPrank();
    }
}
