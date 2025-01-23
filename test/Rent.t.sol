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
import "./MockERC721.t.sol";

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
            owner, address(precompileContract), address(nftStaking), address(nftStakingState), address(rewardToken)
        );
        deal(address(rewardToken), address(this), 10000000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 200000000 * 1e18);

        nftStaking.setRewardStartAt(block.timestamp);

        vm.stopPrank();
    }

    function testRentMachine() public {
        string memory machineId = "machineId";
        stakeByOwner(machineId,0);

        uint256 totalCalcPointBeforeRent = nftStaking.totalCalcPoint();
        uint256 totalAdjustUnitBeforeRent = nftStaking.totalAdjustUnit();

        uint256 rentSeconds = 1 hours;
        uint256 rentFee = 1000 * 1e18;
        rentMachine(machineId,address(this),rentSeconds,rentFee,owner);

        // Assert
        assertEq(rent.getRenter(machineId), address(this));
        assertEq(rent.canRent(machineId), false);
        assertEq(rent.isRented(machineId), true);
        assertEq(rent.totalBurnedAmount(), rentFee);
        assertEq(rent.getBurnedRentFeeByStakeHolder(owner), rentFee);

        assertEq(nftStakingState.getTotalDlcNftStakingBurnedRentFee(), rentFee);
        assertEq(nftStakingState.getRentedGPUCountInDlcNftStaking(), 1);

        address[] memory admins = new address[](1);
        admins[0] = owner;


        uint256 totalCalcPointInRent = nftStaking.totalCalcPoint();
        uint256 totalAdjustUnitInRent = nftStaking.totalAdjustUnit();

        assertEq(totalCalcPointInRent, totalCalcPointBeforeRent * 13 / 10);
        assertGt(totalAdjustUnitInRent, totalAdjustUnitBeforeRent);

        // end machine
        vm.startPrank(admins[0]);
        vm.expectRevert("rent not end");
        rent.endRentMachine(machineId);

        passHours(1);
        rent.endRentMachine(machineId);

        uint256 totalCalcPointAfterRent = nftStaking.totalCalcPoint();
        uint256 totalAdjustUnitAfterRent = nftStaking.totalAdjustUnit();

        assertEq(totalCalcPointAfterRent, totalCalcPointBeforeRent);
        assertEq(totalAdjustUnitAfterRent, totalAdjustUnitBeforeRent);
        vm.stopPrank();

        (NFTStakingState.StakeHolder[] memory topStakeHolders, uint256 total) =
            nftStakingState.getTopStakeHolders(0, 10);
        assertEq(total, 1);
        assertEq(topStakeHolders.length, 1);
        assertEq(topStakeHolders[0].holder, owner);
        assertEq(topStakeHolders[0].rentedGPUCount, 0);
        assertEq(topStakeHolders[0].burnedRentFee, rentFee);
        assertEq(topStakeHolders[0].totalCalcPoint, 100);
        assertEq(topStakeHolders[0].totalGPUCount, 1);
    }

    function testApproveMachineFaultReporting() public {
        // Arrange
        string memory machineId = "machineId";
        stakeByOwner(machineId,0);

        address renter = address(this);

        uint256 rentSeconds = 1 hours;
        uint256 rentFee = 1000 * 1e18;
        rentMachine(machineId, renter,rentSeconds,rentFee,address(0));

        uint256 balanceBeforeReport = rewardToken.balanceOf(address(this));

        reportMachineFault(machineId, renter);

        uint256 balanceAfterReport = rewardToken.balanceOf(renter);

        assertEq(balanceAfterReport, balanceBeforeReport - rent.REPORT_RESERVE_AMOUNT());

        approveReport(machineId, renter);

        uint256 balanceAfterAdminApprove = rewardToken.balanceOf(renter);
        assertEq(balanceAfterAdminApprove, balanceBeforeReport);

        // after approve, pendingSlashMachineId2ApprovedCount should be delete
        assertEq(rent.pendingSlashMachineId2ApprovedCount(machineId), 0);
    }

    function testRejectMachineFaultReporting() public {
        string memory machineId = "machineId";
        stakeByOwner(machineId,0);
        address renter = address(this);

        uint256 rentSeconds = 1 hours;
        uint256 rentFee = 1000 * 1e18;
        rentMachine(machineId, renter,rentSeconds,rentFee,address(0));

        uint256 balanceBeforeReport = rewardToken.balanceOf(address(this));

        reportMachineFault(machineId, renter);

        uint256 balanceAfterReport = rewardToken.balanceOf(renter);

        assertEq(balanceAfterReport, balanceBeforeReport - rent.REPORT_RESERVE_AMOUNT());

        rejectReport(machineId);

        uint256 balanceAfterAdminRefused = rewardToken.balanceOf(address(this));
        assertEq(balanceAfterAdminRefused, balanceBeforeReport - rent.REPORT_RESERVE_AMOUNT());

        assertEq(rent.pendingSlashMachineId2RefuseCount(machineId), 0);
    }

    function testSlashForStakeHolderWithStakeTokenAfterReportApprove() public {
        string memory machineId = "machineId";
        uint256 stakeTokenAmount = 2000*1e18;
        stakeByOwner(machineId,stakeTokenAmount);


//        vm.startPrank(owner);
//        nftStaking.claim(machineId);
//        vm.stopPrank();

        assertEq(nftToken.ownerOf(1),address(nftStaking));

        address renter = address(this);

        uint256 rentSeconds = 1 hours;
        uint256 rentFee = 1000 * 1e18;
        rentMachine(machineId, renter,rentSeconds,rentFee,address(0));
        assertEq(nftStaking.totalReservedAmount(), stakeTokenAmount);
        uint256 ownerBalanceBeforeSlash = rewardToken.balanceOf(owner);
        reportMachineFault(machineId, renter);
        uint256 renterBalanceBeforeApprove = rewardToken.balanceOf(renter);
        approveReport(machineId, renter);
        uint256 renterBalanceAfterApprove = rewardToken.balanceOf(renter);
        uint256 ownerBalanceAfterSlash = rewardToken.balanceOf(owner);
        assertEq(ownerBalanceAfterSlash, ownerBalanceBeforeSlash + stakeTokenAmount - nftStaking.BASE_RESERVE_AMOUNT());
        assertEq(nftToken.ownerOf(1),owner);
        assertEq(renterBalanceAfterApprove, renterBalanceBeforeApprove + nftStaking.BASE_RESERVE_AMOUNT()+ rent.REPORT_RESERVE_AMOUNT());
        assertEq(nftStaking.totalReservedAmount(),0);
        (,,,uint256 endAt,,uint256 _stakeTokenAmount,,,,,,) = nftStaking.machineId2StakeInfos(machineId);
        assertEq(_stakeTokenAmount,0);
        assertEq(endAt,block.timestamp);
        assertEq(nftStaking.isStaking(machineId),false);

        passHours(24);
//        uint256 balance1OfOwner = rewardToken.balanceOf(owner);
//        vm.startPrank(owner);
//        nftStaking.claim(machineId);
//
//        uint256 balance2OfOwner = rewardToken.balanceOf(owner);
//        vm.stopPrank();
//        assertGt(balance2OfOwner,balance1OfOwner);
//
//        (uint256 amount,uint256 unlockTime) = nftStaking.machineId2LockedRewardDetails(machineId,0);
//        assertGt(amount,0);
//        assertEq(unlockTime,block.timestamp + 180 days);


        stakeByOwner(machineId,0);
    }

    function testSlashForStakeHolderWithoutStakeTokenAfterReportApprove() public {
        string memory machineId = "machineId";
        uint256 stakeTokenAmount = 0;
        stakeByOwner(machineId,stakeTokenAmount);
        assertEq(nftStaking.totalReservedAmount(), stakeTokenAmount);

        assertEq(nftToken.ownerOf(1),address(nftStaking));

        address renter = address(this);

        uint256 rentSeconds = 1 hours;
        uint256 rentFee = 1000 * 1e18;

        rentMachine(machineId, renter,rentSeconds,rentFee,address(0));
        assertEq(nftStaking.totalReservedAmount(), stakeTokenAmount);
        uint256 ownerBalanceBeforeSlash = rewardToken.balanceOf(owner);

        reportMachineFault(machineId, renter);
        uint256 renterBalanceBeforeApprove = rewardToken.balanceOf(renter);
        approveReport(machineId, renter);
        uint256 renterBalanceAfterApprove = rewardToken.balanceOf(renter);
        uint256 ownerBalanceAfterSlash = rewardToken.balanceOf(owner);


        assertGt(ownerBalanceAfterSlash, ownerBalanceBeforeSlash + stakeTokenAmount - nftStaking.BASE_RESERVE_AMOUNT());

        assertEq(nftToken.ownerOf(1),owner);

        assertEq(renterBalanceAfterApprove, renterBalanceBeforeApprove + rent.REPORT_RESERVE_AMOUNT());

        assertEq(nftStaking.totalReservedAmount(),0);
        (,,,uint256 endAt,,uint256 _stakeTokenAmount,,,,,,) = nftStaking.machineId2StakeInfos(machineId);
        assertEq(_stakeTokenAmount,0);
        assertEq(endAt,block.timestamp);
        assertEq(nftStaking.isStaking(machineId),false);

//        (uint256 amount,uint256 unlockTime) = nftStaking.machineId2LockedRewardDetails(machineId,0);
//        assertGt(amount,0);
//        assertEq(unlockTime,block.timestamp + 180 days);

        passHours(24);
//        uint256 balance1OfOwner = rewardToken.balanceOf(owner);
//        vm.startPrank(owner);
//        nftStaking.claim(machineId);
//        uint256 balance2OfOwner = rewardToken.balanceOf(owner);
//        vm.stopPrank();
//        assertGt(balance2OfOwner,balance1OfOwner);

        stakeByOwner(machineId,nftStaking.BASE_RESERVE_AMOUNT());

        (,,,,,uint256 _stakeTokenAmount1,,,,,,) = nftStaking.machineId2StakeInfos(machineId);
        assertEq(_stakeTokenAmount1,0);


    }

    function passHours(uint256 n) public {
        uint256 secondsToAdvance = n * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / 6;

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function rentMachine(string memory machineId, address renter, uint256 rentSeconds, uint256 rentFee,address _owner) public {

        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true,true)
        );
