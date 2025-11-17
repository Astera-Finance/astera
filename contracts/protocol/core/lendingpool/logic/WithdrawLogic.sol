// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {
    ILendingPoolAddressesProvider
} from "../../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {
    SafeERC20
} from "../../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IAToken} from "../../../../../contracts/interfaces/IAToken.sol";
import {
    ReserveConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {WadRayMath} from "../../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "../../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {
    UserConfiguration
} from "../../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {
    EnumerableSet
} from "../../../../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Withdraw Logic library
 * @notice Implements the logic to withdraw assets from the protocol.
 * @author Conclave
 * @dev Contains core functions for managing withdrawals and transfers.
 */
library WithdrawLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Emitted when a reserve is disabled as collateral for a user.
     * @param reserve The address of the reserve.
     * @param user The address of the user.
     */
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted when a withdrawal occurs.
     * @param reserve The address of the reserve.
     * @param user The address of the user initiating the withdrawal.
     * @param to The address receiving the withdrawn assets.
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
     * @param reserveType The type of the reserve.
     * @param amount The amount to withdraw.
     * @param to The address that will receive the withdrawal.
     * @param reservesCount The total count of reserves.
     */
    struct withdrawParams {
        address asset;
        bool reserveType;
        uint256 amount;
        address to;
        uint256 reservesCount;
    }

    /**
     * @dev Struct for local variables used in withdraw operations.
     * @param userBalance The current balance of the user.
     * @param amountToWithdraw The final amount to be withdrawn.
     * @param aToken The address of the aToken contract.
     */
    struct withdrawLocalVars {
        uint256 userBalance;
        uint256 amountToWithdraw;
        address aToken;
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve.
     * @param params The parameters for the withdrawal.
     * @param reserves The state of all reserves.
     * @param usersConfig The users configuration mapping.
     * @param reservesList The addresses of all the active reserves.
     * @param addressesProvider The addresses provider instance.
     * @return The final amount withdrawn.
     */
    function withdraw(
        withdrawParams memory params,
        EnumerableSet.AddressSet storage minipoolFlowBorrowing,
        mapping(
            address => mapping(bool => DataTypes.ReserveData)
        ) storage reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(
            uint256 => DataTypes.ReserveReference
        ) storage reservesList,
        ILendingPoolAddressesProvider addressesProvider
    ) internal returns (uint256) {
        DataTypes.ReserveData storage reserve = reserves[params.asset][params.reserveType];
        withdrawLocalVars memory localVars;

        {
            localVars.aToken = reserve.aTokenAddress;

            localVars.userBalance = IAToken(localVars.aToken).balanceOf(msg.sender);

            localVars.amountToWithdraw = params.amount;

            if (params.amount == type(uint256).max) {
                localVars.amountToWithdraw = localVars.userBalance;
            }
        }
        ValidationLogic.validateWithdraw(
            ValidationLogic.ValidateWithdrawParams(
                params.asset,
                params.reserveType,
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

        reserve.updateInterestRates(
            minipoolFlowBorrowing, params.asset, localVars.aToken, 0, localVars.amountToWithdraw
        );

        if (localVars.amountToWithdraw == localVars.userBalance) {
            usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
            emit ReserveUsedAsCollateralDisabled(params.asset, msg.sender);
        }

        IAToken(localVars.aToken)
            .burn(msg.sender, params.to, localVars.amountToWithdraw, reserve.liquidityIndex);

        emit Withdraw(params.asset, msg.sender, params.to, localVars.amountToWithdraw);

        return localVars.amountToWithdraw;
    }

    /**
     * @dev Struct containing parameters for finalizing transfers.
     * @param asset The address of the underlying asset.
     * @param reserveType The type of the reserve.
     * @param from The address of the source.
     * @param to The address of the destination.
     * @param amount The amount being transferred.
     * @param balanceFromBefore The balance of the source before the transfer.
     * @param balanceToBefore The balance of the destination before the transfer.
     * @param reservesCount The total count of reserves.
     */
    struct finalizeTransferParams {
        address asset;
        bool reserveType;
        address from;
        address to;
        uint256 amount;
        uint256 balanceFromBefore;
        uint256 balanceToBefore;
        uint256 reservesCount;
    }

    /**
     * @dev Finalizes an aToken transfer.
     * @param params The parameters for the finalization.
     * @param reserves The state of all reserves.
     * @param usersConfig The users configuration mapping.
     * @param reservesList The addresses of all the active reserves.
     * @param addressesProvider The addresses provider instance.
     */
    function finalizeTransfer(
        finalizeTransferParams memory params,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        ILendingPoolAddressesProvider addressesProvider
    ) internal {
        require(
            msg.sender == reserves[params.asset][params.reserveType].aTokenAddress,
            Errors.LP_CALLER_MUST_BE_AN_ATOKEN
        );

        ValidationLogic.validateTransfer(
            params.from,
            reserves,
            usersConfig[params.from],
            reservesList,
            params.reservesCount,
            addressesProvider.getPriceOracle()
        );

        uint256 reserveId = reserves[params.asset][params.reserveType].id;

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
}
