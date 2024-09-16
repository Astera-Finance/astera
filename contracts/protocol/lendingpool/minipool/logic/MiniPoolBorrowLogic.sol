// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IPriceOracleGetter} from "contracts/interfaces/IPriceOracleGetter.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IAERC6909} from "contracts/interfaces/IAERC6909.sol";
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {MiniPoolGenericLogic} from "./MiniPoolGenericLogic.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {MiniPoolValidationLogic} from "./MiniPoolValidationLogic.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ReserveBorrowConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveBorrowConfiguration.sol";
import {UserConfiguration} from "contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {UserRecentBorrow} from "contracts/protocol/libraries/configuration/UserRecentBorrow.sol";
import {Helpers} from "contracts/protocol/libraries/helpers/Helpers.sol";

/**
 * @title BorrowLogic library
 * @author Cod3x
 * @notice Implements functions to validate actions related to borrowing
 */
library MiniPoolBorrowLogic {
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using ReserveBorrowConfiguration for DataTypes.ReserveBorrowConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using UserRecentBorrow for DataTypes.UserRecentBorrowMap;
    using MiniPoolValidationLogic for MiniPoolValidationLogic.ValidateBorrowParams;

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
        address underlyingAsset;
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
     *
     */
    function calculateUserAccountDataVolatile(
        CalculateUserAccountDataVolatileParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage reservesData,
        DataTypes.UserConfigurationMap memory userConfig,
        DataTypes.UserRecentBorrowMap storage userRecentBorrow,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves
    ) external view returns (uint256, uint256, uint256, uint256, uint256) {
        CalculateUserAccountDataVolatileVars memory vars;

        if (userConfig.isEmpty()) {
            return (0, 0, 0, 0, type(uint256).max);
        }
        // Get the user's volatility tier
        vars.userVolatility =
            calculateUserVolatilityTier(reservesData, userConfig, reserves, params.reservesCount);

        for (vars.i = 0; vars.i < params.reservesCount; vars.i++) {
            vars.currentReserveAddress = reserves[vars.i].asset;
            DataTypes.MiniPoolReserveData storage currentReserve =
                reservesData[vars.currentReserveAddress];
            // basically get same data as user account collateral, but with different LTVs being used depending on user's most volatile asset
            if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
                continue;
            }
            (, vars.liquidationThreshold,, vars.decimals,) =
                currentReserve.configuration.getParams();

            if (vars.userVolatility == 0) {
                vars.ltv = currentReserve.borrowConfiguration.getLowVolatilityLtv();
            } else if (vars.userVolatility == 1) {
                vars.ltv = currentReserve.borrowConfiguration.getMediumVolatilityLtv();
            } else if (vars.userVolatility == 2) {
                vars.ltv = currentReserve.borrowConfiguration.getHighVolatilityLtv();
            }

            vars.tokenUnit = 10 ** vars.decimals;

            vars.reserveUnitPrice =
                IPriceOracleGetter(params.oracle).getAssetPrice(vars.currentReserveAddress);

            if (vars.liquidationThreshold != 0 && userConfig.isUsingAsCollateral(vars.i)) {
                vars.compoundedLiquidityBalance = IAERC6909(currentReserve.aTokenAddress).balanceOf(
                    params.user, currentReserve.aTokenID
                );

                uint256 liquidityBalanceETH =
                    vars.reserveUnitPrice * vars.compoundedLiquidityBalance / vars.tokenUnit;

                vars.totalCollateralInETH = vars.totalCollateralInETH + liquidityBalanceETH;

                vars.avgLtv = vars.avgLtv + (liquidityBalanceETH * vars.ltv);
                vars.avgLiquidationThreshold =
                    vars.avgLiquidationThreshold + (liquidityBalanceETH * vars.liquidationThreshold);
            }

            if (userConfig.isBorrowing(vars.i)) {
                vars.compoundedBorrowBalance = IAERC6909(currentReserve.aTokenAddress).balanceOf(
                    params.user, currentReserve.variableDebtTokenID
                );

                vars.totalDebtInETH = vars.totalDebtInETH
                    + (vars.reserveUnitPrice * vars.compoundedBorrowBalance / vars.tokenUnit);
            }
        }

        vars.avgLtv = vars.totalCollateralInETH > 0 ? vars.avgLtv / vars.totalCollateralInETH : 0;
        vars.avgLiquidationThreshold = vars.totalCollateralInETH > 0
            ? vars.avgLiquidationThreshold / vars.totalCollateralInETH
            : 0;

        if (userRecentBorrow.getTimestamp() < params.lendingUpdateTimestamp) {
            /// Calculate health factor using new total collateral, new totalDebt, olf avgLiqThres
            vars.healthFactor = MiniPoolGenericLogic.calculateHealthFactorFromBalances(
                vars.totalCollateralInETH,
                vars.totalDebtInETH,
                userRecentBorrow.getAverageLiquidationThreshold()
            );
        } else {
            vars.healthFactor = MiniPoolGenericLogic.calculateHealthFactorFromBalances(
                vars.totalCollateralInETH, vars.totalDebtInETH, vars.avgLiquidationThreshold
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
        mapping(address => DataTypes.MiniPoolReserveData) storage reservesData,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves,
        uint256 reservesCount
    ) internal view returns (uint256 userVolatility) {
        for (uint256 i; i < reservesCount; i++) {
            address currentReserveAddress = reserves[i].asset;
            DataTypes.MiniPoolReserveData storage currentReserve =
                reservesData[currentReserveAddress];
            if (!userConfig.isUsingAsCollateralOrBorrowing(i)) {
                continue;
            }
            uint256 currentReserveVolatility =
                currentReserve.borrowConfiguration.getVolatilityTier();
            if (userVolatility < currentReserveVolatility) {
                userVolatility = currentReserveVolatility;
            }
        }
    }

    struct ExecuteBorrowParams {
        address asset;
        address user;
        address onBehalfOf;
        uint256 amount;
        address aTokenAddress;
        uint256 aTokenID;
        uint256 variableDebtTokenID;
        uint256 index;
        bool releaseUnderlying;
        IMiniPoolAddressesProvider addressesProvider;
        uint256 reservesCount;
    }

    function executeBorrow(
        ExecuteBorrowParams memory vars,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(address => DataTypes.UserRecentBorrowMap) storage _usersRecentBorrow
    ) external {
        DataTypes.MiniPoolReserveData storage reserve = reserves[vars.asset];
        require(reserve.configuration.getActive(), Errors.VL_NO_ACTIVE_RESERVE);

        DataTypes.UserConfigurationMap storage userConfig = usersConfig[vars.onBehalfOf];
        DataTypes.UserRecentBorrowMap storage userRecentBorrow = _usersRecentBorrow[vars.onBehalfOf];

        MiniPoolValidationLogic.ValidateBorrowParams memory validateBorrowParams;

        {
            address oracle = vars.addressesProvider.getPriceOracle();

            validateBorrowParams.asset = vars.asset;
            validateBorrowParams.userAddress = vars.onBehalfOf;
            validateBorrowParams.amount = vars.amount;
            validateBorrowParams.amountInETH =
                amountInETH(vars.asset, vars.amount, reserve.configuration.getDecimals(), oracle);
            validateBorrowParams.reservesCount = vars.reservesCount;
            validateBorrowParams.oracle = oracle;
            MiniPoolValidationLogic.validateBorrow(
                validateBorrowParams, reserve, reserves, userConfig, reservesList, userRecentBorrow
            );
        }

        reserve.updateState();

        {
            bool isFirstBorrowing = false;
            {
                vars.aTokenAddress = reserve.aTokenAddress;
                vars.aTokenID = reserve.aTokenID;
                vars.variableDebtTokenID = reserve.variableDebtTokenID;
                vars.index = reserve.variableBorrowIndex;
            }
            isFirstBorrowing = IAERC6909(vars.aTokenAddress).mint(
                vars.user, vars.onBehalfOf, vars.variableDebtTokenID, vars.amount, vars.index
            );

            if (isFirstBorrowing) {
                userConfig.setBorrowing(reserve.id, true);
            }
        }

        reserve.updateInterestRates(vars.asset, 0, vars.releaseUnderlying ? vars.amount : 0);

        if (vars.releaseUnderlying) {
            IAERC6909(vars.aTokenAddress).transferUnderlyingTo(
                vars.user, reserve.aTokenID, vars.amount
            );
        }

        emit Borrow(
            vars.asset, vars.user, vars.onBehalfOf, vars.amount, reserve.currentVariableBorrowRate
        );
    }

    function amountInETH(address asset, uint256 amount, uint256 decimals, address oracle)
        internal
        view
        returns (uint256)
    {
        return IPriceOracleGetter(oracle).getAssetPrice(asset) * amount / (10 ** decimals);
    }

    struct repayParams {
        address asset;
        uint256 amount;
        address onBehalfOf;
        IMiniPoolAddressesProvider addressesProvider;
    }

    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount
    );

    function repay(
        repayParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage _reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig
    ) external returns (uint256) {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[params.asset];

        (uint256 variableDebt) = Helpers.getUserCurrentDebt(params.onBehalfOf, reserve);

        MiniPoolValidationLogic.validateRepay(
            reserve, params.amount, params.onBehalfOf, variableDebt
        );

        uint256 paybackAmount = variableDebt;

        if (params.amount < paybackAmount) {
            paybackAmount = params.amount;
        }

        reserve.updateState();

        IAERC6909(reserve.aTokenAddress).burn(
            params.onBehalfOf,
            params.onBehalfOf, // we dont care about the burn receiver for debtTokens
            reserve.variableDebtTokenID,
            paybackAmount,
            reserve.variableBorrowIndex
        );

        address aToken = reserve.aTokenAddress;
        reserve.updateInterestRates(params.asset, paybackAmount, 0);

        if (variableDebt - paybackAmount == 0) {
            _usersConfig[params.onBehalfOf].setBorrowing(reserve.id, false);
        }

        IERC20(params.asset).safeTransferFrom(msg.sender, aToken, paybackAmount);

        IAERC6909(aToken).handleRepayment(
            msg.sender, params.onBehalfOf, reserve.aTokenID, paybackAmount
        );

        emit Repay(params.asset, params.onBehalfOf, msg.sender, paybackAmount);

        return paybackAmount;
    }
}
