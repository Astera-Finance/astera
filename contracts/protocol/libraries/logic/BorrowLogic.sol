// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {IPriceOracleGetter} from '../../../interfaces/IPriceOracleGetter.sol';
import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {WadRayMath} from '../math/WadRayMath.sol';
import {PercentageMath} from '../math/PercentageMath.sol';
import {Errors} from '../helpers/Errors.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {GenericLogic} from './GenericLogic.sol';
import {ReserveLogic} from './ReserveLogic.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {UserConfiguration} from '../configuration/UserConfiguration.sol';

/**
 * @title BorrowLogic library
 * @author Granary
 * @notice Implements functions to validate actions related to borrowing
 */

 library BorrowLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    struct CalculateUserAccountDataVolatileVars {
        uint256 reserveUnitPrice;
        uint256 tokenUnit;
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 i;
        uint256 healthFactor;
        uint256 totalCollateralInETH;
        uint256 totalDebtInETH;
        uint256 avgLtv;
        uint256 avgLiquidationThreshold;
        uint256 reservesLength;
        uint256 userVolatility;
        bool healthFactorBelowThreshold;
        address currentReserveAddress;
        bool usageAsCollateralEnabled;
        bool userUsesReserveAsCollateral;
    }

    /**
   * @dev Calculates the user data across the reserves.
   * this includes the total liquidity/collateral/borrow balances in ETH,
   * the average Loan To Value, the average Liquidation Ratio, and the Health factor.
   * @param user The address of the user
   * @param reservesData Data of all the reserves
   * @param userConfig The configuration of the user
   * @param reserves The list of the available reserves
   * @param oracle The price oracle address
   * @return The total collateral and total debt of the user in ETH, the avg ltv, liquidation threshold and the HF
   **/
  function calculateUserAccountDataVolatile(
    address user,
    mapping(address => DataTypes.ReserveData) storage reservesData,
    DataTypes.UserConfigurationMap memory userConfig,
    mapping(uint256 => address) storage reserves,
    uint256 reservesCount,
    address oracle
  )
  internal
  view
  returns (
    uint256,
    uint256,
    uint256,
    uint256,
    uint256
  ) {
    CalculateUserAccountDataVolatileVars memory vars;

    if (userConfig.isEmpty()) {
      return (0, 0, 0, 0, uint256(-1));
    }

    // Get the user's volatility tier
    for (vars.i = 0; vars.i < reservesCount; vars.i++) {
      vars.currentReserveAddress = reserves[vars.i];
      DataTypes.ReserveData storage currentReserve = reservesData[vars.currentReserveAddress];

      if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
        continue;
      }

      if (vars.userVolatility < currentReserve.configuration.getVolatilityTier()) {
        vars.userVolatility = currentReserve.configuration.getVolatilityTier();
      }
    }

    for (vars.i = 0; vars.i < reservesCount; vars.i++) {
      vars.currentReserveAddress = reserves[vars.i];
      DataTypes.ReserveData storage currentReserve = reservesData[vars.currentReserveAddress];
      // basically get same data as user account collateral, but with different LTVs being used depending on user's most volatile asset
      if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
        continue;
      }
      (, vars.liquidationThreshold, , vars.decimals, ) = currentReserve
        .configuration
        .getParams();

      if (vars.userVolatility == 0) {
        vars.ltv = currentReserve.configuration.getLowVolatilityLtv();
      } else if (vars.userVolatility == 1) {
        vars.ltv = currentReserve.configuration.getMediumVolatilityLtv();
      } else if (vars.userVolatility == 2) {
        vars.ltv = currentReserve.configuration.getHighVolatilityLtv();
      }

      vars.tokenUnit = 10**vars.decimals;
      vars.reserveUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(vars.currentReserveAddress);

      if (vars.liquidationThreshold != 0 && userConfig.isUsingAsCollateral(vars.i)) {
        vars.compoundedLiquidityBalance = IERC20(currentReserve.aTokenAddress).balanceOf(user);

        uint256 liquidityBalanceETH = vars.reserveUnitPrice.mul(vars.compoundedLiquidityBalance).div(vars.tokenUnit);

        vars.totalCollateralInETH = vars.totalCollateralInETH.add(liquidityBalanceETH);

        vars.avgLtv = vars.avgLtv.add(liquidityBalanceETH.mul(vars.ltv));
        vars.avgLiquidationThreshold = vars.avgLiquidationThreshold.add(
          liquidityBalanceETH.mul(vars.liquidationThreshold)
        );
      }

      if (userConfig.isBorrowing(vars.i)) {
        vars.compoundedBorrowBalance = IERC20(currentReserve.stableDebtTokenAddress).balanceOf(
          user
        );
        vars.compoundedBorrowBalance = vars.compoundedBorrowBalance.add(
          IERC20(currentReserve.variableDebtTokenAddress).balanceOf(user)
        );

        vars.totalDebtInETH = vars.totalDebtInETH.add(
          vars.reserveUnitPrice.mul(vars.compoundedBorrowBalance).div(vars.tokenUnit)
        );
      }
    }

    vars.avgLtv = vars.totalCollateralInETH > 0 ? vars.avgLtv.div(vars.totalCollateralInETH) : 0;
    vars.avgLiquidationThreshold = vars.totalCollateralInETH > 0
      ? vars.avgLiquidationThreshold.div(vars.totalCollateralInETH)
      : 0;

    vars.healthFactor = GenericLogic.calculateHealthFactorFromBalances(
      vars.totalCollateralInETH,
      vars.totalDebtInETH,
      vars.avgLiquidationThreshold
    );
    return (
      vars.totalCollateralInETH,
      vars.totalDebtInETH,
      vars.avgLtv,
      vars.avgLiquidationThreshold,
      vars.healthFactor
    );
  }
    // TODO: Compile all the changes in this contract

    // Note: There are now isolatedReserves and regularReserves
    // Borrowing from an isolatedAsset means that the user's balance derived from isolatedReserves is what validates the borrow
    // Borrowing from a regularAsset means that the user's overall balance dervide from all reserves is what validates the borrow
    // Isolated Reserves are basically a subset of the reserves
    // More params can be added to the reserve config if we want to play around ltvs, liquidation thresholds...
    //
    // Go deeper with the reserves
    // introducing: Risk Tiers !!! (start with 3 of those)
    //
    //
    // Thoughts: When borrowing (both regular and isolated), should we still look at the other 'type', to check that we are not breaking a threshold? Probably, right?
    // So, now matter which borrow is undergoing, we end up looking at all the data
 }