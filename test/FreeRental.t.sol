// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FreeRental} from "../src/rent/FreeRental.sol";
import {Token} from "./MockRewardToken.sol";
import {DBCStakingContractMock} from "./MockDBCAIContract.sol";

contract FreeRentalTest is Test {
    FreeRental public freeRental;
    Token public pointToken;
    DBCStakingContractMock public dbcAIMock;

    address deployer = address(0x01);
    address admin = address(0x02);
    address slashAdmin = address(0x03);
    address platformWallet = address(0x04);
    address machineOwner = address(0x10);
    address renter = address(0x20);
    address nobody = address(0x99);

    string constant MACHINE_1 = "machine_aabbccdd11223344";
    string constant MACHINE_2 = "machine_eeff00112233aabb";
    string constant MACHINE_3 = "machine_3333333333333333";
    uint256 constant PRICE_USD = 500000; // $0.50 per hour
    uint256 constant ONE_HOUR = 3600;

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy mock ERC20
        pointToken = new Token();
        pointToken.initialize(deployer);

        // Deploy mock dbcAI
        dbcAIMock = new DBCStakingContractMock();

        // Deploy FreeRental directly (no proxy for simplicity) -- need to work around _disableInitializers
        // Use a proxy-less approach: deploy impl, then call initialize
        // Actually, _disableInitializers in constructor prevents direct init.
        // We'll use ERC1967Proxy like the existing tests.
        // But to keep it simple, let's just deploy via CREATE with etch.

        // Deploy implementation
        FreeRental impl = new FreeRental();

        // Deploy proxy manually
        bytes memory initData = abi.encodeCall(FreeRental.initialize, (address(pointToken), platformWallet));
        // Using ERC1967Proxy
        bytes memory proxyCode = abi.encodePacked(
            type(ERC1967ProxyHelper).creationCode,
            abi.encode(address(impl), initData)
        );
        address proxyAddr;
        assembly {
            proxyAddr := create(0, add(proxyCode, 0x20), mload(proxyCode))
        }
        require(proxyAddr != address(0), "proxy deploy failed");
        freeRental = FreeRental(proxyAddr);

        // Setup admins
        address[] memory adminArr = new address[](1);
        adminArr[0] = admin;
        freeRental.setAdmins(adminArr, true);

        address[] memory slashArr = new address[](1);
        slashArr[0] = slashAdmin;
        freeRental.setSlashAdmins(slashArr, true);

        // Set dbcAI
        freeRental.setDbcAIContract(address(dbcAIMock));

        // Fund renter with tokens
        pointToken.transfer(renter, 1_000_000 * 1e18);

        vm.stopPrank();

        // Renter approves FreeRental contract
        vm.prank(renter);
        pointToken.approve(address(freeRental), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════
    //  Helper
    // ═══════════════════════════════════════════════════════

    function _registerMachine(string memory machineId, address owner_) internal {
        vm.prank(admin);
        freeRental.registerMachine(machineId, owner_, PRICE_USD);
    }

    function _rentMachine(string memory machineId, uint256 durationSec, uint256 totalPoint) internal {
        vm.prank(admin);
        freeRental.rentMachine(machineId, renter, durationSec, totalPoint);
    }

    // ═══════════════════════════════════════════════════════
    //  1. registerMachine
    // ═══════════════════════════════════════════════════════

    function test_registerMachine() public {
        uint256 countBefore = freeRental.machineCount();
        _registerMachine(MACHINE_1, machineOwner);
        assertEq(freeRental.machineCount(), countBefore + 1);

        (address owner_, uint256 price_, bool reg_, bool enabled_, bool rented_) = freeRental.getMachineInfo(MACHINE_1);
        assertEq(owner_, machineOwner);
        assertEq(price_, PRICE_USD);
        assertTrue(reg_);
        assertTrue(enabled_);
        assertFalse(rented_);
    }

    // ═══════════════════════════════════════════════════════
    //  2. registerMachine not admin reverts
    // ═══════════════════════════════════════════════════════

    function test_registerMachine_notAdmin_reverts() public {
        vm.prank(nobody);
        vm.expectRevert("not admin");
        freeRental.registerMachine(MACHINE_1, machineOwner, PRICE_USD);
    }

    // ═══════════════════════════════════════════════════════
    //  3. registerMachine duplicate reverts
    // ═══════════════════════════════════════════════════════

    function test_registerMachine_duplicate_reverts() public {
        _registerMachine(MACHINE_1, machineOwner);
        vm.prank(admin);
        vm.expectRevert("already registered");
        freeRental.registerMachine(MACHINE_1, machineOwner, PRICE_USD);
    }

    // ═══════════════════════════════════════════════════════
    //  4. registerMachine zero owner reverts
    // ═══════════════════════════════════════════════════════

    function test_registerMachine_zeroOwner_reverts() public {
        vm.prank(admin);
        vm.expectRevert("zero owner");
        freeRental.registerMachine(MACHINE_1, address(0), PRICE_USD);
    }

    // ═══════════════════════════════════════════════════════
    //  5. removeMachine
    // ═══════════════════════════════════════════════════════

    function test_removeMachine() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 countAfterReg = freeRental.machineCount();

        vm.prank(admin);
        freeRental.removeMachine(MACHINE_1);

        assertEq(freeRental.machineCount(), countAfterReg - 1);
        (,, bool reg_,,) = freeRental.getMachineInfo(MACHINE_1);
        assertFalse(reg_);
    }

    // ═══════════════════════════════════════════════════════
    //  6. removeMachine while rented reverts
    // ═══════════════════════════════════════════════════════

    function test_removeMachine_whileRented_reverts() public {
        _registerMachine(MACHINE_1, machineOwner);
        _rentMachine(MACHINE_1, ONE_HOUR, 1000 * 1e18);

        vm.prank(admin);
        vm.expectRevert("currently rented");
        freeRental.removeMachine(MACHINE_1);
    }

    // ═══════════════════════════════════════════════════════
    //  7. setMachineEnabled
    // ═══════════════════════════════════════════════════════

    function test_setMachineEnabled() public {
        _registerMachine(MACHINE_1, machineOwner);

        vm.prank(admin);
        freeRental.setMachineEnabled(MACHINE_1, false);
        (,,, bool enabled_,) = freeRental.getMachineInfo(MACHINE_1);
        assertFalse(enabled_);

        vm.prank(admin);
        freeRental.setMachineEnabled(MACHINE_1, true);
        (,,, enabled_,) = freeRental.getMachineInfo(MACHINE_1);
        assertTrue(enabled_);
    }

    // ═══════════════════════════════════════════════════════
    //  8. setMachinePrice
    // ═══════════════════════════════════════════════════════

    function test_setMachinePrice() public {
        _registerMachine(MACHINE_1, machineOwner);

        vm.prank(admin);
        freeRental.setMachinePrice(MACHINE_1, 1_000_000);
        (, uint256 price_,,,) = freeRental.getMachineInfo(MACHINE_1);
        assertEq(price_, 1_000_000);
    }

    // ═══════════════════════════════════════════════════════
    //  9. rentMachine
    // ═══════════════════════════════════════════════════════

    function test_rentMachine() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        uint256 renterBalBefore = pointToken.balanceOf(renter);

        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        // Tokens transferred from renter to contract
        assertEq(pointToken.balanceOf(renter), renterBalBefore - totalPoint);
        assertEq(pointToken.balanceOf(address(freeRental)), totalPoint);

        // Machine is now rented
        assertTrue(freeRental.machineIsRented(MACHINE_1));
        assertEq(freeRental.lastRentId(), 1);
    }

    // ═══════════════════════════════════════════════════════
    //  10. rentMachine not available reverts (disabled)
    // ═══════════════════════════════════════════════════════

    function test_rentMachine_notAvailable_reverts() public {
        _registerMachine(MACHINE_1, machineOwner);
        vm.prank(admin);
        freeRental.setMachineEnabled(MACHINE_1, false);

        vm.prank(admin);
        vm.expectRevert("machine not available");
        freeRental.rentMachine(MACHINE_1, renter, ONE_HOUR, 1000 * 1e18);
    }

    // ═══════════════════════════════════════════════════════
    //  11. rentMachine already rented reverts
    // ═══════════════════════════════════════════════════════

    function test_rentMachine_alreadyRented_reverts() public {
        _registerMachine(MACHINE_1, machineOwner);
        _rentMachine(MACHINE_1, ONE_HOUR, 1000 * 1e18);

        vm.prank(admin);
        vm.expectRevert("already rented");
        freeRental.rentMachine(MACHINE_1, renter, ONE_HOUR, 1000 * 1e18);
    }

    // ═══════════════════════════════════════════════════════
    //  12. endRent full duration
    // ═══════════════════════════════════════════════════════

    function test_endRent_fullDuration() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        // ownerPoint = 1250 * 100 / 125 = 1000
        uint256 expectedOwner = totalPoint * 100 / 125;
        uint256 expectedPlatform = totalPoint - expectedOwner;

        uint256 platformBalBefore = pointToken.balanceOf(platformWallet);

        // Warp past end time
        vm.warp(block.timestamp + ONE_HOUR + 1);

        vm.prank(admin);
        freeRental.endRent(MACHINE_1);

        // Owner gets pending income
        assertEq(freeRental.ownerPendingIncome(machineOwner), expectedOwner);
        // Platform gets fee
        assertEq(pointToken.balanceOf(platformWallet) - platformBalBefore, expectedPlatform);
        // Machine no longer rented
        assertFalse(freeRental.machineIsRented(MACHINE_1));
    }

    // ═══════════════════════════════════════════════════════
    //  13. endRent early termination (pro-rata refund)
    // ═══════════════════════════════════════════════════════

    function test_endRent_earlyTermination() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        uint256 renterBalBefore = pointToken.balanceOf(renter);

        // Warp to halfway
        vm.warp(block.timestamp + ONE_HOUR / 2);

        vm.prank(admin);
        freeRental.endRent(MACHINE_1);

        // Renter should get ~50% refund
        uint256 renterBalAfter = pointToken.balanceOf(renter);
        uint256 refund = renterBalAfter - renterBalBefore;

        // usedTotal = 1250e18 * 1800 / 3600 = 625e18
        // refund = 1250e18 - 625e18 = 625e18
        assertEq(refund, 625 * 1e18);
    }

    // ═══════════════════════════════════════════════════════
    //  14. reportFault — slash works
    // ═══════════════════════════════════════════════════════

    function test_reportFault() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        // Warp 30 minutes
        vm.warp(block.timestamp + 1800);

        vm.prank(slashAdmin);
        freeRental.reportFault(MACHINE_1);

        // Rent should be ended
        assertFalse(freeRental.machineIsRented(MACHINE_1));

        // Slash info recorded
        (
            string memory slashMachine,
            address slashRenter,
            uint256 slashAmount,
            uint256 refundAmount,
            uint256 createdAt,
            bool executed
        ) = freeRental.machineId2SlashInfo(MACHINE_1);
        assertTrue(executed);
        assertEq(slashRenter, renter);
        assertGt(slashAmount, 0);
    }

    // ═══════════════════════════════════════════════════════
    //  15. reportFault short rental — max slash capped at ownerPoint
    // ═══════════════════════════════════════════════════════

    function test_reportFault_shortRental_maxSlashCapped() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18; // ownerPoint = 1000e18
        // 1 hour rental
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        // maxSlash24h = ownerPoint * 24 * 3600 / 3600 = ownerPoint * 24 = 24000e18
        // But ownerPoint is only 1000e18, so cap: min(ownerPoint, maxSlash24h) but in the code:
        // if (maxSlash24h > r.ownerPoint) maxSlash24h = r.ownerPoint;
        // For 1h rental: maxSlash24h = 1000e18 * 86400 / 3600 = 24000e18 > 1000e18 -> capped to 1000e18
        // usedOwner at full duration = 1000e18, slashAmount = min(usedOwner, maxSlash24h) = min(1000e18, 1000e18) = 1000e18

        // Warp past end time so full usage
        vm.warp(block.timestamp + ONE_HOUR + 1);

        vm.prank(slashAdmin);
        freeRental.reportFault(MACHINE_1);

        (,, uint256 slashAmount,,,) = freeRental.machineId2SlashInfo(MACHINE_1);
        // ownerPoint = 1000e18, maxSlash capped to ownerPoint for short rental
        uint256 ownerPoint = totalPoint * 100 / 125;
        assertLe(slashAmount, ownerPoint);
    }

    // ═══════════════════════════════════════════════════════
    //  16. reportFault no active rent reverts
    // ═══════════════════════════════════════════════════════

    function test_reportFault_noActiveRent_reverts() public {
        _registerMachine(MACHINE_1, machineOwner);
        // No rent started

        vm.prank(slashAdmin);
        vm.expectRevert("no active rent");
        freeRental.reportFault(MACHINE_1);
    }

    // ═══════════════════════════════════════════════════════
    //  17. notify machine offline triggers fault
    // ═══════════════════════════════════════════════════════

    function test_notify_machineOffline() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        vm.warp(block.timestamp + 1800);

        // Call from dbcAI contract
        vm.prank(address(dbcAIMock));
        bool result = freeRental.notify(FreeRental.NotifyType.MachineOffline, MACHINE_1);
        assertTrue(result);

        // Rent ended
        assertFalse(freeRental.machineIsRented(MACHINE_1));
    }

    // ═══════════════════════════════════════════════════════
    //  18. notify non-rented machine returns true (no penalty)
    // ═══════════════════════════════════════════════════════

    function test_notify_notRented_skips() public {
        _registerMachine(MACHINE_1, machineOwner);

        vm.prank(address(dbcAIMock));
        bool result = freeRental.notify(FreeRental.NotifyType.MachineOffline, MACHINE_1);
        assertTrue(result); // Returns true, no penalty
    }

    // ═══════════════════════════════════════════════════════
    //  19. notify unregistered machine returns false
    // ═══════════════════════════════════════════════════════

    function test_notify_notRegistered_returnsFalse() public {
        vm.prank(address(dbcAIMock));
        bool result = freeRental.notify(FreeRental.NotifyType.MachineOffline, "unregistered_machine");
        assertFalse(result);
    }

    // ═══════════════════════════════════════════════════════
    //  20. notify only dbcAI
    // ═══════════════════════════════════════════════════════

    function test_notify_onlyDbcAI() public {
        vm.prank(nobody);
        vm.expectRevert("only dbcAI");
        freeRental.notify(FreeRental.NotifyType.MachineOffline, MACHINE_1);
    }

    // ═══════════════════════════════════════════════════════
    //  21. claimIncome
    // ═══════════════════════════════════════════════════════

    function test_claimIncome() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        vm.warp(block.timestamp + ONE_HOUR + 1);
        vm.prank(admin);
        freeRental.endRent(MACHINE_1);

        uint256 pending = freeRental.ownerPendingIncome(machineOwner);
        assertGt(pending, 0);

        uint256 balBefore = pointToken.balanceOf(machineOwner);
        vm.prank(machineOwner);
        freeRental.claimIncome();

        assertEq(pointToken.balanceOf(machineOwner), balBefore + pending);
        assertEq(freeRental.ownerPendingIncome(machineOwner), 0);
        assertEq(freeRental.ownerTotalClaimed(machineOwner), pending);
    }

    // ═══════════════════════════════════════════════════════
    //  22. claimIncome no pending reverts
    // ═══════════════════════════════════════════════════════

    function test_claimIncome_noPending_reverts() public {
        vm.prank(nobody);
        vm.expectRevert("no pending income");
        freeRental.claimIncome();
    }

    // ═══════════════════════════════════════════════════════
    //  23. canRent query
    // ═══════════════════════════════════════════════════════

    function test_canRent_query() public {
        // Unregistered -> false
        assertFalse(freeRental.canRent(MACHINE_1));

        // Registered + enabled -> true
        _registerMachine(MACHINE_1, machineOwner);
        assertTrue(freeRental.canRent(MACHINE_1));

        // Disabled -> false
        vm.prank(admin);
        freeRental.setMachineEnabled(MACHINE_1, false);
        assertFalse(freeRental.canRent(MACHINE_1));

        // Re-enabled -> true
        vm.prank(admin);
        freeRental.setMachineEnabled(MACHINE_1, true);
        assertTrue(freeRental.canRent(MACHINE_1));

        // Rented -> false
        _rentMachine(MACHINE_1, ONE_HOUR, 1250 * 1e18);
        assertFalse(freeRental.canRent(MACHINE_1));
    }

    // ═══════════════════════════════════════════════════════
    //  24. getMachineInfo query
    // ═══════════════════════════════════════════════════════

    function test_getMachineInfo_query() public {
        _registerMachine(MACHINE_1, machineOwner);

        (address o, uint256 p, bool r, bool e, bool rented) = freeRental.getMachineInfo(MACHINE_1);
        assertEq(o, machineOwner);
        assertEq(p, PRICE_USD);
        assertTrue(r);
        assertTrue(e);
        assertFalse(rented);
    }

    // ═══════════════════════════════════════════════════════
    //  25. platform fee split (25%)
    // ═══════════════════════════════════════════════════════

    function test_platformFeeSplit() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        vm.warp(block.timestamp + ONE_HOUR + 1);
        uint256 platformBefore = pointToken.balanceOf(platformWallet);

        vm.prank(admin);
        freeRental.endRent(MACHINE_1);

        uint256 platformGot = pointToken.balanceOf(platformWallet) - platformBefore;
        uint256 ownerGot = freeRental.ownerPendingIncome(machineOwner);

        // ownerPoint = 1250 * 100 / 125 = 1000
        // platformPoint = 1250 - 1000 = 250
        assertEq(ownerGot, 1000 * 1e18);
        assertEq(platformGot, 250 * 1e18);

        // Verify 25% fee
        assertEq(platformGot * 100 / ownerGot, 25);
    }

    // ═══════════════════════════════════════════════════════
    //  26. registerMachines batch
    // ═══════════════════════════════════════════════════════

    function test_registerMachines_batch() public {
        string[] memory ids = new string[](3);
        ids[0] = MACHINE_1;
        ids[1] = MACHINE_2;
        ids[2] = MACHINE_3;

        address[] memory owners = new address[](3);
        owners[0] = machineOwner;
        owners[1] = machineOwner;
        owners[2] = machineOwner;

        vm.prank(admin);
        freeRental.registerMachines(ids, owners, PRICE_USD);

        assertEq(freeRental.machineCount(), 3);
        (address o1,,,,) = freeRental.getMachineInfo(MACHINE_1);
        assertEq(o1, machineOwner);
        (address o2,,,,) = freeRental.getMachineInfo(MACHINE_2);
        assertEq(o2, machineOwner);
    }

    // ═══════════════════════════════════════════════════════
    //  27. VERSION
    // ═══════════════════════════════════════════════════════

    function test_VERSION() public view {
        assertEq(freeRental.VERSION(), 4);
    }

    // ═══════════════════════════════════════════════════════
    //  28. registerMachine zero price reverts
    // ═══════════════════════════════════════════════════════

    function test_registerMachine_zeroPrice_reverts() public {
        vm.prank(admin);
        vm.expectRevert("zero price");
        freeRental.registerMachine(MACHINE_1, machineOwner, 0);
    }

    // ═══════════════════════════════════════════════════════
    //  29. endRent no active rent reverts
    // ═══════════════════════════════════════════════════════

    function test_endRent_noActiveRent_reverts() public {
        vm.prank(admin);
        vm.expectRevert("no active rent");
        freeRental.endRent(MACHINE_1);
    }

    // ═══════════════════════════════════════════════════════
    //  30. emergencyEndRent — full refund to renter
    // ═══════════════════════════════════════════════════════

    function test_emergencyEndRent() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        uint256 renterBalBefore = pointToken.balanceOf(renter);
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        vm.warp(block.timestamp + 600); // 10 min in

        vm.prank(deployer); // owner
        freeRental.emergencyEndRent(MACHINE_1);

        // Full refund to renter
        assertEq(pointToken.balanceOf(renter), renterBalBefore);
        assertFalse(freeRental.machineIsRented(MACHINE_1));
    }

    // ═══════════════════════════════════════════════════════
    //  31. emergencyEndRent only owner
    // ═══════════════════════════════════════════════════════

    function test_emergencyEndRent_notOwner_reverts() public {
        _registerMachine(MACHINE_1, machineOwner);
        _rentMachine(MACHINE_1, ONE_HOUR, 1250 * 1e18);

        vm.prank(admin);
        vm.expectRevert();
        freeRental.emergencyEndRent(MACHINE_1);
    }

    // ═══════════════════════════════════════════════════════
    //  32. getRentInfo query
    // ═══════════════════════════════════════════════════════

    function test_getRentInfo() public {
        _registerMachine(MACHINE_1, machineOwner);
        uint256 totalPoint = 1250 * 1e18;
        _rentMachine(MACHINE_1, ONE_HOUR, totalPoint);

        (
            string memory mid,
            address o,
            address r,
            uint256 start,
            uint256 end_,
            uint256 paid,
            bool ended
        ) = freeRental.getRentInfo(1);

        assertEq(keccak256(bytes(mid)), keccak256(bytes(MACHINE_1)));
        assertEq(o, machineOwner);
        assertEq(r, renter);
        assertEq(end_ - start, ONE_HOUR);
        assertEq(paid, totalPoint);
        assertFalse(ended);
    }

    // ═══════════════════════════════════════════════════════
    //  33. getPendingIncome
    // ═══════════════════════════════════════════════════════

    function test_getPendingIncome() public {
        assertEq(freeRental.getPendingIncome(machineOwner), 0);

        _registerMachine(MACHINE_1, machineOwner);
        _rentMachine(MACHINE_1, ONE_HOUR, 1250 * 1e18);
        vm.warp(block.timestamp + ONE_HOUR + 1);
        vm.prank(admin);
        freeRental.endRent(MACHINE_1);

        assertEq(freeRental.getPendingIncome(machineOwner), 1000 * 1e18);
    }

    // ═══════════════════════════════════════════════════════
    //  34. notify non-offline type returns true
    // ═══════════════════════════════════════════════════════

    function test_notify_nonOfflineType_returnsTrue() public {
        vm.prank(address(dbcAIMock));
        bool result = freeRental.notify(FreeRental.NotifyType.MachineOnline, MACHINE_1);
        assertTrue(result);
    }

    // ═══════════════════════════════════════════════════════
    //  35. batch register skips zero address and duplicates
    // ═══════════════════════════════════════════════════════

    function test_registerMachines_batch_skipsInvalid() public {
        // First register MACHINE_1 individually
        _registerMachine(MACHINE_1, machineOwner);

        string[] memory ids = new string[](3);
        ids[0] = MACHINE_1; // duplicate, should skip
        ids[1] = MACHINE_2; // zero address owner, should skip
        ids[2] = MACHINE_3; // valid

        address[] memory owners = new address[](3);
        owners[0] = machineOwner;
        owners[1] = address(0); // zero address
        owners[2] = machineOwner;

        vm.prank(admin);
        freeRental.registerMachines(ids, owners, PRICE_USD);

        // Only MACHINE_3 should be newly registered (MACHINE_1 was already registered, MACHINE_2 skipped)
        assertEq(freeRental.machineCount(), 2); // 1 from first register + 1 from batch
    }

    // ═══════════════════════════════════════════════════════
    //  36. setMachinePrice zero reverts
    // ═══════════════════════════════════════════════════════

    function test_setMachinePrice_zeroPrice_reverts() public {
        _registerMachine(MACHINE_1, machineOwner);

        vm.prank(admin);
        vm.expectRevert("zero price");
        freeRental.setMachinePrice(MACHINE_1, 0);
    }

    // ═══════════════════════════════════════════════════════
    //  37. rentMachine zero duration reverts
    // ═══════════════════════════════════════════════════════

    function test_rentMachine_zeroDuration_reverts() public {
        _registerMachine(MACHINE_1, machineOwner);

        vm.prank(admin);
        vm.expectRevert("zero duration");
        freeRental.rentMachine(MACHINE_1, renter, 0, 1000 * 1e18);
    }

    // ═══════════════════════════════════════════════════════
    //  38. owner can also act as admin
    // ═══════════════════════════════════════════════════════

    function test_ownerCanActAsAdmin() public {
        vm.prank(deployer);
        freeRental.registerMachine(MACHINE_1, machineOwner, PRICE_USD);
        (,, bool reg,,) = freeRental.getMachineInfo(MACHINE_1);
        assertTrue(reg);
    }
}

// ═══════════════════════════════════════════════════════
//  Minimal ERC1967Proxy helper for test deployment
// ═══════════════════════════════════════════════════════

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ERC1967ProxyHelper is ERC1967Proxy {
    constructor(address impl, bytes memory data) ERC1967Proxy(impl, data) {}
}
