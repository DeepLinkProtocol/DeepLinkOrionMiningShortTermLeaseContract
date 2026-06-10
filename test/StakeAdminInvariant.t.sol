// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Rent} from "../src/rent/Rent.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

/// @title v18 stakeAdmin 不变量(状态化模糊)测试
/// @notice 随机序列(extend/warp)下验证: endAt 单调不减 / 其他 StakeInfo 字段恒定 / version 恒=18
contract StakeAdminHandler is Test {
    NFTStaking nft;
    address owner;
    string[] mids;
    mapping(bytes32 => uint256) public initEnd;
    mapping(bytes32 => uint256) public initReserved;
    mapping(bytes32 => uint256) public initCalc;
    mapping(bytes32 => address) public initHolder;
    uint256 public extendCalls;

    constructor(NFTStaking _nft, address _owner, string[] memory _mids) {
        nft = _nft; owner = _owner;
        for (uint256 i = 0; i < _mids.length; i++) {
            mids.push(_mids[i]);
            bytes32 k = keccak256(bytes(_mids[i]));
            (address h, , , uint256 e, uint256 c, uint256 r, , , , , ) = _nft.machineId2StakeInfos(_mids[i]);
            initEnd[k] = e; initReserved[k] = r; initCalc[k] = c; initHolder[k] = h;
        }
    }

    function extend(uint256 idx, uint256 h) public {
        string memory m = mids[idx % mids.length];
        h = bound(h, 2, 4320);
        ( , , , uint256 e, , , , , , , ) = nft.machineId2StakeInfos(m);
        if (block.timestamp >= e) return; // 到期不能延
        vm.prank(owner);
        try nft.adminAddStakeHours(m, h) { extendCalls++; } catch {}
    }

    function rotateAdmin(uint256 a) public {
        address na = address(uint160(bound(a, 0, type(uint160).max)));
        vm.prank(owner);
        nft.setStakeAdmin(na);
    }

    function warp(uint256 dt) public {
        dt = bound(dt, 1, 200 hours);
        vm.warp(block.timestamp + dt);
    }

    function count() external view returns (uint256) { return mids.length; }
    function midAt(uint256 i) external view returns (string memory) { return mids[i]; }
}

contract StakeAdminInvariant is Test {
    Rent public rent;
    NFTStaking public nftStaking;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;
    address owner = address(0x01);
    uint256 constant STAKER_PK = 0xA11CE;
    address stakerAddr;
    StakeAdminHandler handler;

    function setUp() public {
        stakerAddr = vm.addr(STAKER_PK);
        vm.startPrank(owner);
        rewardToken = new Token();
        nftToken = new DLCNode(owner);
        ERC1967Proxy p1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(p1));
        ERC1967Proxy p2 = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(p2));
        NFTStaking(address(p1)).initialize(owner, address(nftToken), address(rewardToken), address(rent), address(dbcAIContract), 1);
        Rent(address(p2)).initialize(owner, address(IPrecompileContract(address(0x11))), address(nftStaking), address(dbcAIContract), address(rewardToken));
        deal(address(rewardToken), address(nftStaking), 180000000 * 1e18);
        nftStaking.setRewardStartAt(block.timestamp);
        address[] memory addrs = new address[](1); addrs[0] = owner;
        nftStaking.setDLCClientWallets(addrs);
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.reportStakingStatus.selector), abi.encode());
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.stopPrank();
        _passHours(1);

        _stake("INV1", 1000 ether, 1000);
        _stake("INV2", 500 ether, 800);

        string[] memory mids = new string[](2);
        mids[0] = "INV1"; mids[1] = "INV2";
        handler = new StakeAdminHandler(nftStaking, owner, mids);
        targetContract(address(handler));
    }

    function _stake(string memory machineId, uint256 reserveAmount, uint256 stakeHours) internal {
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.getMachineInfo.selector),
            abi.encode(stakerAddr, 100, 3500, "NVIDIA GeForce RTX 4060 Ti", 1, "", 1, machineId, 16));
        vm.mockCall(address(nftStaking.dbcAIContract()), abi.encodeWithSelector(IDBCAIContract.getMachineState.selector), abi.encode(true, true));
        vm.startPrank(stakerAddr);
        dealERC1155(address(nftToken), stakerAddr, 1, 1, false);
        deal(address(rewardToken), stakerAddr, 100000 ether);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);
        vm.stopPrank();
        vm.startPrank(owner);
        uint256[] memory t = new uint256[](1); uint256[] memory b = new uint256[](1); t[0] = 1; b[0] = 1;
        nftStaking.stakeV2(stakerAddr, machineId, t, b, stakeHours, false);
        if (reserveAmount > 0) nftStaking.addDLCToStake(machineId, reserveAmount);
        vm.stopPrank();
    }

    function _passHours(uint256 n) internal { vm.warp(vm.getBlockTimestamp() + n * 3600); vm.roll(vm.getBlockNumber() + n * 600); }

    // ── 不变量 ──
    function invariant_endAt_never_decreases() public view {
        for (uint256 i = 0; i < handler.count(); i++) {
            string memory m = handler.midAt(i);
            bytes32 k = keccak256(bytes(m));
            ( , , , uint256 e, , , , , , , ) = nftStaking.machineId2StakeInfos(m);
            assertGe(e, handler.initEnd(k), "endAt monotonic non-decreasing");
        }
    }

    function invariant_other_fields_preserved() public view {
        for (uint256 i = 0; i < handler.count(); i++) {
            string memory m = handler.midAt(i);
            bytes32 k = keccak256(bytes(m));
            ( address h, , , , uint256 c, uint256 r, , , , , ) = nftStaking.machineId2StakeInfos(m);
            assertEq(h, handler.initHolder(k), "holder preserved");
            assertEq(r, handler.initReserved(k), "reservedAmount preserved");
            assertEq(c, handler.initCalc(k), "calcPoint preserved");
        }
    }

    function invariant_version_is_18() public view {
        assertEq(nftStaking.version(), 18);
    }
}
