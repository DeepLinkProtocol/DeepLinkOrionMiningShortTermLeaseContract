// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/NFTStaking.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SetMachineToNonPersonal Tests
 * @notice Tests for the new setMachineToNonPersonal function (v14)
 */
contract SetMachinePersonalTest is Test {
    NFTStaking public staking;
    NFTStaking public stakingProxy;
    address public owner = address(0x1);
    address public nonOwner = address(0x2);
    address public dlcClientWallet = address(0x3);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy implementation
        NFTStaking impl = new NFTStaking();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            NFTStaking.initialize.selector,
            owner, // initialOwner
            address(0x10), // nftToken
            address(0x11), // rewardToken
            address(0x12), // rentContract
            address(0x13), // dbcAIContract
            uint8(1) // phaseLevel
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        stakingProxy = NFTStaking(address(proxy));

        // Set DLC client wallet
        address[] memory wallets = new address[](1);
        wallets[0] = dlcClientWallet;
        stakingProxy.setDLCClientWallets(wallets);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════
    // setMachineToNonPersonal tests
    // ═══════════════════════════════════════════

    function test_setMachineToNonPersonal_basic() public {
        // First mark as personal
        vm.prank(dlcClientWallet);
        string[] memory ids = new string[](1);
        ids[0] = "machine_abc123";
        stakingProxy.setMachineToPersonal(ids);

        // Verify it's personal
        assertTrue(stakingProxy.isPersonalMachine("machine_abc123"));

        // Owner sets to non-personal
        vm.prank(owner);
        stakingProxy.setMachineToNonPersonal(ids);

        // Verify it's no longer personal
        assertFalse(stakingProxy.isPersonalMachine("machine_abc123"));
    }

    function test_setMachineToNonPersonal_batch() public {
        // Mark 3 machines as personal
        vm.prank(dlcClientWallet);
        string[] memory ids = new string[](3);
        ids[0] = "machine_001";
        ids[1] = "machine_002";
        ids[2] = "machine_003";
        stakingProxy.setMachineToPersonal(ids);

        assertTrue(stakingProxy.isPersonalMachine("machine_001"));
        assertTrue(stakingProxy.isPersonalMachine("machine_002"));
        assertTrue(stakingProxy.isPersonalMachine("machine_003"));

        // Owner batch set to non-personal
        vm.prank(owner);
        stakingProxy.setMachineToNonPersonal(ids);

        assertFalse(stakingProxy.isPersonalMachine("machine_001"));
        assertFalse(stakingProxy.isPersonalMachine("machine_002"));
        assertFalse(stakingProxy.isPersonalMachine("machine_003"));
    }

    function test_setMachineToNonPersonal_onlyOwner() public {
        string[] memory ids = new string[](1);
        ids[0] = "machine_xyz";

        // Non-owner should fail with specific OZ v5 error
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        stakingProxy.setMachineToNonPersonal(ids);
    }

    function test_setMachineToNonPersonal_dlcClientWalletCannotCall() public {
        string[] memory ids = new string[](1);
        ids[0] = "machine_xyz";

        // DLC client wallet should also fail (only owner can call)
        vm.prank(dlcClientWallet);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", dlcClientWallet));
        stakingProxy.setMachineToNonPersonal(ids);
    }

    function test_setMachineToNonPersonal_alreadyNonPersonal_isNoop() public {
        // Machine is non-personal by default
        assertFalse(stakingProxy.isPersonalMachine("machine_new"));

        // Setting to non-personal when already non-personal must be a no-op:
        // value stays false AND event MUST NOT emit (idempotent guard)
        string[] memory ids = new string[](1);
        ids[0] = "machine_new";
        vm.recordLogs();
        vm.prank(owner);
        stakingProxy.setMachineToNonPersonal(ids);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertFalse(stakingProxy.isPersonalMachine("machine_new"));
        // Must be ZERO MachinePersonalChanged events (idempotent: no value change → no event)
        bytes32 sig = keccak256("MachinePersonalChanged(string,bool)");
        uint256 matched = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) matched++;
        }
        assertEq(matched, 0, "should not emit event when no change");
    }

    function test_setMachineToNonPersonal_emitsEvent() public {
        // Mark as personal first
        vm.prank(dlcClientWallet);
        string[] memory ids = new string[](1);
        ids[0] = "machine_event_test";
        stakingProxy.setMachineToPersonal(ids);

        // Expect event with indexed machineId (topic1 = keccak("machine_event_test"))
        // Indexed string is hashed in event topic, so we verify topic1 matches
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit NFTStaking.MachinePersonalChanged("machine_event_test", false);
        stakingProxy.setMachineToNonPersonal(ids);
    }

    function test_setMachineToPersonal_isIdempotent() public {
        // setMachineToPersonal should also be idempotent (symmetric with setMachineToNonPersonal)
        string[] memory ids = new string[](1);
        ids[0] = "machine_persidemp";

        // First call: changes state, emits event
        vm.prank(dlcClientWallet);
        vm.expectEmit(true, false, false, true);
        emit NFTStaking.MachinePersonalChanged("machine_persidemp", true);
        stakingProxy.setMachineToPersonal(ids);
        assertTrue(stakingProxy.isPersonalMachine("machine_persidemp"));

        // Second call (already personal): must NOT emit
        vm.recordLogs();
        vm.prank(dlcClientWallet);
        stakingProxy.setMachineToPersonal(ids);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("MachinePersonalChanged(string,bool)");
        uint256 matched = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) matched++;
        }
        assertEq(matched, 0, "second setMachineToPersonal call should not emit");
    }

    function test_setMachineToPersonal_batchLimit_101_reverts() public {
        // 101 batch should revert (matches setMachineToNonPersonal symmetry)
        string[] memory ids = new string[](101);
        for (uint i = 0; i < 101; i++) {
            ids[i] = string(abi.encodePacked("machine_p_", vm.toString(i)));
        }
        vm.prank(dlcClientWallet);
        vm.expectRevert("batch too large");
        stakingProxy.setMachineToPersonal(ids);
    }

    function test_setMachineToPersonal_realProductionMachineId() public {
        // Production machineIds are 64-char hex (sha256 of hardware fingerprint)
        string memory longId = "e6d30a33ebda9387c266548269a15b35bcdd6991391f60d266bed054f6f12e26";
        string[] memory ids = new string[](1);
        ids[0] = longId;

        vm.prank(dlcClientWallet);
        stakingProxy.setMachineToPersonal(ids);
        assertTrue(stakingProxy.isPersonalMachine(longId));

        vm.prank(owner);
        stakingProxy.setMachineToNonPersonal(ids);
        assertFalse(stakingProxy.isPersonalMachine(longId));
    }

    function test_setMachineToNonPersonal_batchLimit() public {
        // 101 machines should revert
        string[] memory ids = new string[](101);
        for (uint i = 0; i < 101; i++) {
            ids[i] = string(abi.encodePacked("machine_", vm.toString(i)));
        }

        vm.prank(owner);
        vm.expectRevert("batch too large");
        stakingProxy.setMachineToNonPersonal(ids);
    }

    function test_setMachineToNonPersonal_exactBatchLimit() public {
        // 100 machines should work
        string[] memory ids = new string[](100);
        for (uint i = 0; i < 100; i++) {
            ids[i] = string(abi.encodePacked("machine_", vm.toString(i)));
        }

        // Mark all personal first
        vm.prank(dlcClientWallet);
        stakingProxy.setMachineToPersonal(ids);

        // Owner sets all to non-personal (should not revert)
        vm.prank(owner);
        stakingProxy.setMachineToNonPersonal(ids);

        // Verify all non-personal
        for (uint i = 0; i < 100; i++) {
            assertFalse(stakingProxy.isPersonalMachine(ids[i]));
        }
    }

    function test_setMachineToNonPersonal_emptyArray() public {
        // Empty array should succeed (no-op)
        string[] memory ids = new string[](0);
        vm.prank(owner);
        stakingProxy.setMachineToNonPersonal(ids);
    }

    function test_setMachineToNonPersonal_toggleBackAndForth() public {
        string[] memory ids = new string[](1);
        ids[0] = "machine_toggle";

        // Default: non-personal
        assertFalse(stakingProxy.isPersonalMachine("machine_toggle"));

        // Set personal
        vm.prank(dlcClientWallet);
        stakingProxy.setMachineToPersonal(ids);
        assertTrue(stakingProxy.isPersonalMachine("machine_toggle"));

        // Set non-personal
        vm.prank(owner);
        stakingProxy.setMachineToNonPersonal(ids);
        assertFalse(stakingProxy.isPersonalMachine("machine_toggle"));

        // Set personal again
        vm.prank(dlcClientWallet);
        stakingProxy.setMachineToPersonal(ids);
        assertTrue(stakingProxy.isPersonalMachine("machine_toggle"));

        // Set non-personal again
        vm.prank(owner);
        stakingProxy.setMachineToNonPersonal(ids);
        assertFalse(stakingProxy.isPersonalMachine("machine_toggle"));
    }

    // ═══════════════════════════════════════════
    // Version test
    // ═══════════════════════════════════════════

    function test_version_is_14() public view {
        assertEq(stakingProxy.version(), 14);
    }
}
