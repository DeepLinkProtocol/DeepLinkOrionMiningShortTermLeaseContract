// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/rent/Rent.sol";
import "../src/NFTStaking.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {IOracle} from "../src/interface/IOracle.sol";

contract RentWhitelistCountTest is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    Token public rewardToken;
    DLCNode public nftToken;

    address owner = address(0x01);
    address admin = address(0xAD01);

    function setUp() public {
        vm.startPrank(owner);

        IPrecompileContract precompileContract = IPrecompileContract(address(0x11));
        IDBCAIContract dbcAIContract = IDBCAIContract(address(0x13));
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

        // Set admin for whitelist
        address[] memory admins = new address[](1);
        admins[0] = admin;
        rent.setAdminsToAddRentWhiteList(admins);

        // Mock dbcAI calls
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.reportStakingStatus.selector), abi.encode());

        vm.stopPrank();
    }

    function test_initialCountIsZero() public view {
        assertEq(rent.rentWhitelistCount(), 0, "Initial count should be 0");
    }

    function test_addOneMachine() public {
        vm.prank(admin);
        string[] memory ids = new string[](1);
        ids[0] = "machine_001";
        rent.setRentingWhitelist(ids, true);

        assertEq(rent.rentWhitelistCount(), 1);
        assertTrue(rent.rentWhitelist("machine_001"));
    }

    function test_addMultipleMachines() public {
        vm.prank(admin);
        string[] memory ids = new string[](3);
        ids[0] = "machine_001";
        ids[1] = "machine_002";
        ids[2] = "machine_003";
        rent.setRentingWhitelist(ids, true);

        assertEq(rent.rentWhitelistCount(), 3);
    }

    function test_removeMachine() public {
        vm.startPrank(admin);
        string[] memory ids = new string[](3);
        ids[0] = "machine_001";
        ids[1] = "machine_002";
        ids[2] = "machine_003";
        rent.setRentingWhitelist(ids, true);
        assertEq(rent.rentWhitelistCount(), 3);

        string[] memory removeIds = new string[](1);
        removeIds[0] = "machine_002";
        rent.setRentingWhitelist(removeIds, false);
        vm.stopPrank();

        assertEq(rent.rentWhitelistCount(), 2);
        assertFalse(rent.rentWhitelist("machine_002"));
        assertTrue(rent.rentWhitelist("machine_001"));
    }

    function test_addSameMachineTwice_noDoubleCount() public {
        vm.startPrank(admin);
        string[] memory ids = new string[](1);
        ids[0] = "machine_001";
        rent.setRentingWhitelist(ids, true);
        assertEq(rent.rentWhitelistCount(), 1);

        rent.setRentingWhitelist(ids, true);
        vm.stopPrank();

        assertEq(rent.rentWhitelistCount(), 1, "Idempotent add should not double count");
    }

    function test_removeNonExistent_noUnderflow() public {
        vm.prank(admin);
        string[] memory ids = new string[](1);
        ids[0] = "machine_nonexistent";
        rent.setRentingWhitelist(ids, false);

        assertEq(rent.rentWhitelistCount(), 0, "Should not underflow");
    }

    function test_removeSameTwice_noUnderflow() public {
        vm.startPrank(admin);
        string[] memory ids = new string[](1);
        ids[0] = "machine_001";
        rent.setRentingWhitelist(ids, true);
        assertEq(rent.rentWhitelistCount(), 1);

        rent.setRentingWhitelist(ids, false);
        assertEq(rent.rentWhitelistCount(), 0);

        rent.setRentingWhitelist(ids, false);
        vm.stopPrank();

        assertEq(rent.rentWhitelistCount(), 0, "Should not underflow on double remove");
    }

    function test_batchAddRemove() public {
        vm.startPrank(admin);

        string[] memory addIds = new string[](5);
        addIds[0] = "m0"; addIds[1] = "m1"; addIds[2] = "m2"; addIds[3] = "m3"; addIds[4] = "m4";
        rent.setRentingWhitelist(addIds, true);
        assertEq(rent.rentWhitelistCount(), 5);

        string[] memory removeIds = new string[](3);
        removeIds[0] = "m0"; removeIds[1] = "m2"; removeIds[2] = "m4";
        rent.setRentingWhitelist(removeIds, false);
        vm.stopPrank();

        assertEq(rent.rentWhitelistCount(), 2);
    }

    function test_nonAdminCannotSet() public {
        address nonAdmin = address(0x9999);
        vm.prank(nonAdmin);
        string[] memory ids = new string[](1);
        ids[0] = "machine_001";
        vm.expectRevert("has no permission to set renting whitelist");
        rent.setRentingWhitelist(ids, true);
    }

    function test_batchWithDuplicates() public {
        vm.prank(admin);
        string[] memory ids = new string[](4);
        ids[0] = "machine_A";
        ids[1] = "machine_B";
        ids[2] = "machine_A"; // duplicate
        ids[3] = "machine_C";
        rent.setRentingWhitelist(ids, true);

        assertEq(rent.rentWhitelistCount(), 3, "Duplicate in batch should count once");
    }

    function test_addThenRemoveAll() public {
        vm.startPrank(admin);
        string[] memory ids = new string[](3);
        ids[0] = "a"; ids[1] = "b"; ids[2] = "c";
        rent.setRentingWhitelist(ids, true);
        assertEq(rent.rentWhitelistCount(), 3);

        rent.setRentingWhitelist(ids, false);
        vm.stopPrank();

        assertEq(rent.rentWhitelistCount(), 0, "Remove all should be 0");
    }

    function test_version() public view {
        assertEq(rent.version(), 9, "Version should be 9");
    }
}
