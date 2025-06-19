// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/IStakingContract.sol";
import "../interface/IRewardToken.sol";
import "../interface/IRentContract.sol";
import "../interface/IPrecompileContract.sol";
import "forge-std/console.sol";
import "../interface/IDBCAIContract.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IOracle.sol";

/// @custom:oz-upgrades-from OldRent
contract Rent is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint8 public constant SECONDS_PER_BLOCK = 6;
    uint256 public constant REPORT_RESERVE_AMOUNT = 10_000 ether;
    uint256 public constant SLASH_AMOUNT = 10_000 ether;
    uint256 public constant ONE_CALC_POINT_USD_VALUE_PER_MONTH = 5_080;
    uint256 public constant FACTOR = 10_000;
    uint256 public constant USD_DECIMALS = 1_000_000;

    IRewardToken public feeToken;
    IPrecompileContract public precompileContract;
    IStakingContract public stakingContract;
    IDBCAIContract public dbcAIContract;

    address public canUpgradeAddress;
    uint256 public lastRentId;
    uint256 public totalBurnedAmount;
    uint8 public voteThreshold;
    bool public registered;
    RentGPUInfo public rentGPUInfo;

    enum SlashType {
        Offline,
        RenterReport
    }

    enum NotifyType {
        ContractRegister,
        MachineRegister,
        MachineUnregister,
        MachineOnline,
        MachineOffline
    }

    enum Vote {
        None,
        Yes,
        No,
        Finished
    }

    struct RentInfo {
        address stakeHolder;
        string machineId;
        uint256 rentStatTime;
        uint256 rentEndTime;
        address renter;
    }

    struct BurnedDetail {
        uint256 rentId;
        uint256 burnTime;
        uint256 burnDLCAmount;
        address renter;
    }

    struct BurnedInfo {
        BurnedDetail[] details;
        uint256 totalBurnedAmount;
    }

    struct SlashInfo {
        address stakeHolder;
        string machineId;
        uint256 slashAmount;
        uint256 rentStartAtTimestamp;
        uint256 rentEndAtTimestamp;
        uint256 rentedDurationSeconds;
        address renter;
        SlashType slashType;
        uint256 createdAt;
        bool paid;
    }

    struct RentGPUInfo {
        uint256 rentedGPUCount;
        uint256 rentingGPUCount;
    }

    address[] public adminsToApprove;
    string[] public pendingSlashMachineIds;

    mapping(uint256 => RentInfo) public rentId2RentInfo;
    mapping(string => uint256) public machineId2RentId;
    mapping(address => uint256[]) public renter2RentIds;
    mapping(string => BurnedInfo) public machineId2BurnedInfo;
    mapping(string => SlashInfo) public machineId2SlashInfo;
    mapping(string => mapping(address => Vote)) public pendingSlashMachineId2ApprovedAdmins;
    mapping(string => uint8) public pendingSlashMachineId2ApprovedCount;
    mapping(string => uint8) public pendingSlashMachineId2RefuseCount;
    mapping(address => uint256) public stakeHolder2RentFee;
    mapping(address => RentGPUInfo) public stakeHolder2RentGPUInfo;
    mapping(string => uint256) public machineId2LastRentEndBlock;
    mapping(string => SlashInfo[]) public machineId2SlashInfos;

    struct FeeInfo {
        uint256 baseFee;
        uint256 extraFee;
        uint256 platformFee;
    }

    IOracle public oracle;
    mapping(uint256 => FeeInfo) public rentId2FeeInfoInDLC;
    mapping(string => bool) public rentWhitelist;
    mapping(address => bool) public adminsToSetRentWhiteList;
    mapping(string => bool) public machine2ProxyRented;

    event RentMachine(
        address indexed machineOnwer,
        uint256 rentId,
        string machineId,
        uint256 rentEndTime,
        address renter,
        uint256 rentFee
    );
    event RenewRent(
        address indexed machineOnwer,
        string machineId,
        uint256 rentId,
        uint256 additionalRentSeconds,
        uint256 additionalRentFee,
        address renter
    );
    event ExtraRentFeeTransfer(address indexed machineOnwer, uint256 rentId, uint256 amount);
    event EndRentMachine(address machineOnwer, uint256 rentId, string machineId, uint256 rentEndTime, address renter);
    event ReportMachineFault(uint256 rentId, string machineId, address reporter);
    event BurnedFee(
        string machineId, uint256 rentId, uint256 burnTime, uint256 burnDLCAmount, address renter, uint8 rentGpuCount
    );
    event PayBackFee(string machineId, uint256 rentId, address renter, uint256 amount);
    event PayToContractOnRent(uint256 rentId, address renter, uint256 totalRentFee);
    event RentFee(uint256 rentId, address renter, uint256 baseRentFee, uint256 extraRentFee, uint256 platformFee);

    event RenterPayExtraRentFee(uint256 rentId, address renter, uint256 amount);
    event ApprovedReport(string machineId, address admin);
    event RefusedReport(string machineId, address admin);
    event ExecuteReport(string machineId, Vote vote);
    event MachineRegister(string machineId, uint256 calcPoint);
    event MachineUnregister(string machineId, uint256 calcPoint);
    event PaidSlash(string machineId);
    event SlashMachineOnOffline(
        address indexed stakeHolder,
        string machineId,
        address indexed renter,
        uint256 slashAmount,
        uint256 rentStartAt,
        uint256 rentEndAt,
        SlashType slashType
    );
    event RemoveCalcPointOnOffline(string machineId);
    event AddCalcPointOnline(string machineId);

    event AddBackCalcPointOnOnline(string machineId, uint256 calcPoint);
    event PlatformFeeTransfer(address indexed machineOnwer, uint256 rentId, uint256 amount);

    error NotApproveAdmin();
    error ZeroCalcPoint();
    error CallerNotStakingContract();
    error ZeroAddress();
    error CanNotUpgrade(address);
    error CountOfApproveAdminsShouldBeFive();
    error ElementNotFound();
    error uint256Overflow();
    error InvalidRentDuration(uint256 rentDuration);
    error MachineCanNotRent();
    error RentDurationTooLong(uint256 rentDuration, uint256 maxRentDuration);
    error RenTimeCannotOverMachineUnstakeTime();
    error MachineCanNotRentWithin100BlocksAfterLastRent();
    error BalanceNotEnough();
    error RentEnd();
    error RentNotEnd();
    error NotRenter();
    error RentingNotExist();
    error MachineNotRented();
    error ReserveAmountForReportShouldBe10000();
    error ReportedMachineNotFound();
    error VoteFinished();
    error NotDBCAIContract();
    error RewardNotStart();
    error NotValidMachineId();
    error RenterAndPayerIsSame();
    error ProxyRentCanNotEndByRenter();
    error NotProxyRentingMachine();

    modifier onlyApproveAdmins() {
        bool found = false;
        for (uint8 i = 0; i < adminsToApprove.length; i++) {
            if (msg.sender == adminsToApprove[i]) {
                found = true;
                break;
            }
        }
        require(found, NotApproveAdmin());
        _;
    }

    modifier onlyStakingContract() {
        require(msg.sender == address(stakingContract), CallerNotStakingContract());
        _;
    }

    modifier onlyDBCAIContract() {
        require(msg.sender == address(dbcAIContract), NotDBCAIContract());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _precompileContract,
        address _stakingContract,
        address _dbcAIContract,
        address _feeToken
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
        feeToken = IRewardToken(_feeToken);
        precompileContract = IPrecompileContract(_precompileContract);
        stakingContract = IStakingContract(_stakingContract);
        dbcAIContract = IDBCAIContract(_dbcAIContract);
        voteThreshold = 3;
        canUpgradeAddress = msg.sender;
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(newImplementation != address(0), ZeroAddress());
        require(msg.sender == canUpgradeAddress, CanNotUpgrade(msg.sender));
    }

    function setCanUpgradeAddress(address addr) external onlyOwner {
        canUpgradeAddress = addr;
    }

    function setDBCAIContract(address addr) external onlyOwner {
        dbcAIContract = IDBCAIContract(addr);
    }

    function setOracle(address addr) external onlyOwner {
        oracle = IOracle(addr);
    }

    function setAdminsToApproveMachineFaultReporting(address[] calldata admins) external onlyOwner {
        require(admins.length == 5, CountOfApproveAdminsShouldBeFive());
        adminsToApprove = admins;
    }

    function setFeeToken(address _feeToken) external onlyOwner {
        require(_feeToken != address(0x0), ZeroAddress());
        feeToken = IRewardToken(_feeToken);
    }

    function setStakingContract(address addr) external onlyOwner {
        stakingContract = IStakingContract(addr);
    }

    function setPrecompileContract(address _precompileContract) external onlyOwner {
        require(_precompileContract != address(0x0), ZeroAddress());
        precompileContract = IPrecompileContract(_precompileContract);
    }

    function findUintIndex(uint256[] memory arr, uint256 v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == v) {
                return i;
            }
        }
        revert ElementNotFound();
    }

    function removeValueOfUintArray(uint256 v, uint256[] storage arr) internal {
        uint256 index = findUintIndex(arr, v);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function findStringIndex(string[] memory arr, string memory v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (keccak256(abi.encodePacked(arr[i])) == keccak256(abi.encodePacked(v))) {
                return i;
            }
        }
        revert ElementNotFound();
    }

    function removeValueOfStringArray(string memory addr, string[] storage arr) internal {
        uint256 index = findStringIndex(arr, addr);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function getNextRentId() internal returns (uint256) {
        require(lastRentId < type(uint256).max, uint256Overflow());
        lastRentId += 1;
        return lastRentId;
    }

    function canRent(string calldata machineId) public view returns (bool) {
        if (!inRentWhiteList(machineId)) {
            return false;
        }
        if (isRented(machineId)) {
            return false;
        }
        if (!stakingContract.isStaking(machineId)) {
            return false;
        }

        if (stakingContract.machineIsBlocked(machineId)) {
            return false;
        }

        if (stakingContract.isStakingButOffline(machineId)) {
            return false;
        }

        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        if (rewardEndAt == stakingContract.getRewardDuration()) {
            return false;
        }

        (, uint256 calcPoint,, uint256 endAtTimestamp, uint256 nextRenterCanRentAt,, bool isOnline, bool isRegistered) =
            stakingContract.getMachineInfo(machineId);
        if (!isOnline || !isRegistered || isRented(machineId) || calcPoint == 0) {
            return false;
        }

        if (nextRenterCanRentAt > block.timestamp || nextRenterCanRentAt == 0) {
            // not reach the start rent block number yet
            return false;
        }
        if (endAtTimestamp > 0) {
            return endAtTimestamp > block.timestamp && endAtTimestamp - block.timestamp > 1 hours;
        }

        return endAtTimestamp == 0;
    }

    function getMachineInfo(string memory machineId)
        public
        view
        returns (uint256 availableRentHours, uint256 reservedAmount, uint256 rentFeePerHour)
    {
        (,,, uint256 endAt,, uint256 _reservedAmount,,) = stakingContract.getMachineInfo(machineId);
        uint256 rentFee = getMachinePrice(machineId, 1 hours / SECONDS_PER_BLOCK);
        if (isRented(machineId)) {
            return (0, _reservedAmount, rentFee);
        }

        return (endAt - block.timestamp / 1 hours, _reservedAmount, rentFee);
    }

    function getMachinePrice(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        uint256 baseMachinePrice = getBaseMachinePrice(machineId, rentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, rentSeconds);
        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);
        uint256 platformFee = (baseMachinePrice + extraRentFee) * platformFeeRate / 100;
        return baseMachinePrice + extraRentFee + platformFee;
    }

    function getBaseMachinePrice(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        (, uint256 calcPointInFact,,,,,,,) = dbcAIContract.getMachineInfo(machineId, true);
        require(calcPointInFact > 0, ZeroCalcPoint());

        // calcPont factor : 10000 ; ONE_CALC_POINT_USD_VALUE_PER_MONTH factor: 10000
        uint256 totalFactor = FACTOR * FACTOR;
        uint256 dlcUSDPrice = oracle.getTokenPriceInUSD(10, address(feeToken));

        uint256 rentFeeUSD = USD_DECIMALS * rentSeconds * calcPointInFact * ONE_CALC_POINT_USD_VALUE_PER_MONTH / 30 / 24
            / 60 / 60 / totalFactor;
        rentFeeUSD = rentFeeUSD * 6 / 10; // 60% of the total rent fee
        uint256 baseRentFeeUSD = 1e18 * rentFeeUSD / dlcUSDPrice;
        return baseRentFeeUSD;
    }

    function getExtraRentFee(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        uint256 rentMinutes = rentSeconds / 60;

        uint256 fee = stakingContract.getMachineExtraRentFee(machineId) * rentMinutes;
        if (fee == 0) {
            return 0;
        }
        uint256 dlcUSDPrice = oracle.getTokenPriceInUSD(10, address(feeToken));
        uint256 baseRentFeeUSD = 1e18 * fee / dlcUSDPrice;
        return baseRentFeeUSD;
    }

    function inRentWhiteList(string calldata machineId) public view returns (bool) {
        //        bool valid = keccak256(abi.encodePacked(machineId))
        //            == keccak256(abi.encodePacked("224e55bfa6bfde34c66c307428aa6cb883c12100f8782fea0c5e0f0ccdfa87f9"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("f2a12613c18c14722e7e90049064b7769a7653a0dfa572fc5835136cb91aabe3"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("2dd9d41711289e099a9d04ae122fc68666487138559261ac5e4918594e7a2752"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("4d7462c0f558cf058e1ec1c8c374f2c2aea90305d5c0f417fd36c07bcb1b56c9"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("bce9e409e6772cc85794b929003358619acd3423e3e5e1d8f82cb303e338eea5"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("3571ab1356e5813b1c06d614f68221e2ee0b3394d085dd39500e197c801d34da"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("48533076f4ec0d51829c2e407154250df27fb8e8e31763f3910ae8676b9d1fc4"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("5f0a9ffd7daf97608079feac3c0018ea7224bfbf824cd61edd8b6e76fd2b4a17"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("385cd58aff68d8a7176beed24fcc0defcace0d744f60ace5ba75d49dca89bc33"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("b8eb8e9293b26ce28055a12f146330fcfccfa81749aedd37939f3b7fd1f16d70"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("82d5f725d35af07e6134c6a513806c6e3296e683db531623755d725575eee22b"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("a6f8afa323d61b24a36c8eb399cf4133a9442d69d1e6eebc771e4a75a6948244"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("966d79e2fb6cfbe8cb0724fed1454f873c33a8457cc610caa137f5f32841c7fa"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("4d7462c0f558cf058e1ec1c8c374f2c2aea90305d5c0f417fd36c07bcb1b56c9"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("445b27d59cfe5bf5159eb034e4608954152a1239ca6729ad703ca349e6340538"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("6d7bbfdf34622706c198717afb92fd46f1967b7bfbd173a4a6064383f8c6fa1f"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("ef3d457644c8c3cd6ebdb3214ela7129d4ecf5d06e53b0e9c0e644336b8960b1"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("0f1e6391ac430d8e2dc5be00f94b92cf87aadd2320abb897772fa8cb14342d80"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("b1691667485179d37ffe8fda6d534a797c014d034d56f2c16eb6f9740b2d147e"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("dc14e7ba74778870d8b985c807a606240f7623a2b1765f3bf5a778917144bb95"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("5808feb5f65215c92114b316ef66ffa937624ef3c8a2f3c2ea9374018a8b1398"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("c1a3fd3df2e2b23ecc7ae198ff7aace4acd4ea015483088a800c1587f1c25818"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("321ac31bd15523c33c38098ae778dcb5383da2d598f5e011243c3c8c9b1e9ba4"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("0bfe670d641f27902fe4ee31280dbfe4b6236ca5d7c45233339801a1312e367f"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("cae5b7208ff65268ca1bfb0f65ce134f592664468136d86ab2023923a109b22a"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("5b8b4b7487de11703ecd4d76d6deb8266a5b392ab4bc39798181c059569b8691"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("cbaf2a50e4885f08d633f7505feb9a9b3bc8184b87974129146c16f8b5007d0"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("439443e8e7985713c20f577a26edcd62e0fe8dcf7c60638f81ecb03b2bc17635"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("8c2085bdc6ca4996e71512787d442e732285219f19c708abb6908a2700ed8cd0"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("9d0905956e2c50d35dc6b1dc73e3a06682148553a6d15565b4d2d705fb9505c8"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("a92e5274aa7fee20b4f9a2b6d2774406739541d98be92a65acbabdffb43c5e12"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("2df868545989c46d7f7bbc80e6f094633b5ec08dfec339877d63248f15869034"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("0429180a4eaf95bf8290ec54d5de95d181e45770812b025e088871366f7effc2"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("58d4cd84a88432d126da78aafa21d61797ef86b12325b468991c20c20bc41dbc"))
        //            || keccak256(abi.encodePacked(machineId));

        //                == keccak256(abi.encodePacked("0021ffc67cdd3368390622153eac6f14739c51273dc374064657fe6a01c4ba10"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("d3cc8b1f12732f8f8dab863e681eeae59797fc91424b870a7dd3a84197f68f2d"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("bcbaf2a50e4885f08d633f7505feb9a9b3bc8184b87974129146c16f8b5007d0"))
        //            || keccak256(abi.encodePacked(machineId))
        //
        //                == keccak256(abi.encodePacked("7d52dba0adc1d1a4c5b22c2720ad7aa70d92bca1ff51ad3d7eabf179af2f068f"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("11e3597dad5e79049cb8ddaa823995fe31854f3c5de2678a1db7aaad96a72d77"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("e0c93e0dbccf9f64ba237b9aa19b0ab337903a03754ac0b383c835ec3dc35e43"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("9c3a7b5a7897c58245e81dc2750dead00ed856809263ce3f974bfb8da1451278"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("d6526df1b49caa7ae47f9833549023a6b6e4a92acc2650d2773317fcb5e0e547"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("b7273cf6c4fe7b1df1e7c2d4ea6fa244e142bf9f418ff04b7a5e37f61ee4aeae"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("e9ce34a54840c258d5f906e191571f851459a4d91ebca7a7ec8752c04cc9485a"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("947444b0d5aea4d711b81bcd41be4a01650d73e3c84c87120136fad83fc9fffa"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("0e70749c13824e64e90eadd9cf87cdbd35b10755e1dc64fe47522336e4aa704f"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("839195c0dd76344ce43bf2b7799aca9696d04462fa43558002ebc86a7c5bb30c"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("71c0e057a8641cf42d3d7b6e3b883cd64a298077506cb46bba91e54acb9d9f75"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("b6797a54ef3be69c9b15ed63232d7abaa975eef1c071f242df0fdb1ecaa1f236"));
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("7c1c410d8e9725825ed5cb3bf96c0495da3b3923ce65dd75800f6dca3837a135"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("846c0d04ebd6560cfaff1721928132f698f82434d1d463c320693f415c20f10c"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("c8faba0edf0b87e844b3ede789437fd214a9a6f208ec376bc74cee3e202fd683"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("a2c281e3506d7ca3d6403f41a5e9b0c17d23b26f97bef08208279a16aa7cdc92"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("cfbbdbb7a16f2e45762a5c1b693339e90015dd5d732f06ef491d3b655315a682"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("7e96790d09b2f3dd94cebc8acedb38d95f9b6cd23aec81cd77bbd0f20ea48624"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("151710d93fc1088eb4e1e842b8b22f53763823db6011a83aa2cc126d181c8774"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("e98aa2fa1a0f37ecf66f01a67aad1c11d5f45d8af5ee4ab6db3beb7ad627304a"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("190210ab33ed0355dc11a28a00e4ffc57a54e52277c25e10358272e73eddb79a"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("935f090179b42a9a45a6ce4893dc4f47a11a32fbc54b3189205b55ca4ff9ccff"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("148a09d00cc955b0f1d1276e959ebad2115e11f95e0e7eebbf15fb6699a23093"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("6ebdb12de38abe2de58c845502ed3db49017b4888e7784ba9ce02d593f9fef4a"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("e7902547db9b72bb2812d4908ab7794d2ebf06f2a582f234fbb88d9744bbb306"))
        //            || keccak256(abi.encodePacked(machineId))
        //
        //                == keccak256(abi.encodePacked("9f86e1572935f720d7c1ff739b5e43cdb63f3b037e88cddb7ef16202e254734a"))
        //            || keccak256(abi.encodePacked(machineId))
        //
        //                == keccak256(abi.encodePacked("7155b00d7c3d6e105c14f5375e450c5975e31154d451b906764c248901b6828c"))
        //            || keccak256(abi.encodePacked(machineId))
        //
        //                == keccak256(abi.encodePacked("c90a8dd75d845e0b9b083822cd0bf0c86f857e1d4f541cd621f865eabce96735"))
        //            || keccak256(abi.encodePacked(machineId))
        //
        //                == keccak256(abi.encodePacked("c00ec5bb1b5a1451f28400235b3c507b59e5a640120bb58f155853ca5d2841b5"))
        //            || keccak256(abi.encodePacked(machineId))
        //
        //                == keccak256(abi.encodePacked("a30b2bcc6fe3740296add29762d9e67d75a6402393e4ad4f7c7fd980e42910ea"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("3571ab1356e5813b1c06d614f68221e2ee0b3394d085dd39500e197c801d34da"))
        //            || keccak256(abi.encodePacked(machineId))
        //                == keccak256(abi.encodePacked("5a3cc6adb8eec8ed4eea637f19e6252854d102760100cc90e52b19afc866dd78"));
        return rentWhitelist[machineId];
    }

    function setRentingWhitelist(string[] calldata machineIds, bool isAdd) external {
        require(adminsToSetRentWhiteList[msg.sender], "has no permission to set renting whitelist");
        for (uint256 i = 0; i < machineIds.length; i++) {
            rentWhitelist[machineIds[i]] = isAdd;
        }
    }

    function setAdminsToAddRentWhiteList(address[] calldata admins) external onlyOwner {
        for (uint256 i = 0; i < admins.length; i++) {
            adminsToSetRentWhiteList[admins[i]] = true;
        }
    }

    function rentMachine(string calldata machineId, uint256 rentSeconds) external {
        _rentMachine(msg.sender, msg.sender, machineId, rentSeconds);
    }

    function rentProxyMachine(address renter, string calldata machineId, uint256 rentSeconds) external {
        require(msg.sender != renter, RenterAndPayerIsSame());
        _rentMachine(msg.sender, renter, machineId, rentSeconds);
    }

    function _rentMachine(address payer, address renter, string calldata machineId, uint256 rentSeconds) internal {
        require(inRentWhiteList(machineId), NotValidMachineId());
        require(rentSeconds >= 10 minutes && rentSeconds <= 2 hours, InvalidRentDuration(rentSeconds));
        require(canRent(machineId), MachineCanNotRent());

        (address machineHolder,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        require(block.timestamp + rentSeconds < endAtTimestamp, RenTimeCannotOverMachineUnstakeTime());
        uint256 rewardDuration = stakingContract.getRewardDuration();
        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        require(rewardEndAt > rewardDuration, RewardNotStart());
        uint256 maxRentDuration = Math.min(Math.min(endAtTimestamp, rewardEndAt) - block.timestamp, rewardDuration);
        require(rentSeconds <= maxRentDuration, RentDurationTooLong(rentSeconds, maxRentDuration));
        machine2ProxyRented[machineId] = msg.sender != renter;

        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock != 0) {
            require(block.number > lastRentEndBlock + 30, MachineCanNotRentWithin100BlocksAfterLastRent());
        }

        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);

        uint256 baseRentFee = getBaseMachinePrice(machineId, rentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, rentSeconds);
        uint256 platformFee = (baseRentFee + extraRentFee) * platformFeeRate / 100;
        uint256 totalRentFee = baseRentFee + extraRentFee + platformFee;
        require(feeToken.balanceOf(payer) >= totalRentFee, BalanceNotEnough());

        uint256 _now = block.timestamp;

        // save rent info
        lastRentId = getNextRentId();
        rentId2RentInfo[lastRentId] = RentInfo({
            stakeHolder: machineHolder,
            machineId: machineId,
            rentStatTime: _now,
            rentEndTime: _now + rentSeconds,
            renter: renter
        });
        machineId2RentId[machineId] = lastRentId;
        renter2RentIds[renter].push(lastRentId);

        FeeInfo memory feeInfo;
        feeInfo.baseFee = baseRentFee;
        feeInfo.extraFee = extraRentFee;
        feeInfo.platformFee = platformFee;
        rentId2FeeInfoInDLC[lastRentId] = feeInfo;

        feeToken.transferFrom(msg.sender, address(this), totalRentFee);
        emit RentFee(lastRentId, msg.sender, baseRentFee, extraRentFee, platformFee);
        emit PayToContractOnRent(lastRentId, msg.sender, totalRentFee);

        // burn rent fee
        //        feeToken.burnFrom(payer, baseRentFee);
        //        emit BurnedFee(machineId, lastRentId, block.timestamp, baseRentFee, renter, 1);
        //        totalBurnedAmount += baseRentFee;

        // add machine burn info
        //        BurnedDetail memory burnedDetail =
        //            BurnedDetail({rentId: lastRentId, burnTime: block.timestamp, burnDLCAmount: baseRentFee, renter: renter});

        stakeHolder2RentGPUInfo[machineHolder].rentedGPUCount += 1;
        stakeHolder2RentGPUInfo[machineHolder].rentingGPUCount += 1;
        rentGPUInfo.rentedGPUCount += 1;
        rentGPUInfo.rentingGPUCount += 1;

        stakeHolder2RentFee[machineHolder] += baseRentFee;
        //        BurnedInfo storage burnedInfo = machineId2BurnedInfo[machineId];
        //        burnedInfo.details.push(burnedDetail);
        //        burnedInfo.totalBurnedAmount += baseRentFee;

        // notify staking contract renting machine action happened
        stakingContract.rentMachine(machineId);

        emit RentMachine(machineHolder, lastRentId, machineId, block.timestamp + rentSeconds, renter, baseRentFee);
    }

    function proxyRenewRent(address renter, string memory machineId, uint256 additionalRentSeconds) external {
        _renewRent(renter, machineId, additionalRentSeconds);
    }

    function renewRent(string memory machineId, uint256 additionalRentSeconds) external {
        _renewRent(msg.sender, machineId, additionalRentSeconds);
    }

    function _renewRent(address renter, string memory machineId, uint256 additionalRentSeconds) internal {
        uint256 rentId = machineId2RentId[machineId];
        require(rentId2RentInfo[rentId].rentEndTime > block.timestamp, RentEnd());
        require(rentId2RentInfo[rentId].renter == renter, NotRenter());
        require(isRented(machineId), MachineNotRented());
        require(
            additionalRentSeconds >= 10 minutes && additionalRentSeconds <= 2 hours,
            InvalidRentDuration(additionalRentSeconds)
        );

        (,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        uint256 maxRentDuration =
            Math.min(Math.min(endAtTimestamp, rewardEndAt) - block.timestamp, stakingContract.getRewardDuration());

        require(
            rentId2RentInfo[rentId].rentEndTime + additionalRentSeconds < endAtTimestamp,
            RenTimeCannotOverMachineUnstakeTime()
        );

        if (msg.sender != renter) {
            require(machine2ProxyRented[machineId] == true, NotProxyRentingMachine());
        }

        uint256 newRentDuration = rentId2RentInfo[rentId].rentEndTime - block.timestamp + additionalRentSeconds;
        require(newRentDuration <= maxRentDuration, RentDurationTooLong(newRentDuration, maxRentDuration));

        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);

        uint256 baseRentFee = getBaseMachinePrice(machineId, additionalRentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, additionalRentSeconds);
        uint256 platformFee = (baseRentFee + extraRentFee) * platformFeeRate / 100;
        uint256 additionalRentFeeInFact = baseRentFee + extraRentFee + platformFee;
        require(feeToken.balanceOf(msg.sender) >= additionalRentFeeInFact, BalanceNotEnough());

        // Update rent end time
        rentId2RentInfo[rentId].rentEndTime += additionalRentSeconds;

        FeeInfo storage feeInfo = rentId2FeeInfoInDLC[lastRentId];
        feeInfo.baseFee += baseRentFee;
        feeInfo.extraFee += extraRentFee;
        feeInfo.platformFee += platformFee;

        feeToken.transferFrom(msg.sender, address(this), platformFee + extraRentFee);

        // add machine burn info
        BurnedDetail memory burnedDetail = BurnedDetail({
            rentId: rentId,
            burnTime: block.timestamp,
            burnDLCAmount: additionalRentFeeInFact,
            renter: renter
        });

        (address machineHolder,) = getMachineHolderAndCalcPoint(machineId);

        stakeHolder2RentFee[machineHolder] += additionalRentFeeInFact;
        BurnedInfo storage burnedInfo = machineId2BurnedInfo[machineId];
        burnedInfo.details.push(burnedDetail);
        burnedInfo.totalBurnedAmount += additionalRentFeeInFact;

        // update total burned amount
        totalBurnedAmount += additionalRentFeeInFact;
        stakingContract.renewRentMachine(machineId, additionalRentFeeInFact);
        emit RenewRent(machineHolder, machineId, rentId, additionalRentSeconds, additionalRentFeeInFact, renter);
    }

    function endRentMachine(string calldata machineId) external {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        if (msg.sender != rentInfo.renter) {
            require(rentInfo.rentEndTime <= block.timestamp, RentNotEnd());
        } else {
            require(machine2ProxyRented[machineId] == false, ProxyRentCanNotEndByRenter());
        }
        machine2ProxyRented[machineId] == false;
        require(rentInfo.rentEndTime > 0, RentingNotExist());

        (address machineHolder,) = getMachineHolderAndCalcPoint(machineId);

        FeeInfo memory feeInfo = rentId2FeeInfoInDLC[rentId];
        removeValueOfUintArray(rentId, renter2RentIds[rentInfo.renter]);
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];

        stakeHolder2RentGPUInfo[machineHolder].rentingGPUCount -= 1;
        rentGPUInfo.rentingGPUCount -= 1;

        uint256 _now = block.timestamp;
        if (_now < rentInfo.rentEndTime) {
            uint256 rentDuration = rentInfo.rentEndTime - rentInfo.rentStatTime;
            uint256 usdDuration = _now - rentInfo.rentStatTime;

            uint256 totalRentFee = feeInfo.baseFee + feeInfo.extraFee + feeInfo.platformFee;

            feeInfo.baseFee = feeInfo.baseFee * usdDuration / rentDuration;
            feeInfo.extraFee = feeInfo.extraFee * usdDuration / rentDuration;
            feeInfo.platformFee = feeInfo.platformFee * usdDuration / rentDuration;

            uint256 payBackFee = totalRentFee - feeInfo.baseFee - feeInfo.extraFee - feeInfo.platformFee;
            if (payBackFee > 0) {
                feeToken.transfer(rentInfo.renter, payBackFee);
                emit PayBackFee(machineId, rentId, rentInfo.renter, payBackFee);
            }
        }

        if (feeInfo.baseFee > 0) {
            feeToken.approve(address(this), feeInfo.baseFee);
            feeToken.burnFrom(address(this), feeInfo.baseFee);
            emit BurnedFee(machineId, lastRentId, block.timestamp, feeInfo.baseFee, rentInfo.renter, 1);
            totalBurnedAmount += feeInfo.baseFee;
        }

        if (feeInfo.extraFee > 0) {
            feeToken.transfer(machineHolder, feeInfo.extraFee);
            emit ExtraRentFeeTransfer(machineHolder, lastRentId, feeInfo.extraFee);
        }
        if (feeInfo.platformFee > 0) {
            distributePlatformFee(rentId, machineId, feeInfo.platformFee);
        }

        stakingContract.endRentMachine(machineId, feeInfo.baseFee, feeInfo.platformFee);
        machineId2LastRentEndBlock[machineId] = block.number;
        delete rentId2FeeInfoInDLC[rentId];
        emit EndRentMachine(machineHolder, rentId, machineId, rentInfo.rentEndTime, rentInfo.renter);
    }

    function getMachineHolderAndCalcPoint(string memory machineId) public view returns (address, uint256) {
        (address holder, uint256 calcPoint,,,,,,) = stakingContract.getMachineInfo(machineId);
        return (holder, calcPoint);
    }

    function reportMachineFault(string calldata machineId, uint256 reserveAmount) external {
        require(reserveAmount == REPORT_RESERVE_AMOUNT, ReserveAmountForReportShouldBe10000());

        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        require(rentInfo.renter == msg.sender, NotRenter());
        require(rentInfo.rentEndTime >= block.timestamp, RentEnd());

        SafeERC20.safeTransferFrom(feeToken, msg.sender, address(this), REPORT_RESERVE_AMOUNT);
        machineId2SlashInfo[rentInfo.machineId] = newSlashInfo(
            rentInfo.stakeHolder,
            rentInfo.machineId,
            SLASH_AMOUNT,
            rentInfo.rentStatTime,
            rentInfo.rentEndTime,
            block.timestamp - rentInfo.rentStatTime,
            SlashType.RenterReport,
            rentInfo.renter
        );
        pendingSlashMachineIds.push(rentInfo.machineId);
        emit ReportMachineFault(rentId, rentInfo.machineId, msg.sender);
    }

    function newSlashInfo(
        address slasher,
        string memory machineId,
        uint256 slashAmount,
        uint256 rentStartAt,
        uint256 rentEndAt,
        uint256 rentDuration,
        SlashType slashType,
        address renter
    ) internal view returns (SlashInfo memory) {
        SlashInfo memory slashInfo = SlashInfo({
            stakeHolder: slasher,
            machineId: machineId,
            slashAmount: slashAmount,
            rentStartAtTimestamp: rentStartAt,
            rentEndAtTimestamp: rentEndAt,
            rentedDurationSeconds: rentDuration,
            renter: renter,
            slashType: slashType,
            createdAt: block.timestamp,
            paid: false
        });
        return slashInfo;
    }

    function addSlashInfoAndReport(SlashInfo memory slashInfo) internal {
        machineId2SlashInfos[slashInfo.machineId].push(slashInfo);
        stakingContract.reportMachineFault(slashInfo.machineId, slashInfo.renter);
    }

    function approveMachineFaultReporting(string calldata machineId) external onlyApproveAdmins {
        require(machineId2SlashInfo[machineId].renter != address(0x0), ReportedMachineNotFound());

        require(pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] != Vote.Finished, VoteFinished());
        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.Yes;
        emit ApprovedReport(machineId, msg.sender);
        pendingSlashMachineId2ApprovedCount[machineId] += 1;
        if (pendingSlashMachineId2ApprovedCount[machineId] >= voteThreshold) {
            SlashInfo memory slashInfo = machineId2SlashInfo[machineId];
            addSlashInfoAndReport(slashInfo);

            removeValueOfStringArray(machineId, pendingSlashMachineIds);
            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2ApprovedCount[machineId];

            for (uint8 i = 0; i < adminsToApprove.length; i++) {
                pendingSlashMachineId2ApprovedAdmins[machineId][adminsToApprove[i]] = Vote.Finished;
            }

            SafeERC20.safeTransfer(feeToken, slashInfo.renter, REPORT_RESERVE_AMOUNT);
            emit ExecuteReport(machineId, Vote.Yes);
        }
    }

    function rejectMachineFaultReporting(string calldata machineId) external onlyApproveAdmins {
        require(machineId2SlashInfo[machineId].renter != address(0), ReportedMachineNotFound());

        require(pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] != Vote.Finished, VoteFinished());
        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.No;
        pendingSlashMachineId2RefuseCount[machineId] += 1;
        emit RefusedReport(machineId, msg.sender);
        if (pendingSlashMachineId2RefuseCount[machineId] >= voteThreshold) {
            removeValueOfStringArray(machineId, pendingSlashMachineIds);
            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2ApprovedCount[machineId];

            for (uint8 i = 0; i < adminsToApprove.length; i++) {
                pendingSlashMachineId2ApprovedAdmins[machineId][adminsToApprove[i]] = Vote.Finished;
            }

            uint256 amountPerAdmin = REPORT_RESERVE_AMOUNT / adminsToApprove.length;
            for (uint256 i = 0; i < adminsToApprove.length; i++) {
                if (adminsToApprove[i] == address(0)) {
                    continue;
                }
                SafeERC20.safeTransfer(feeToken, adminsToApprove[i], amountPerAdmin);
            }

            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2RefuseCount[machineId];

            emit ExecuteReport(machineId, Vote.No);
        }
    }

    function version() external pure returns (uint256) {
        return 0;
    }

    function getBurnedRentFeeByStakeHolder(address stakeHolder) public view returns (uint256) {
        return stakeHolder2RentFee[stakeHolder];
    }

    function getTotalBurnedRentFee() public view returns (uint256) {
        return totalBurnedAmount;
    }

    function getRentedGPUCountOfStakeHolder(address stakeHolder) public view returns (uint256) {
        return stakeHolder2RentGPUInfo[stakeHolder].rentedGPUCount;
    }

    function getTotalRentedGPUCount() public view returns (uint256) {
        return rentGPUInfo.rentedGPUCount;
    }

    function isRented(string memory machineId) public view returns (bool) {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        if (rentInfo.renter != address(0)) {
            return true;
        }
        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock > 0) {
            return block.number <= lastRentEndBlock + 30;
        }
        return false;
    }

    function getRenter(string calldata machineId) public view returns (address) {
        uint256 rentId = machineId2RentId[machineId];
        address renter = rentId2RentInfo[rentId].renter;
        return renter;
    }

    function notify(NotifyType tp, string calldata machineId) external onlyDBCAIContract returns (bool) {
        if (tp == NotifyType.ContractRegister) {
            registered = true;
            return true;
        }

        bool isStaking = stakingContract.isStaking(machineId);
        if (!isStaking) {
            return false;
        }

        if (tp == NotifyType.MachineOffline) {
            uint256 rentId = machineId2RentId[machineId];
            RentInfo memory rentInfo = rentId2RentInfo[rentId];
            if (
                rentInfo.renter != address(0) && block.timestamp <= rentInfo.rentEndTime
                    && block.timestamp > rentInfo.rentStatTime
            ) {
                SlashInfo memory slashInfo = newSlashInfo(
                    rentInfo.stakeHolder,
                    rentInfo.machineId,
                    SLASH_AMOUNT,
                    rentInfo.rentStatTime,
                    rentInfo.rentEndTime,
                    block.timestamp - rentInfo.rentStatTime,
                    SlashType.Offline,
                    rentInfo.renter
                );
                addSlashInfoAndReport(slashInfo);
                emit SlashMachineOnOffline(
                    rentInfo.stakeHolder,
                    rentInfo.machineId,
                    rentInfo.renter,
                    SLASH_AMOUNT,
                    rentInfo.rentStatTime,
                    rentInfo.rentEndTime,
                    SlashType.Offline
                );
            } else {
                stakingContract.stopRewarding(machineId);
                emit RemoveCalcPointOnOffline(machineId);
            }
        } else if (tp == NotifyType.MachineOnline && stakingContract.isStakingButOffline(machineId)) {
            stakingContract.recoverRewarding(machineId);
            emit AddCalcPointOnline(machineId);
        }
        return true;
    }

    function getSlashInfosByMachineId(string memory machineId, uint256 pageNumber, uint256 pageSize)
        external
        view
        returns (SlashInfo[] memory paginatedSlashInfos, uint256 totalCount)
    {
        totalCount = machineId2SlashInfos[machineId].length;

        if (pageNumber == 0 || pageSize == 0 || totalCount == 0) {
            return (new SlashInfo[](0), 0);
        }

        // Calculate the start index for the requested page
        uint256 startIndex = (pageNumber - 1) * pageSize;

        // Ensure startIndex is within bounds
        if (startIndex >= totalCount) {
            return (new SlashInfo[](0), totalCount);
        }

        // Calculate the end index for pagination
        uint256 endIndex = startIndex + pageSize > totalCount ? totalCount : startIndex + pageSize;
        uint256 resultSize = endIndex - startIndex;

        // Create a new array for paginated results
        paginatedSlashInfos = new SlashInfo[](resultSize);

        // Populate the paginated array
        for (uint256 i = 0; i < resultSize; i++) {
            paginatedSlashInfos[i] = machineId2SlashInfos[machineId][startIndex + i];
        }
    }

    function paidSlash(string memory machineId) external onlyStakingContract {
        SlashInfo[] storage slashInfos = machineId2SlashInfos[machineId];
        for (uint256 i = 0; i < slashInfos.length; i++) {
            if (slashInfos[i].paid) {
                return;
            }
            if (keccak256(abi.encodePacked(slashInfos[i].machineId)) == keccak256(abi.encodePacked(machineId))) {
                slashInfos[i].paid = true;
                emit PaidSlash(machineId);
            }
        }
    }

    function isInSlashing(string memory machineId) public view returns (bool) {
        return machineId2SlashInfo[machineId].paid == false;
    }

    function distributePlatformFee(uint256 rentId, string memory machineId, uint256 platformFee) internal {
        (address[] memory beneficiaries, uint256[] memory rates,) = stakingContract.getMachineConfig(machineId);
        for (uint8 i = 0; i < beneficiaries.length; i++) {
            feeToken.transfer(beneficiaries[i], platformFee * rates[i] / 100);
            emit PlatformFeeTransfer(beneficiaries[i], rentId, platformFee * rates[i] / 100);
        }
    }
}
