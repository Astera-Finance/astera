// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IOracle} from "../../../../../contracts/interfaces/IOracle.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {MiniPoolGenericLogic} from "./MiniPoolGenericLogic.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {MiniPoolValidationLogic} from "./MiniPoolValidationLogic.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {Helpers} from "../../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {ILendingPool} from "../../../../../contracts/interfaces/ILendingPool.sol";
import {ATokenNonRebasing} from
    "../../../../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";

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
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using MiniPoolValidationLogic for MiniPoolValidationLogic.ValidateBorrowParams;

    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );

    struct CalculateUserAccountDataVolatileLocalVars {
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
        address currentReserveAddress;
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
        address oracle;
    }

    /**
     * @dev Calculates the user data across the reserves.
     * this includes the total liquidity/collateral/borrow balances in ETH,
     * the average Loan To Value, the average Liquidation Ratio, and the Health factor.
     * @param params the params necessary to get the correct borrow data
     * @return The total collateral and total debt of the user in ETH, the avg ltv, liquidation threshold and the HF
     */
    function calculateUserAccountDataVolatile(
        CalculateUserAccountDataVolatileParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => address) storage reservesList
    ) external view returns (uint256, uint256, uint256, uint256, uint256) {
        CalculateUserAccountDataVolatileLocalVars memory vars;

        if (userConfig.isEmpty()) {
            return (0, 0, 0, 0, type(uint256).max);
        }

        for (vars.i = 0; vars.i < params.reservesCount; vars.i++) {
            if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
                continue;
            }

            vars.currentReserveAddress = reservesList[vars.i];
            DataTypes.MiniPoolReserveData storage currentReserve =
                reserves[vars.currentReserveAddress];

            (vars.ltv, vars.liquidationThreshold,, vars.decimals,) =
                currentReserve.configuration.getParams();

            vars.tokenUnit = 10 ** vars.decimals;

            vars.reserveUnitPrice = IOracle(params.oracle).getAssetPrice(vars.currentReserveAddress);

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

        vars.healthFactor = MiniPoolGenericLogic.calculateHealthFactorFromBalances(
            vars.totalCollateralInETH, vars.totalDebtInETH, vars.avgLiquidationThreshold
        );

        return (
            vars.totalCollateralInETH,
            vars.totalDebtInETH,
            vars.avgLtv,
            vars.avgLiquidationThreshold,
            vars.healthFactor
        );
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
        bool unwrap,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        mapping(uint256 => address) storage reservesList,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig
    ) external {
        DataTypes.MiniPoolReserveData storage reserve = reserves[vars.asset];
        require(reserve.configuration.getActive(), Errors.VL_NO_ACTIVE_RESERVE);

        DataTypes.UserConfigurationMap storage userConfig = usersConfig[vars.onBehalfOf];

        MiniPoolValidationLogic.ValidateBorrowParams memory validateBorrowParams;

        {
            address oracle = vars.addressesProvider.getPriceOracle();

            validateBorrowParams.userAddress = vars.onBehalfOf;
            validateBorrowParams.amount = vars.amount;
            validateBorrowParams.amountInETH =
                amountInETH(vars.asset, vars.amount, reserve.configuration.getDecimals(), oracle);
            validateBorrowParams.reservesCount = vars.reservesCount;
            validateBorrowParams.oracle = oracle;
            MiniPoolValidationLogic.validateBorrow(
                validateBorrowParams, reserve, reserves, userConfig, reservesList
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
                vars.user, reserve.aTokenID, vars.amount, unwrap
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
        return IOracle(oracle).getAssetPrice(asset) * amount / (10 ** decimals);
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
        bool wrap,
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
            false,
            reserve.variableBorrowIndex
        );

        address aToken = reserve.aTokenAddress;
        reserve.updateInterestRates(params.asset, paybackAmount, 0);

        if (variableDebt - paybackAmount == 0) {
            _usersConfig[params.onBehalfOf].setBorrowing(reserve.id, false);
        }

        if (wrap) {
            address underlying = ATokenNonRebasing(params.asset).UNDERLYING_ASSET_ADDRESS();
            address lendingPool = params.addressesProvider.getLendingPool();
            uint256 underlyingAmount =
                ATokenNonRebasing(params.asset).convertToAssets(paybackAmount);

            IERC20(underlying).safeTransferFrom(msg.sender, address(this), underlyingAmount);
            IERC20(underlying).forceApprove(lendingPool, underlyingAmount);
            ILendingPool(lendingPool).deposit(underlying, true, underlyingAmount, aToken);
        } else {
            IERC20(params.asset).safeTransferFrom(msg.sender, aToken, paybackAmount);
        }

        IAERC6909(aToken).handleRepayment(
            msg.sender, params.onBehalfOf, reserve.aTokenID, paybackAmount
        );

        emit Repay(params.asset, params.onBehalfOf, msg.sender, paybackAmount);

        return paybackAmount;
    }
}
