// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IERC20} from "../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {IERC6909} from "../../../interfaces/IERC6909.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title Helpers library
 * @author Aave
 */
library Helpers {
    /**
     * @dev Fetches the user current variable debt balances
     * @param user The user address
     * @param reserve The reserve data object
     * @return The variable debt balance
     *
     */
    function getUserCurrentDebt(address user, DataTypes.ReserveData storage reserve)
        internal
        view
        returns (uint256)
    {
        return (IERC20(reserve.variableDebtTokenAddress).balanceOf(user));
    }

    function getUserCurrentDebtMemory(address user, DataTypes.ReserveData memory reserve)
        internal
        view
        returns (uint256)
    {
        return (IERC20(reserve.variableDebtTokenAddress).balanceOf(user));
    }

    function getUserCurrentDebt(address user, DataTypes.MiniPoolReserveData storage reserve)
        internal
        view
        returns (uint256)
    {
        return (IERC6909(reserve.aTokenAddress).balanceOf(user, reserve.variableDebtTokenID));
    }

    function getUserCurrentDebtMemory(address user, DataTypes.MiniPoolReserveData memory reserve)
        internal
        view
        returns (uint256)
    {
        return (IERC6909(reserve.aTokenAddress).balanceOf(user, reserve.variableDebtTokenID));
    }
}
