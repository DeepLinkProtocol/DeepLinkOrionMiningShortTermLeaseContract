// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {NFTStakingState} from "../src/state/NFTStakingState.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";

import {IRewardToken} from "../src/interface/IRewardToken.sol";
import {ITool} from "../src/interface/ITool.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Tool.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

contract RentTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    NFTStakingState public nftStakingState;
    IPrecompileContract public precompileContract;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;

    Tool public tool;
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

        ERC1967Proxy proxy3 = new ERC1967Proxy(address(new Tool()), "");
        Tool(address(proxy3)).initialize(owner);
        tool = Tool(address(proxy3));

        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(proxy1));

        ERC1967Proxy proxy2 = new ERC1967Proxy(address(new NFTStakingState()), "");
        nftStakingState = NFTStakingState(address(proxy2));

        ERC1967Proxy proxy = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(proxy));

        NFTStaking(address(proxy1)).initialize(
            owner,
            address(nftToken),
            address(rewardToken),
            address(nftStakingState),
            address(rent),
            address(dbcAIContract),
            address(tool),
            1
        );
        NFTStakingState(address(proxy2)).initialize(owner, address(rent), address(nftStaking));
        Rent(address(proxy)).initialize(
            owner,
            address(precompileContract),
            address(nftStaking),
            address(nftStakingState),
            address(dbcAIContract),
            address(rewardToken)
        );
        deal(address(rewardToken), address(this), 10000000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 200000000 * 1e18);

        nftStaking.setRewardStartAt(block.timestamp);

        vm.stopPrank();
    }

    function test_daily_reward() public view {
        assertEq(nftStaking.getDailyRewardAmount(), 3000000 * 1e18);
    }

    function stakeByOwner(string memory machineId, uint256 reserveAmount, uint256 stakeHours, address _owner) public {
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(_owner, 100, 3500, "", 1, "", 1, machineId)
        );

        vm.startPrank(_owner);
        dealERC1155(address(nftToken), _owner, 1, 1, false);
        assertEq(nftToken.balanceOf(_owner, 1), 1, "owner erc1155 failed");
        deal(address(rewardToken), _owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);

        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        uint256 totalCalcPointBefore = nftStaking.totalCalcPoint();
        nftStaking.stake(machineId, nftTokens, nftTokensBalance, stakeHours);
        nftStaking.addDLCToStake(machineId, reserveAmount);
        vm.stopPrank();
        uint256 totalCalcPoint = nftStaking.totalCalcPoint();

        assertEq(totalCalcPoint, totalCalcPointBefore + 100);
    }

    function testStake() public {
        address stakeHolder = owner;
        //        assertEq(nftToken.balanceOf(stakeHolder, 1), 100);
        //        address nftAddr = address(nftToken);
        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";
        string memory machineId3 = "machineId3";

        //        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.transferFrom.selector), abi.encode(true));
        //        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.startPrank(stakeHolder);
        // staking.stake(machineId, 0, tokenIds, 1);
        stakeByOwner(machineId, 0, 480, stakeHolder);
        vm.stopPrank();

        //        (address[] memory topHolders, uint256[] memory topCalcPoints) = state.getTopStakeHolders();
        //        assertEq(topHolders[0], stakeHolder);
        //        assertEq(topCalcPoints[0], 100);

        (NFTStakingState.StakeHolder[] memory topHolders,) = nftStakingState.getTopStakeHolders(0, 10);
        assertEq(topHolders[0].holder, stakeHolder, "topHolders[0].holder, stakeHolder");
        assertEq(topHolders[0].totalCalcPoint, 100, "top1 holder calc point 100 failed");
        assertTrue(nftStaking.isStaking(machineId));

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
        stakeByOwner(machineId2, 0, 480, stakeHolder2);
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
        console.log("reward4  ", reward4);

        (, uint256 rewardAmountCanClaim0, uint256 lockedRewardAmount0,) = nftStaking.getRewardInfo(machineId2);
        assertEq(rewardAmountCanClaim0, reward4 / 10);
        assertEq(lockedRewardAmount0, reward4 - reward4 / 10);

        vm.prank(stakeHolder2);
        nftStaking.claim(machineId2);

        reward4 = nftStaking.getReward(machineId2);
        assertEq(reward4, 0, "machineId2 get reward  failed after claim");

        passDays(1);
        (uint256 release, uint256 locked) = nftStaking.calculateReleaseReward(machineId2, true);
        assertEq(release, ((locked + release) * 1 days / nftStaking.LOCK_PERIOD()), "111");
        vm.stopPrank();
        uint256[] memory tokenIds3 = new uint256[](1);
        tokenIds3[0] = 10;
        vm.startPrank(stakeHolder);
        // staking.stake(machineId3, 10 * 1e18, tokenIds2, 3);
        stakeByOwner(machineId3, 10 * 1e18, 2, stakeHolder);
        (NFTStakingState.StakeHolder[] memory topHolders1, uint256 total) = nftStakingState.getTopStakeHolders(0, 10);
        assertEq(topHolders1.length, 2, "topHolders1.length");
        assertEq(total, 2, "total");
        assertEq(topHolders1[0].totalCalcPoint, 200, "top 1 holder calc point 300 failed");
        assertEq(topHolders1[1].totalCalcPoint, 100, "top 2 holder calc point 200 failed");

        (address holder, uint256 calcPoint, uint256 gpuCount,, uint256 totalReservedAmount,,,) =
            nftStakingState.stakeHolders(stakeHolder);

        assertEq(holder, stakeHolder, "");
        assertEq(calcPoint, 200);

        assertEq(gpuCount, 2, "gpuCount");

        assertEq(totalReservedAmount, 10 * 1e18);
        vm.stopPrank();
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
}
