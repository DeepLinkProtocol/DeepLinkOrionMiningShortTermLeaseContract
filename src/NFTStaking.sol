// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "./interface/IPrecompileContract.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./library/Ln.sol";
import "./interface/IStateContract.sol";

contract NFTStaking is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    IPrecompileContract public precompileContract;
    uint8 public constant secondsPerBlock = 6;
    IERC20 public rewardToken;

    uint256 public rewardAmountPerSecond;
    uint256 public constant baseReserveAmount = 10_000 * 10 ** 18;

    uint256 public nonlinearCoefficientNumerator;
    uint256 public nonlinearCoefficientDenominator;

    string[] public machineIds;
    mapping(address => uint256) public stakeholder2Reserved;
    uint256 public totalReservedAmount;
    mapping(string => address) public machineId2Address;
    uint256 public startAt;
    uint256 public slashAmountOfReport;
    uint256 public totalCalcPoint;

    struct StakeInfo {
        address holder;
        uint256 startAtBlockNumber;
        uint256 lastClaimAtBlockNumber;
        uint256 endAtBlockNumber;
        uint256 calcPoint;
        uint256 reservedAmount;
        uint256[] nftTokenIds;
        uint256 rentId;
        uint256 lnResultNumerator;
        uint256 lnResultDenominator;
        uint256 claimedAmount;
    }

    struct SlashPayedDetail {
        uint256 fromReservedAmount;
        uint256 fromRewardAmount;
        uint256 totalPayedAmount;
        uint256 at;
    }

    struct SlashPayedInfo {
        uint256 totalPayedAmount;
        address to;
    }

    mapping(address => uint8) public walletAddress2StakingMachineCount;

    address[] public addressInStaking;

    mapping(uint256 => SlashPayedInfo) public slashReportId2SlashPaidInfo;

    mapping(string => StakeInfo) public machineId2StakeInfos;

    IERC721 public nftToken;

    struct LockedRewardDetail {
        uint256 amount;
        uint256 unlockAt;
    }

    mapping(string => LockedRewardDetail[]) public machineId2LockedRewardDetails;

    uint8 public constant MAX_NFTS_PER_MACHINE = 20;
    uint256 public daily_reward;
//    uint256 public constant REWARD_DURATION = 60 days;
    uint256 public constant REWARD_DURATION = 0.05 days; //todo: change to 60 days

    uint256 public constant LOCK_PERIOD = 180 days;
    uint8 public constant DAILY_UNLOCK_RATE = 5; // 0.5% = 5/1000
    uint256 public constant SECONDS_PER_DAY = 1 days;


