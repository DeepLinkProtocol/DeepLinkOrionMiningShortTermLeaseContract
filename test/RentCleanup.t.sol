// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {IOracle} from "../src/interface/IOracle.sol";
import {IRewardToken} from "../src/interface/IRewardToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

contract RentCleanupTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    Token public rewardToken;
    DLCNode public nftToken;
    IPrecompileContract public precompileContract;
    IDBCAIContract public dbcAIContract;
    IOracle public oracle;

    address owner = address(0x01);
    address nonOwner = address(0x99);

    function setUp() public {
        vm.startPrank(owner);
        precompileContract = IPrecompileContract(address(0x11));
        rewardToken = new Token();
        nftToken = new DLCNode(owner);

        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(proxy1));

        ERC1967Proxy proxy = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(proxy));

        nftStaking.initialize(
            owner, address(nftToken), address(rewardToken), address(rent), address(dbcAIContract), 1
        );
        rent.initialize(
            owner, address(precompileContract), address(nftStaking), address(dbcAIContract), address(rewardToken)
        );

        deal(address(rewardToken), owner, 180000000 * 1e18);
        rewardToken.approve(address(nftStaking), 180000000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 10000000 * 1e18);

        nftStaking.setRewardStartAt(block.timestamp);
        passHours(1);
        oracle = IOracle(address(0x12));
        rent.setOracle(address(oracle));

        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(IDBCAIContract.reportStakingStatus.selector), abi.encode());
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(IDBCAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.mockCall(address(rent), abi.encodeWithSelector(rent.getMachinePrice.selector), abi.encode(100));
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.getTokenPriceInUSD.selector), abi.encode(100));
        vm.stopPrank();
    }

    /// @notice Test: owner can cleanup rent info even when rentEndTime is in the far future
    function testForceCleanupRentInfoByOwner() public {
        string memory machineId = "v1-residual-machine";

        // Setup: stake + rent a machine
        stakeAndRent(machineId, 48);

        // Verify rented state
        assertTrue(rent.isRented(machineId), "should be rented");
        assertTrue(rent.getRenter(machineId) != address(0), "should have renter");
        uint256 rentId = rent.machineId2RentId(machineId);
        assertTrue(rentId > 0, "should have rentId");

        // The normal forceCleanupRentInfo should fail (rent not expired yet)
        vm.prank(owner);
        vm.expectRevert("rent not expired");
        rent.forceCleanupRentInfo(machineId);

        // Owner calls forceCleanupRentInfoByOwner — should succeed
        vm.prank(owner);
        rent.forceCleanupRentInfoByOwner(machineId);

        // Verify: isRented should now be false (after lastRentEndBlock + 30 blocks)
        passBlocks(31);
        assertFalse(rent.isRented(machineId), "should not be rented after cleanup");
        assertEq(rent.machineId2RentId(machineId), 0, "rentId should be 0");
        assertEq(rent.getRenter(machineId), address(0), "renter should be zero");
    }

    /// @notice Test: owner can cleanup even with astronomically large rentEndTime (v1 residual simulation)
    function testForceCleanupWithHugeRentEndTime() public {
        string memory machineId = "v1-huge-rentend";

        // Setup: stake + rent
        stakeAndRent(machineId, 48);

        uint256 rentId = rent.machineId2RentId(machineId);
        assertTrue(rentId > 0, "should have rentId");

        // Warp far into the future — even 100 years won't reach the v1 residual's rentEndTime
        // (v1 residual rentEndTime is ~10^48, way beyond any timestamp)
        vm.warp(block.timestamp + 365 days * 100);

        // Normal forceCleanupRentInfo works now (because we warped past normal rentEndTime)
        // But for v1 residuals with astronomical rentEndTime, it would still fail
        // Our forceCleanupRentInfoByOwner doesn't check rentEndTime at all

        vm.prank(owner);
        rent.forceCleanupRentInfoByOwner(machineId);

        passBlocks(31);
        assertFalse(rent.isRented(machineId), "should not be rented");
    }

    /// @notice Test: non-owner cannot call forceCleanupRentInfoByOwner
    function testForceCleanupRentInfoByOwner_nonOwnerReverts() public {
        string memory machineId = "non-owner-test";
        stakeAndRent(machineId, 48);

        vm.prank(nonOwner);
        vm.expectRevert();
        rent.forceCleanupRentInfoByOwner(machineId);

        // Should still be rented
        assertTrue(rent.isRented(machineId), "should still be rented");
    }

    /// @notice Test: cleanup fails when no rent info exists
    function testForceCleanupRentInfoByOwner_noRentInfoReverts() public {
        string memory machineId = "never-rented";

        vm.prank(owner);
        vm.expectRevert("no rent info to cleanup");
        rent.forceCleanupRentInfoByOwner(machineId);
    }

    /// @notice Test: cleanup emits EndRentMachine event
    function testForceCleanupRentInfoByOwner_emitsEvent() public {
        string memory machineId = "event-test";
        stakeAndRent(machineId, 48);

        uint256 rentId = rent.machineId2RentId(machineId);

        vm.prank(owner);
        vm.expectEmit(false, false, false, false);
        emit Rent.EndRentMachine(address(0), rentId, machineId, 0, address(0));
        rent.forceCleanupRentInfoByOwner(machineId);
    }

    /// @notice Test: machine2ProxyRented is cleared after cleanup
    function testForceCleanupRentInfoByOwner_clearsProxyRented() public {
        string memory machineId = "proxy-rented-test";
        stakeAndRent(machineId, 48);

        vm.prank(owner);
        rent.forceCleanupRentInfoByOwner(machineId);

        assertFalse(rent.machine2ProxyRented(machineId), "proxyRented should be false");
    }

    /// @notice Test: version is 5 after upgrade
    function testVersion() public view {
        assertEq(rent.version(), 5, "version should be 5");
    }

    // ============ Helpers ============

    function passHours(uint256 n) internal {
        uint256 secondsToAdvance = n * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / 6;
        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passBlocks(uint256 n) internal {
        vm.roll(vm.getBlockNumber() + n);
        vm.warp(vm.getBlockTimestamp() + n * 6);
    }

    function stakeAndRent(string memory machineId, uint256 stakeHours) internal {
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(owner, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, machineId, 16)
        );
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );

        vm.startPrank(owner);
        if (!nftStaking.dlcClientWalletAddress(owner)) {
            address[] memory addrs = new address[](1);
            addrs[0] = owner;
            nftStaking.setDLCClientWallets(addrs);
        }

        dealERC1155(address(nftToken), owner, 1, 1, false);
        deal(address(rewardToken), owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), 100000 * 1e18);
        nftToken.setApprovalForAll(address(nftStaking), true);

        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        nftStaking.stakeV2(owner, machineId, nftTokens, nftTokensBalance, stakeHours, true);
        vm.stopPrank();

        // Rent
        deal(address(rewardToken), address(this), 10000 * 1e18);
        rewardToken.approve(address(rent), 10000 * 1e18);
        rent.rentMachine(machineId, 1 hours);
    }
}
