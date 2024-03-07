// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from '../../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {SafeMath} from '../../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IMiniPoolAddressesProvider} from '../../../../interfaces/IMiniPoolAddressesProvider.sol';
import {IAERC6909} from '../../../../interfaces/IAERC6909.sol';
import {IReserveInterestRateStrategy} from '../../../../interfaces/IReserveInterestRateStrategy.sol';
import {ReserveConfiguration} from '../../../libraries/configuration/ReserveConfiguration.sol';
import {ReserveBorrowConfiguration} from '../../../libraries/configuration/ReserveBorrowConfiguration.sol';
import {MathUtils} from '../../../libraries/math/MathUtils.sol';
import {WadRayMath} from '../../../libraries/math/WadRayMath.sol';
import {PercentageMath} from '../../../libraries/math/PercentageMath.sol';
import {Errors} from '../../../libraries/helpers/Errors.sol';
import {DataTypes} from '../../../libraries/types/DataTypes.sol';
import {UserConfiguration} from '../../../libraries/configuration/UserConfiguration.sol';
import {MiniPoolValidationLogic} from './MiniPoolValidationLogic.sol';
import {MiniPoolReserveLogic} from './MiniPoolReserveLogic.sol';


/**
 * @title Deposit Logic library
 * @notice Implements the logic to deposit assets into the protocol
 */

library MiniPoolDepositLogic {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;
  using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
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
        uint256 amount;
        address onBehalfOf;
    }

    function deposit(
            DepositParams memory params,
            mapping(address => DataTypes.MiniPoolReserveData) storage _reserves,
            mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
            IMiniPoolAddressesProvider _addressesProvider
        ) external {
         DataTypes.MiniPoolReserveData storage reserve = _reserves[params.asset];

        MiniPoolValidationLogic.validateDeposit(reserve, params.amount);

        address aToken = reserve.aTokenAddress;

        reserve.updateState();
        reserve.updateInterestRates(params.asset, params.amount, 0);

        IERC20(params.asset).safeTransferFrom(msg.sender, aToken, params.amount);

        bool isFirstDeposit = IAERC6909(reserve.aTokenAddress).
                                mint(
                                    msg.sender,
                                    params.onBehalfOf, 
                                    reserve.aTokenID,
                                    params.amount, 
                                    reserve.liquidityIndex);


        if (isFirstDeposit) {
            _usersConfig[params.onBehalfOf].setUsingAsCollateral(reserve.id, true);
            emit ReserveUsedAsCollateralEnabled(params.asset, params.onBehalfOf);
        }


        emit Deposit(params.asset, msg.sender, params.onBehalfOf, params.amount);
    }


}

