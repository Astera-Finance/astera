// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {IPriceOracleGetter} from '../../../interfaces/IPriceOracleGetter.sol';
import {ILendingPoolAddressesProvider} from '../../../interfaces/ILendingPoolAddressesProvider.sol';
import {IAToken} from '../../../interfaces/IAToken.sol';
import {IVariableDebtToken} from '../../../interfaces/IVariableDebtToken.sol';
import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {WadRayMath} from '../math/WadRayMath.sol';
import {PercentageMath} from '../math/PercentageMath.sol';
import {Errors} from '../helpers/Errors.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {GenericLogic} from './GenericLogic.sol';
import {ReserveLogic} from './ReserveLogic.sol';
import {ValidationLogic} from './ValidationLogic.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {ReserveBorrowConfiguration} from '../configuration/ReserveBorrowConfiguration.sol';
import {UserConfiguration} from '../configuration/UserConfiguration.sol';
import {UserRecentBorrow} from '../configuration/UserRecentBorrow.sol';

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
    using ReserveBorrowConfiguration for DataTypes.ReserveBorrowConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using UserRecentBorrow for DataTypes.UserRecentBorrowMap;
    using ValidationLogic for ValidationLogic.ValidateBorrowParams;

    event Borrow(
      address indexed reserve,
      address user,
      address indexed onBehalfOf,
      uint256 amount,
      uint256 borrowRate
  );

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
        bool currentReserveType;
        bool usageAsCollateralEnabled;
        bool userUsesReserveAsCollateral;
    }

    /**
    * @param user The address of the user
    * @param reservesData Data of all the reserves
    * @param userConfig The configuration of the user
    * @param reserves The list of the available reserves
    * @param oracle The price oracle address
     */
    struct CalculateUserAccountDataVolatileParams {
      address user;
      uint256 reservesCount;
      uint256 lendingUpdateTimestamp;
      address oracle;
    }

    /**
   * @dev Calculates the user data across the reserves.
   * this includes the total liquidity/collateral/borrow balances in ETH,
   * the average Loan To Value, the average Liquidation Ratio, and the Health factor.
   * @param params the params necessary to get the correct borrow data
   * @return The total collateral and total debt of the user in ETH, the avg ltv, liquidation threshold and the HF
   **/
  function calculateUserAccountDataVolatile(
    CalculateUserAccountDataVolatileParams memory params,
    mapping(address => mapping(bool => DataTypes.ReserveData)) storage reservesData,
    DataTypes.UserConfigurationMap memory userConfig,
    DataTypes.UserRecentBorrowMap storage userRecentBorrow,
    mapping(uint256 => DataTypes.ReserveReference) storage reserves
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
      return (0, 0, 0, 0, type(uint256).max);
    }
    // Get the user's volatility tier
    vars.userVolatility = calculateUserVolatilityTier(reservesData,userConfig,reserves,params.reservesCount);
    // for (vars.i = 0; vars.i < params.reservesCount; vars.i++) {
    //   vars.currentReserveAddress = reserves[vars.i];
    //   DataTypes.ReserveData storage currentReserve = reservesData[vars.currentReserveAddress];

    //   if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
    //     continue;
    //   }

    //   if (vars.userVolatility < currentReserve.borrowConfiguration.getVolatilityTier()) {
    //     vars.userVolatility = currentReserve.borrowConfiguration.getVolatilityTier();
    //   }
    // }


    for (vars.i = 0; vars.i < params.reservesCount; vars.i++) {
      vars.currentReserveAddress = reserves[vars.i].asset;
      vars.currentReserveType = reserves[vars.i].reserveType;
      DataTypes.ReserveData storage currentReserve = reservesData[vars.currentReserveAddress][vars.currentReserveType];
      // basically get same data as user account collateral, but with different LTVs being used depending on user's most volatile asset
      if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
        continue;
      }
      (, vars.liquidationThreshold, , vars.decimals, ) = currentReserve
        .configuration
        .getParams();

      if (vars.userVolatility == 0) {
        vars.ltv = currentReserve.borrowConfiguration.getLowVolatilityLtv();
      } else if (vars.userVolatility == 1) {
        vars.ltv = currentReserve.borrowConfiguration.getMediumVolatilityLtv();
      } else if (vars.userVolatility == 2) {
        vars.ltv = currentReserve.borrowConfiguration.getHighVolatilityLtv();
      }

      vars.tokenUnit = 10**vars.decimals;
      vars.reserveUnitPrice = IPriceOracleGetter(params.oracle).getAssetPrice(vars.currentReserveAddress);

      if (vars.liquidationThreshold != 0 && userConfig.isUsingAsCollateral(vars.i)) {
        vars.compoundedLiquidityBalance = IERC20(currentReserve.aTokenAddress).balanceOf(params.user);

        uint256 liquidityBalanceETH = vars.reserveUnitPrice.mul(vars.compoundedLiquidityBalance).div(vars.tokenUnit);

        vars.totalCollateralInETH = vars.totalCollateralInETH.add(liquidityBalanceETH);

        vars.avgLtv = vars.avgLtv.add(liquidityBalanceETH.mul(vars.ltv));
        vars.avgLiquidationThreshold = vars.avgLiquidationThreshold.add(
          liquidityBalanceETH.mul(vars.liquidationThreshold)
        );
      }

      if (userConfig.isBorrowing(vars.i)) {
        vars.compoundedBorrowBalance = IERC20(currentReserve.variableDebtTokenAddress).balanceOf(
          params.user
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

    if (userRecentBorrow.getTimestamp() < params.lendingUpdateTimestamp) {
      /// Calculate health factor using new total collateral, new totalDebt, olf avgLiqThres
      vars.healthFactor = GenericLogic.calculateHealthFactorFromBalances(
        vars.totalCollateralInETH,
        vars.totalDebtInETH,
        userRecentBorrow.getAverageLiquidationThreshold()
      );
    } else {
      vars.healthFactor = GenericLogic.calculateHealthFactorFromBalances(
        vars.totalCollateralInETH,
        vars.totalDebtInETH,
        vars.avgLiquidationThreshold
      );
    }


    userRecentBorrow.setAverageLtv(vars.avgLtv);
    userRecentBorrow.setAverageLiquidationThreshold(vars.avgLiquidationThreshold);
    userRecentBorrow.setTimestamp(block.timestamp);

    return (
      vars.totalCollateralInETH,
      vars.totalDebtInETH,
      vars.avgLtv,
      vars.avgLiquidationThreshold,
      vars.healthFactor
    );
  }

  function calculateUserVolatilityTier(
    mapping(address => mapping(bool => DataTypes.ReserveData)) storage reservesData,
    DataTypes.UserConfigurationMap memory userConfig,
    mapping(uint256 => DataTypes.ReserveReference) storage reserves,
    uint256 reservesCount
  )
  internal
  view
  returns (
    uint256 userVolatility
  ) {
    for (uint256 i; i < reservesCount; i++) {
      address currentReserveAddress = reserves[i].asset;
      bool currentReserveType = reserves[i].reserveType;
      DataTypes.ReserveData storage currentReserve = reservesData[currentReserveAddress][currentReserveType];
      if(!userConfig.isUsingAsCollateralOrBorrowing(i)) {
        continue;
      }
      uint256 currentReserveVolatility = currentReserve.borrowConfiguration.getVolatilityTier();
      if (userVolatility < currentReserveVolatility) {
        userVolatility = currentReserveVolatility;
      }
    }
  }

  struct ExecuteBorrowParams {
    address asset;
    bool reserveType;
    address user;
    address onBehalfOf;
    uint256 amount;
    address aTokenAddress;
    bool releaseUnderlying;
    ILendingPoolAddressesProvider addressesProvider;
    uint256 reservesCount;
  }


  function executeBorrow(
    ExecuteBorrowParams memory vars,
    mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
    mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
    mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
    mapping(address => DataTypes.UserRecentBorrowMap) storage _usersRecentBorrow
  ) public {
    DataTypes.ReserveData storage reserve = reserves[vars.asset][vars.reserveType];
    require(reserve.configuration.getActive(), Errors.VL_NO_ACTIVE_RESERVE);
    
    DataTypes.UserConfigurationMap storage userConfig = usersConfig[vars.onBehalfOf];
    DataTypes.UserRecentBorrowMap storage userRecentBorrow = _usersRecentBorrow[vars.onBehalfOf];

    ValidationLogic.ValidateBorrowParams memory validateBorrowParams;

    /*{
    address oracle = vars.addressesProvider.getPriceOracle();

    uint256 amountInETH =
      IPriceOracleGetter(oracle).getAssetPrice(vars.asset).mul(vars.amount).div(
        10**reserve.configuration.getDecimals()
      );

    }*/
    address oracle = vars.addressesProvider.getPriceOracle();
    uint256 amountInETH = amountInETH(vars.asset, vars.amount, reserve.configuration.getDecimals(), oracle);

    validateBorrowParams.asset = vars.asset;
    validateBorrowParams.userAddress = vars.onBehalfOf;
    validateBorrowParams.amount = vars.amount;
    validateBorrowParams.amountInETH = amountInETH;
    validateBorrowParams.reservesCount = vars.reservesCount;
    validateBorrowParams.oracle = oracle;
    ValidationLogic.validateBorrow(
      validateBorrowParams,
      reserve,
      reserves,
      userConfig,
      reservesList,
      userRecentBorrow
    );

    reserve.updateState();

    {
      bool isFirstBorrowing = false;

      isFirstBorrowing = IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
        vars.user,
        vars.onBehalfOf,
        vars.amount,
        reserve.variableBorrowIndex
      );

      if (isFirstBorrowing) {
        userConfig.setBorrowing(reserve.id, true);
      }
    }

    reserve.updateInterestRates(
      vars.asset,
      vars.aTokenAddress,
      0,
      vars.releaseUnderlying ? vars.amount : 0
    );

    if (vars.releaseUnderlying) {
      IAToken(vars.aTokenAddress).transferUnderlyingTo(vars.user, vars.amount);
    }

    emit Borrow(
      vars.asset,
      vars.user,
      vars.onBehalfOf,
      vars.amount,
      reserve.currentVariableBorrowRate
    );

  }

  function amountInETH(
    address asset,
    uint256 amount,
    uint256 decimals,
    address oracle
  ) internal view returns (uint256) {
    return IPriceOracleGetter(oracle).getAssetPrice(asset).mul(amount).div(10**decimals);
  }
 }