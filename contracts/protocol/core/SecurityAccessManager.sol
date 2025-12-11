//SPDX-License_Identifier: agpl-3.0
pragma solidity ^0.8.20;

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ISecurityAccessManager} from "contracts/interfaces/ISecurityAccessManager.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";

import {console2} from "forge-std/console2.sol";

contract SecurityAccessManager is AccessControl, ISecurityAccessManager {
    // Add upgradeablity due to user register
    uint208 public constant LVL1_DEFAULT_MAX_DEPOSIT = 1000e8;
    uint208 public constant LVL2_DEFAULT_MAX_DEPOSIT = 5000e8;
    uint208 public constant LVL3_DEFAULT_MAX_DEPOSIT = 10000e8;
    uint32 public constant MAX_COOLDOWN = 10 days;
    uint32 public constant LVL1_DEFAULT_COOLDOWN = 2 days;
    uint32 public constant LVL2_DEFAULT_COOLDOWN = 1 days;
    uint32 public constant LVL3_DEFAULT_COOLDOWN = 12 hours;
    uint16 public constant MAX_CHECKPOINTS = 10000;
    uint16 public constant LVL1_DEFAULT_TRUST_POINTS_THRESHOLD = 0;
    uint16 public constant LVL2_DEFAULT_TRUST_POINTS_THRESHOLD = 100;
    uint16 public constant LVL3_DEFAULT_TRUST_POINTS_THRESHOLD = 500;
    uint8 public constant MAX_LEVEL = 10;
    uint8 public constant DEFAULT_LEVELS = 3;
    uint8 public constant MAX_DEPOSIT_DECIMALS = 8;
    bytes32 public constant POINTS_MANAGER = bytes32("POINTS_MANAGER");

    mapping(address user => UserRegister) private userRegister;

    mapping(address asset => LevelParams[]) private levelParams;

    modifier onlyAToken(address sender) {
        console2.log("Checking AToken: ", sender);
        console2.log("Level params length: ", levelParams[sender].length);
        require(levelParams[sender].length > 0, Errors.SAM_UNAUTHORIZED);
        _;
    }

    constructor(address _admin, address[] memory _pointsManagers, address[] memory assets) {
        // Initialize level parameters via _setLevelParams
        uint32[] memory cooldownTimes = new uint32[](DEFAULT_LEVELS);
        uint208[] memory maxDeposits = new uint208[](DEFAULT_LEVELS);
        uint16[] memory trustPointsThresholds = new uint16[](DEFAULT_LEVELS);
        cooldownTimes[0] = LVL1_DEFAULT_COOLDOWN;
        cooldownTimes[1] = LVL2_DEFAULT_COOLDOWN;
        cooldownTimes[2] = LVL3_DEFAULT_COOLDOWN;
        maxDeposits[0] = LVL1_DEFAULT_MAX_DEPOSIT;
        maxDeposits[1] = LVL2_DEFAULT_MAX_DEPOSIT;
        maxDeposits[2] = LVL3_DEFAULT_MAX_DEPOSIT;
        trustPointsThresholds[0] = LVL1_DEFAULT_TRUST_POINTS_THRESHOLD;
        trustPointsThresholds[1] = LVL2_DEFAULT_TRUST_POINTS_THRESHOLD;
        trustPointsThresholds[2] = LVL3_DEFAULT_TRUST_POINTS_THRESHOLD;
        for (uint256 i = 0; i < assets.length; i++) {
            _setLevelParams(cooldownTimes, maxDeposits, trustPointsThresholds, assets[i]);
            console2.log("LevelParams %s: %s", assets[0], levelParams[assets[0]].length);
            console2.log("LevelParams %s: %s", assets[1], levelParams[assets[1]].length);
            console2.log("LevelParams %s: %s", assets[2], levelParams[assets[2]].length);
            console2.log("LevelParams %s: %s", assets[i], levelParams[assets[i]].length);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        for (uint256 i = 0; i < _pointsManagers.length; i++) {
            _grantRole(POINTS_MANAGER, _pointsManagers[i]);
        }
    }

    /**
     * SETTERS
     */

    /**
     * @dev Sets level parameters for a specific asset
     * @param _cooldownTimes - cooldown times for each level in seconds
     * @param _maxDeposits  - max deposit for specific assets in 8 decimals (e.g., 1000 USDC = 1000e8)
     * @param _trustPointsThresholds - trust points thresholds for each level
     * @param _asset - address of the asset
     */
    function setLevelParams(
        uint32[] memory _cooldownTimes,
        uint208[] memory _maxDeposits,
        uint16[] memory _trustPointsThresholds,
        address _asset
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setLevelParams(_cooldownTimes, _maxDeposits, _trustPointsThresholds, _asset);
    }

    function increaseTrustPoints(address user, uint16 amount) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(POINTS_MANAGER, msg.sender),
            Errors.SAM_UNAUTHORIZED
        );
        // change to only keeper -> offchain action
        userRegister[user].trustPoints += amount;
        emit TrustPointsChanged(user, amount);
    }

    function decreaseTrustPoints(address user, uint16 amount) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(POINTS_MANAGER, msg.sender),
            Errors.SAM_UNAUTHORIZED
        );
        if (userRegister[user].trustPoints >= amount) {
            // change to only keeper -> offchain action
            userRegister[user].trustPoints -= amount;
            emit TrustPointsChanged(user, amount);
        } else {
            userRegister[user].trustPoints = 0;
            emit TrustPointsChanged(user, 0);
        }
    }

    function _setLevelParams(
        uint32[] memory _cooldownTimes,
        uint208[] memory _maxDeposits,
        uint16[] memory _trustPointsThresholds,
        address _asset
    ) private {
        LevelParams memory internalLevelParams;
        require(_cooldownTimes.length == _maxDeposits.length, Errors.SAM_WRONG_ARRAY_LENGTH);
        require(
            _cooldownTimes.length == _trustPointsThresholds.length, Errors.SAM_WRONG_ARRAY_LENGTH
        );
        delete levelParams[_asset];
        for (uint256 i = 0; i < _cooldownTimes.length; i++) {
            uint256 previousCooldownTime = i == 0 ? MAX_COOLDOWN : _cooldownTimes[i - 1];
            require(_cooldownTimes[i] <= previousCooldownTime, Errors.SAM_COOLDOWN_NOT_DECREASING);
            uint256 previousMaxDeposit = i == 0 ? 0 : _maxDeposits[i - 1];
            require(_maxDeposits[i] >= previousMaxDeposit, Errors.SAM_MAX_DEPOSIT_NOT_INCREASING);
            uint256 previousTrustPointsThreshold = i == 0 ? 0 : _trustPointsThresholds[i - 1];
            require(
                _trustPointsThresholds[i] >= previousTrustPointsThreshold,
                Errors.SAM_TRUSTPOINTS_NOT_INCREASING
            );
            internalLevelParams.cooldownTime = _cooldownTimes[i];
            internalLevelParams.maxDeposit = _maxDeposits[i];
            internalLevelParams.trustPointsThreshold = _trustPointsThresholds[i];
            levelParams[_asset].push(internalLevelParams);
            emit LevelParamsChanged(
                _asset,
                i,
                internalLevelParams.cooldownTime,
                internalLevelParams.maxDeposit,
                internalLevelParams.trustPointsThreshold
            );
        }
    }

    function registerDeposit(uint208 _amount, address _user) public onlyAToken(msg.sender) {
        uint8 userLevel = getUserLevel(_user, msg.sender);
        uint256 allFunds = getAllFunds(_user, msg.sender);

        require(levelParams[msg.sender].length > 0, Errors.SAM_NO_LEVEL_PARAMS_FOR_ASSET);

        require(
            allFunds + _amount <= getMaxDepositInOriginDecimals(userLevel, msg.sender),
            Errors.SAM_EXCEEDED_MAX_DEPOSIT
        );
        require(
            userRegister[_user].depositCheckpoints[msg.sender].length + 1 < MAX_CHECKPOINTS,
            Errors.SAM_MAX_CHECKPOINTS_REACHED
        );

        DepositCheckpoints memory newCheckpoint =
            DepositCheckpoints({depositAmount: _amount, depositTime: uint48(block.timestamp)});
        userRegister[_user].depositCheckpoints[msg.sender].push(newCheckpoint);
    }

    function unregisterDeposit(uint208 _amount, address _user) public onlyAToken(msg.sender) {
        DepositCheckpoints[] storage depositCheckpointsPtr =
            userRegister[_user].depositCheckpoints[msg.sender];
        require(depositCheckpointsPtr.length > 0, Errors.SAM_WRONG_CHECKPOINTS_LENGTH);
        require(_amount > 0, Errors.SAM_WRONG_AMOUNT);
        console2.log("All funds: %s vs amount: %s", getAllFunds(_user, msg.sender), _amount);
        require(_amount <= getAllFunds(_user, msg.sender), Errors.SAM_NOT_ENOGUH_FUNDS);

        for (uint256 i = depositCheckpointsPtr.length; i > 0; i--) {
            if (depositCheckpointsPtr[i - 1].depositAmount > _amount) {
                depositCheckpointsPtr[i - 1].depositAmount -= _amount;
                _amount = 0;
                break;
            } else {
                _amount -= depositCheckpointsPtr[i - 1].depositAmount;
                depositCheckpointsPtr.pop();
            }
        }
        console2.log("Unregister amount: ", _amount);
        require(_amount == 0, Errors.SAM_NOT_ENOGUH_FUNDS);
    }

    /**
     * GETTERS
     */

    function getUserLevel(address _user, address _asset) public view returns (uint8) {
        uint256 trustPoints = userRegister[_user].trustPoints;
        LevelParams[] memory _levelParams = levelParams[_asset];

        for (uint8 i = uint8(_levelParams.length - 1); i >= 0; i--) {
            if (trustPoints >= _levelParams[uint8(i)].trustPointsThreshold) {
                return uint8(i);
            }
        }
        return 0; // Default to lowest tier
    }

    /**
     * @dev Used instead available liquidity
     * @param _user User address
     */
    function getLiquidFunds(address _user, address _asset) public view returns (uint256) {
        uint256 totalDeposit = 0;
        uint8 userLevel = getUserLevel(_user, _asset);
        DepositCheckpoints[] memory _depositCheckpoints =
            userRegister[_user].depositCheckpoints[_asset];
        uint256 userDepositCheckpointsLength = _depositCheckpoints.length;
        for (uint256 i = 0; i < userDepositCheckpointsLength; i++) {
            // console2.log("Deposit time: ", _depositCheckpoints[i].depositTime);
            // console2.log(" Current time: ", block.timestamp);
            // console2.log(" Cooldown: ", levelParams[_asset][userLevel].cooldownTime);
            if (
                block.timestamp - _depositCheckpoints[i].depositTime
                    >= levelParams[_asset][userLevel].cooldownTime
            ) {
                totalDeposit += _depositCheckpoints[i].depositAmount;
            }
            // Potentially add else with break because from first indexes - there are the oldest deposits so later we can't have older
        }
        return totalDeposit;
    }

    function getAllFunds(address _user, address _asset) public view returns (uint256) {
        uint256 totalDeposit = 0;

        DepositCheckpoints[] memory _depositCheckpoints =
            userRegister[_user].depositCheckpoints[_asset];
        uint256 userDepositCheckpointsLength = _depositCheckpoints.length;
        for (uint256 i = 0; i < userDepositCheckpointsLength; i++) {
            totalDeposit += _depositCheckpoints[i].depositAmount;
        }
        return totalDeposit;
    }

    function getUserTrustPoints(address _user, address _asset)
        external
        view
        returns (DepositCheckpoints[] memory)
    {
        return userRegister[_user].depositCheckpoints[_asset];
    }

    function getUserDepositCheckpoints(address _user) external view returns (uint256) {
        return userRegister[_user].trustPoints;
    }

    function getLevelParams(address _asset) external view returns (LevelParams[] memory) {
        return levelParams[_asset];
    }

    function getMaxDepositInOriginDecimals(uint256 _userLevel, address _asset)
        public
        view
        returns (uint256)
    {
        return (levelParams[_asset][_userLevel].maxDeposit
                * 10
                ** IERC20Detailed(_asset).decimals()) / 10 ** MAX_DEPOSIT_DECIMALS;
    }
}