//
//        vm.mockCall(
//            address(nftStaking),
//            abi.encodeWithSelector(NFTStaking.getMachineInfo.selector),
//            abi.encode(_owner, 100, 0, 0, 0, 0, true, true)
//        );

        vm.mockCall(
            address(precompileContract),
            abi.encodeWithSelector(precompileContract.getDLCRentFeeByCalcPoint.selector),
            abi.encode(rentFee)
        );

        vm.startPrank(renter);
        rewardToken.approve(address(rent), rentFee);
        rent.rentMachine(machineId, rentSeconds, rentFee);
        vm.stopPrank();
    }

    function reportMachineFault(string memory machineId, address renter) public {
        vm.startPrank(renter);
        uint256 balanceBeforeReport = rewardToken.balanceOf(renter);

        rewardToken.approve(address(rent), rent.REPORT_RESERVE_AMOUNT());
        rent.reportMachineFault(machineId, rent.REPORT_RESERVE_AMOUNT());
        vm.stopPrank();

        uint256 balanceAfterReport = rewardToken.balanceOf(renter);

        assertEq(balanceAfterReport, balanceBeforeReport - rent.REPORT_RESERVE_AMOUNT(), "reportMachineFault failed");
    }

    function approveReport(string memory machineId, address renter) public {
        address[] memory admins = new address[](5);
        admins[0] = renter;
        admins[1] = owner;
        admins[2] = admin3;
        admins[3] = admin4;
        admins[4] = admin5;

        vm.prank(owner);
        rent.setAdminsToApproveMachineFaultReporting(admins);
        rent.approveMachineFaultReporting(machineId);
        assertEq(rent.pendingSlashMachineId2ApprovedCount(machineId), 1);

        vm.prank(renter);
        rent.approveMachineFaultReporting(machineId);

        vm.prank(admin3);
        rent.approveMachineFaultReporting(machineId);
    }

    function rejectReport(string memory machineId) public {
        address[] memory admins = new address[](5);
        admins[0] = owner;
        admins[1] = admin2;
        admins[2] = admin3;
        admins[3] = admin4;
        admins[4] = admin5;

        uint256 adminBalanceBeforeReject = rewardToken.balanceOf(admin2);

        vm.prank(owner);
        rent.setAdminsToApproveMachineFaultReporting(admins);
        vm.prank(owner);
        rent.rejectMachineFaultReporting(machineId);
        assertEq(rent.pendingSlashMachineId2RefuseCount(machineId), 1);

        vm.prank(admin2);
        rent.rejectMachineFaultReporting(machineId);

        vm.prank(admin3);
        rent.rejectMachineFaultReporting(machineId);
        uint256 adminBalanceAfterReject = rewardToken.balanceOf(admin2);

        assertEq(adminBalanceAfterReject, adminBalanceBeforeReject + rent.REPORT_RESERVE_AMOUNT() / admins.length);
    }

    function stakeByOwner(string memory machineId,uint256 reserveAmount) public {
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "", 1, "", 1, machineId)
        );

//        vm.mockCall(
//            address(nftStaking),
//            abi.encodeWithSelector(NFTStaking.getMachineInfo.selector),
//            abi.encode(owner, 100, 0, block.timestamp + 2 hours, 0, reserveAmount, true, true)
//        );

        vm.startPrank(owner);
        nftToken.safeBatchMint(owner, 1, 1);
        deal(address(rewardToken),owner,100000*1e18);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.approve(address(nftStaking), 1);

        uint256[] memory nftTokens = new uint256[](1);
        nftTokens[0] = 1;
        nftStaking.stake(machineId, reserveAmount, nftTokens, 2);
        vm.stopPrank();
        uint256 totalCalcPointBeforeRent = nftStaking.totalCalcPoint();

        assertEq(totalCalcPointBeforeRent, 100);
    }
}
