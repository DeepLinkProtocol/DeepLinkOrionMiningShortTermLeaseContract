// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
//
//import "./interface/IStateContract.sol";
//import "./interface/IRewardToken.sol";
//import "./interface/IRentContract.sol";
//import "./interface/IDBCAIContract.sol";
//import "./interface/ITool.sol";
//import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
//import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
//import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
//
//contract OwnerManager is OwnableUpgradeable, UUPSUpgradeable {
//    IStateContract public stateContract;
//    IRentContract public rentContract;
//    IDBCAIContract public dbcAIContract;
//    ITool public toolContract;
//
//    IERC721 public nftToken;
//    IRewardToken public rewardToken;
//
//    uint256 public rewardStartGPUThreshold;
//    uint256 public rewardStartAtTimestamp;
//
//    address public dlcClientWalletAddress;
//    address public canUpgradeAddress;
//
//    modifier onlyRentContractOrThis() {
//        require(
//            msg.sender == address(rentContract) || msg.sender == address(this),
//            "only rent contract or this can call this function"
//        );
//        _;
//    }
//
//    modifier onlyRentContract() {
//        require(msg.sender == address(rentContract), "only rent contract can call this function");
//        _;
//    }
//
//    function setToolContract(ITool _toolContract) internal onlyOwner {
//        toolContract = _toolContract;
//    }
//
//
//    function setThreshold(uint256 _threshold) public onlyOwner {
//        rewardStartGPUThreshold = _threshold;
//    }
//
//    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
//        require(newImplementation != address(0), "new implementation is the zero address");
//        require(msg.sender == canUpgradeAddress, "only canUpgradeAddress can authorize upgrade");
//    }
//
//    function setUpgradeAddress(address addr) external onlyOwner {
//        canUpgradeAddress = addr;
//    }
//
//    function requestUpgradeAddress(address addr) external pure returns (bytes memory) {
//        bytes memory data = abi.encodeWithSignature("setUpgradeAddress(address)", addr);
//        return data;
//    }
//
//    function setStateContract(address _stateContract) external onlyOwner {
//        stateContract = IStateContract(_stateContract);
//    }
//
//    function setRewardToken(address token) external onlyOwner {
//        rewardToken = IRewardToken(token);
//    }
//
//    function setRentContract(address _rentContract) external onlyOwner {
//        rentContract = IRentContract(_rentContract);
//    }
//
//    function setNftToken(address token) external onlyOwner {
//        nftToken = IERC721(token);
//    }
//
//    function setRewardStartAt(uint256 timestamp) external onlyOwner {
//        require(timestamp >= block.timestamp, "time must be greater than current block number");
//        rewardStartAtTimestamp = timestamp;
//    }
//
//    function setDLCClientWallet(address addr) external onlyOwner {
//        dlcClientWalletAddress = addr;
//    }
//
//    function setDBCAIContract(address addr) external onlyOwner {
//        dbcAIContract = IDBCAIContract(addr);
//    }
//}