//    struct MachineInfo {
//        uint256 calcPoint;
//        uint256 gpuCount;
//        uint256 reserveAmount;
//    }
//
//    struct StakeHolderInfo {
//        address holder;
//        uint256 totalCalcPoint;
//        uint256 totalGPUCount;
//        uint256 totalReservedAmount;
//        string[] machineIds;
//        mapping(string => MachineInfo) machineId2Info;
//    }
//
//    struct SimpleStakeHolder {
//        address holder;
//        uint256 totalCalcPoint;
//    }
//
//    SimpleStakeHolder[3] public topStakeHolders;
//    mapping(address => StakeHolderInfo) public stakeHolders;

    uint8 public phaseLevel;

    struct MachineInfo {
        uint256 calcPoint;
        uint256 gpuCount;
        uint256 reserveAmount;
    }

    struct StakeHolderInfo {
        address holder;
        uint256 totalCalcPoint;
        uint256 totalGPUCount;
        uint256 totalReservedAmount;
        string[] machineIds;
        mapping(string => MachineInfo) machineId2Info;
    }

    struct SimpleStakeHolder {
        address holder;
        uint256 totalCalcPoint;
    }

    SimpleStakeHolder[3] public topStakeHolders;
    mapping(address => StakeHolderInfo) public stakeHolders;


    event nonlinearCoefficientChanged(uint256 nonlinearCoefficientNumerator, uint256 nonlinearCoefficientDenominator);

    event staked(address indexed stakeholder, string machineId, uint256 stakeAtBlockNumber);
    event unStaked(address indexed stakeholder, string machineId, uint256 unStakeAtBlockNumber);
    event claimed(
        address indexed stakeholder,
        string machineId,
        uint256 rewardAmount,
        uint256 slashAmount,
        uint256 claimAtBlockNumber
    );
    event claimedAll(address indexed stakeholder, uint256 claimAtBlockNumber);
    event rewardTokenSet(address indexed addr);
    event nftTokenSet(address indexed addr);
    event slashPayedDetail(
        string machineId,
        uint256 fromReservedAmount,
        uint256 fromRewardAmount,
        uint256 totalPayedAmount,
        uint256 reportId,
        address to
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _nftToken,
        address _rewardToken,
        address _precompileContract,
        uint8 _phase_level
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
        nftToken = IERC721(_nftToken);
        phaseLevel = _phase_level;
        nonlinearCoefficientNumerator = 1;
        nonlinearCoefficientDenominator = 10;

        if (phaseLevel == 1) {
            daily_reward = 6000000 * 1e18;
        }
        if (phaseLevel == 2) {
            daily_reward = 8000000 * 1e18;
        }
        if (phaseLevel == 3) {
            daily_reward = 19330000 * 1e18;
        }

        if (_rewardToken != address(0x0)) {
            rewardToken = IERC20(_rewardToken);
        }
        if (_precompileContract != address(0x0)) {
            precompileContract = IPrecompileContract(_precompileContract);
        }
        startAt = block.number;
        slashAmountOfReport = 10000 * 1e18;
        rewardAmountPerSecond = uint256(daily_reward / 1 days);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setPrecompileContract(address _registerContract) external onlyOwner {
        precompileContract = IPrecompileContract(_registerContract);
    }

    function claimLeftRewardTokens() external onlyOwner {
        uint256 balance = rewardToken.balanceOf(address(this));
        rewardToken.transfer(msg.sender, balance);
    }

    function setRewardToken(address token) external onlyOwner {
        rewardToken = IERC20(token);
        emit rewardTokenSet(token);
    }

    function setNftToken(address token) external onlyOwner {
        nftToken = IERC721(token);
        emit nftTokenSet(token);
    }

    function setNonlinearCoefficient(uint256 numerator, uint256 denominator) public onlyOwner {
        nonlinearCoefficientNumerator = numerator;
        nonlinearCoefficientDenominator = denominator;

        emit nonlinearCoefficientChanged(numerator, denominator);
    }

    function rewardPerSecond() public view returns (uint256) {
        if (getRewardStartAt() > 0) {
            return rewardAmountPerSecond;
        }

        return 0;
    }

    function reportDlcNftStaking(
        string memory msgToSign,
        string memory substrateSig,
        string memory substratePubKey,
        string memory machineId
    ) internal returns (bool success) {
        return precompileContract.reportDlcNftStaking(msgToSign, substrateSig, substratePubKey, machineId, phaseLevel);
    }

    function reportDlcNftEndStaking(
        string memory msgToSign,
        string memory substrateSig,
        string memory substratePubKey,
        string memory machineId
    ) internal returns (bool success) {
        return
            precompileContract.reportDlcNftEndStaking(msgToSign, substrateSig, substratePubKey, machineId, phaseLevel);
    }

    function getRentingDuration(
        string memory msgToSign,
        string memory substrateSig,
        string memory substratePubKey,
        string memory machineId,
        uint256 rentId
    ) public view returns (uint256 duration) {
        return precompileContract.getRentingDuration(msgToSign, substrateSig, substratePubKey, machineId, rentId);
    }

    function getValidRewardDuration(uint256 last_claim_at, uint256 total_stake_duration, uint256 phase_number)
        public
        view
        returns (uint256 valid_duration)
    {
        return precompileContract.getValidRewardDuration(last_claim_at, total_stake_duration, phase_number);
    }

    function getRewardStartAt() public view returns (uint256 phaseOneRewardStartAt) {
        return precompileContract.getDlcNftStakingRewardStartAt(phaseLevel);
    }

    function stake(
        string memory msgToSign,
        string memory substrateSig,
        string memory substratePubKey,
        string calldata machineId,
        uint256 amount,
        uint256[] calldata nftTokenIds,
        uint256 rentId
    ) external nonReentrant {
        uint256 rewardStart = getRewardStartAt();
        if (rewardStart > 0) {
            require((block.number - rewardStart) * secondsPerBlock < REWARD_DURATION, "staking ended");
        }

        address stakeholder = msg.sender;
        require(stakeholder != address(0), "invalid stakeholder address");
        require(!isStaking(machineId), "machine already staked");
        require(nftTokenIds.length > 0, "nft token ids is empty");
        uint256 calcPoint = getMachineCalcPoint(machineId) * nftTokenIds.length;
        totalCalcPoint += calcPoint;
        require(calcPoint > 0, "machine calc point not found");
        uint256 rentDuration = getRentingDuration(msgToSign, substrateSig, substratePubKey, machineId, rentId);
        require(
            rentDuration * secondsPerBlock >= REWARD_DURATION, "rent duration must be longer than 60 days"
        );

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        uint256 slashedAt = getSlashedAt(machineId);

        if (slashedAt > 0) {
            uint256 shouldSlashAmount = getLeftSlashedAmount(machineId);
            require(amount >= shouldSlashAmount, "should pay slash amount before stake");
            address reporter = getSlashedReporter(machineId);
            require(reporter != address(0), "reporter not found");
            rewardToken.transferFrom(stakeholder, reporter, shouldSlashAmount);
            amount = amount - shouldSlashAmount;
            setSlashedPayedDetail(machineId, shouldSlashAmount, 0, reporter);
        } else {
            if (stakeInfo.endAtBlockNumber == 0) {
                require(stakeInfo.startAtBlockNumber == 0, "machine already staked");
                require(stakeInfo.endAtBlockNumber == 0, "machine stake not end");
            }
        }

        if (amount > 0) {
            stakeholder2Reserved[stakeholder] += amount;
            totalReservedAmount += amount;
            rewardToken.transferFrom(stakeholder, address(this), amount);
        }
        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            nftToken.transferFrom(msg.sender, address(this), nftTokenIds[i]);
        }

        (uint256 numerator, uint256 denominator) = getLnResult(amount);
        if (numerator == 0 && denominator == 0) {
            denominator = 1;
        }
        uint256 currentTime = block.number;
        machineId2StakeInfos[machineId] = StakeInfo({
            startAtBlockNumber: currentTime,
            lastClaimAtBlockNumber: currentTime,
            endAtBlockNumber: 0,
            calcPoint: calcPoint,
            reservedAmount: amount,
            nftTokenIds: nftTokenIds,
            rentId: rentId,
            holder: stakeholder,
            lnResultNumerator: numerator,
            lnResultDenominator: denominator,
            claimedAmount: 0
        });

        machineId2Address[machineId] = stakeholder;

        require(
            reportDlcNftStaking(msgToSign, substrateSig, substratePubKey, machineId) == true, "report staking failed"
        );

        uint256 stakedMachineCount = walletAddress2StakingMachineCount[stakeholder];
        if (stakedMachineCount == 0) {
            addressInStaking.push(stakeholder);
        }
        walletAddress2StakingMachineCount[stakeholder] += 1;
        machineIds.push(machineId);
        addOrUpdateStakeHolder(stakeholder, machineId, calcPoint, amount);

        emit staked(stakeholder, machineId, currentTime);
    }

    function getLnResult(uint256 reserveAmount) public pure returns (uint256, uint256) {
        uint256 value = 0;
        if (reserveAmount >= baseReserveAmount) {
            value = reserveAmount - baseReserveAmount;
        }
        return LogarithmLibrary.lnAsFraction(value + baseReserveAmount, baseReserveAmount);
    }

    function getMachineCalcPoint(string memory machineId) internal view returns (uint256) {
        return precompileContract.getMachineCalcPoint(machineId);
    }
