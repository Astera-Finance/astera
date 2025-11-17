// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IAERC6909} from "../../../../../contracts/interfaces/IAERC6909.sol";
import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {
    IMiniPoolAddressesProvider
} from "../../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {
    ReserveConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {
    UserConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {MiniPoolValidationLogic} from "./MiniPoolValidationLogic.sol";

/**
 * @title MiniPool Withdraw Logic Library
 * @notice Implements the logic to withdraw assets from the protocol.
 * @author Conclave
 */
library MiniPoolWithdrawLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /**
     * @dev Emitted when a reserve is disabled as collateral for a user.
     * @param reserve The address of the reserve.
     * @param user The address of the user.
     */
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted on withdrawals.
     * @param reserve The address of the reserve.
     * @param user The address initiating the withdrawal.
     * @param to The address receiving the withdrawal.
     * @param amount The amount being withdrawn.
     */
    event Withdraw(
        address indexed reserve, address indexed user, address indexed to, uint256 amount
    );

    /**
     * @dev Emitted when a reserve is enabled as collateral for a user.
     * @param reserve The address of the reserve.
     * @param user The address of the user.
     */
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    /**
     * @dev Struct containing parameters for withdraw operations.
     * @param asset The address of the underlying asset.
     * @param amount The amount to withdraw.
     * @param to The address that will receive the withdrawal.
     * @param reservesCount The total count of reserves.
     */
    struct withdrawParams {
        address asset;
        uint256 amount;
        address to;
        uint256 reservesCount;
    }

    /**
     * @dev Struct containing local variables for withdraw operations.
     * @param userBalance The user's current balance.
     * @param amountToWithdraw The amount being withdrawn.
     * @param aToken The address of the aToken.
     * @param id The ID of the aToken.
     */
    struct withdrawLocalVars {
        uint256 userBalance;
        uint256 amountToWithdraw;
        address aToken;
        uint256 id;
    }

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve.
     * @param params The withdraw parameters.
     * @param unwrap Whether to unwrap the token during withdrawal.
     * @param reserves The state of all reserves.
     * @param usersConfig The users configuration mapping.
     * @param reservesList The addresses of all active reserves.
     * @param addressesProvider The addresses provider instance.
     * @return The final amount withdrawn.
     */
    function withdraw(
        withdrawParams memory params,
        bool unwrap,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => address) storage reservesList,
        IMiniPoolAddressesProvider addressesProvider
    ) external returns (uint256) {
        DataTypes.MiniPoolReserveData storage reserve = reserves[params.asset];
        withdrawLocalVars memory localVars;

        {
            localVars.aToken = reserve.aErc6909;
            localVars.id = reserve.aTokenID;

            localVars.userBalance = IAERC6909(localVars.aToken).balanceOf(msg.sender, localVars.id);

            localVars.amountToWithdraw = params.amount;

            if (params.amount == type(uint256).max) {
                localVars.amountToWithdraw = localVars.userBalance;
            }
        }
        MiniPoolValidationLogic.validateWithdraw(
            MiniPoolValidationLogic.ValidateWithdrawParams(
                params.asset,
                localVars.amountToWithdraw,
                localVars.userBalance,
                params.reservesCount,
                addressesProvider.getPriceOracle()
            ),
            reserves,
            usersConfig[msg.sender],
            reservesList
        );

        reserve.updateState();

        reserve.updateInterestRates(params.asset, 0, localVars.amountToWithdraw);

        if (localVars.amountToWithdraw == localVars.userBalance) {
            usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
            emit ReserveUsedAsCollateralDisabled(params.asset, msg.sender);
        }

        IAERC6909(localVars.aToken)
            .burn(
                msg.sender,
                params.to,
                localVars.id,
                localVars.amountToWithdraw,
                unwrap,
                reserve.liquidityIndex
            );

        emit Withdraw(params.asset, msg.sender, params.to, localVars.amountToWithdraw);

        return localVars.amountToWithdraw;
    }

    /**
     * @dev Struct containing parameters for finalizing transfers.
     * @param asset The address of the underlying asset.
     * @param from The address of the source.
     * @param to The address of the destination.
     * @param amount The amount being transferred.
     * @param balanceFromBefore The balance of the source before the transfer.
     * @param balanceToBefore The balance of the destination before the transfer.
     * @param reservesCount The total count of reserves.
     */
    struct finalizeTransferParams {
        address asset;
        address from;
        address to;
        uint256 amount;
        uint256 balanceFromBefore;
        uint256 balanceToBefore;
        uint256 reservesCount;
    }

    /**
     * @notice Finalizes an aToken transfer.
     * @param params The parameters for the finalization.
     * @param reserves The state of all reserves.
     * @param usersConfig The users configuration mapping.
     * @param reservesList The addresses of all active reserves.
     * @param addressesProvider The addresses provider instance.
     */
    function finalizeTransfer(
        finalizeTransferParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => address) storage reservesList,
        IMiniPoolAddressesProvider addressesProvider
    ) internal {
        require(msg.sender == reserves[params.asset].aErc6909, Errors.LP_CALLER_MUST_BE_AN_ATOKEN);

        MiniPoolValidationLogic.validateTransfer(
            params.from,
            reserves,
            usersConfig[params.from],
            reservesList,
            params.reservesCount,
            addressesProvider.getPriceOracle()
        );

        uint256 reserveId = reserves[params.asset].id;

        if (params.from != params.to) {
            if (params.balanceFromBefore - params.amount == 0) {
                DataTypes.UserConfigurationMap storage fromConfig = usersConfig[params.from];
                fromConfig.setUsingAsCollateral(reserveId, false);
                emit ReserveUsedAsCollateralDisabled(params.asset, params.from);
            }

            if (params.balanceToBefore == 0 && params.amount != 0) {
                DataTypes.UserConfigurationMap storage toConfig = usersConfig[params.to];
                toConfig.setUsingAsCollateral(reserveId, true);
                emit ReserveUsedAsCollateralEnabled(params.asset, params.to);
            }
        }
    }

    /**
     * @notice Internal function to withdraw an `amount` of underlying asset from the reserve.
     * @param params The withdraw parameters.
     * @param reserves The state of all reserves.
     * @param usersConfig The users configuration mapping.
     * @param reservesList The addresses of all active reserves.
     * @param addressesProvider The addresses provider instance.
     */
    function internalWithdraw(
        withdrawParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => address) storage reservesList,
        IMiniPoolAddressesProvider addressesProvider
    ) internal {
        DataTypes.MiniPoolReserveData storage reserve = reserves[params.asset];
        withdrawLocalVars memory localVars;

        {
            localVars.aToken = reserve.aErc6909;
            localVars.id = reserve.aTokenID;

            localVars.userBalance =
                IAERC6909(localVars.aToken).balanceOf(address(this), localVars.id);

            localVars.amountToWithdraw = params.amount;

            if (params.amount == type(uint256).max) {
                localVars.amountToWithdraw = localVars.userBalance;
            }
            uint256 availableLiquidity = IERC20(params.asset).balanceOf(localVars.aToken);
            if (localVars.amountToWithdraw > availableLiquidity) {
                localVars.amountToWithdraw = availableLiquidity;
            }
        }
        MiniPoolValidationLogic.validateWithdraw(
            MiniPoolValidationLogic.ValidateWithdrawParams(
                params.asset,
                localVars.amountToWithdraw,
                localVars.userBalance,
                params.reservesCount,
                addressesProvider.getPriceOracle()
            ),
            reserves,
            usersConfig[address(this)],
            reservesList
        );
        reserve.updateState();

        reserve.updateInterestRates(params.asset, 0, localVars.amountToWithdraw);

        IAERC6909(localVars.aToken)
            .burn(
                address(this),
                params.to,
                localVars.id,
                localVars.amountToWithdraw,
                false,
                reserve.liquidityIndex
            );

        emit Withdraw(params.asset, address(this), params.to, localVars.amountToWithdraw);
    }
}
