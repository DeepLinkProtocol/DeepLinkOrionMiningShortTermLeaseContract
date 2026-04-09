// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {Rent} from "../src/rent/Rent.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";

/// @notice Mock dbcAI that tracks registration state
contract TrackingDbcAI is IDBCAIContract {
    mapping(string => bool) public registered;

    function reportStakingStatus(
        string calldata, NFTStaking.StakingType, string calldata machineId, uint256, bool isStake
    ) external {
        registered[machineId] = isStake;
    }

    function getMachineState(string calldata machineId, string calldata, NFTStaking.StakingType)
        external view returns (bool, bool)
    {
        return (false, registered[machineId]);
    }

    function getMachineInfo(string calldata, bool)
        external pure returns (address, uint256, uint256, string memory, uint256, string memory, uint256, string memory, uint256)
    {
        return (address(0), 100, 0, "", 0, "", 1, "", 32);
    }

    function freeGpuAmount(string calldata) external pure returns (uint256) { return 1; }
}

contract ForceUnregisterDbcAITest is Test {
    NFTStaking public nftStaking;
    Rent public rent;
    TrackingDbcAI public dbcAI;
    Token public rewardToken;
    DLCNode public nftToken;

    address owner = address(0x01);
    address staker = address(0x06);

    function setUp() public {
        vm.startPrank(owner);

        rewardToken = new Token();
        nftToken = new DLCNode(owner);
        dbcAI = new TrackingDbcAI();

        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new NFTStaking()), "");
        nftStaking = NFTStaking(address(proxy1));
        ERC1967Proxy proxy2 = new ERC1967Proxy(address(new Rent()), "");
        rent = Rent(address(proxy2));

        nftStaking.initialize(
            owner, address(nftToken), address(rewardToken), address(rent), address(dbcAI), 1
        );
        rent.initialize(
            owner, address(0x11), address(nftStaking), address(dbcAI), address(rewardToken)
        );

        deal(address(rewardToken), address(nftStaking), 180_000_000 * 1e18);
        nftStaking.setRewardStartAt(block.timestamp);

        address[] memory dlcWallets = new address[](1);
        dlcWallets[0] = owner;
        nftStaking.setDLCClientWallets(dlcWallets);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════════════
    //  forceUnregisterDbcAI 测试
    // ══════════════════════════════════════════════════════════

    function test_forceUnregisterDbcAI_success() public {
        // 先手动注册机器到 dbcAI
        dbcAI.reportStakingStatus("DeepLinkEVM", NFTStaking.StakingType.ShortTerm, "machine1", 1, true);
        assertTrue(dbcAI.registered("machine1"), "should be registered before");

        // owner 调 forceUnregisterDbcAI
        vm.prank(owner);
        nftStaking.forceUnregisterDbcAI("machine1");

        // 验证 dbcAI 注册状态已清除
        assertFalse(dbcAI.registered("machine1"), "should be unregistered after");
    }

    function test_forceUnregisterDbcAI_onlyOwner() public {
        dbcAI.reportStakingStatus("DeepLinkEVM", NFTStaking.StakingType.ShortTerm, "machine1", 1, true);

        // 非 owner 调用应该 revert
        vm.prank(address(0x99));
        vm.expectRevert();
        nftStaking.forceUnregisterDbcAI("machine1");

        // 注册状态不变
        assertTrue(dbcAI.registered("machine1"), "should still be registered");
    }

    function test_forceUnregisterDbcAI_alreadyUnregistered() public {
        // 未注册的机器也能调（幂等），dbcAI.reportStakingStatus(false) 不会 revert
        vm.prank(owner);
        nftStaking.forceUnregisterDbcAI("nonexistent_machine");
        // 不 revert 就算通过
        assertFalse(dbcAI.registered("nonexistent_machine"));
    }

    function test_forceUnregisterDbcAI_batchTenMachines() public {
        // 模拟 10 台机器批量注销
        string[10] memory mids = [
            "machine_001", "machine_002", "machine_003", "machine_004", "machine_005",
            "machine_006", "machine_007", "machine_008", "machine_009", "machine_010"
        ];

        // 注册 10 台
        for (uint i = 0; i < 10; i++) {
            dbcAI.reportStakingStatus("DeepLinkEVM", NFTStaking.StakingType.ShortTerm, mids[i], 1, true);
            assertTrue(dbcAI.registered(mids[i]));
        }

        // 批量注销
        vm.startPrank(owner);
        for (uint i = 0; i < 10; i++) {
            nftStaking.forceUnregisterDbcAI(mids[i]);
        }
        vm.stopPrank();

        // 验证全部注销
        for (uint i = 0; i < 10; i++) {
            assertFalse(dbcAI.registered(mids[i]), "machine should be unregistered");
        }
    }
}