//
//    function getMachineGPUCount(string memory machineId) public view returns (uint256) {
//        return precompileContract.getMachineGPUCount(machineId);
//    }

    function getRentDuration(uint256 lastClaimAt, uint256 slashAt, uint256 endAt, string memory machineId)
        public
        view
        returns (uint256)
    {
        return precompileContract.getRentDuration(lastClaimAt, slashAt, endAt, machineId);
    }

    function getDlcMachineRentDuration(uint256 lastClaimAt, uint256 slashAt, string memory machineId)
        public
        view
        returns (uint256 rentDuration)
    {
        return precompileContract.getDlcMachineRentDuration(lastClaimAt, slashAt, machineId);
    }

    function getSlashedAt(string memory machineId) public view returns (uint256) {
        if (!precompileContract.isSlashed(machineId)) {
            return 0;
        }

        uint256 slashReportId = getDlcMachineSlashedReportId(machineId);

        if (isPaidSlashed(slashReportId)) {
            return 0;
        }

        return precompileContract.getDlcMachineSlashedAt(machineId);
    }

    function getLeftSlashedAmount(string memory machineId) public view returns (uint256) {
        if (getSlashedAt(machineId) > 0) {
            uint256 slashReportId = precompileContract.getDlcMachineSlashedReportId(machineId);
            SlashPayedInfo storage slashPayedInfo = slashReportId2SlashPaidInfo[slashReportId];
            return slashAmountOfReport - slashPayedInfo.totalPayedAmount;
        }
        return 0;
    }

    function setSlashedPayedDetail(
        string memory machineId,
        uint256 fromReservedAmount,
        uint256 fromRewardAmount,
        address to
    ) internal {
        uint256 total = fromReservedAmount + fromRewardAmount;
        uint256 slashReportId = precompileContract.getDlcMachineSlashedReportId(machineId);
        SlashPayedInfo storage slashPayedInfo = slashReportId2SlashPaidInfo[slashReportId];
        slashPayedInfo.totalPayedAmount += total;
        slashPayedInfo.to = to;
        slashReportId2SlashPaidInfo[slashReportId] = slashPayedInfo;
        emit slashPayedDetail(
            machineId, fromReservedAmount, fromRewardAmount, slashPayedInfo.totalPayedAmount, slashReportId, to
        );
    }

    function getDlcMachineSlashedReportId(string memory machineId) public view returns (uint256) {
        if (!precompileContract.isSlashed(machineId)) {
            return 0;
        }
        return uint256(precompileContract.getDlcMachineSlashedReportId(machineId));
    }

    function getSlashedReporter(string memory machineId) public view returns (address) {
        uint256 slashReportId = getDlcMachineSlashedReportId(machineId);
        bool isPaid = isPaidSlashed(slashReportId);
        if (isPaid) {
            return address(0x0);
        }
        return precompileContract.getDlcMachineSlashedReporter(machineId);
    }

    function isPaidSlashed(uint256 slashReportId) internal view returns (bool) {
        SlashPayedInfo storage slashPayedInfo = slashReportId2SlashPaidInfo[slashReportId];
        return slashPayedInfo.totalPayedAmount == slashAmountOfReport;
    }

    function _getTotalRewardAmount(string memory machineId, StakeInfo storage stakeInfo)
        internal
        view
        returns (uint256)
    {
        if (stakeInfo.lastClaimAtBlockNumber == 0) {
            return 0;
        }
        uint256 rewardStartAt = getRewardStartAt();

        uint256 lastClaimAtBlockNumber = stakeInfo.lastClaimAtBlockNumber;
        if (rewardStartAt > stakeInfo.lastClaimAtBlockNumber) {
            lastClaimAtBlockNumber = rewardStartAt;
        }

        uint256 slashedAt = getSlashedAt(machineId);
        uint256 totalRewardDuration = _getStakeHolderRentDuration(
            stakeInfo.lastClaimAtBlockNumber, slashedAt, stakeInfo.endAtBlockNumber, machineId
        );
        if (totalRewardDuration == 0) {
            return 0;
        }

        totalRewardDuration = getValidRewardDuration(stakeInfo.lastClaimAtBlockNumber, totalRewardDuration, phaseLevel);

        uint256 rewardPerSecond_ = rewardPerSecond();
        if (rewardPerSecond_ == 0) {
            return 0;
        }

        uint256 rentDuration = getDlcMachineRentDuration(stakeInfo.lastClaimAtBlockNumber, slashedAt, machineId);

        uint256 totalBaseReward = rewardPerSecond_ * totalRewardDuration;

        uint256 currentMachineMultiCalcPoint =
            (stakeInfo.calcPoint * (totalRewardDuration - rentDuration) + stakeInfo.calcPoint * 13 / 10 * rentDuration);
        uint256 _totalStakedMachineMultiCalcPoint = currentMachineMultiCalcPoint;
        for (uint256 i = 0; i < machineIds.length; i++) {
            string storage _machineId = machineIds[i];
            uint256 _slash_at = getSlashedAt(_machineId);
            if (keccak256(abi.encodePacked(_machineId)) == keccak256(abi.encodePacked(machineId))) {
                continue;
            }
            StakeInfo storage _stakeInfo = machineId2StakeInfos[_machineId];

            if (_stakeInfo.endAtBlockNumber == 0) {
                uint256 _totalRewardDuration = _getStakeHolderRentDuration(
                    stakeInfo.lastClaimAtBlockNumber, _slash_at, _stakeInfo.endAtBlockNumber, machineId
                );

                _totalRewardDuration =
                    getValidRewardDuration(stakeInfo.lastClaimAtBlockNumber, totalRewardDuration, phaseLevel);

                uint256 _rentDuration =
                    getDlcMachineRentDuration(stakeInfo.lastClaimAtBlockNumber, getSlashedAt(_machineId), machineId);

                uint256 _currentMachineMultiCalcPoint = (
                    _stakeInfo.calcPoint * (_totalRewardDuration - _rentDuration)
                        + _stakeInfo.calcPoint * 13 / 10 * _rentDuration
                );

                _totalStakedMachineMultiCalcPoint += _currentMachineMultiCalcPoint;
            }
        }

        uint256 otherRewardAmount = 0;
        for (uint256 i = 0; i < machineIds.length; i++) {
            string storage _machineId = machineIds[i];
            uint256 _slash_at = getSlashedAt(_machineId);
            if (keccak256(abi.encodePacked(_machineId)) == keccak256(abi.encodePacked(machineId))) {
                continue;
            }
            StakeInfo storage _stakeInfo = machineId2StakeInfos[_machineId];
            if (_stakeInfo.startAtBlockNumber > stakeInfo.lastClaimAtBlockNumber) {
                uint256 _totalRewardDuration = _getStakeHolderRentDuration(
                    stakeInfo.lastClaimAtBlockNumber, _slash_at, _stakeInfo.endAtBlockNumber, machineId
                );

                _totalRewardDuration =
                    getValidRewardDuration(stakeInfo.lastClaimAtBlockNumber, totalRewardDuration, phaseLevel);

                uint256 _rentDuration =
                    getDlcMachineRentDuration(stakeInfo.lastClaimAtBlockNumber, getSlashedAt(_machineId), machineId);

                uint256 _currentMachineMultiCalcPoint = (
                    _stakeInfo.calcPoint * (_totalRewardDuration - _rentDuration)
                        + stakeInfo.calcPoint * 13 / 10 * _rentDuration
                );

                uint256 expectBaseRewardAmount = rewardPerSecond_ * _totalRewardDuration;
                uint256 _baseRewardAmount =
                    expectBaseRewardAmount * _currentMachineMultiCalcPoint / _totalStakedMachineMultiCalcPoint;

                otherRewardAmount += _baseRewardAmount
                    + _baseRewardAmount * nonlinearCoefficientNumerator / nonlinearCoefficientDenominator
                        * _stakeInfo.lnResultNumerator / _stakeInfo.lnResultDenominator;
            }
        }

        uint256 baseRewardAmount = totalBaseReward * currentMachineMultiCalcPoint / _totalStakedMachineMultiCalcPoint;

        uint256 value = 0;
        if (stakeInfo.reservedAmount > baseReserveAmount) {
            value = stakeInfo.reservedAmount - baseReserveAmount;
        }

        uint256 totalRewardAmount = baseRewardAmount
            + baseRewardAmount * nonlinearCoefficientNumerator / nonlinearCoefficientDenominator
                * stakeInfo.lnResultNumerator / stakeInfo.lnResultDenominator;
        if (totalRewardAmount + otherRewardAmount > totalBaseReward) {
            totalRewardAmount = totalRewardAmount * totalBaseReward / (totalRewardAmount + otherRewardAmount);
        }

        return totalRewardAmount;
    }

    function getRewardAmountCanClaim(string memory machineId)
        public
        returns (uint256 canClaimAmount, uint256 lockedAmount)
    {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        uint256 totalRewardAmount = _getTotalRewardAmount(machineId, stakeInfo);

        uint256 slashAmount = getLeftSlashedAmount(machineId);
        if (slashAmount > 0) {
            if (totalRewardAmount >= slashAmount) {
                totalRewardAmount - slashAmount;
            } else {
                return (0, 0);
            }
        }

        (uint256 _canClaimAmount, uint256 _lockedAmount) = _getRewardDetail(totalRewardAmount);
        (uint256 dailyReleaseAmount, uint256 lockedAmountBefore) = _calculateDailyReleaseReward(machineId, true);
        return (_canClaimAmount + dailyReleaseAmount, _lockedAmount + lockedAmountBefore);
    }

    function _getRewardDetail(uint256 totalRewardAmount)
        internal
        pure
        returns (uint256 canClaimAmount, uint256 lockedAmount)
    {
        uint256 releaseImmediateAmount = totalRewardAmount / 10;
        uint256 releaseLinearLockedAmount = totalRewardAmount - releaseImmediateAmount;
        return (releaseImmediateAmount, releaseLinearLockedAmount);
    }

    function _getStakeHolderRentDuration(uint256 lastClaimAt, uint256 slashAt, uint256 endAt, string memory machineId)
        internal
        view
        returns (uint256)
    {
        return getRentDuration(lastClaimAt, slashAt, endAt, machineId);
    }

    function _getDLCUserRentDuration(uint256 lastClaimAt, uint256 slashAt, string memory machineId)
        internal
        view
        returns (uint256)
    {
        return getDlcMachineRentDuration(lastClaimAt, slashAt, machineId);
    }

    function getReward(string memory machineId) external view returns (uint256) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        return _getTotalRewardAmount(machineId, stakeInfo);
    }

    function claim(
        string memory msgToSign,
        string memory substrateSig,
        string memory substratePubKey,
        string memory machineId
    ) public canClaim(machineId) {
        address stakeholder = msg.sender;
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == stakeholder, "not stakeholder");

        uint256 rewardAmount = _getTotalRewardAmount(machineId, stakeInfo);
        if (rewardAmount > 0) {
            require(
                (block.number - stakeInfo.lastClaimAtBlockNumber) * secondsPerBlock >= 1 days,
                "last claim less than 1 day"
            );
        }
        uint256 leftSlashAmount = getLeftSlashedAmount(machineId);

        if (getSlashedAt(machineId) > 0) {
            if (rewardAmount >= leftSlashAmount) {
                rewardAmount = rewardAmount - leftSlashAmount;
                address reporter = getSlashedReporter(machineId);
                require(reporter != address(0), "reporter not found");
                rewardToken.transfer(reporter, leftSlashAmount);
                setSlashedPayedDetail(machineId, 0, leftSlashAmount, reporter);
            } else {
                rewardAmount = 0;
                uint256 leftSlashAmountAfterPayedReward = leftSlashAmount - rewardAmount;
                uint256 reservedAmount = stakeholder2Reserved[stakeholder];
                uint256 paidSlashAmountFromReserved = 0;
                if (reservedAmount >= leftSlashAmountAfterPayedReward) {
                    paidSlashAmountFromReserved = leftSlashAmountAfterPayedReward;
                    uint256 leftReservedAmount = 0;
                    if (reservedAmount - paidSlashAmountFromReserved > 0) {
                        leftReservedAmount = reservedAmount - paidSlashAmountFromReserved;
                    }
                    stakeholder2Reserved[stakeholder] = leftReservedAmount;
                    stakeInfo.reservedAmount = leftReservedAmount;
                    if (totalReservedAmount - reservedAmount + leftReservedAmount > 0) {
                        totalReservedAmount = totalReservedAmount - reservedAmount + leftReservedAmount;
                    } else {
                        totalReservedAmount = 0;
                    }

                    (uint256 numerator, uint256 denominator) = getLnResult(leftReservedAmount);
                    stakeInfo.lnResultNumerator = numerator;
                    if (numerator == 0 && denominator == 0) {
                        denominator = 1;
                    }
                    stakeInfo.lnResultDenominator = denominator;
                } else {
                    paidSlashAmountFromReserved = reservedAmount;
                    stakeholder2Reserved[stakeholder] = 0;
                    stakeInfo.reservedAmount = 0;
                    stakeInfo.lnResultNumerator = 0;
                    stakeInfo.lnResultDenominator = 1;
                    totalReservedAmount -= reservedAmount;
                }
                address reporter = getSlashedReporter(machineId);
                require(reporter != address(0), "reporter not found");
                rewardToken.transfer(reporter, paidSlashAmountFromReserved + rewardAmount);
                setSlashedPayedDetail(machineId, paidSlashAmountFromReserved, rewardAmount, reporter);
            }
            if (getSlashedAt(machineId) == 0) {
                require(reportDlcNftStaking(msgToSign, substrateSig, substratePubKey, machineId));
            }
        }

        (uint256 canClaimAmount, uint256 lockedAmount) = _getRewardDetail(rewardAmount);
        (uint256 _dailyReleaseAmount,) = _calculateDailyReleaseReward(machineId, false);
        canClaimAmount += _dailyReleaseAmount;

        if (canClaimAmount > 0) {
            rewardToken.transfer(stakeholder, canClaimAmount);
        }
        stakeInfo.claimedAmount += canClaimAmount;
        stakeInfo.lastClaimAtBlockNumber = block.number;

        if (lockedAmount > 0) {
            machineId2LockedRewardDetails[machineId].push(
                LockedRewardDetail({amount: lockedAmount, unlockAt: block.number + LOCK_PERIOD})
            );
        }

        emit claimed(stakeholder, machineId, canClaimAmount, leftSlashAmount, block.number);
    }

    modifier canClaim(string memory machineId) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder != address(0), "Invalid stakeholder address");
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        require(stakeInfo.startAtBlockNumber > 0, "staking not found");
        require(machineId2Address[machineId] != address(0), "machine not found");
        _;
    }

    function _calculateDailyReleaseReward(string memory machineId, bool onlyRead)
        internal
        returns (uint256 dailyReleaseAmount, uint256 lockedAmount)
    {
        LockedRewardDetail[] storage lockedRewardDetails = machineId2LockedRewardDetails[machineId];
        uint256 _dailyReleaseAmount = 0;
        uint256 _lockedAmount = 0;
        for (uint256 i = 0; i < lockedRewardDetails.length; i++) {
            if (lockedRewardDetails[i].amount == 0) {
                continue;
            }
            if (block.number >= lockedRewardDetails[i].unlockAt) {
                _dailyReleaseAmount += lockedRewardDetails[i].amount;
                if (!onlyRead) {
                    lockedRewardDetails[i].amount = 0;
                }
            } else {
                uint256 dailyUnlockAmount = (lockedRewardDetails[i].amount * DAILY_UNLOCK_RATE) / 1000;
                _dailyReleaseAmount += dailyUnlockAmount;
                if (!onlyRead) {
                    lockedRewardDetails[i].amount -= dailyUnlockAmount;
                }
            }
            _lockedAmount += lockedRewardDetails[i].amount;
        }
        return (_dailyReleaseAmount, _lockedAmount - _dailyReleaseAmount);
    }

    function unStakeAndClaim(
        string memory msgToSign,
        string memory substrateSig,
        string memory substratePubKey,
        string calldata machineId
    ) public nonReentrant {
        address stakeholder = msg.sender;
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == stakeholder, "not stakeholder");
        require(stakeInfo.startAtBlockNumber > 0, "staking not found");

        require(machineId2Address[machineId] != address(0), "machine not found");

        uint256 rewardStartAt = getRewardStartAt();
        if (rewardStartAt > 0) {
            uint256 slashedAt = getSlashedAt(machineId);
            if (slashedAt == 0) {
                require(
                    (block.number - stakeInfo.startAtBlockNumber) * secondsPerBlock > REWARD_DURATION,
                    "staking reward duration not end yet"
                );
            }
        }
        _unStakeAndClaim(msgToSign, substrateSig, substratePubKey, machineId, stakeholder);
        removeMachine(stakeholder, machineId);
    }

    function _unStakeAndClaim(
        string memory msgToSign,
        string memory substrateSig,
        string memory substratePubKey,
        string calldata machineId,
        address stakeholder
    ) internal {
        claim(msgToSign, substrateSig, substratePubKey, machineId);
        uint256 reservedAmount = stakeholder2Reserved[stakeholder];
        if (reservedAmount > 0) {
            stakeholder2Reserved[stakeholder] = 0;
            rewardToken.transfer(stakeholder, reservedAmount);
            if (totalReservedAmount > reservedAmount) {
                totalReservedAmount -= reservedAmount;
            } else {
                totalReservedAmount = 0;
            }
        }

        uint256 currentTime = block.number;
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        stakeInfo.endAtBlockNumber = currentTime;
        if (totalCalcPoint >= stakeInfo.calcPoint) {
            totalCalcPoint -= stakeInfo.calcPoint;
        } else {
            totalCalcPoint = 0;
        }
        machineId2Address[machineId] = address(0);

        for (uint256 i = 0; i < stakeInfo.nftTokenIds.length; i++) {
            if (stakeInfo.nftTokenIds[i] == 0) {
                continue;
            }
            nftToken.transferFrom(address(this), msg.sender, stakeInfo.nftTokenIds[i]);
        }
        require(
            reportDlcNftEndStaking(msgToSign, substrateSig, substratePubKey, machineId) == true,
            "report end staking failed"
        );
        removeMachineIdByValueUnordered(machineId);

        uint256 stakedMachineCount = walletAddress2StakingMachineCount[stakeholder];
        if (stakedMachineCount > 0) {
            if (stakedMachineCount == 1) {
                removeAddressByValueUnordered(stakeholder);
            }
            walletAddress2StakingMachineCount[stakeholder] -= 1;
        }

        emit unStaked(msg.sender, machineId, currentTime);
    }

    function getStakeHolder(string calldata machineId) external view returns (address) {
        return machineId2Address[machineId];
    }

    function isStaking(string calldata machineId) public view returns (bool) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.holder != address(0) && stakeInfo.startAtBlockNumber > 0 && stakeInfo.endAtBlockNumber == 0
            && getSlashedAt(machineId) == 0;
    }

    function addNFTs(string calldata machineId, uint256[] calldata nftTokenIds) external {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        require(stakeInfo.nftTokenIds.length + nftTokenIds.length <= MAX_NFTS_PER_MACHINE, "too many nfts, max is 20");
        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            uint256 tokenID = nftTokenIds[i];
            nftToken.transferFrom(msg.sender, address(this), tokenID);
            stakeInfo.nftTokenIds.push(tokenID);
        }

        uint256 oldCalcPoint = stakeInfo.calcPoint;

        uint256 newCalcPoint = getMachineCalcPoint(machineId) * stakeInfo.nftTokenIds.length;
        if (totalCalcPoint >= oldCalcPoint) {
            totalCalcPoint = totalCalcPoint - oldCalcPoint + newCalcPoint;
        } else {
            totalCalcPoint = newCalcPoint;
        }

        stakeInfo.calcPoint = newCalcPoint;
        addOrUpdateStakeHolder(stakeInfo.holder, machineId, stakeInfo.calcPoint, 0);
    }

    function reservedNFTs(string calldata machineId) public view returns (uint256[] memory nftTokenIds) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        return stakeInfo.nftTokenIds;
    }

    function removeMachineIdByValueUnordered(string memory machineId) public {
        uint256 index = findMachineIdIndex(machineId);

        machineIds[index] = machineIds[machineIds.length - 1];

        machineIds.pop();
    }

    function removeAddressByValueUnordered(address addr) public {
        uint256 index = findAddressInStakingIndex(addr);

        addressInStaking[index] = addressInStaking[addressInStaking.length - 1];

        addressInStaking.pop();
    }

