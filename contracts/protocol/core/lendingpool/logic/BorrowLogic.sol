// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IOracle} from "../../../../../contracts/interfaces/IOracle.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../../../../contracts/interfaces/IVariableDebtToken.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {ReserveConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {Helpers} from "../../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {IFlowLimiter} from "../../../../../contracts/interfaces/base/IFlowLimiter.sol";
import {EnumerableSet} from
    "../../../../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title BorrowLogic library
 * @author Cod3x
 * @notice Implements functions to validate and execute borrowing-related actions in the protocol.
 * @dev Contains core borrowing logic including user account data calculation, borrow execution and repayment handling.
 */
library BorrowLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using ValidationLogic for ValidationLogic.ValidateBorrowParams;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Emitted when a borrow occurs.
     * @param reserve The address of the borrowed underlying asset.
     * @param user The address initiating the borrow.
     * @param onBehalfOf The address receiving the borrowed assets.
     * @param amount The amount of assets borrowed.
     * @param borrowRate The current borrow rate.
     */
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );

    /// @dev Struct containing local variables for calculating user account data.
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
        bool currentReserveType;
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
     * @param reservesList Mapping of reserve references.
     * @return totalCollateralETH Total collateral in ETH.
     * @return totalDebtETH Total debt in ETH.
     * @return avgLtv Average loan to value.
     * @return avgLiquidationThreshold Average liquidation threshold.
     * @return healthFactor The user's health factor.
     */
    function calculateUserAccountDataVolatile(
        CalculateUserAccountDataVolatileParams memory params,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList
    ) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return GenericLogic.calculateUserAccountData(
            params.user, reserves, userConfig, reservesList, params.reservesCount, params.oracle
        );
    }

    /**
     * @dev Parameters for executing a borrow operation.
     * @param asset The address of the underlying asset.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param user The address initiating the borrow.
     * @param onBehalfOf The address receiving the borrowed assets.
     * @param amount The amount to borrow.
     * @param aTokenAddress The address of the aToken contract.
     * @param releaseUnderlying Whether to release the underlying asset.
     * @param addressesProvider The addresses provider instance.
     * @param reservesCount Total number of initialized reserves.
     */
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

    /**
     * @dev Executes a borrow operation.
     * @param vars The borrow parameters.
     * @param reserves Mapping of reserve data.
     * @param reservesList Mapping of reserve references.
     * @param usersConfig Mapping of user configurations.
     */
    function executeBorrow(
        ExecuteBorrowParams memory vars,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig
    ) internal {
        DataTypes.ReserveData storage reserve = reserves[vars.asset][vars.reserveType];
        require(reserve.configuration.getActive(), Errors.VL_NO_ACTIVE_RESERVE);

        DataTypes.UserConfigurationMap storage userConfig = usersConfig[vars.onBehalfOf];

        ValidationLogic.ValidateBorrowParams memory validateBorrowParams;

        address oracle = vars.addressesProvider.getPriceOracle();

        validateBorrowParams.userAddress = vars.onBehalfOf;
        validateBorrowParams.amount = vars.amount;
        validateBorrowParams.amountInETH =
            amountInETH(vars.asset, vars.amount, reserve.configuration.getDecimals(), oracle);
        validateBorrowParams.reservesCount = vars.reservesCount;
        validateBorrowParams.oracle = oracle;
        ValidationLogic.validateBorrow(
            validateBorrowParams, reserve, reserves, userConfig, reservesList
        );

        reserve.updateState();

        {
            bool isFirstBorrowing = false;

            isFirstBorrowing = IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
                vars.user, vars.onBehalfOf, vars.amount, reserve.variableBorrowIndex
            );

            if (isFirstBorrowing) {
                userConfig.setBorrowing(reserve.id, true);
            }
        }

        reserve.updateInterestRates(
            minipoolFlowBorrowing,
            vars.asset,
            vars.aTokenAddress,
            0,
            vars.releaseUnderlying ? vars.amount : 0
        );

        if (vars.releaseUnderlying) {
            IAToken(vars.aTokenAddress).transferUnderlyingTo(vars.user, vars.amount);
        }

        emit Borrow(
            vars.asset, vars.user, vars.onBehalfOf, vars.amount, reserve.currentVariableBorrowRate
        );
    }

    /**
     * @dev Parameters for executing a mini pool borrow operation.
     * @param asset The address of the underlying asset.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The amount to borrow.
     * @param miniPoolAddress The address of the mini pool.
     * @param aTokenAddress The address of the aToken contract.
     * @param addressesProvider The addresses provider instance.
     * @param reservesCount Total number of initialized reserves.
     */
    struct ExecuteMiniPoolBorrowParams {
        address asset;
        bool reserveType;
        uint256 amount;
        address miniPoolAddress;
        address aTokenAddress;
        ILendingPoolAddressesProvider addressesProvider;
        uint256 reservesCount;
    }

    /**
     * @dev Executes a mini pool borrow operation.
     * @param params The mini pool borrow parameters.
     * @param reserves Mapping of reserve data.
     */
    function executeMiniPoolBorrow(
        ExecuteMiniPoolBorrowParams memory params,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves
    ) internal {
        IFlowLimiter flowLimiter = IFlowLimiter(params.addressesProvider.getFlowLimiter());
        DataTypes.ReserveData storage reserve = reserves[params.asset][params.reserveType];

        require(reserve.configuration.getActive(), Errors.VL_NO_ACTIVE_RESERVE);
        require(reserve.configuration.getBorrowingEnabled(), Errors.VL_BORROWING_NOT_ENABLED);

        flowLimiter.revertIfFlowLimitReached(params.asset, params.miniPoolAddress, params.amount);

        reserve.updateState();

        // Note: This mint operation does not update the user configuration to reflect the borrowed asset for the miniPoolAddress.
        // This means that when querying the user configuration for the miniPoolAddress, no assets will be shown as borrowed.
        // This design choice ensures that the health factor check will always pass for unbacked borrows by mini pools in the system.
        IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
            params.miniPoolAddress,
            params.miniPoolAddress,
            params.amount,
            reserve.variableBorrowIndex
        );

        reserve.updateInterestRates(
            minipoolFlowBorrowing, params.asset, params.aTokenAddress, 0, params.amount
        );

        IAToken(params.aTokenAddress).transferUnderlyingTo(params.miniPoolAddress, params.amount);

        emit Borrow(
            params.asset,
            params.miniPoolAddress,
            params.miniPoolAddress,
            params.amount,
            reserve.currentVariableBorrowRate
        );
    }

    /**
     * @dev Calculates the amount in ETH for a given asset amount.
     * @param asset The address of the asset.
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
     * @dev Parameters for repaying a borrow.
     * @param asset The address of the borrowed asset.
     * @param reserveType Whether the reserve is boosted by a vault.
     * @param amount The amount to repay.
     * @param onBehalfOf The address of the user who will get their debt reduced.
     * @param addressesProvider The addresses provider instance.
     */
    struct RepayParams {
        address asset;
        bool reserveType;
        uint256 amount;
        address onBehalfOf;
        ILendingPoolAddressesProvider addressesProvider;
    }

    /**
     * @dev Emitted when a repayment occurs.
     * @param reserve The address of the reserve.
     * @param user The address of the user who got their debt reduced/removed.
     * @param repayer The address of the repayer.
     * @param amount The amount repaid.
     */
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount
    );

    /**
     * @dev Handles the repayment of a borrow.
     * @param params The repay parameters.
     * @param _reserves Mapping of reserve data.
     * @param _usersConfig Mapping of user configurations.
     * @return The actual amount repaid.
     */
    function repay(
        RepayParams memory params,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage _reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig
    ) internal returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[params.asset][params.reserveType];

        (address aToken, uint256 paybackAmount) =
            _repay(params, minipoolFlowBorrowing, reserve, _usersConfig);

        IERC20(params.asset).safeTransferFrom(msg.sender, aToken, paybackAmount);

        IAToken(aToken).handleRepayment(msg.sender, params.onBehalfOf, paybackAmount);

        emit Repay(params.asset, params.onBehalfOf, msg.sender, paybackAmount);

        return paybackAmount;
    }

    /**
     * @dev Handles the repayment of a borrow using aTokens.
     * @param params The repay parameters.
     * @param _reserves Mapping of reserve data.
     * @param _usersConfig Mapping of user configurations.
     * @return The actual amount repaid.
     */
    function repayWithAtokens(
        RepayParams memory params,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage _reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig
    ) internal returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[params.asset][params.reserveType];

        (address aToken, uint256 paybackAmount) =
            _repay(params, minipoolFlowBorrowing, reserve, _usersConfig);

        IAToken(aToken).burn(params.onBehalfOf, aToken, paybackAmount, reserve.liquidityIndex);

        IAToken(aToken).handleRepayment(msg.sender, params.onBehalfOf, paybackAmount);

        emit Repay(params.asset, params.onBehalfOf, msg.sender, paybackAmount);

        return paybackAmount;
    }

    /**
     * @dev Helper function to handle repayment logic.
     * @param params The repay parameters.
     * @param reserve The reserve data.
     * @param _usersConfig Mapping of user configurations.
     * @return aToken The address of the aToken.
     * @return paybackAmount The actual amount repaid.
     */
    function _repay(
        RepayParams memory params,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        DataTypes.ReserveData storage reserve,
        mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig
    ) private returns (address aToken, uint256 paybackAmount) {
        (uint256 variableDebt) = Helpers.getUserCurrentDebt(params.onBehalfOf, reserve);

        ValidationLogic.validateRepay(reserve, params.amount, params.onBehalfOf, variableDebt);

        paybackAmount = variableDebt;

        if (params.amount < paybackAmount) {
            paybackAmount = params.amount;
        }

        reserve.updateState();

        IVariableDebtToken(reserve.variableDebtTokenAddress).burn(
            params.onBehalfOf, paybackAmount, reserve.variableBorrowIndex
        );

        aToken = reserve.aTokenAddress;
        reserve.updateInterestRates(minipoolFlowBorrowing, params.asset, aToken, paybackAmount, 0);

        if (variableDebt - paybackAmount == 0) {
            _usersConfig[params.onBehalfOf].setBorrowing(reserve.id, false);
        }
    }
}
