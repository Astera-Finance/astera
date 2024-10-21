// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {ILendingPoolAddressesProvider} from
    "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {SafeERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";

import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../../../contracts/interfaces/IVariableDebtToken.sol";
import {IPriceOracleGetter} from "../../../../../contracts/interfaces/IPriceOracleGetter.sol";
import {GenericLogic} from
    "../../../../../contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
import {Helpers} from "../../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {ValidationLogic} from
    "../../../../../contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import {UserConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ReserveLogic} from
    "../../../../../contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title LiquidationLogic
 * @author Cod3x
 */
library LiquidationLogic {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

    /**
     * @dev Emitted when a borrower is liquidated
     * @param collateral The address of the collateral being liquidated
     * @param principal The address of the reserve
     * @param user The address of the user being liquidated
     * @param debtToCover The total amount liquidated
     * @param liquidatedCollateralAmount The amount of collateral being liquidated
     * @param liquidator The address of the liquidator
     * @param receiveAToken true if the liquidator wants to receive aTokens, false otherwise
     *
     */
    event LiquidationCall(
        address indexed collateral,
        address indexed principal,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken
    );

    /**
     * @dev Emitted when a reserve is disabled as collateral for an user
     * @param reserve The address of the reserve
     * @param user The address of the user
     *
     */
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted when a reserve is enabled as collateral for an user
     * @param reserve The address of the reserve
     * @param user The address of the user
     *
     */
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    struct liquidationCallParams {
        address addressesProvider;
        uint256 reservesCount;
        address collateralAsset;
        bool collateralAssetType;
        address debtAsset;
        bool debtAssetType;
        address user;
        uint256 debtToCover;
        bool receiveAToken;
    }

    /**
     * @dev Function to liquidate a position if its Health Factor drops below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param reserves Data of all the reserves
     * @param usersConfig The configuration of the user
     * @param reservesList Reverves list
     * @param params Liquidation parameters
     */
    function liquidationCall(
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        liquidationCallParams memory params
    ) external {
        DataTypes.ReserveData storage collateralReserve =
            reserves[params.collateralAsset][params.collateralAssetType];
        DataTypes.ReserveData storage debtReserve = reserves[params.debtAsset][params.debtAssetType];
        DataTypes.UserConfigurationMap storage userConfig = usersConfig[params.user];

        LiquidationCallLocalVars memory vars;
        ILendingPoolAddressesProvider addressesProvider =
            ILendingPoolAddressesProvider(params.addressesProvider);

        (,,,, vars.healthFactor) = GenericLogic.calculateUserAccountData(
            params.user,
            reserves,
            userConfig,
            reservesList,
            params.reservesCount,
            addressesProvider.getPriceOracle()
        );

        (vars.userVariableDebt) = Helpers.getUserCurrentDebt(params.user, debtReserve);

        ValidationLogic.validateLiquidationCall(
            collateralReserve, debtReserve, userConfig, vars.healthFactor, vars.userVariableDebt
        );

        vars.collateralAtoken = IAToken(collateralReserve.aTokenAddress);

        vars.userCollateralBalance = vars.collateralAtoken.balanceOf(params.user);

        vars.maxLiquidatableDebt =
            vars.userVariableDebt.percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);

        vars.actualDebtToLiquidate = params.debtToCover > vars.maxLiquidatableDebt
            ? vars.maxLiquidatableDebt
            : params.debtToCover;

        (vars.maxCollateralToLiquidate, vars.debtAmountNeeded) =
        _calculateAvailableCollateralToLiquidate(
            addressesProvider,
            collateralReserve,
            debtReserve,
            params.collateralAsset,
            params.debtAsset,
            vars.actualDebtToLiquidate,
            vars.userCollateralBalance
        );

        // If debtAmountNeeded < actualDebtToLiquidate, there isn't enough
        // collateral to cover the actual amount that is being liquidated, hence we liquidate
        // a smaller amount

        if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
            vars.actualDebtToLiquidate = vars.debtAmountNeeded;
        }

        // If the liquidator reclaims the underlying asset, we make sure there is enough available liquidity in the
        // collateral reserve
        if (!params.receiveAToken) {
            uint256 currentAvailableCollateral =
                IAToken(vars.collateralAtoken).getTotalManagedAssets();
            if (currentAvailableCollateral < vars.maxCollateralToLiquidate) {
                revert(Errors.LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE);
            }
        }

        debtReserve.updateState();

        if (vars.userVariableDebt >= vars.actualDebtToLiquidate) {
            IVariableDebtToken(debtReserve.variableDebtTokenAddress).burn(
                params.user, vars.actualDebtToLiquidate, debtReserve.variableBorrowIndex
            );
        } else {
            IVariableDebtToken(debtReserve.variableDebtTokenAddress).burn(
                params.user, vars.userVariableDebt, debtReserve.variableBorrowIndex
            );
        }

        debtReserve.updateInterestRates(
            params.debtAsset, debtReserve.aTokenAddress, vars.actualDebtToLiquidate, 0
        );

        if (params.receiveAToken) {
            vars.liquidatorPreviousATokenBalance =
                IERC20(vars.collateralAtoken).balanceOf(msg.sender);
            vars.collateralAtoken.transferOnLiquidation(
                params.user, msg.sender, vars.maxCollateralToLiquidate
            );

            if (vars.liquidatorPreviousATokenBalance == 0) {
                DataTypes.UserConfigurationMap storage liquidatorConfig = usersConfig[msg.sender];
                liquidatorConfig.setUsingAsCollateral(collateralReserve.id, true);
                emit ReserveUsedAsCollateralEnabled(params.collateralAsset, msg.sender);
            }
        } else {
            collateralReserve.updateState();
            collateralReserve.updateInterestRates(
                params.collateralAsset,
                address(vars.collateralAtoken),
                0,
                vars.maxCollateralToLiquidate
            );

            // Burn the equivalent amount of aToken, sending the underlying to the liquidator
            vars.collateralAtoken.burn(
                params.user,
                msg.sender,
                vars.maxCollateralToLiquidate,
                collateralReserve.liquidityIndex
            );
        }

        // If the collateral being liquidated is equal to the params.user balance,
        // we set the currency as not being used as collateral anymore
        if (vars.maxCollateralToLiquidate == vars.userCollateralBalance) {
            userConfig.setUsingAsCollateral(collateralReserve.id, false);
            emit ReserveUsedAsCollateralDisabled(params.collateralAsset, params.user);
        }

        // Transfers the debt asset being repaid to the aToken, where the liquidity is kept
        IERC20(params.debtAsset).safeTransferFrom(
            msg.sender, debtReserve.aTokenAddress, vars.actualDebtToLiquidate
        );

        IAToken(debtReserve.aTokenAddress).handleRepayment(
            msg.sender, params.user, vars.actualDebtToLiquidate
        );

        emit LiquidationCall(
            params.collateralAsset,
            params.debtAsset,
            params.user,
            vars.actualDebtToLiquidate,
            vars.maxCollateralToLiquidate,
            msg.sender,
            params.receiveAToken
        );
    }

    struct LiquidationCallLocalVars {
        uint256 userCollateralBalance;
        uint256 userVariableDebt;
        uint256 maxLiquidatableDebt;
        uint256 actualDebtToLiquidate;
        uint256 liquidationRatio;
        uint256 maxAmountCollateralToLiquidate;
        uint256 maxCollateralToLiquidate;
        uint256 debtAmountNeeded;
        uint256 healthFactor;
        uint256 liquidatorPreviousATokenBalance;
        IAToken collateralAtoken;
        bool isCollateralEnabled;
        DataTypes.InterestRateMode borrowRateMode;
        uint256 errorCode;
        string errorMsg;
    }

    struct AvailableCollateralToLiquidateLocalVars {
        uint256 liquidationBonus;
        uint256 collateralPrice;
        uint256 debtAssetPrice;
        uint256 maxAmountCollateralToLiquidate;
        uint256 debtAssetDecimals;
        uint256 collateralDecimals;
    }

    /**
     * @dev Calculates how much of a specific collateral can be liquidated, given
     * a certain amount of debt asset.
     * - This function needs to be called after all the checks to validate the liquidation have been performed,
     *   otherwise it might fail.
     * @param addressesProvider The lendingpool address provider
     * @param collateralReserve The data of the collateral reserve
     * @param debtReserve The data of the debt reserve
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param userCollateralBalance The collateral balance for the specific `collateralAsset` of the user being liquidated
     * @return collateralAmount: The maximum amount that is possible to liquidate given all the liquidation constraints
     *                           (user balance, close factor)
     *         debtAmountNeeded: The amount to repay with the liquidation
     *
     */
    function _calculateAvailableCollateralToLiquidate(
        ILendingPoolAddressesProvider addressesProvider,
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) internal view returns (uint256, uint256) {
        uint256 collateralAmount;
        uint256 debtAmountNeeded;
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        AvailableCollateralToLiquidateLocalVars memory vars;

        vars.collateralPrice = oracle.getAssetPrice(collateralAsset);
        vars.debtAssetPrice = oracle.getAssetPrice(debtAsset);

        (,, vars.liquidationBonus, vars.collateralDecimals,) =
            collateralReserve.configuration.getParams();
        vars.debtAssetDecimals = debtReserve.configuration.getDecimals();

        // This is the maximum possible amount of the selected collateral that can be liquidated, given the
        // max amount of liquidatable debt
        vars.maxAmountCollateralToLiquidate = (
            (vars.debtAssetPrice * debtToCover * (10 ** vars.collateralDecimals)).percentMul(
                vars.liquidationBonus
            )
        ) / (vars.collateralPrice * (10 ** vars.debtAssetDecimals));

        if (vars.maxAmountCollateralToLiquidate > userCollateralBalance) {
            collateralAmount = userCollateralBalance;
            debtAmountNeeded = (
                (vars.collateralPrice * collateralAmount * (10 ** vars.debtAssetDecimals))
                    / (vars.debtAssetPrice * (10 ** vars.collateralDecimals))
            ).percentDiv(vars.liquidationBonus);
        } else {
            collateralAmount = vars.maxAmountCollateralToLiquidate;
            debtAmountNeeded = debtToCover;
        }
        return (collateralAmount, debtAmountNeeded);
    }
}
