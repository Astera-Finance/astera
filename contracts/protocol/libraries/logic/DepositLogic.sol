// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {ILendingPoolAddressesProvider} from '../../../interfaces/ILendingPoolAddressesProvider.sol';
import {SafeERC20} from '../../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {IAToken} from '../../../interfaces/IAToken.sol';
import {IVariableDebtToken} from '../../../interfaces/IVariableDebtToken.sol';
import {IReserveInterestRateStrategy} from '../../../interfaces/IReserveInterestRateStrategy.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {ReserveBorrowConfiguration} from '../configuration/ReserveBorrowConfiguration.sol';
import {MathUtils} from '../math/MathUtils.sol';
import {WadRayMath} from '../math/WadRayMath.sol';
import {PercentageMath} from '../math/PercentageMath.sol';
import {Errors} from '../helpers/Errors.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {ReserveLogic} from './ReserveLogic.sol';
import {UserConfiguration} from '../configuration/UserConfiguration.sol';
import {ValidationLogic} from './ValidationLogic.sol';

/**
 * @title Deposit Logic library
 * @notice Implements the logic to deposit assets into the protocol
 */

library DepositLogic {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;
  using ReserveLogic for DataTypes.ReserveData;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using UserConfiguration for DataTypes.UserConfigurationMap;

    event Deposit(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount
    );

    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);




    struct DepositParams {
        address asset;
        bool reserveType;
        uint256 amount;
        address onBehalfOf;
    }

    function deposit(
            DepositParams memory params,
            mapping(address => mapping(bool => DataTypes.ReserveData)) storage _reserves,
            mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
            ILendingPoolAddressesProvider _addressesProvider
        ) external {
         DataTypes.ReserveData storage reserve = _reserves[params.asset][params.reserveType];

        ValidationLogic.validateDeposit(reserve, params.amount);

        address aToken = reserve.aTokenAddress;

        reserve.updateState();
        reserve.updateInterestRates(params.asset, aToken, params.amount, 0);

        IERC20(params.asset).safeTransferFrom(msg.sender, aToken, params.amount);

        bool isFirstDeposit = IAToken(aToken).mint(params.onBehalfOf, params.amount, reserve.liquidityIndex);

        if (isFirstDeposit) {
            _usersConfig[params.onBehalfOf].setUsingAsCollateral(reserve.id, true);
            emit ReserveUsedAsCollateralEnabled(params.asset, params.onBehalfOf);
        }


        emit Deposit(params.asset, msg.sender, params.onBehalfOf, params.amount);
    }


}

