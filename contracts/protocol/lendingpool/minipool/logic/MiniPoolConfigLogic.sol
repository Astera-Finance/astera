// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {SafeMath} from "../../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {IERC20} from "../../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../interfaces/ILendingPoolAddressesProvider.sol";
import {SafeERC20} from "../../../../dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IAToken} from "../../../../interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../../interfaces/IVariableDebtToken.sol";
import {IReserveInterestRateStrategy} from "../../../../interfaces/IReserveInterestRateStrategy.sol";
import {ReserveConfiguration} from "../../../libraries/configuration/ReserveConfiguration.sol";
import {ReserveBorrowConfiguration} from
    "../../../libraries/configuration/ReserveBorrowConfiguration.sol";
import {MathUtils} from "../../../libraries/math/MathUtils.sol";
import {WadRayMath} from "../../../libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../libraries/math/PercentageMath.sol";
import {Errors} from "../../../libraries/helpers/Errors.sol";
import {DataTypes} from "../../../libraries/types/DataTypes.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {UserConfiguration} from "../../../libraries/configuration/UserConfiguration.sol";
import {MiniPoolValidationLogic} from "./MiniPoolValidationLogic.sol";

/**
 * @title Config Logic library
 * @notice Implements the logic to configure assets into the protocol
 */
library MiniPoolConfigLogic {
/*
    function setUserUseReserveAsCollateral(address asset, bool reserveType, bool useAsCollateral)
    internal
    override
    whenNotPaused
  {
    DataTypes.ReserveData storage reserve = _reserves[asset][reserveType];

    ValidationLogic.validateSetUseReserveAsCollateral(
      reserve,
      asset,
      reserveType,
      useAsCollateral,
      _reserves,
      _usersConfig[msg.sender],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, useAsCollateral);

    if (useAsCollateral) {
      emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
    } else {
      emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
    }
  }
*/
}
