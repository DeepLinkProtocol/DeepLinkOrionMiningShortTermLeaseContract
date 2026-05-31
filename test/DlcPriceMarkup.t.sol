// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RentTest} from "./Rent.t.sol";

/// @notice v13 DLC 价格加成 (+6%) 专项测试。
/// 验证：DLC 计价 (getBaseMachinePrice / getExtraRentFee / 进而 getMachinePrice) 按 markup 精确上调，
/// 而积分计价 (getBaseMachinePriceInUSD / getExtraRentFeeInUSD / getExtraRentFeeInPoint) 完全不受影响。
/// 复用 RentTest 的 setUp + stakeByOwner helper (calcPoint=100, oracle dlcPrice=100)。
contract DlcPriceMarkupTest is RentTest {
    uint256 constant FACTOR = 10000;

    function _stakeOne(string memory machineId) internal {
        // reserveAmount=0, stakeHours=100, isPersonal=true → calcPoint=100
        stakeByOwner(machineId, 0, 100, true);
    }

    /// 默认 (升级后未 set) dlcPriceMarkupBps==0 → getter 当作 FACTOR(不涨)，DLC 价格保持原值
    function test_default_zero_is_no_markup() public {
        string memory machineId = "markupZero";
        _stakeOne(machineId);

        assertEq(rent.dlcPriceMarkupBps(), 0, "default storage must be 0 after deploy");

        // markup=0 fallback 到 FACTOR：getBaseMachinePrice 应等于 baseUSD/dlcPrice 原值，不归零、不放大
        uint256 baseUsd = rent.getBaseMachinePriceInUSD(machineId, 3600);
        assertGt(baseUsd, 0, "base USD must be non-zero (calcPoint=100)");
        uint256 baseDlc = rent.getBaseMachinePrice(machineId, 3600);
        // baseDlc = 1e18 * baseUsd / dlcPrice(100) * FACTOR / FACTOR
        assertEq(baseDlc, 1e18 * baseUsd / 100, "markup=0 must behave as no-markup (not zero)");
    }

    /// 核心：set 10600 → DLC base/extra 精确 +6%，而积分 USD/Point 计价完全不变
    function test_markup_6pct_dlc_only() public {
        string memory machineId = "markup6pct";
        _stakeOne(machineId);

        // ---- 涨价前 (markup=0 → 不涨) ----
        uint256 baseUsdBefore = rent.getBaseMachinePriceInUSD(machineId, 3600);
        uint256 extraUsdBefore = rent.getExtraRentFeeInUSD(machineId, 3600);
        uint256 extraPointBefore = rent.getExtraRentFeeInPoint(machineId, 3600);
        uint256 baseDlcBefore = rent.getBaseMachinePrice(machineId, 3600);
        uint256 extraDlcBefore = rent.getExtraRentFee(machineId, 3600);

        // ---- owner 设置 +6% ----
        vm.prank(owner);
        rent.setDlcPriceMarkupBps(10600);
        assertEq(rent.dlcPriceMarkupBps(), 10600, "markup stored");

        // ---- 涨价后 ----
        uint256 baseUsdAfter = rent.getBaseMachinePriceInUSD(machineId, 3600);
        uint256 extraUsdAfter = rent.getExtraRentFeeInUSD(machineId, 3600);
        uint256 extraPointAfter = rent.getExtraRentFeeInPoint(machineId, 3600);
        uint256 baseDlcAfter = rent.getBaseMachinePrice(machineId, 3600);
        uint256 extraDlcAfter = rent.getExtraRentFee(machineId, 3600);

        // 积分路径：USD / Point 计价完全不变 (P0 — 积分零影响)
        assertEq(baseUsdAfter, baseUsdBefore, "USD base MUST NOT change (point path)");
        assertEq(extraUsdAfter, extraUsdBefore, "USD extra MUST NOT change (point path)");
        assertEq(extraPointAfter, extraPointBefore, "Point extra MUST NOT change (point path)");

        // DLC 路径：精确 +6%
        assertEq(baseDlcAfter, baseDlcBefore * 10600 / FACTOR, "DLC base must be +6%");
        // extra 可能为 0 (矿工未设 extraRentFee)，仅在非零时校验比例
        if (extraDlcBefore > 0) {
            assertEq(extraDlcAfter, extraDlcBefore * 10600 / FACTOR, "DLC extra must be +6%");
        }
    }

    /// setter 权限：非 owner 调用必须 revert
    function test_setter_onlyOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        rent.setDlcPriceMarkupBps(10600);
    }

    /// setter 范围：[FACTOR, 2*FACTOR] 之外必须 revert，边界值可用
    function test_setter_range() public {
        vm.startPrank(owner);

        vm.expectRevert(bytes("markup out of range"));
        rent.setDlcPriceMarkupBps(FACTOR - 1); // 9999 < 100% 拒绝

        vm.expectRevert(bytes("markup out of range"));
        rent.setDlcPriceMarkupBps(2 * FACTOR + 1); // 20001 > 200% 拒绝

        rent.setDlcPriceMarkupBps(FACTOR); // 10000 = 不涨，合法
        assertEq(rent.dlcPriceMarkupBps(), FACTOR);

        rent.setDlcPriceMarkupBps(2 * FACTOR); // 20000 = 翻倍，合法
        assertEq(rent.dlcPriceMarkupBps(), 2 * FACTOR);

        vm.stopPrank();
    }

    /// markup=FACTOR(显式设不涨) 与 markup=0(默认不涨) 行为一致
    function test_explicit_factor_equals_default() public {
        string memory machineId = "markupFactor";
        _stakeOne(machineId);

        uint256 baseDefault = rent.getBaseMachinePrice(machineId, 3600);

        vm.prank(owner);
        rent.setDlcPriceMarkupBps(FACTOR);
        uint256 baseExplicit = rent.getBaseMachinePrice(machineId, 3600);

        assertEq(baseExplicit, baseDefault, "explicit FACTOR must equal default-0 behavior");
    }
}