//    function removeStringValueOfArray(string memory addr, string[] storage arr) internal {
//        uint256 index = findStringIndex(arr, addr);
//        arr[index] = arr[arr.length - 1];
//        arr.pop();
//    }

    function findMachineIdIndex(string memory machineId) internal view returns (uint256) {
        for (uint256 i = 0; i < machineIds.length; i++) {
            if (keccak256(abi.encodePacked(machineIds[i])) == keccak256(abi.encodePacked(machineId))) {
                return i;
            }
        }
        revert("Element not found");
    }

//    function findStringIndex(string[] memory arr, string memory v) internal pure returns (uint256) {
//        for (uint256 i = 0; i < arr.length; i++) {
//            if (keccak256(abi.encodePacked(arr[i])) == keccak256(abi.encodePacked(v))) {
//                return i;
//            }
//        }
//        revert("Element not found");
//    }

    function findAddressInStakingIndex(address addr) internal view returns (uint256) {
        for (uint256 i = 0; i < addressInStaking.length; i++) {
            if (addressInStaking[i] == addr) {
                return i;
            }
        }
        revert("Element not found");
    }

    function GPUCountDetail() public view returns (uint256 totalGPUCount, uint256 gpuCountBeforeRewardStart) {
        return precompileContract.getDlcStakingGPUCount(phaseLevel);
    }

    function getRentedGPUCountInDlcNftStaking() external view returns (uint256) {
        return precompileContract.getRentedGPUCountInDlcNftStaking(phaseLevel);
    }

    function getTotalDlcNftStakingBurnedRentFee() external view returns (uint256) {
        return precompileContract.getTotalDlcNftStakingBurnedRentFee(phaseLevel);
    }

    function getRentedGPUCountOfMachineInDlcNftStaking(string memory machineId) public view returns (uint256) {
        return precompileContract.getRentedGPUCountOfMachineInDlcNftStaking(phaseLevel, machineId);
    }

    function getDlcNftStakingBurnedRentFeeByMachine(string memory machineId) public view returns (uint256) {
        return precompileContract.getDlcNftStakingBurnedRentFeeByMachine(phaseLevel, machineId);
    }

    function getTotalRewardAmount(address _holder) public returns (uint256, uint256) {
        uint256 totalReleasedAmount = 0;
        uint256 totalLockedAmount = 0;
        string[] memory machineIdsOfHolder = getHolderMachineIds(_holder);
        for (uint256 i = 0; i < machineIdsOfHolder.length; i++) {
            string memory machineId = machineIdsOfHolder[i];
            uint256 claimedAmount = machineId2StakeInfos[machineIdsOfHolder[i]].claimedAmount;
            (uint256 canClaimedAmount, uint256 lockedAmount) = getRewardAmountCanClaim(machineId);
            totalReleasedAmount += claimedAmount + canClaimedAmount;
            totalLockedAmount += lockedAmount;
        }
        return (totalReleasedAmount, totalLockedAmount);
    }
