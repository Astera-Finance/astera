// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IERC6909} from "../../../../contracts/interfaces/base/IERC6909.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title Helpers library
 * @author Conclave
 * @notice Library containing helper functions for fetching user debt balances.
 */
library Helpers {
    /**
     * @dev Fetches the user current variable debt balance from a standard reserve.
     * @param user The address of the user to check debt for.
     * @param reserve The `ReserveData` storage object containing reserve information.
     * @return The current variable debt balance of the user.
     */
    function getUserCurrentDebt(address user, DataTypes.ReserveData storage reserve)
        internal
        view
        returns (uint256)
    {
        return (IERC20(reserve.variableDebtTokenAddress).balanceOf(user));
    }

    /**
     * @dev Fetches the user current variable debt balance from a standard reserve using memory data.
     * @param user The address of the user to check debt for.
     * @param reserve The `ReserveData` memory object containing reserve information.
     * @return The current variable debt balance of the user.
     */
    function getUserCurrentDebtMemory(address user, DataTypes.ReserveData memory reserve)
        internal
        view
        returns (uint256)
    {
        return (IERC20(reserve.variableDebtTokenAddress).balanceOf(user));
    }

    /**
     * @dev Fetches the user current variable debt balance from a minipool reserve.
     * @param user The address of the user to check debt for.
     * @param reserve The `MiniPoolReserveData` storage object containing minipool reserve information.
     * @return The current variable debt balance of the user.
     */
    function getUserCurrentDebt(address user, DataTypes.MiniPoolReserveData storage reserve)
        internal
        view
        returns (uint256)
    {
        return (IERC6909(reserve.aErc6909).balanceOf(user, reserve.variableDebtTokenID));
    }

    /**
     * @dev Fetches the user current variable debt balance from a minipool reserve using memory data.
     * @param user The address of the user to check debt for.
     * @param reserve The `MiniPoolReserveData` memory object containing minipool reserve information.
     * @return The current variable debt balance of the user.
     */
    function getUserCurrentDebtMemory(address user, DataTypes.MiniPoolReserveData memory reserve)
        internal
        view
        returns (uint256)
    {
        return (IERC6909(reserve.aErc6909).balanceOf(user, reserve.variableDebtTokenID));
    }
}
