//SPDX-License_Identifier: agpl-3.0
pragma solidity ^0.8.20;

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ISecurityAccessManager} from "contracts/interfaces/ISecurityAccessManager.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";

contract SecurityAccessManager is AccessControl, ISecurityAccessManager {
    // Add upgradeablity due to user register
    uint208 public constant LVL1_DEFAULT_MAX_DEPOSIT = 1000 ether; // in USD
    uint208 public constant LVL2_DEFAULT_MAX_DEPOSIT = 5000 ether; // in USD
    uint208 public constant LVL3_DEFAULT_MAX_DEPOSIT = 10000 ether; // in USD
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
    bytes32 public constant POINTS_MANAGER = bytes32("POINTS_MANAGER");

    mapping(address => UserRegister) userRegister;

    mapping(address => bool) flashloanWhitelistedUser;

    LevelParams[] levelParams;

    constructor(address _admin, address[] memory _pointsManagers) {
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
        _setLevelParams(cooldownTimes, maxDeposits, trustPointsThresholds);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        for (uint256 i = 0; i < _pointsManagers.length; i++) {
            _grantRole(POINTS_MANAGER, _pointsManagers[i]);
        }
    }

    /**
     * SETTERS
     */

    function addUserToFlashloanWhitelist(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
        flashloanWhitelistedUser[user] = true;
        emit UserWhitelisted(user);
    }

    function removeUserFromFlashloanWhitelist(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
        flashloanWhitelistedUser[user] = false;
        emit UserRemovedFromWhitelist(user);
    }

    function setLevelParams(
        uint32[] memory _cooldownTimes,
        uint208[] memory _maxDeposits,
        uint16[] memory _trustPointsThresholds
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setLevelParams(_cooldownTimes, _maxDeposits, _trustPointsThresholds);
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
        }
    }

    function _setLevelParams(
        uint32[] memory _cooldownTimes,
        uint208[] memory _maxDeposits,
        uint16[] memory _trustPointsThresholds
    ) private {
        LevelParams memory internalLevelParams;
        require(_cooldownTimes.length == _maxDeposits.length, Errors.SAM_WRONG_ARRAY_LENGTH);
        require(
            _cooldownTimes.length == _trustPointsThresholds.length, Errors.SAM_WRONG_ARRAY_LENGTH
        );
        delete levelParams;
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
            levelParams.push(internalLevelParams);
        }
    }

    function registerDeposit(uint208 _amount, address _asset) public {
        uint8 userLevel = getUserLevel(msg.sender);
        require(_amount < levelParams[userLevel].maxDeposit, Errors.SAM_EXCEEDED_MAX_DEPOSIT);
        require(
            userRegister[msg.sender].depositCheckpoints[_asset].length + 1 < MAX_CHECKPOINTS,
            Errors.SAM_MAX_CHECKPOINTS_REACHED
        );
        DepositCheckpoints memory newCheckpoint =
            DepositCheckpoints({depositAmount: _amount, depositTime: uint48(block.timestamp)});
        userRegister[msg.sender].depositCheckpoints[_asset].push(newCheckpoint);
    }

    function unregisterDeposit(uint208 _amount, address _asset) public {
        DepositCheckpoints[] storage depositCheckpointsPtr =
            userRegister[msg.sender].depositCheckpoints[_asset];
        require(depositCheckpointsPtr.length > 0, Errors.SAM_WRONG_CHECKPOINTS_LENGTH);
        require(_amount > 0, Errors.SAM_WRONG_AMOUNT);
        require(_amount < getAllFunds(msg.sender, _asset), Errors.SAM_NOT_ENOGUH_FUNDS);
        for (uint256 i = depositCheckpointsPtr.length - 1; i >= 0; i--) {
            if (depositCheckpointsPtr[i].depositAmount > _amount) {
                depositCheckpointsPtr[i].depositAmount -= _amount;
                _amount = 0;
                break;
            } else {
                _amount -= depositCheckpointsPtr[i].depositAmount;
                depositCheckpointsPtr.pop();
            }
        }
        require(_amount == 0, Errors.SAM_NOT_ENOGUH_FUNDS);
    }

    /**
     * GETTERS
     */
    function isFlashloanWhitelisted(address user) external view returns (bool) {
        return flashloanWhitelistedUser[user];
    }

    function getUserLevel(address user) public view returns (uint8) {
        uint256 trustPoints = userRegister[user].trustPoints;
        LevelParams[] memory _levelParams = levelParams;

        for (uint8 i = uint8(_levelParams.length - 1); i >= 0; i--) {
            if (trustPoints >= _levelParams[uint8(i)].trustPointsThreshold) {
                return uint8(i);
            }
        }
        return 0; // Default to lowest tier
    }

    /**
     * @dev Used instead available liquidity
     * @param user User address
     */
    function getLiquidFunds(address user, address _asset) public view returns (uint256) {
        uint256 totalDeposit = 0;
        uint8 userLevel = getUserLevel(user);

        DepositCheckpoints[] memory _depositCheckpoints =
            userRegister[user].depositCheckpoints[_asset];
        uint256 userDepositCheckpointsLength = _depositCheckpoints.length;
        for (uint256 i = 0; i < userDepositCheckpointsLength; i++) {
            if (
                block.timestamp - _depositCheckpoints[i].depositTime
                    >= levelParams[userLevel].cooldownTime
            ) {
                totalDeposit += _depositCheckpoints[i].depositAmount;
            }
            // Potentially add else with break because from first indexes - there are the oldest deposits so later we can't have older
        }
        return totalDeposit;
    }

    function getAllFunds(address user, address _asset) public view returns (uint256) {
        uint256 totalDeposit = 0;

        DepositCheckpoints[] memory _depositCheckpoints =
            userRegister[user].depositCheckpoints[_asset];
        uint256 userDepositCheckpointsLength = _depositCheckpoints.length;
        for (uint256 i = 0; i < userDepositCheckpointsLength; i++) {
            totalDeposit += _depositCheckpoints[i].depositAmount;
        }
        return totalDeposit;
    }

    function getUserDepositCheckpoints(address user, address _asset)
        external
        view
        returns (DepositCheckpoints[] memory)
    {
        return userRegister[user].depositCheckpoints[_asset];
    }
}
