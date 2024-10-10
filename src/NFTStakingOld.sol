// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
//
//import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
//import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
//import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
//import "abdk-libraries-solidity/ABDKMath64x64.sol";
//import "./interface/IPrecompileContract.sol";
//import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
//import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
//
///// @custom:oz-upgrades-from NFTStakingV5
//contract NFTStakingV6 is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
//    IPrecompileContract public precompileContract;
//    uint256 public constant secondsPerBlock = 6;
//    IERC20 public rewardToken;
//
//    uint256 public rewardAmountPerSecond;
//    uint256 public constant baseReserveAmount = 10_000 * 10 ** 18;
//
//    uint256 public totalStakedMachineMultiCalcPoint;
//    uint256 public nonlinearCoefficient;
//
//    string[] public machineIds;
//    mapping(address => uint256) public stakeholder2Reserved;
//    mapping(string => address) public machineId2Address;
//    uint256 public startAt;
//    uint256 public constant oneYearSeconds = 365 days;
//    uint256 public slashAmountOfReport;
//
//    struct StakeInfo {
//        uint256 startAtBlockNumber;
//        uint256 lastClaimAtBlockNumber;
//        uint256 endAtBlockNumber;
//        uint256 calcPoint;
//        uint256 reservedAmount;
//        uint256[] nftTokenIds;
//    }
//
//    struct SlashPayedDetail {
//        uint256 fromReservedAmount;
//        uint256 fromRewardAmount;
//        uint256 totalPayedAmount;
//        uint256 at;
//    }
//
//    struct SlashPayedInfo {
//        uint256 totalPayedAmount;
//        address to;
//    }
//
//    mapping(uint256 => SlashPayedInfo) public slashReportId2SlashPaidInfo;
//
//    mapping(address => mapping(string => StakeInfo)) public address2StakeInfos;
//
//    IERC721 public nftToken;
//
//    struct Machine {
//        string gpuType;
//        uint256 hashPower;
//        uint256 stakedNFTs;
//        uint256 accumulatedReward;
//        uint256 lastRewardTimestamp;
//    }
//
//    mapping(uint256 => Machine) public machines;
//    mapping(address => mapping(uint256 => uint256[])) public userStakes;
//
//    struct LockedRewardDetail {
//        uint256 amount;
//        uint256 unlockAt;
//    }
//
//    mapping(string => LockedRewardDetail[]) public machineId2LockedRewardDetails;
//
//    uint256 public constant MAX_NFTS_PER_MACHINE = 20;
//    uint256 public constant REWARD_START_THRESHOLD = 500;
//    uint256 public constant DAILY_REWARD = 6000000 * 1e18;
//    //    uint256 public constant REWARD_DURATION = 60 days;
//    uint256 public constant REWARD_DURATION = 0.5 days; //todo: change to 60 days
//
//    uint256 public constant LOCK_PERIOD = 180 days;
//    uint256 public constant DAILY_UNLOCK_RATE = 5; // 0.5% = 5/1000
//    uint256 public constant SECONDS_PER_DAY = 1 days;
//
//    struct RewardPausedDetail {
//        uint256 pausedAtBlockNumber;
//        uint256 recoverAtBlockNumber;
//    }
//
//    RewardPausedDetail[] public rewardPausedDetails;
//
//    mapping(address => mapping(string => uint256[])) public address2NftTokenIds;
//
//    uint256 public constant PHASE_LEVEL = 1;
//
//    event Staked(address indexed user, uint256 machineId, uint256[] tokenIds);
//    event Unstaked(address indexed user, uint256 machineId, uint256[] tokenIds);
//    event RewardClaimed(address indexed user, uint256 amount);
//    event GlobalRewardsUpdated(uint256 timestamp);
//    event PhaseChanged(uint256 newPhase, uint256 timestamp);
//
//    event nonlinearCoefficientChanged(uint256 nonlinearCoefficient);
//
//    event staked(address indexed stakeholder, string machineId, uint256 stakeAtBlockNumber);
//    event unStaked(address indexed stakeholder, string machineId, uint256 unStakeAtBlockNumber);
//    event claimed(
//        address indexed stakeholder,
//        string machineId,
//        uint256 rewardAmount,
//        uint256 slashAmount,
//        uint256 claimAtBlockNumber
//    );
//    event claimedAll(address indexed stakeholder, uint256 claimAtBlockNumber);
//    event rewardTokenSet(address indexed addr);
//    event nftTokenSet(address indexed addr);
//    event slashPayedDetail(
//        string machineId,
//        uint256 fromReservedAmount,
//        uint256 fromRewardAmount,
//        uint256 totalPayedAmount,
//        uint256 reportId,
//        address to
//    );
//
//    /// @custom:oz-upgrades-unsafe-allow constructor
//    constructor() {
//        _disableInitializers();
//    }
//
//    function initialize(address _initialOwner, address _nftToken, address _rewardToken, address _precompileContract)
//    public
//    initializer
//    {
//        __Ownable_init(_initialOwner);
//        __UUPSUpgradeable_init();
//        __ReentrancyGuard_init();
//        nftToken = IERC721(_nftToken);
//
//        if (_rewardToken != address(0x0)) {
//            rewardToken = IERC20(_rewardToken);
//        }
//        if (_precompileContract != address(0x0)) {
//            precompileContract = IPrecompileContract(_precompileContract);
//        }
//        startAt = block.number;
//        slashAmountOfReport = 10000 * 10 ** 18;
//        rewardAmountPerSecond = uint256(DAILY_REWARD / 1 days);
//    }
//
//    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
//
//    function setPrecompileContract(address _registerContract) external onlyOwner {
//        precompileContract = IPrecompileContract(_registerContract);
//    }
//
//    function claimLeftRewardTokens() external onlyOwner {
//        uint256 balance = rewardToken.balanceOf(address(this));
//        rewardToken.transfer(msg.sender, balance);
//    }
//
//    function setRewardToken(address token) external onlyOwner {
//        rewardToken = IERC20(token);
//        emit rewardTokenSet(token);
//    }
//
//    function setNftToken(address token) external onlyOwner {
//        nftToken = IERC721(token);
//        emit nftTokenSet(token);
//    }
//
//    function setNonlinearCoefficient(uint256 value) public onlyOwner {
//        nonlinearCoefficient = value;
//        emit nonlinearCoefficientChanged(value);
//    }
//
//    function rewardPerSecond() public view returns (uint256) {
//        if (getRewardStartAt() > 0) {
//            return rewardAmountPerSecond;
//        }
//
//        return 0;
//    }
//
//    function reportPhaseOneDlcNftStaking(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string memory machineId
//    ) public returns (bool success) {
//        return precompileContract.reportDlcNftStaking(msgToSign, substrateSig, substratePubKey, machineId, PHASE_LEVEL);
//    }
//
//    function reportPhaseOneDlcNftEndStaking(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string memory machineId
//    ) public returns (bool success) {
//        return precompileContract.reportDlcNftEndStaking(msgToSign, substrateSig, substratePubKey, machineId, PHASE_LEVEL);
//    }
//
//    function getRentingDuration(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string memory machineId,
//        uint256 rentId
//    ) public view returns (uint256 duration) {
//        return precompileContract.getRentingDuration(msgToSign, substrateSig, substratePubKey, machineId, rentId);
//    }
//
//    function getValidRewardDuration(uint256 last_claim_at, uint256 total_stake_duration, uint256 phase_number)
//    public
//    view
//    returns (uint256 valid_duration)
//    {
//        return precompileContract.getValidRewardDuration(last_claim_at, total_stake_duration, phase_number);
//    }
//
//    function getRewardStartAt() public view returns (uint256 phaseOneRewardStartAt) {
//        return precompileContract.getDlcNftStakingRewardStartAt(PHASE_LEVEL);
//    }
//
//    function stake(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string calldata machineId,
//        uint256 amount,
//        uint256[] calldata nftTokenIds,
//        uint256 rentId
//    ) external {
//        //        require(block.number - getPhaseOneRewardStartAt() < REWARD_DURATION, "staking ended");
//
//        address stakeholder = msg.sender;
//        require(stakeholder != address(0), "invalid stakeholder address");
//        require(!isStaking(machineId), "machine already staked");
//        require(nftTokenIds.length > 0, "nft token ids is empty");
//        uint256 calcPoint = getMachineCalcPoint(machineId) * nftTokenIds.length;
//        require(calcPoint > 0, "machine calc point not found");
//        uint256 rentDuration = getRentingDuration(msgToSign, substrateSig, substratePubKey, machineId, rentId);
//        // todo check rent duration
////        require(
////            rentDuration * secondsPerBlock >= REWARD_DURATION, "rent duration is too short, must be longer than 60 days"
////        );
//
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//        uint256 slashedAt = getSlashedAt(machineId);
//
//        if (slashedAt > 0) {
//            uint256 shouldSlashAmount = getLeftSlashedAmount(machineId);
//            require(amount >= shouldSlashAmount, "should pay slash amount before stake");
//            address reporter = getSlashedReporter(machineId);
//            require(reporter != address(0), "reporter not found");
//            rewardToken.transferFrom(stakeholder, reporter, shouldSlashAmount);
//            amount = amount - shouldSlashAmount;
//            setSlashedPayedDetail(machineId, shouldSlashAmount, 0, reporter);
//        } else {
//            if (stakeInfo.endAtBlockNumber == 0) {
//                require(stakeInfo.startAtBlockNumber == 0, "machine already staked");
//                require(stakeInfo.endAtBlockNumber == 0, "machine stake not end");
//            }
//        }
//
//        if (amount > 0) {
//            stakeholder2Reserved[stakeholder] += amount;
//            rewardToken.transferFrom(stakeholder, address(this), amount);
//        }
//        for (uint256 i = 0; i < nftTokenIds.length; i++) {
//            nftToken.transferFrom(msg.sender, address(this), nftTokenIds[i]);
//        }
//
//        uint256 currentTime = block.number;
//        address2StakeInfos[stakeholder][machineId] = StakeInfo({
//            startAtBlockNumber: currentTime,
//            lastClaimAtBlockNumber: currentTime,
//            endAtBlockNumber: 0,
//            calcPoint: calcPoint,
//            reservedAmount: amount,
//            nftTokenIds: nftTokenIds
//        });
//
//        machineId2Address[machineId] = stakeholder;
//        totalStakedMachineMultiCalcPoint += calcPoint;
//
//        require(
//            reportPhaseOneDlcNftStaking(msgToSign, substrateSig, substratePubKey, machineId) == true,
//            "report staking failed"
//        );
//
//        emit staked(stakeholder, machineId, currentTime);
//    }
//
//    function getMachineCalcPoint(string memory machineId) internal view returns (uint256) {
//        return precompileContract.getMachineCalcPoint(machineId);
//    }
//
//    function getRentDuration(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        uint256 lastClaimAt,
//        uint256 slashAt,
//        string memory machineId
//    ) public view returns (uint256) {
//        return precompileContract.getRentDuration(
//            msgToSign, substrateSig, substratePubKey, lastClaimAt, slashAt, machineId
//        );
//    }
//
//    function getDlcMachineRentDuration(uint256 lastClaimAt, uint256 slashAt, string memory machineId)
//    public
//    view
//    returns (uint256 rentDuration)
//    {
//        return precompileContract.getDlcMachineRentDuration(lastClaimAt, slashAt, machineId);
//    }
//
//    function getSlashedAt(string memory machineId) public view returns (uint256) {
//        if (!precompileContract.isSlashed(machineId)) {
//            return 0;
//        }
//
//        uint256 slashReportId = getDlcMachineSlashedReportId(machineId);
//
//        if (isPaidSlashed(slashReportId)) {
//            return 0;
//        }
//
//        return precompileContract.getDlcMachineSlashedAt(machineId);
//    }
//
//    function getLeftSlashedAmount(string memory machineId) public view returns (uint256) {
//        if (getSlashedAt(machineId) > 0) {
//            uint256 slashReportId = precompileContract.getDlcMachineSlashedReportId(machineId);
//            SlashPayedInfo storage slashPayedInfo = slashReportId2SlashPaidInfo[slashReportId];
//            return slashAmountOfReport - slashPayedInfo.totalPayedAmount;
//        }
//        return 0;
//    }
//
//    function setSlashedPayedDetail(
//        string memory machineId,
//        uint256 fromReservedAmount,
//        uint256 fromRewardAmount,
//        address to
//    ) internal {
//        uint256 total = fromReservedAmount + fromRewardAmount;
//        uint256 slashReportId = precompileContract.getDlcMachineSlashedReportId(machineId);
//        SlashPayedInfo storage slashPayedInfo = slashReportId2SlashPaidInfo[slashReportId];
//        slashPayedInfo.totalPayedAmount += total;
//        slashPayedInfo.to = to;
//        slashReportId2SlashPaidInfo[slashReportId] = slashPayedInfo;
//        emit slashPayedDetail(
//            machineId, fromReservedAmount, fromRewardAmount, slashPayedInfo.totalPayedAmount, slashReportId, to
//        );
//    }
//
//    function getDlcMachineSlashedReportId(string memory machineId) public view returns (uint256) {
//        if (!precompileContract.isSlashed(machineId)) {
//            return 0;
//        }
//        return uint256(precompileContract.getDlcMachineSlashedReportId(machineId));
//    }
//
//    function getSlashedReporter(string memory machineId) public view returns (address) {
//        uint256 slashReportId = getDlcMachineSlashedReportId(machineId);
//        bool isPaid = isPaidSlashed(slashReportId);
//        if (isPaid) {
//            return address(0x0);
//        }
//        return precompileContract.getDlcMachineSlashedReporter(machineId);
//    }
//
//    function isPaidSlashed(uint256 slashReportId) internal view returns (bool) {
//        SlashPayedInfo storage slashPayedInfo = slashReportId2SlashPaidInfo[slashReportId];
//        return slashPayedInfo.totalPayedAmount == slashAmountOfReport;
//    }
//
//    function _getTotalRewardAmount(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string memory machineId,
//        StakeInfo storage stakeInfo
//    ) internal view returns (uint256) {
//        if (stakeInfo.lastClaimAtBlockNumber == 0) {
//            return 0;
//        }
//        // todo ?
////        require(getRewardStartAt() > 0, "reward not start");
//        uint256 lastClaimAtBlockNumber = stakeInfo.lastClaimAtBlockNumber;
//        if (getRewardStartAt() > stakeInfo.lastClaimAtBlockNumber) {
//            lastClaimAtBlockNumber = getRewardStartAt();
//        }
//
//        uint256 slashedAt = getSlashedAt(machineId);
//        uint256 totalRewardDuration = _getStakeHolderRentDuration(
//            msgToSign, substrateSig, substratePubKey, stakeInfo.lastClaimAtBlockNumber, slashedAt, machineId
//        );
//        if (totalRewardDuration == 0) {
//            return 0;
//        }
//
//        totalRewardDuration = getValidRewardDuration(stakeInfo.lastClaimAtBlockNumber, totalRewardDuration, 1);
//
//        uint256 rewardPerSecond_ = rewardPerSecond();
//        if (rewardPerSecond_ == 0) {
//            return 0;
//        }
//
//        uint256 rentDuration = getDlcMachineRentDuration(stakeInfo.lastClaimAtBlockNumber, slashedAt, machineId);
//        uint256 totalBaseReward =
//            rewardPerSecond_ * (totalRewardDuration - rentDuration) + ((rewardPerSecond_ * 13) / 10) * rentDuration;
//
//        uint256 _totalStakedMachineMultiCalcPoint = totalStakedMachineMultiCalcPoint;
//        if (slashedAt > 0) {
//            _totalStakedMachineMultiCalcPoint += stakeInfo.calcPoint;
//        }
//        uint256 baseRewardAmount = (totalBaseReward * stakeInfo.calcPoint) / _totalStakedMachineMultiCalcPoint;
//        uint256 value = 0;
//        if (stakeInfo.reservedAmount > baseReserveAmount) {
//            value = stakeInfo.reservedAmount - baseReserveAmount;
//        }
//        uint256 tmp = 1 + value / baseReserveAmount;
//        int128 ln = ABDKMath64x64.fromUInt(tmp);
//        uint256 totalRewardAmount = baseRewardAmount * (1 + nonlinearCoefficient * ABDKMath64x64.toUInt(ln));
//
//        return totalRewardAmount;
//    }
//
//    function getRewardAmountCanClaim(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string memory machineId
//    ) public view returns (uint256 canClaimAmount, uint256 lockedAmount) {
//        address stakeholder = machineId2Address[machineId];
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//
//        uint256 totalRewardAmount =
//                        _getTotalRewardAmount(msgToSign, substrateSig, substratePubKey, machineId, stakeInfo);
//
//        uint256 slashAmount = getLeftSlashedAmount(machineId);
//        if (slashAmount > 0) {
//            if (totalRewardAmount >= slashAmount) {
//                totalRewardAmount - slashAmount;
//            } else {
//                return (0, 0);
//            }
//        }
//
//        return _getRewardDetail(totalRewardAmount);
//    }
//
//    function _getRewardDetail(uint256 totalRewardAmount)
//    internal
//    pure
//    returns (uint256 canClaimAmount, uint256 lockedAmount)
//    {
//        uint256 releaseImmediateAmount = totalRewardAmount / 10;
//        uint256 releaseLinearLockedAmount = totalRewardAmount - releaseImmediateAmount;
//
//        return (releaseImmediateAmount, releaseLinearLockedAmount);
//    }
//
//    function _getStakeHolderRentDuration(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        uint256 lastClaimAt,
//        uint256 slashAt,
//        string memory machineId
//    ) internal view returns (uint256) {
//        return getRentDuration(msgToSign, substrateSig, substratePubKey, lastClaimAt, slashAt, machineId);
//    }
//
//    function _getDLCUserRentDuration(uint256 lastClaimAt, uint256 slashAt, string memory machineId)
//    internal
//    view
//    returns (uint256)
//    {
//        return getDlcMachineRentDuration(lastClaimAt, slashAt, machineId);
//    }
//
//    function getReward(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string memory machineId
//    ) external view returns (uint256) {
//        address stakeholder = machineId2Address[machineId];
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//        return _getTotalRewardAmount(msgToSign, substrateSig, substratePubKey, machineId, stakeInfo);
//    }
//
//    function claim(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string memory machineId
//    ) public canClaim(machineId) {
//        address stakeholder = msg.sender;
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//
//        uint256 rewardAmount = _getTotalRewardAmount(msgToSign, substrateSig, substratePubKey, machineId, stakeInfo);
//        if (rewardAmount > 0) {
//            require(
//                (block.number - stakeInfo.lastClaimAtBlockNumber) * secondsPerBlock > 1 days,
//                "can not claim yet since last claim less than 1 day"
//            );
//        }
//        uint256 leftSlashAmount = getLeftSlashedAmount(machineId);
//
//        if (getSlashedAt(machineId) > 0) {
//            if (rewardAmount >= leftSlashAmount) {
//                rewardAmount = rewardAmount - leftSlashAmount;
//                address reporter = getSlashedReporter(machineId);
//                require(reporter != address(0), "reporter not found");
//                rewardToken.transfer(reporter, leftSlashAmount);
//                setSlashedPayedDetail(machineId, 0, leftSlashAmount, reporter);
//            } else {
//                rewardAmount = 0;
//                uint256 leftSlashAmountAfterPayedReward = leftSlashAmount - rewardAmount;
//                uint256 reservedAmount = stakeholder2Reserved[stakeholder];
//                uint256 paidSlashAmountFromReserved = 0;
//                if (reservedAmount >= leftSlashAmountAfterPayedReward) {
//                    paidSlashAmountFromReserved = leftSlashAmountAfterPayedReward;
//                    stakeholder2Reserved[stakeholder] = reservedAmount - leftSlashAmountAfterPayedReward;
//                } else {
//                    paidSlashAmountFromReserved = reservedAmount;
//                    stakeholder2Reserved[stakeholder] = 0;
//                }
//                address reporter = getSlashedReporter(machineId);
//                require(reporter != address(0), "reporter not found");
//                rewardToken.transfer(reporter, paidSlashAmountFromReserved + rewardAmount);
//                setSlashedPayedDetail(machineId, paidSlashAmountFromReserved, rewardAmount, reporter);
//            }
//            if (getSlashedAt(machineId) == 0) {
//                require(reportPhaseOneDlcNftStaking(msgToSign, substrateSig, substratePubKey, machineId));
//            }
//        }
//
//        (uint256 canClaimAmount, uint256 lockedAmount) = _getRewardDetail(rewardAmount);
//        canClaimAmount += _calculateDailyReleaseReward(machineId, false);
//
//        if (canClaimAmount > 0) {
//            rewardToken.transfer(stakeholder, canClaimAmount);
//        }
//        stakeInfo.lastClaimAtBlockNumber = block.number;
//
//        if (lockedAmount > 0) {
//            machineId2LockedRewardDetails[machineId].push(
//                LockedRewardDetail({amount: lockedAmount, unlockAt: block.number + LOCK_PERIOD})
//            );
//        }
//
//        emit claimed(stakeholder, machineId, canClaimAmount, leftSlashAmount, block.number);
//    }
//
//    modifier canClaim(string memory machineId) {
//        address stakeholder = machineId2Address[machineId];
//
//        require(stakeholder != address(0), "Invalid stakeholder address");
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//        require(stakeInfo.startAtBlockNumber > 0, "staking not found");
//        require(machineId2Address[machineId] != address(0), "machine not found");
//        _;
//    }
//
//    function _calculateDailyReleaseReward(string memory machineId, bool onlyRead) internal returns (uint256) {
//        LockedRewardDetail[] storage lockedRewardDetails = machineId2LockedRewardDetails[machineId];
//        uint256 totalLockedAmount = 0;
//        for (uint256 i = 0; i < lockedRewardDetails.length; i++) {
//            if (lockedRewardDetails[i].amount == 0) {
//                continue;
//            }
//            if (block.number >= lockedRewardDetails[i].unlockAt) {
//                totalLockedAmount += lockedRewardDetails[i].amount;
//                if (!onlyRead) {
//                    lockedRewardDetails[i].amount = 0;
//                }
//            } else {
//                uint256 dailyUnlockAmount = (lockedRewardDetails[i].amount * DAILY_UNLOCK_RATE) / 1000;
//                totalLockedAmount += dailyUnlockAmount;
//                if (onlyRead) {
//                    lockedRewardDetails[i].amount -= dailyUnlockAmount;
//                }
//            }
//        }
//        return totalLockedAmount;
//    }
//
//    function unStakeAndClaim(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string calldata machineId
//    ) public {
//        address stakeholder = msg.sender;
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//        require(stakeInfo.startAtBlockNumber > 0, "staking not found");
//
//        require(machineId2Address[machineId] != address(0), "machine not found");
//
//        //        uint256 slashedAt = getSlashedAt(machineId);
//        // if (slashedAt == 0) {
//        // todo check stake duration
//        //        require(
//        //            (block.number - stakeInfo.startAtBlockNumber) *secondsPerBlock > REWARD_DURATION, "stake duration is too short, must be longer than 60 days"
//        //        );
//        // }
//        _unStakeAndClaim(msgToSign, substrateSig, substratePubKey, machineId, stakeholder);
//    }
//
//    function _unStakeAndClaim(
//        string memory msgToSign,
//        string memory substrateSig,
//        string memory substratePubKey,
//        string calldata machineId,
//        address stakeholder
//    ) internal {
//        claim(msgToSign, substrateSig, substratePubKey, machineId);
//        uint256 reservedAmount = stakeholder2Reserved[stakeholder];
//        if (reservedAmount > 0) {
//            stakeholder2Reserved[stakeholder] = 0;
//            rewardToken.transfer(stakeholder, reservedAmount);
//        }
//
//        uint256 currentTime = block.number;
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//        stakeInfo.endAtBlockNumber = currentTime;
//        machineId2Address[machineId] = address(0);
//        if (totalStakedMachineMultiCalcPoint > stakeInfo.calcPoint) {
//            totalStakedMachineMultiCalcPoint -= stakeInfo.calcPoint;
//        } else {
//            totalStakedMachineMultiCalcPoint = 0;
//        }
//        for (uint256 i = 0; i < stakeInfo.nftTokenIds.length; i++) {
//            if (stakeInfo.nftTokenIds[i] == 0) {
//                continue;
//            }
//            nftToken.transferFrom(address(this), msg.sender, stakeInfo.nftTokenIds[i]);
//        }
//        require(
//            reportPhaseOneDlcNftEndStaking(msgToSign, substrateSig, substratePubKey, machineId) == true,
//            "report end staking failed"
//        );
//        emit unStaked(msg.sender, machineId, currentTime);
//    }
//
//    function getStakeHolder(string calldata machineId) external view returns (address) {
//        return machineId2Address[machineId];
//    }
//
//    function isStaking(string calldata machineId) public view returns (bool) {
//        address stakeholder = machineId2Address[machineId];
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//        return stakeholder != address(0) && stakeInfo.startAtBlockNumber > 0 && stakeInfo.endAtBlockNumber == 0
//            && getSlashedAt(machineId) == 0;
//    }
//
//    function addNFTs(string calldata machineId, uint256[] calldata nftTokenIds) external {
//        StakeInfo storage stakeInfo = address2StakeInfos[msg.sender][machineId];
//        uint256[] storage machineNftTokenIds = address2NftTokenIds[msg.sender][machineId];
//        require(stakeInfo.nftTokenIds.length + nftTokenIds.length <= MAX_NFTS_PER_MACHINE, "too many nfts, max is 20");
//        for (uint256 i = 0; i < nftTokenIds.length; i++) {
//            uint256 tokenID = nftTokenIds[i];
//            nftToken.transferFrom(msg.sender, address(this), tokenID);
//            stakeInfo.nftTokenIds.push(tokenID);
//            machineNftTokenIds.push(tokenID);
//        }
//
//        uint256 oldCalcPoint = stakeInfo.calcPoint;
//        uint256 newCalcPoint = getMachineCalcPoint(machineId) * nftTokenIds.length;
//        totalStakedMachineMultiCalcPoint += newCalcPoint - oldCalcPoint;
//        stakeInfo.calcPoint = newCalcPoint;
//    }
//
//    function reservedNFTs(string calldata machineId) public view returns (uint256[] memory nftTokenIds) {
//        address stakeholder = machineId2Address[machineId];
//        StakeInfo storage stakeInfo = address2StakeInfos[stakeholder][machineId];
//        return stakeInfo.nftTokenIds;
//    }
//
//    function version() public pure returns (uint256) {
//        return 1;
//    }
//}
