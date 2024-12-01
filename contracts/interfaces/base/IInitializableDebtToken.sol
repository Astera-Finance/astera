// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {ILendingPool} from "../../../contracts/interfaces/ILendingPool.sol";
import {IRewarder} from "../../../contracts/interfaces/IRewarder.sol";

/**
 * @title IInitializableDebtToken interface.
 * @author Cod3x
 */
interface IInitializableDebtToken {
    /**
     * @dev Emitted when a debt token is initialized
     * @param underlyingAsset The address of the underlying asset
     * @param pool The address of the associated lending pool
     * @param rewarder The address of the incentives controller for this aToken
     * @param debtTokenDecimals the decimals of the debt token
     * @param reserveType Whether the reserve is boosted by a vault
     * @param debtTokenName the name of the debt token
     * @param debtTokenSymbol the symbol of the debt token
     * @param params A set of encoded parameters for additional initialization
     *
     */
    event Initialized(
        address indexed underlyingAsset,
        address indexed pool,
        address rewarder,
        uint8 debtTokenDecimals,
        bool reserveType,
        string debtTokenName,
        string debtTokenSymbol,
        bytes params
    );

    function initialize(
        ILendingPool pool,
        address underlyingAsset,
        IRewarder rewarder,
        uint8 debtTokenDecimals,
        bool reserveType,
        string memory debtTokenName,
        string memory debtTokenSymbol,
        bytes calldata params
    ) external;
}
