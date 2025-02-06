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
 * @title MiniPoolBorrowLogic library
 * @author Cod3x
 * @notice Implements functions to validate and execute borrowing-related actions in the MiniPool.
 * @dev Contains core borrowing logic including health factor calculations, borrow execution and repayment handling.
 */
library MiniPoolBorrowLogic {
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using MiniPoolValidationLogic for MiniPoolValidationLogic.ValidateBorrowParams;

    /**
     * @dev Emitted on borrow.
     * @param reserve The address of the reserve being borrowed from.
     * @param user The address initiating the borrow.
     * @param onBehalfOf The address receiving the borrowed assets.
     * @param amount The amount being borrowed.
     * @param borrowRate The current borrow rate for the reserve.
     */
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );

    /**
     * @dev Struct containing local variables used in account data calculation.
     */
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
     * @dev Parameters for calculating user account data.
     * @param user The address of the user.
     * @param reservesCount Total number of initialized reserves.
     * @param oracle The price oracle address.
     */
    struct CalculateUserAccountDataVolatileParams {
        address user;
        uint256 reservesCount;
        address oracle;
    }

    /**
     * @dev Calculates the user data across the reserves.
     * @param params The parameters needed for calculation.
     * @param reserves Mapping of reserve data.
     * @param userConfig The user's configuration.
     * @param reservesList List of initialized reserves.
     * @return totalCollateralInETH Total collateral in ETH.
     * @return totalDebtInETH Total debt in ETH.
     * @return avgLtv Average loan to value ratio.
     * @return avgLiquidationThreshold Average liquidation threshold.
     * @return healthFactor User's health factor.
     */
    function calculateUserAccountDataVolatile(
        CalculateUserAccountDataVolatileParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => address) storage reservesList
    ) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return MiniPoolGenericLogic.calculateUserAccountData(
            params.user, reserves, userConfig, reservesList, params.reservesCount, params.oracle
        );
    }

    /**
     * @dev Parameters for executing a borrow operation.
     */
    struct ExecuteBorrowParams {
        address asset;
        address user;
        address onBehalfOf;
        uint256 amount;
        address aErc6909;
        uint256 aTokenID;
        uint256 variableDebtTokenID;
        uint256 index;
        bool releaseUnderlying;
        IMiniPoolAddressesProvider addressesProvider;
        uint256 reservesCount;
        uint256 minAmount;
    }

    /**
     * @dev Executes a borrow operation.
     * @param vars The borrow parameters.
     * @param unwrap Whether to unwrap the underlying asset.
     * @param reserves Mapping of reserve data.
     * @param reservesList List of initialized reserves.
     * @param usersConfig Mapping of user configurations.
     */
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
            validateBorrowParams.minAmount = vars.minAmount;
            MiniPoolValidationLogic.validateBorrow(
                validateBorrowParams, reserve, reserves, userConfig, reservesList
            );
        }

        reserve.updateState();

        {
            bool isFirstBorrowing = false;
            {
                vars.aErc6909 = reserve.aErc6909;
                vars.aTokenID = reserve.aTokenID;
                vars.variableDebtTokenID = reserve.variableDebtTokenID;
                vars.index = reserve.variableBorrowIndex;
            }
            isFirstBorrowing = IAERC6909(vars.aErc6909).mint(
                vars.user, vars.onBehalfOf, vars.variableDebtTokenID, vars.amount, vars.index
            );

            if (isFirstBorrowing) {
                userConfig.setBorrowing(reserve.id, true);
            }
        }

        reserve.updateInterestRates(vars.asset, 0, vars.releaseUnderlying ? vars.amount : 0);

        if (vars.releaseUnderlying) {
            IAERC6909(vars.aErc6909).transferUnderlyingTo(
                vars.user, reserve.aTokenID, vars.amount, unwrap
            );
        }

        emit Borrow(
            vars.asset, vars.user, vars.onBehalfOf, vars.amount, reserve.currentVariableBorrowRate
        );
    }

    /**
     * @dev Converts an amount to its ETH equivalent.
     * @param asset The asset address.
     * @param amount The amount to convert.
     * @param decimals The decimals of the asset.
     * @param oracle The price oracle address.
     * @return The amount in ETH.
     */
    function amountInETH(address asset, uint256 amount, uint256 decimals, address oracle)
        internal
        view
        returns (uint256)
    {
        return IOracle(oracle).getAssetPrice(asset) * amount / (10 ** decimals);
    }

    /**
     * @dev Parameters for repaying a borrowed position.
     */
    struct RepayParams {
        address asset;
        uint256 amount;
        address onBehalfOf;
        IMiniPoolAddressesProvider addressesProvider;
        uint256 minAmount;
    }

    /**
     * @dev Emitted on repayment.
     * @param reserve The address of the reserve being repaid.
     * @param user The user whose debt is being repaid.
     * @param repayer The address making the repayment.
     * @param amount The amount being repaid.
     */
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount
    );

    /**
     * @dev Handles the repayment of a borrowed position.
     * @param params The repayment parameters.
     * @param wrap Whether to wrap the underlying asset.
     * @param _reserves Mapping of reserve data.
     * @param _usersConfig Mapping of user configurations.
     * @return The amount repaid.
     */
    function repay(
        RepayParams memory params,
        bool wrap,
        mapping(address => DataTypes.MiniPoolReserveData) storage _reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig
    ) external returns (uint256) {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[params.asset];

        (uint256 variableDebt) = Helpers.getUserCurrentDebt(params.onBehalfOf, reserve);

        MiniPoolValidationLogic.validateRepay(
            reserve, params.amount, params.onBehalfOf, variableDebt, params.minAmount
        );

        uint256 paybackAmount = variableDebt;

        if (params.amount < paybackAmount) {
            paybackAmount = params.amount;
        }

        reserve.updateState();

        IAERC6909(reserve.aErc6909).burn(
            params.onBehalfOf,
            address(0), // we dont care about the burn receiver for debtTokens
            reserve.variableDebtTokenID,
            paybackAmount,
            false,
            reserve.variableBorrowIndex
        );

        address aToken = reserve.aErc6909;
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
