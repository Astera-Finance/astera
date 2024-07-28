// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {SafeMath} from "../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {IERC20} from "../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {ILendingPoolAddressesProvider} from "../../../interfaces/ILendingPoolAddressesProvider.sol";
import {SafeERC20} from "../../../dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IAToken} from "../../../interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../interfaces/IVariableDebtToken.sol";
import {IReserveInterestRateStrategy} from "../../../interfaces/IReserveInterestRateStrategy.sol";
import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {ReserveBorrowConfiguration} from "../configuration/ReserveBorrowConfiguration.sol";
import {MathUtils} from "../math/MathUtils.sol";
import {WadRayMath} from "../math/WadRayMath.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {UserConfiguration} from "../configuration/UserConfiguration.sol";
import {ValidationLogic} from "./ValidationLogic.sol";

/**
 * @title Config Logic library
 * @notice Implements the logic to configure assets into the protocol
 */
library ConfigLogic {
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