//
//    function addOrUpdateStakeHolder(
//        address _holder,
//        string memory _machineId,
//        uint256 _calcPoint,
//        uint256 _reservedAmount
//    ) internal {
//        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
//
//        if (stakeHolderInfo.holder == address(0)) {
//            stakeHolderInfo.holder = _holder;
//        }
//
//        MachineInfo memory previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
//        stakeHolderInfo.machineId2Info[_machineId].calcPoint = _calcPoint;
//        if (stakeHolderInfo.machineId2Info[_machineId].gpuCount == 0) {
//            uint256 gpuCount = getMachineGPUCount(_machineId);
//            stakeHolderInfo.machineId2Info[_machineId].gpuCount = gpuCount;
//
//            stakeHolderInfo.totalGPUCount = stakeHolderInfo.totalGPUCount + gpuCount;
//        }
//        if (previousMachineInfo.reserveAmount == 0 && previousMachineInfo.calcPoint == 0) {
//            stakeHolderInfo.totalReservedAmount += _reservedAmount;
//            stakeHolderInfo.machineId2Info[_machineId].reserveAmount = _reservedAmount;
//            stakeHolderInfo.machineIds.push(_machineId);
//        }
//
//        stakeHolderInfo.totalCalcPoint = stakeHolderInfo.totalCalcPoint + _calcPoint - previousMachineInfo.calcPoint;
//
//        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
//    }
//
//    function removeMachine(address _holder, string memory _machineId) internal {
//        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
//
//        MachineInfo memory stakeInfoToRemove = stakeHolderInfo.machineId2Info[_machineId];
//        require(stakeInfoToRemove.calcPoint > 0, "Machine not found");
//
//        stakeHolderInfo.totalCalcPoint -= stakeInfoToRemove.calcPoint;
//        stakeHolderInfo.totalGPUCount -= stakeInfoToRemove.gpuCount;
//        stakeHolderInfo.totalReservedAmount -= stakeInfoToRemove.reserveAmount;
//        removeStringValueOfArray(_machineId, stakeHolderInfo.machineIds);
//        delete stakeHolderInfo.machineId2Info[_machineId];
//
//        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
//    }
//
//    function updateTopStakeHolders(address _holder, uint256 _totalCalcPoint) internal {
//        uint256 minIndex = 0;
//        bool shouldInsert = false;
//
//        for (uint256 i = 1; i < topStakeHolders.length; i++) {
//            if (topStakeHolders[i].totalCalcPoint < topStakeHolders[minIndex].totalCalcPoint) {
//                minIndex = i;
//            }
//        }
//
//        if (topStakeHolders[minIndex].totalCalcPoint == 0 || _totalCalcPoint > topStakeHolders[minIndex].totalCalcPoint)
//        {
//            topStakeHolders[minIndex] = SimpleStakeHolder(_holder, _totalCalcPoint);
//            shouldInsert = true;
//        }
//
//        if (shouldInsert) {
//            sortTopStakeHolders();
//        }
//    }
//
//    function sortTopStakeHolders() internal {
//        for (uint256 i = 0; i < topStakeHolders.length - 1; i++) {
//            for (uint256 j = i + 1; j < topStakeHolders.length; j++) {
//                if (topStakeHolders[i].totalCalcPoint < topStakeHolders[j].totalCalcPoint) {
//                    SimpleStakeHolder memory temp = topStakeHolders[i];
//                    topStakeHolders[i] = topStakeHolders[j];
//                    topStakeHolders[j] = temp;
//                }
//            }
//        }
//    }
//
//    function getTotalRewardAmount(address _holder) public returns (uint256, uint256) {
//        uint256 totalReleasedAmount = 0;
//        uint256 totalLockedAmount = 0;
//        for (uint256 i = 0; i < stakeHolders[_holder].machineIds.length; i++) {
//            string storage machineId = stakeHolders[_holder].machineIds[i];
//            uint256 claimedAmount = machineId2StakeInfos[stakeHolders[_holder].machineIds[i]].claimedAmount;
//            (uint256 canClaimedAmount, uint256 lockedAmount) = getRewardAmountCanClaim(machineId);
//            totalReleasedAmount += claimedAmount + canClaimedAmount;
//            totalLockedAmount += lockedAmount;
//        }
//        return (totalReleasedAmount, totalLockedAmount);
//    }
//






    function version() external pure returns (uint256)  {
        return 1;
    }


    function findStringIndex(string[] memory arr, string memory v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (keccak256(abi.encodePacked(arr[i])) == keccak256(abi.encodePacked(v))) {
                return i;
            }
        }
        revert("Element not found");
    }


    function getMachineGPUCount(string memory machineId) public view returns (uint256) {
        return precompileContract.getMachineGPUCount(machineId);
    }

    function removeStringValueOfArray(string memory addr, string[] storage arr) internal {
        uint256 index = findStringIndex(arr, addr);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function addOrUpdateStakeHolder(
        address _holder,
        string memory _machineId,
        uint256 _calcPoint,
        uint256 _reservedAmount
    ) internal {

        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        if (stakeHolderInfo.holder == address(0)) {
            stakeHolderInfo.holder = _holder;
        }

        MachineInfo memory previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
        stakeHolderInfo.machineId2Info[_machineId].calcPoint = _calcPoint;
        if (stakeHolderInfo.machineId2Info[_machineId].gpuCount == 0) {
            uint256 gpuCount = getMachineGPUCount(_machineId);

            stakeHolderInfo.machineId2Info[_machineId].gpuCount = gpuCount;

            stakeHolderInfo.totalGPUCount = stakeHolderInfo.totalGPUCount + gpuCount;
        }
        if (previousMachineInfo.reserveAmount == 0 && previousMachineInfo.calcPoint == 0) {
            stakeHolderInfo.totalReservedAmount += _reservedAmount;
            stakeHolderInfo.machineId2Info[_machineId].reserveAmount = _reservedAmount;
            stakeHolderInfo.machineIds.push(_machineId);
        }

        stakeHolderInfo.totalCalcPoint = stakeHolderInfo.totalCalcPoint + _calcPoint - previousMachineInfo.calcPoint;

        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
    }

    function removeMachine(address _holder, string memory _machineId) internal {
        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];

        MachineInfo memory stakeInfoToRemove = stakeHolderInfo.machineId2Info[_machineId];
        require(stakeInfoToRemove.calcPoint > 0, "Machine not found");

        stakeHolderInfo.totalCalcPoint -= stakeInfoToRemove.calcPoint;
        stakeHolderInfo.totalGPUCount -= stakeInfoToRemove.gpuCount;
        stakeHolderInfo.totalReservedAmount -= stakeInfoToRemove.reserveAmount;
        removeStringValueOfArray(_machineId, stakeHolderInfo.machineIds);
        delete stakeHolderInfo.machineId2Info[_machineId];

        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
    }

    function updateTopStakeHolders(address _holder, uint256 _totalCalcPoint) internal {
        uint256 minIndex = 0;
        bool shouldInsert = false;
        bool isExistingHolder = false;

        for (uint256 i = 0; i < topStakeHolders.length; i++) {
            if (topStakeHolders[i].holder == _holder) {
                if (_totalCalcPoint > topStakeHolders[i].totalCalcPoint) {
                    topStakeHolders[i].totalCalcPoint = _totalCalcPoint;
                    shouldInsert = true;
                }
                isExistingHolder = true;
                break;
            }
        }

        if (!isExistingHolder) {
            for (uint256 i = 1; i < topStakeHolders.length; i++) {
                if (topStakeHolders[i].totalCalcPoint < topStakeHolders[minIndex].totalCalcPoint) {
                    minIndex = i;
                }
            }

            if (topStakeHolders[minIndex].totalCalcPoint == 0 || _totalCalcPoint > topStakeHolders[minIndex].totalCalcPoint) {
                topStakeHolders[minIndex] = SimpleStakeHolder(_holder, _totalCalcPoint);
                shouldInsert = true;
            }
        }

        if (shouldInsert) {
            sortTopStakeHolders();
        }
    }

    function sortTopStakeHolders() internal {
        for (uint256 i = 0; i < topStakeHolders.length - 1; i++) {
            for (uint256 j = i + 1; j < topStakeHolders.length; j++) {
                if (topStakeHolders[i].totalCalcPoint < topStakeHolders[j].totalCalcPoint) {
                    SimpleStakeHolder memory temp = topStakeHolders[i];
                    topStakeHolders[i] = topStakeHolders[j];
                    topStakeHolders[j] = temp;
                }
            }
        }
    }

    function getHolderMachineIds(address _holder) public view returns (string[] memory)  {
        return stakeHolders[_holder].machineIds;
    }

    function getRentedGPUCountOfStakeHolder(address _holder) external view returns (uint256) {
        uint256 totalRentedGpuCount = 0;
        for (uint256 i = 0; i < stakeHolders[_holder].machineIds.length; i++) {
            string memory machineId = stakeHolders[_holder].machineIds[i];
            uint256 rentedGpuCount = getRentedGPUCountOfMachineInDlcNftStaking(machineId);
            totalRentedGpuCount += rentedGpuCount;
        }
        return totalRentedGpuCount;
    }

    function getBurnedRentFeeOfStakeHolder(address _holder) external view returns (uint256) {
        uint256 totalRentedRentFee = 0;
        for (uint256 i = 0; i < stakeHolders[_holder].machineIds.length; i++) {
            string memory machineId = stakeHolders[_holder].machineIds[i];
            uint256 rentFee = getDlcNftStakingBurnedRentFeeByMachine(machineId);
            totalRentedRentFee += rentFee;
        }
        return totalRentedRentFee;
    }

    function getTopStakeHolders() external view returns (address[3] memory top3HoldersAddress,uint256[3] memory top3HoldersCalcPoint) {
        for (uint256 i = 0; i < topStakeHolders.length; i++) {
            address holder = topStakeHolders[i].holder;
            uint256 _totalCalcPoint = topStakeHolders[i].totalCalcPoint;
            top3HoldersAddress[i] = holder;
            top3HoldersCalcPoint[i] = _totalCalcPoint;
        }

        return (top3HoldersAddress, top3HoldersCalcPoint);
    }
}

