// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {NFTStakingState} from "../src/state/NFTStakingState.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/interface/IPrecompileContract.sol";
import {Deploy} from "../script/DeployForTest.s.sol";
import {DeployState} from "../script/state/DeployForTest.s.sol";

import {DLCNode} from "./MockERC721.t.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract StakingTest is Test {
    NFTStaking public staking;
    NFTStakingState public state;
    address public rewardTokenAddr = address(0x0);
    address public precompileContractAddr = address(0x1);
    address public nftAddr;
    address stakeHolder = address(0x1);
    address stakeHolder2 = address(0x2);

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
//        address stateProxy = stateDeploy.deploy();
//        state = NFTStakingState(stateProxy);
//        state.addOrUpdateStakeHolder(0x0000000000000000000000000000000000000001, "machineId", 100, 0);
//        state.setPrecompileContract(precompileContractAddr);
//        state.setValidCaller(address(staking));
        assertEq(staking.owner(), address(this));
        rewardTokenAddr = address(new MockERC20());
        MockERC20(rewardTokenAddr).initialize("rewardToken", "rwd", 18);

        staking.setRewardToken(rewardTokenAddr);
        staking.setPrecompileContract(precompileContractAddr);
        staking.setNftToken(nftAddr);
//        staking.setStateContract(address(state));

        deal(rewardTokenAddr, stakeHolder, 1000000 * 1e18);
        vm.prank(stakeHolder);
        MockERC20(rewardTokenAddr).approve(proxy, 100000 * 1e18);

        DLCNode(nftAddr).safeBatchMint(address(stakeHolder), 1, 1);
        deal(rewardTokenAddr, stakeHolder2, 1000000 * 1e18);
        vm.prank(stakeHolder2);
        MockERC20(rewardTokenAddr).approve(proxy, 100000 * 1e18);
        assertEq(MockERC20(rewardTokenAddr).balanceOf(stakeHolder2), 1000000 * 1e18);

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.reportDlcNftStaking.selector),
            abi.encode(true)
        );

        vm.mockCall(
            precompileContractAddr, abi.encodeWithSelector(IPrecompileContract.isSlashed.selector), abi.encode(false)
        );

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getMachineCalcPoint.selector),
            abi.encode(100)
        );
    }

    function test_mock_contract() public {
        vm.mockCall(rewardTokenAddr, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(100000 * 10 ** 18));
        assertEq(staking.rewardToken().balanceOf(msg.sender), 100000 * 10 ** 18);

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getMachineCalcPoint.selector),
            abi.encode(100)
        );
        assertEq(staking.precompileContract().getMachineCalcPoint("111"), 100);
    }

    function test_getLnResult() public view {
        uint256 baseReward = 6000000 * 1e18;
        (uint256 numerator1, uint256 denominator1) = staking.getLnResult(10000 * 1e18);
        uint256 v1W = baseReward
            + baseReward * staking.nonlinearCoefficientNumerator() / staking.nonlinearCoefficientDenominator() * numerator1
                / denominator1;
        console.log("numerator1 ", numerator1);
        console.log("denominator1 ", denominator1);

        (uint256 numerator2, uint256 denominator2) = staking.getLnResult(100000 * 1e18);
        uint256 v10W = baseReward
            + baseReward * staking.nonlinearCoefficientNumerator() / staking.nonlinearCoefficientDenominator() * numerator2
                / denominator2;
        console.log("numerator2 ", numerator2);
        console.log("denominator2 ", denominator2);

        (uint256 numerator3, uint256 denominator3) = staking.getLnResult(1000000 * 1e18);
        uint256 v100W = baseReward
            + baseReward * staking.nonlinearCoefficientNumerator() / staking.nonlinearCoefficientDenominator() * numerator3
                / denominator3;
        console.log("numerator3 ", numerator3);
        console.log("denominator3 ", denominator3);

        (uint256 numerator4, uint256 denominator4) = staking.getLnResult(10000000 * 1e18);
        uint256 v1000W = baseReward
            + baseReward * staking.nonlinearCoefficientNumerator() / staking.nonlinearCoefficientDenominator() * numerator4
                / denominator4;
        console.log("numerator4 ", numerator4);
        console.log("denominator4 ", denominator4);

        (uint256 numerator5, uint256 denominator5) = staking.getLnResult(100000000 * 1e18);
        uint256 v10000W = baseReward
            + baseReward * staking.nonlinearCoefficientNumerator() / staking.nonlinearCoefficientDenominator() * numerator5
                / denominator5;
        console.log("numerator5 ", numerator5);
        console.log("denominator5 ", denominator5);

        console.log("v1W: ", v1W);
        console.log("v10W: ", v10W);
        console.log("v100W: ", v100W);
        console.log("v1000W: ", v1000W);
        console.log("v10000W: ", v10000W);
    }

    function test_reward_per_second() public {
        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getDlcNftStakingRewardStartAt.selector),
            abi.encode(0)
        );

        assertEq(staking.rewardPerSecond(), 0);

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getDlcNftStakingRewardStartAt.selector),
            abi.encode(1)
        );

        assertEq(staking.daily_reward(), 6000000 * 1e18);
        uint256 phaseOneRewardPerSecond = uint256(staking.daily_reward() / 1 days);
        assertEq(staking.rewardPerSecond(), phaseOneRewardPerSecond);
    }

    function test_stake() public {
        assertEq(DLCNode(nftAddr).ownerOf(1), address(stakeHolder));
        vm.prank(stakeHolder);
        DLCNode(nftAddr).approve(address(staking), 1);

        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";
        string memory machineId3 = "machineId3";

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getDlcNftStakingRewardStartAt.selector),
            abi.encode(0)
        );

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getRentingDuration.selector),
            abi.encode(14400 * 60)
        );

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getDlcMachineSlashedAt.selector),
            abi.encode(0)
        );

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.reportDlcNftStaking.selector),
            abi.encode(true)
        );

        vm.mockCall(
            precompileContractAddr,
            abi.encodeWithSelector(IPrecompileContract.getMachineGPUCount.selector),
            abi.encode(1)
        );
        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.transferFrom.selector), abi.encode(true));
        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.prank(stakeHolder);
        staking.stake("abc", "sig", "pubkey", machineId, 0, tokenIds, 1);

        (address[3] memory  topHolders, uint256[3] memory topCalcPoints) = state.getTopStakeHolders();
        assertEq(topHolders[0], stakeHolder);
        assertEq(topCalcPoints[0], 100);

        assertTrue(staking.isStaking(machineId));

        {
            // other user stake the same machine should fail
            vm.prank(stakeHolder2);
            vm.expectRevert("machine already staked");
            staking.stake("abc", "sig", "pubkey", "machineId", 0, tokenIds, 1);
            assertTrue(staking.isStaking(machineId));
        }

        {
            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getRentDuration.selector),
                abi.encode(1)
            );

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getValidRewardDuration.selector),
                abi.encode(1)
            );

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getMachineGPUCount.selector),
                abi.encode(1)
            );

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getDlcMachineRentDuration.selector),
                abi.encode(0)
            );

            // should be 0 since reward not start
            vm.prank(stakeHolder);
            assertEq(staking.getReward(machineId), 0);
            uint256 rewardStartAtBlockNumber = 10;
            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getDlcNftStakingRewardStartAt.selector),
                abi.encode(rewardStartAtBlockNumber)
            );

            // after 1s of the reward start
            uint256 rewardStarrAtTimestamp = rewardStartAtBlockNumber * 6;
            uint256 secondsAfterRewardStart = 1;
            uint256 _now = rewardStarrAtTimestamp + secondsAfterRewardStart;
            vm.warp(_now);
            assertEq(vm.getBlockTimestamp(), 61);

            staking.setNonlinearCoefficient(1, 10);
            vm.prank(stakeHolder);
            assertGt(staking.getReward(machineId), 0);
            vm.prank(stakeHolder);
            assertEq(staking.getReward(machineId), staking.rewardPerSecond() * secondsAfterRewardStart);

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getDlcMachineRentDuration.selector),
                abi.encode(1)
            );
            vm.prank(stakeHolder);
            assertEq(staking.getReward(machineId), staking.rewardPerSecond() * secondsAfterRewardStart);

            uint256[] memory tokenIds0 = new uint256[](1);
            tokenIds0[0] = 2;
            vm.roll(10);
            assertEq(vm.getBlockNumber(), 10);

            vm.prank(stakeHolder2);
            staking.stake("abc", "sig", "pubkey", machineId2, 100000 * 1e18, tokenIds0, 2);

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getRentDuration.selector),
                abi.encode(1)
            );

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getValidRewardDuration.selector),
                abi.encode(1)
            );

            vm.warp(_now + 1);
            vm.prank(stakeHolder2);
            assertGt(staking.getReward(machineId2), staking.rewardPerSecond() * secondsAfterRewardStart / 2);
            vm.prank(stakeHolder2);
            uint256 reward2 = staking.getReward(machineId2);
            assertLt(reward2, staking.rewardPerSecond() * secondsAfterRewardStart);

            uint256[] memory tokenIds2 = new uint256[](1);
            tokenIds2[0] = 3;

            vm.prank(stakeHolder2);
            staking.addNFTs(machineId2, tokenIds2);

            vm.prank(stakeHolder2);
            uint256 reward3 = staking.getReward(machineId2);
            assertGt(reward3, reward2);
            vm.prank(stakeHolder2);
            (uint256 rewardAmountCanClaim, uint256 lockedRewardAmount) = staking.getRewardAmountCanClaim(machineId2);
            assertEq(rewardAmountCanClaim, reward3 * 1 / 10);
            assertEq(lockedRewardAmount, reward3 - reward3 * 1 / 10);

            vm.roll(10 + 14400);
            vm.warp(_now + 1 + 144000 * 6);

            vm.prank(stakeHolder2);

            staking.claim("abc", "sig", "pubkey", machineId2);

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getRentDuration.selector),
                abi.encode(0)
            );

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getValidRewardDuration.selector),
                abi.encode(0)
            );
            vm.prank(stakeHolder2);
            (uint256 rewardAmountCanClaim1, uint256 lockedRewardAmount1) = staking.getRewardAmountCanClaim(machineId2);
            assertEq(rewardAmountCanClaim1, lockedRewardAmount * staking.DAILY_UNLOCK_RATE() / 1000);
            assertEq(lockedRewardAmount1, lockedRewardAmount - lockedRewardAmount * staking.DAILY_UNLOCK_RATE() / 1000);

            vm.mockCall(
                precompileContractAddr,
                abi.encodeWithSelector(IPrecompileContract.getMachineCalcPoint.selector),
                abi.encode(200)
            );

            uint256[] memory tokenIds1 = new uint256[](1);
            tokenIds2[0] = 3;
            vm.prank(stakeHolder);
            staking.stake("abc", "sig", "pubkey", machineId3, 10 * 1e18, tokenIds1, 3);


            (address[3] memory topHolders1, uint256[3] memory topCalcPoints1) = state.getTopStakeHolders();
            assertEq(topHolders1[0], stakeHolder);
            assertEq(topCalcPoints1[0], 300);

            (address holder, uint256 calcPoint, uint256 gpuCount, uint256 totalReservedAmount) =
                state.stakeHolders(stakeHolder);

            assertEq(holder, stakeHolder);
            assertEq(calcPoint, 300);
            assertEq(gpuCount, 2);
            assertEq(totalReservedAmount, 10 * 1e18);
        }
    }
}
