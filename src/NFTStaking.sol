// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./library/Ln.sol";
import "./interface/IStateContract.sol";
import "./interface/IRewardToken.sol";
import "./interface/IRentContract.sol";
import "forge-std/console.sol";

/// @custom:oz-upgrades-from OldNFTStaking
contract NFTStaking is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint8 public constant SECONDS_PER_BLOCK = 6;
    uint256 public constant BASE_RESERVE_AMOUNT = 1000 * 1e18;
    uint8 public constant MAX_NFTS_PER_MACHINE = 50;
    uint256 public constant REWARD_DURATION = 60 days;
    //        uint256 public constant REWARD_DURATION = 0.5 days; //todo: change to 60 days. 0.5 day only for test
    uint256 public constant LOCK_PERIOD = 180 days;
    uint8 public constant DAILY_UNLOCK_RATE = 5; // 0.5% = 5/1000

    IERC721 public nftToken;

    IStateContract public stateContract;
    IRewardToken public rewardToken;
    IRentContract public rentContract;

    uint256 public totalReservedAmount;
    uint256 public totalCalcPoint;
    // uint = calcPoint * ln(reservedAmount)
    uint256 public totalAdjustUnit;
    uint256 public dailyRewardAmount;
    uint256 public rewardPerUnit;
    uint256 public lastUpdateTime;
    uint8 public phaseLevel;
    uint256 public totalGpuCount;
    uint256 public rewardStartAtBlockNumber;
    uint256 public rewardStartGPUThreshold;

    struct StakeInfo {
        address holder;
        uint256 startAtBlockNumber;
        uint256 lastClaimAtBlockNumber;
        uint256 endAtBlockNumber;
        uint256 calcPoint;
        uint256 reservedAmount;
        uint256[] nftTokenIds;
        uint256 claimedAmount;
        uint256 pendingRewards;
        uint256 userRewardDebt;
        bool isRentedByUser;
        uint256 gpuCount;
        uint256 rentEndAt;
    }

    mapping(string => StakeInfo) public machineId2StakeInfos;

    struct LockedRewardDetail {
        uint256 amount;
        uint256 unlockTime;
    }

    mapping(string => LockedRewardDetail[]) public machineId2LockedRewardDetails;

    struct ApprovedReportInfo {
        address renter;
    }

    mapping(string => ApprovedReportInfo[]) private pendingSlashedMachineId2Renter;

    struct MachineUploadInfo {
        string gpuType;
        uint256 gpuMem;
        uint256 cpuRate;
        string cpuType;
        uint256 pricePerHour;
        uint256 reserveAmount;
        uint256 nextRenterCanRentAt;
        uint64 east;
        uint64 west;
        uint64 south;
        uint64 north;
    }

    mapping(string => MachineUploadInfo) public machineId2UploadInfo;

    address public dlcClientWalletAddress;

    event staked(address indexed stakeholder, string machineId, uint256 stakeAtBlockNumber);
    event unStaked(address indexed stakeholder, string machineId, uint256 unStakeAtBlockNumber);
    event claimed(
        address indexed stakeholder,
        string machineId,
        uint256 rewardAmount,
        uint256 moveToReservedAmount,
        bool paidSlash
    );

    address canUpgradeAddress;

    event RewardTokenSet(address indexed addr);
    event NftTokenSet(address indexed addr);
    event AddNFTs(string machineId, uint256[] nftTokenIds);
    event PaySlash(string machineId, address renter, uint256 slashAmount);
    event RentMachine(string machineId);
    event EndRentMachine(string machineId, uint256 rentedGpuCount);
    event ReportMachineFault(string machineId, address renter);
    event DLCClientWalletSet(address indexed addr);

    modifier onlyRentContract() {
        require(msg.sender == address(rentContract), "only rent contract can call this function");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _nftToken,
        address _rewardToken,
        address _stateContract,
        address _rentContract,
        uint8 _phase_level
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        nftToken = IERC721(_nftToken);
        stateContract = IStateContract(_stateContract);
        rentContract = IRentContract(_rentContract);
        phaseLevel = _phase_level;

        if (phaseLevel == 1) {
            dailyRewardAmount = 3000000 * 1e18;
            rewardStartGPUThreshold = 500;
        }
        if (phaseLevel == 2) {
            dailyRewardAmount = 4000000 * 1e18;
            rewardStartGPUThreshold = 1000;
        }
        if (phaseLevel == 3) {
            dailyRewardAmount = 9665000 * 1e18;
            rewardStartGPUThreshold = 2000;
        }

        if (_rewardToken != address(0x0)) {
            rewardToken = IRewardToken(_rewardToken);
        }

        lastUpdateTime = block.timestamp;
        rewardStartAtBlockNumber = 0;
    }

    function setThreshold(uint256 _threshold) external onlyOwner {
        rewardStartGPUThreshold = _threshold;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(msg.sender == canUpgradeAddress, "only canUpgradeAddress can authorize upgrade");
        canUpgradeAddress = address(0);
    }

    function setUpgradeAddress(address addr) external onlyOwner {
        canUpgradeAddress = addr;
    }

    function requestUpgradeAddress(address addr) external pure returns (bytes memory) {
        bytes memory data = abi.encodeWithSignature("setUpgradeAddress(address)", addr);
        return data;
    }

    function setStateContract(address _stateContract) external onlyOwner {
        stateContract = IStateContract(_stateContract);
    }

    function setRewardToken(address token) external onlyOwner {
        rewardToken = IRewardToken(token);
        emit RewardTokenSet(token);
    }

    function setRentContract(address _rentContract) external onlyOwner {
        rentContract = IRentContract(_rentContract);
    }

    function setNftToken(address token) external onlyOwner {
        nftToken = IERC721(token);
        emit NftTokenSet(token);
    }

    function setRewardStartAt(uint256 blockNumber) external onlyOwner {
        require(blockNumber >= block.number, "block number must be greater than current block number");
        rewardStartAtBlockNumber = blockNumber;
    }

    function setDLCClientWallet(address addr) external onlyOwner {
        dlcClientWalletAddress = addr;
    }

    function getDailyRewardAmount() public view returns (uint256) {
        if (rewardStartAtBlockNumber > 0) {
            return dailyRewardAmount;
        }
        return 0;
    }

    function updateRewardPerCalcPoint() internal {
        if (totalAdjustUnit > 0) {
            uint256 timeDelta = block.timestamp - lastUpdateTime;
            uint256 periodReward = (getDailyRewardAmount() * timeDelta) / 1 days;

            rewardPerUnit += LogarithmLibrary.safeDiv(periodReward, totalAdjustUnit);
        }
        lastUpdateTime = block.timestamp;
    }

    function joinStaking(string memory machineId, uint256 calcPoint, uint256 reserveAmount) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        // update global reward rate
        updateRewardPerCalcPoint();

        uint256 lnReserveAmount = LogarithmLibrary.LnUint256(
            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
        );

        // update pending rewards of the machine
        stakeInfo.pendingRewards += ((rewardPerUnit - stakeInfo.userRewardDebt) * stakeInfo.calcPoint * lnReserveAmount)
            / LogarithmLibrary.getDecimals();

        stakeInfo.userRewardDebt = rewardPerUnit;

        uint256 oldLnReserved = LogarithmLibrary.LnUint256(
            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
        );

        uint256 newLnReserved =
            LogarithmLibrary.LnUint256(reserveAmount > BASE_RESERVE_AMOUNT ? reserveAmount : BASE_RESERVE_AMOUNT);

        totalAdjustUnit -= stakeInfo.calcPoint * oldLnReserved;
        totalAdjustUnit += calcPoint * newLnReserved;
        totalCalcPoint = totalCalcPoint - stakeInfo.calcPoint + calcPoint;

        stakeInfo.calcPoint = calcPoint;
        if (reserveAmount > stakeInfo.reservedAmount) {
            totalReservedAmount += reserveAmount - stakeInfo.reservedAmount;
            stakeInfo.reservedAmount = reserveAmount;
            rewardToken.transferFrom(stakeInfo.holder, address(this), reserveAmount);
        }
    }

    function getCurrentRewardRate() internal view returns (uint256) {
        uint256 tempRewardPerUnit = rewardPerUnit;

        uint256 rewardStartTime = getRewardStartTime();

        uint256 _lastUpdateTime = rewardStartTime < lastUpdateTime ? lastUpdateTime : rewardStartTime;
        uint256 timeDelta = block.timestamp - _lastUpdateTime;

        if (totalAdjustUnit > 0) {
            uint256 periodReward = (getDailyRewardAmount() * timeDelta) / 1 days;
            tempRewardPerUnit += LogarithmLibrary.safeDiv(periodReward, totalAdjustUnit);
        }

        return tempRewardPerUnit;
    }

    function calculateRewards(string memory machineId, uint256 currentRewardPerUnit) public view returns (uint256) {
        if (currentRewardPerUnit == 0) {
            return 0;
        }
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];

        uint256 lnReserveAmount = LogarithmLibrary.LnUint256(
            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
        );

        uint256 accumulatedReward = (
            (currentRewardPerUnit - stakeInfo.userRewardDebt) * stakeInfo.calcPoint * lnReserveAmount
        ) / LogarithmLibrary.getDecimals();
        uint256 rewardAmount = stakeInfo.pendingRewards + accumulatedReward;

        return rewardAmount;
    }

    function getRewardsAndUpdateGlobalRewardRate(string memory machineId) public returns (uint256) {
        uint256 currentRewardPerUnit = getCurrentRewardRate();

        uint256 rewards = calculateRewards(machineId, currentRewardPerUnit);

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        stakeInfo.userRewardDebt = currentRewardPerUnit;
        stakeInfo.pendingRewards = 0;
        lastUpdateTime = block.timestamp;
        rewardPerUnit = currentRewardPerUnit;
        return rewards;
    }

    function getRewardStartTime() public view returns (uint256) {
        if (rewardStartAtBlockNumber == 0) {
            return 0;
        }

        if (block.number > rewardStartAtBlockNumber) {
            uint256 timeDuration = (block.number - rewardStartAtBlockNumber) * SECONDS_PER_BLOCK;
            return block.timestamp - timeDuration;
        }

        return block.timestamp + (rewardStartAtBlockNumber - block.number) * SECONDS_PER_BLOCK;
    }

    function stake(
        string calldata machineId,
        uint256 amount,
        uint256[] calldata nftTokenIds,
        string calldata gpuType,
        uint256 gpuMem,
        uint256 cpuRate,
        string calldata cpuType,
        uint256 pricePerHour,
        uint256 availableRentBlockNumbers,
        uint256 nextRenterCanRentAt,
        uint256 calcPoint,
        uint64 east,
        uint64 west,
        uint64 south,
        uint64 north
    ) external nonReentrant {
        require(cpuRate >= 3500, "cpu rate must be greater than or equal to 3500");
        require(
            (availableRentBlockNumbers >= 2 hours / SECONDS_PER_BLOCK) || availableRentBlockNumbers == 0,
            "available rent duration must be greater than or equal to 2 hours"
        );

        if (rewardStartAtBlockNumber > 0) {
            require((block.number - rewardStartAtBlockNumber) * SECONDS_PER_BLOCK < REWARD_DURATION, "staking ended");
        }

        address stakeholder = msg.sender;
        require(stakeholder != address(0), "invalid stakeholder address");
        require(!isStaking(machineId), "machine already staked");
        require(nftTokenIds.length > 0, "nft token ids is empty");
        calcPoint = calcPoint * nftTokenIds.length;
        require(calcPoint > 0, "machine calc point not found");
        uint256 rentEndAt = 0;
        if (availableRentBlockNumbers > 0) {
            rentEndAt = block.number + availableRentBlockNumbers;
        }
        if (nextRenterCanRentAt == 0) {
            nextRenterCanRentAt = block.number;
        }
        // if (rewardStartAtBlockNumber > 0) {
        //     require(
        //         (rentEndAt - rewardStartAtBlockNumber) * SECONDS_PER_BLOCK >=
        //             REWARD_DURATION,
        //         "rent time must be greater than 60 days since reward start"
        //     );
        // } else {
        //     require(
        //         (rentEndAt - block.number) * SECONDS_PER_BLOCK >=
        //             REWARD_DURATION,
        //         "rent time must be greater than 60 days since reward start"
        //     );
        // }

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        ApprovedReportInfo[] memory approvedReportInfos = pendingSlashedMachineId2Renter[machineId];

        if (approvedReportInfos.length > 0) {
            require(
                amount >= BASE_RESERVE_AMOUNT * approvedReportInfos.length, "amount must be greater than slash amount"
            );
            for (uint8 i = 0; i < approvedReportInfos.length; i++) {
                // pay slash to renters
                payToRentersForSlashing(machineId, approvedReportInfos[i].renter);
                amount -= BASE_RESERVE_AMOUNT;
            }
            delete pendingSlashedMachineId2Renter[machineId];
        } else {
            if (stakeInfo.endAtBlockNumber == 0) {
                require(stakeInfo.startAtBlockNumber == 0, "machine already staked");
            }
        }

        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            nftToken.transferFrom(stakeholder, address(this), nftTokenIds[i]);
        }
        uint8 gpuCount = 1;
        totalGpuCount += gpuCount;
        if (totalGpuCount >= rewardStartGPUThreshold) {
            rewardStartAtBlockNumber = block.number;
        }

        uint256 currentTime = block.number;

        machineId2StakeInfos[machineId] = StakeInfo({
            startAtBlockNumber: currentTime,
            lastClaimAtBlockNumber: currentTime,
            endAtBlockNumber: 0,
            calcPoint: 0,
            reservedAmount: 0,
            nftTokenIds: nftTokenIds,
            holder: stakeholder,
            claimedAmount: 0,
            userRewardDebt: 0,
            pendingRewards: 0,
            isRentedByUser: false,
            gpuCount: gpuCount,
            rentEndAt: rentEndAt
        });

        joinStaking(machineId, calcPoint, amount);

        stateContract.addOrUpdateStakeHolder(stakeholder, machineId, calcPoint, amount, gpuCount, true);

        machineId2UploadInfo[machineId] = MachineUploadInfo({
            gpuType: gpuType,
            gpuMem: gpuMem,
            cpuRate: cpuRate,
            cpuType: cpuType,
            pricePerHour: pricePerHour,
            reserveAmount: amount,
            nextRenterCanRentAt: nextRenterCanRentAt,
            east: east,
            west: west,
            south: south,
            north: north
        });

        emit staked(stakeholder, machineId, currentTime);
    }

    function addStakeBlockTime(string memory machineId, uint256 blockNumbers) external {
        require(blockNumbers > 2 hours / SECONDS_PER_BLOCK, "block numbers must be greater than 2 hours");
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        if (block.number < stakeInfo.rentEndAt) {
            // rent not finished, add block time from rent end block before
            stakeInfo.rentEndAt += blockNumbers;
        } else {
            // rent finished, add block time from current block
            stakeInfo.rentEndAt = block.number + blockNumbers;
        }
    }

    function getPendingSlashCount(string memory machineId) public view returns (uint256) {
        return pendingSlashedMachineId2Renter[machineId].length;
    }

    function getRewardAmountCanClaim(string memory machineId)
        public
        returns (uint256 canClaimAmount, uint256 lockedAmount)
    {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");

        uint256 currentRewardPerUnit = getCurrentRewardRate();
        uint256 totalRewardAmount = calculateRewards(machineId, currentRewardPerUnit);

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

    function getReward(string memory machineId) external view returns (uint256) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        uint256 currentRewardPerUnit = getCurrentRewardRate();
        return calculateRewards(machineId, currentRewardPerUnit);
    }

    function _claim(string memory machineId) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        address stakeholder = stakeInfo.holder;
        uint256 canClaimAmount = 0;
        uint256 lockedAmount = 0;
        uint256 rewardAmount = 0;
        uint256 currentBlock = block.number;
        if (stakeInfo.rentEndAt < currentBlock && (currentBlock - stakeInfo.rentEndAt >= 1 hours / SECONDS_PER_BLOCK)) {
            rewardAmount = getRewardsAndUpdateGlobalRewardRate(machineId);
            (canClaimAmount, lockedAmount) = _getRewardDetail(rewardAmount);
        }
        (uint256 _dailyReleaseAmount,) = _calculateDailyReleaseReward(machineId, false);
        canClaimAmount += _dailyReleaseAmount;

        uint256 moveToReserveAmount = 0;
        if (canClaimAmount > 0) {
            if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT) {
                (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                    tryMoveReserve(machineId, canClaimAmount, stakeInfo);
                canClaimAmount = leftAmountCanClaim;
                moveToReserveAmount = _moveToReserveAmount;
            }
        }

        ApprovedReportInfo[] storage approvedReportInfos = pendingSlashedMachineId2Renter[machineId];
        bool paidSlash = false;
        if (approvedReportInfos.length > 0 && stakeInfo.reservedAmount >= BASE_RESERVE_AMOUNT) {
            ApprovedReportInfo memory lastSlashInfo = approvedReportInfos[approvedReportInfos.length - 1];
            payToRentersForSlashing(machineId, lastSlashInfo.renter);
            approvedReportInfos.pop();
            stakeInfo.reservedAmount -= BASE_RESERVE_AMOUNT;
            totalReservedAmount -= BASE_RESERVE_AMOUNT;
            paidSlash = true;
            stateContract.subReserveAmount(msg.sender, machineId, BASE_RESERVE_AMOUNT);
        }

        if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT) {
            (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                tryMoveReserve(machineId, canClaimAmount, stakeInfo);
            canClaimAmount = leftAmountCanClaim;
            moveToReserveAmount = _moveToReserveAmount;
        }

        if (canClaimAmount > 0) {
            rewardToken.transfer(stakeholder, canClaimAmount);
        }

        stakeInfo.claimedAmount += canClaimAmount;
        stakeInfo.lastClaimAtBlockNumber = block.number;

        stateContract.addClaimedRewardAmount(msg.sender, machineId, rewardAmount + dailyRewardAmount, canClaimAmount);

        if (lockedAmount > 0) {
            machineId2LockedRewardDetails[machineId].push(
                LockedRewardDetail({amount: lockedAmount, unlockTime: block.timestamp + LOCK_PERIOD})
            );
        }

        emit claimed(stakeholder, machineId, canClaimAmount, moveToReserveAmount, paidSlash);
    }

    function claim(string memory machineId) public canClaim(machineId) {
        address stakeholder = msg.sender;
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        if (getPendingSlashCount(machineId) > 0) {
            require(stakeInfo.endAtBlockNumber == 0, "machine should restake and paid slash before claim");
        }

        require(stakeInfo.holder == stakeholder, "not stakeholder");
        require(
            (block.number - stakeInfo.lastClaimAtBlockNumber) * SECONDS_PER_BLOCK >= 1 days,
            "last claim less than 1 day"
        );

        _claim(machineId);
    }

    function tryMoveReserve(string memory machineId, uint256 canClaimAmount, StakeInfo storage stakeInfo)
        internal
        returns (uint256 moveToReserveAmount, uint256 leftAmountCanClaim)
    {
        uint256 leftAmountShouldReserve = BASE_RESERVE_AMOUNT - stakeInfo.reservedAmount;
        if (canClaimAmount >= leftAmountShouldReserve) {
            canClaimAmount -= leftAmountShouldReserve;
            moveToReserveAmount = leftAmountShouldReserve;
        } else {
            moveToReserveAmount = canClaimAmount;
            canClaimAmount = 0;
        }

        // the amount should be transfer to reserve
        totalReservedAmount += moveToReserveAmount;
        stakeInfo.reservedAmount += moveToReserveAmount;
        //        rewardToken.mint(address(this), moveToReserveAmount);
        stateContract.addReserveAmount(msg.sender, machineId, moveToReserveAmount);
        return (moveToReserveAmount, canClaimAmount);
    }

    modifier canClaim(string memory machineId) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder != address(0), "Invalid stakeholder address");
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        require(stakeInfo.startAtBlockNumber > 0, "staking not found");
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
            uint256 locked = lockedRewardDetails[i].amount;
            if (locked == 0) {
                continue;
            }

            if (block.timestamp >= lockedRewardDetails[i].unlockTime) {
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
            _lockedAmount += locked;
        }
        return (_dailyReleaseAmount, _lockedAmount - _dailyReleaseAmount);
    }

    function unStakeAndClaim(string calldata machineId) public nonReentrant {
        address stakeholder = msg.sender;
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == stakeholder, "not stakeholder");
        require(stakeInfo.startAtBlockNumber > 0, "staking not found");
        require(block.number > stakeInfo.rentEndAt, "staking not ended");
        require(block.number - stakeInfo.rentEndAt > 2 hours / SECONDS_PER_BLOCK, "staking must be more than 2 hours");

        // if (rewardStartAtBlockNumber > 0) {
        //     require(
        //         (block.number - stakeInfo.startAtBlockNumber) * SECONDS_PER_BLOCK > REWARD_DURATION,
        //         "staking reward duration not end yet"
        //     );
        // }
        claim(machineId);
        _unStake(machineId, stakeholder);
        stateContract.removeMachine(stakeholder, machineId);
    }

    function unStake(string calldata machineId) public nonReentrant {
        require(msg.sender == dlcClientWalletAddress, "not dlc client wallet");
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.startAtBlockNumber > 0, "staking not found");
        require(block.number > stakeInfo.rentEndAt, "staking not ended");
        require(block.number - stakeInfo.rentEndAt > 2 hours / SECONDS_PER_BLOCK, "staking must be more than 2 hours");
        _unStake(machineId, stakeInfo.holder);
        stateContract.removeMachine(stakeInfo.holder, machineId);
    }

    function _unStake(string calldata machineId, address stakeholder) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        uint256 reservedAmount = stakeInfo.reservedAmount;

        if (reservedAmount > 0) {
            stakeInfo.reservedAmount = 0;
            rewardToken.transfer(stakeholder, reservedAmount);
            if (totalReservedAmount > reservedAmount) {
                totalReservedAmount -= reservedAmount;
            } else {
                totalReservedAmount = 0;
            }
        }

        uint256 currentTime = block.number;
        stakeInfo.endAtBlockNumber = currentTime;

        for (uint256 i = 0; i < stakeInfo.nftTokenIds.length; i++) {
            if (stakeInfo.nftTokenIds[i] == 0) {
                continue;
            }
            nftToken.transferFrom(address(this), msg.sender, stakeInfo.nftTokenIds[i]);
        }
        joinStaking(machineId, 0, 0);
        emit unStaked(msg.sender, machineId, currentTime);
    }

    function getStakeHolder(string calldata machineId) external view returns (address) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.holder;
    }

    function isStaking(string calldata machineId) public view returns (bool) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        bool _isStaking = stakeInfo.holder != address(0) && stakeInfo.startAtBlockNumber > 0;
        if (stakeInfo.endAtBlockNumber != 0) {
            _isStaking = _isStaking && block.number < stakeInfo.endAtBlockNumber;
        }

        return _isStaking;
    }

    function addNFTs(string calldata machineId, uint256[] calldata nftTokenIds) external {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        require(stakeInfo.holder == msg.sender, "not stakeholder");
        require(stakeInfo.nftTokenIds.length + nftTokenIds.length <= MAX_NFTS_PER_MACHINE, "too many nfts, max is 50");
        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            uint256 tokenID = nftTokenIds[i];
            nftToken.transferFrom(msg.sender, address(this), tokenID);
            stakeInfo.nftTokenIds.push(tokenID);
        }

        uint256 newCalcPoint = stakeInfo.calcPoint * stakeInfo.nftTokenIds.length;
        joinStaking(machineId, newCalcPoint, stakeInfo.reservedAmount);

        stateContract.addOrUpdateStakeHolder(stakeInfo.holder, machineId, stakeInfo.calcPoint, 0, 0, false);
        emit AddNFTs(machineId, nftTokenIds);
    }

    function reservedNFTs(string calldata machineId) public view returns (uint256[] memory nftTokenIds) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");
        return stakeInfo.nftTokenIds;
    }

    function getTotalGPUCountInStaking() public view returns (uint256) {
        return totalGpuCount;
    }

    function getLeftGPUCountToStartReward() public view returns (uint256) {
        return rewardStartGPUThreshold > totalGpuCount ? rewardStartGPUThreshold - totalGpuCount : 0;
    }

    function rentMachine(string calldata machineId, uint256 fee, uint8 rentedGPUCount) external onlyRentContract {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        stakeInfo.isRentedByUser = true;

        uint256 newCalcPoint = (stakeInfo.calcPoint * 13) / 10;
        joinStaking(machineId, newCalcPoint, stakeInfo.reservedAmount);
        stateContract.addOrUpdateStakeHolder(
            stakeInfo.holder, machineId, newCalcPoint, stakeInfo.reservedAmount, 0, false
        );
        stateContract.setBurnedRentFee(stakeInfo.holder, machineId, fee);
        stateContract.addRentedGPUCount(stakeInfo.holder, machineId, rentedGPUCount);
        emit RentMachine(machineId);
    }

    function renewRentMachine(string calldata machineId, uint256 fee) external onlyRentContract {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        stateContract.setBurnedRentFee(stakeInfo.holder, machineId, fee);
    }

    function endRentMachine(string calldata machineId, uint8 rentedGPUCount) external onlyRentContract {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.isRentedByUser, "not rented by user");
        stakeInfo.isRentedByUser = false;

        MachineUploadInfo storage uploadInfo = machineId2UploadInfo[machineId];
        uploadInfo.nextRenterCanRentAt = block.number + 100;

        uint256 newCalcPoint = (stakeInfo.calcPoint * 10) / 13;
        joinStaking(machineId, newCalcPoint, stakeInfo.reservedAmount);
        stateContract.addOrUpdateStakeHolder(
            stakeInfo.holder, machineId, newCalcPoint, stakeInfo.reservedAmount, 0, false
        );

        stateContract.subRentedGPUCount(stakeInfo.holder, machineId, rentedGPUCount);

        emit EndRentMachine(machineId, rentedGPUCount);
    }

    function reportMachineFault(string calldata machineId, address renter) external onlyRentContract {
        if (renter == address(0)) {
            // if renter is not set, it means the machine is not rented by user
            // so we should pay the slash to the staking contract
            renter = address(this);
        }
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        uint256 reservedAmount = stakeInfo.reservedAmount;
        emit ReportMachineFault(machineId, renter);

        if (reservedAmount > BASE_RESERVE_AMOUNT) {
            payToRentersForSlashing(machineId, renter);
            stakeInfo.reservedAmount -= BASE_RESERVE_AMOUNT;
            totalReservedAmount -= BASE_RESERVE_AMOUNT;
        } else {
            pendingSlashedMachineId2Renter[machineId].push(ApprovedReportInfo({renter: renter}));
        }

        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
        stateContract.removeMachine(stakeInfo.holder, machineId);
    }

    function getMachineHolder(string memory machineId) external view returns (address) {
        return machineId2StakeInfos[machineId].holder;
    }

    function payToRentersForSlashing(string memory machineId, address renter) internal {
        rewardToken.transfer(renter, BASE_RESERVE_AMOUNT);
        emit PaySlash(machineId, renter, BASE_RESERVE_AMOUNT);
    }

    function getMachinesInStaking(uint256 page, uint256 pageSize) external view returns (string[] memory) {
        return stateContract.getMachinesInStaking(page, pageSize);
    }

    function getTotalCalcPointAndReservedAmount() external view returns (uint256, uint256) {
        return (totalCalcPoint, totalReservedAmount);
    }

    function canRent(string calldata machineId, uint256 rentBlockNumbers) public view returns (bool) {
        require(isStaking(machineId), "machine not staked");

        MachineUploadInfo storage uploadInfo = machineId2UploadInfo[machineId];
        if (uploadInfo.nextRenterCanRentAt > block.number) {
            // not reach the start rent block number yet
            return false;
        }

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        if ((block.number < stakeInfo.rentEndAt && stakeInfo.rentEndAt - block.number > 1 hours / SECONDS_PER_BLOCK)) {
            uint256 maxRentDuration = stakeInfo.rentEndAt - block.number;
            return maxRentDuration >= rentBlockNumbers;
        }

        // unLimit stake time
        return stakeInfo.rentEndAt == 0;
    }

    function getRentEndAt(string memory machineId) public view returns (uint256) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.rentEndAt;
    }

    function getMachinePricePerHour(string memory machineId) public view returns (uint256) {
        MachineUploadInfo storage uploadInfo = machineId2UploadInfo[machineId];
        return uploadInfo.pricePerHour;
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getMachineUploadInfo(string memory machineId) external view returns (MachineUploadInfo memory) {
        return machineId2UploadInfo[machineId];
    }
}
