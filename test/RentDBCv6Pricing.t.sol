// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// [v6 2026-07-09] RentDBC 定价重设计专项测试：base 60%→5% + extra 每机矿工自设 + 全局封顶（镜像 DLC）。
import {Test} from "forge-std/Test.sol";
import {RentDBC} from "../src/rent/RentDBC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import {DBCStakingContractMock} from "./MockDBCAIContract.sol";

contract RentDBCv6PricingTest is Test {
    RentDBC public rentDbc;
    Token public dbc;
    Token public dlp;
    DBCStakingContractMock public dbcAI;

    address owner = address(0x01);
    address platform = address(0x100);
    address priceSetter = address(0x101);
    address payerWallet = address(0xCAFE); // rentAdmin
    address stranger = address(0xBAD);
    string constant MID = "machineId";   // mock calcPoint=100000
    string constant MID2 = "machineId2"; // 另一台
    uint256 constant PRICE = 5000; // DBC/USD 6dec
    uint256 constant CAP = 1666;   // $0.1/hr = 100000/60 ≈ 1666 (USD 6dec/min)

    function setUp() public {
        vm.startPrank(owner);
        dbc = new Token();
        dbc.initialize(owner);
        dlp = new Token();
        dlp.initialize(owner);
        dbcAI = new DBCStakingContractMock();

        ERC1967Proxy proxy = new ERC1967Proxy(address(new RentDBC()), "");
        rentDbc = RentDBC(address(proxy));
        rentDbc.initialize(owner, address(dbcAI), address(dbc), address(dlp), platform);
        rentDbc.setPriceSetter(priceSetter);
        rentDbc.setPlatformFeeRate(10);
        address[] memory admins = new address[](1);
        admins[0] = payerWallet;
        rentDbc.setRentAdmins(admins, true);
        vm.stopPrank();

        vm.prank(priceSetter);
        rentDbc.setTokenPriceInUSD(PRICE);
    }

    // ── extra 封顶未设时禁止设价 ──
    function test_v6_SetExtra_BeforeCapSet_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(RentDBC.MaxRentExtraFeeNotSet.selector);
        rentDbc.setExtraRentFeeByAdmin(MID, 1000);
    }

    // ── 设封顶后, admin 设价 ≤ 封顶成功, 每机独立读回 ──
    function test_v6_SetExtraPerMachine_Independent() public {
        vm.startPrank(owner);
        rentDbc.setMaxExtraRentFeeInUSDPerMinutes(CAP);
        rentDbc.setExtraRentFeeByAdmin(MID, 1000);
        rentDbc.setExtraRentFeeByAdmin(MID2, 500);
        vm.stopPrank();
        assertEq(rentDbc.getMachineExtraRentFee(MID), 1000, "MID rate");
        assertEq(rentDbc.getMachineExtraRentFee(MID2), 500, "MID2 rate");
        // 未设的机器 extra = 0
        assertEq(rentDbc.getMachineExtraRentFee("unset"), 0, "unset=0");
        // getRentFees 的 extra 随每机费率不同
        (,, uint256 extra1) = rentDbc.getRentFees(MID, 1 hours);
        (,, uint256 extra2) = rentDbc.getRentFees(MID2, 1 hours);
        assertGt(extra1, extra2, "MID extra > MID2");
        assertEq(extra1, uint256(1000) * (3600 / 60) * 1e15, "extra1 formula");
        assertEq(extra2, uint256(500) * (3600 / 60) * 1e15, "extra2 formula");
    }

    // ── 超封顶设价 revert ──
    function test_v6_SetExtra_OverCap_Reverts() public {
        vm.startPrank(owner);
        rentDbc.setMaxExtraRentFeeInUSDPerMinutes(CAP);
        vm.expectRevert(abi.encodeWithSelector(RentDBC.CanNotOverExtraFeeLimit.selector, CAP));
        rentDbc.setExtraRentFeeByAdmin(MID, CAP + 1);
        vm.stopPrank();
    }

    // ── 恰好等于封顶允许 ──
    function test_v6_SetExtra_AtCap_Ok() public {
        vm.startPrank(owner);
        rentDbc.setMaxExtraRentFeeInUSDPerMinutes(CAP);
        rentDbc.setExtraRentFeeByAdmin(MID, CAP);
        vm.stopPrank();
        assertEq(rentDbc.getMachineExtraRentFee(MID), CAP, "at cap ok");
    }

    // ── rentAdmin 也能设价; 非 admin/owner revert ──
    function test_v6_SetExtra_ByRentAdmin_Ok_StrangerReverts() public {
        vm.prank(owner);
        rentDbc.setMaxExtraRentFeeInUSDPerMinutes(CAP);
        // rentAdmin 代写 OK
        vm.prank(payerWallet);
        rentDbc.setExtraRentFeeByAdmin(MID, 800);
        assertEq(rentDbc.getMachineExtraRentFee(MID), 800, "rentAdmin set");
        // 陌生人 revert
        vm.prank(stranger);
        vm.expectRevert(RentDBC.NotRentAdmin.selector);
        rentDbc.setExtraRentFeeByAdmin(MID, 100);
    }

    // ── 仅 owner 能设封顶 ──
    function test_v6_SetMaxCap_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        rentDbc.setMaxExtraRentFeeInUSDPerMinutes(CAP);
    }

    // ── 批量设价 (≤100), 超封顶 revert ──
    function test_v6_SetExtraBatch() public {
        vm.startPrank(owner);
        rentDbc.setMaxExtraRentFeeInUSDPerMinutes(CAP);
        string[] memory ids = new string[](2);
        ids[0] = MID;
        ids[1] = MID2;
        rentDbc.setExtraRentFeeByAdminBatch(ids, 700);
        vm.stopPrank();
        assertEq(rentDbc.getMachineExtraRentFee(MID), 700, "batch MID");
        assertEq(rentDbc.getMachineExtraRentFee(MID2), 700, "batch MID2");
        // 批量超封顶 revert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RentDBC.CanNotOverExtraFeeLimit.selector, CAP));
        rentDbc.setExtraRentFeeByAdminBatch(ids, CAP + 1);
    }

    // ── base 5%: 相对旧 60% 应为 5/60；这里锚定 5% 公式直接计算 ──
    function test_v6_Base5Percent_Formula() public view {
        // base(USD 6dec) = 1e6 * 3600 * 100000 * 5080 * 5 / 100 / 30/24/60/60 / (1e4*1e4)
        uint256 expectedUSD = uint256(1e6) * 3600 * 100000 * 5080 * 5 / 100 / 30 / 24 / 60 / 60 / (10000 * 10000);
        uint256 gotUSD = rentDbc.getBaseMachinePriceInUSD(MID, 1 hours);
        assertEq(gotUSD, expectedUSD, "base 5% USD formula");
        assertGt(gotUSD, 0, "base>0 at realistic calcPoint");
        // base DBC = 1e18 * USD / price (markup=FACTOR 默认不加成)
        uint256 gotDBC = rentDbc.getBaseMachinePrice(MID, 1 hours);
        assertEq(gotDBC, 1e18 * expectedUSD / PRICE, "base DBC");
    }

    // ── 未设 extra 的机器: getRentFees extra=0, 但 base/platform 仍算 (租客只付 base+平台) ──
    function test_v6_UnsetExtra_ZeroMinerShare() public {
        vm.prank(owner);
        rentDbc.setMaxExtraRentFeeInUSDPerMinutes(CAP);
        // MID 未设 extra
        (uint256 base, uint256 plat, uint256 extra) = rentDbc.getRentFees(MID, 1 hours);
        assertEq(extra, 0, "unset extra=0 (miner share 0 until set)");
        assertGt(base, 0, "base>0");
        assertGt(plat, 0, "platform>0");
    }
}
