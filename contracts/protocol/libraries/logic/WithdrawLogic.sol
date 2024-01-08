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
 * @title withdraw Logic library
 * @notice Implements the logic to withdraw assets into the protocol
 */

library WithdrawLogic {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;
  using ReserveLogic for DataTypes.ReserveData;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using UserConfiguration for DataTypes.UserConfigurationMap;

    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);
    event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);



    struct withdrawParams {
        address asset;
        bool reserveType;
        uint256 amount;
        address to;
        uint256 reservesCount;
    }

    struct withdrawLocalVars {
        uint256 userBalance;
        uint256 amountToWithdraw;
        address aToken;
    }

    function withdraw(
            withdrawParams memory params,
            mapping(address => mapping(bool => DataTypes.ReserveData)) storage reservesData,
            mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
            mapping(uint256 => DataTypes.ReserveReference) storage reserves,
            ILendingPoolAddressesProvider addressesProvider
    ) external returns (uint256) {
        DataTypes.ReserveData storage reserve = reservesData[params.asset][params.reserveType];
        withdrawLocalVars memory localVars;
        
        {localVars.aToken = reserve.aTokenAddress;

        localVars.userBalance = IAToken(localVars.aToken).balanceOf(msg.sender);

        localVars.amountToWithdraw = params.amount;

        if (params.amount == type(uint256).max) {
            localVars.amountToWithdraw = localVars.userBalance;
        }
        }
        ValidationLogic.validateWithdraw(
            ValidationLogic.ValidateWithdrawParams(
                params.asset,
                params.reserveType,
                localVars.amountToWithdraw,
                localVars.userBalance,
                params.reservesCount,
                addressesProvider.getPriceOracle()
            ),
            reservesData,
            usersConfig[msg.sender],
            reserves
        );

        reserve.updateState();

        reserve.updateInterestRates(params.asset, localVars.aToken, 0, localVars.amountToWithdraw);

        if (localVars.amountToWithdraw == localVars.userBalance) {
            usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
            emit ReserveUsedAsCollateralDisabled(params.asset, msg.sender);
        }

        IAToken(localVars.aToken).burn(msg.sender, params.to, localVars.amountToWithdraw, reserve.liquidityIndex);

        emit Withdraw(params.asset, msg.sender, params.to, localVars.amountToWithdraw);

        return localVars.amountToWithdraw;
    }

}

