// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {ILendingPool} from "../../../contracts/interfaces/ILendingPool.sol";
import {IRewarder} from "../../../contracts/interfaces/IRewarder.sol";

/**
 * @title IInitializableAToken interface.
 * @author Cod3x
 */
interface IInitializableAToken {
    /**
     * @dev Emitted when an aToken is initialized
     * @param underlyingAsset The address of the underlying asset
     * @param pool The address of the associated lending pool
     * @param treasury The address of the treasury
     * @param rewarder The address of the incentives controller for this aToken
     * @param aTokenDecimals the decimals of the underlying
     * @param reserveType Whether the reserve is boosted by a vault
     * @param aTokenName the name of the aToken
     * @param aTokenSymbol the symbol of the aToken
     * @param params A set of encoded parameters for additional initialization
     *
     */
    event Initialized(
        address indexed underlyingAsset,
        address indexed pool,
        address treasury,
        address rewarder,
        uint8 aTokenDecimals,
        bool reserveType,
        string aTokenName,
        string aTokenSymbol,
        bytes params
    );

    function initialize(
        ILendingPool pool,
        address treasury,
        address underlyingAsset,
        IRewarder rewarder,
        uint8 aTokenDecimals,
        bool reserveType,
        string calldata aTokenName,
        string calldata aTokenSymbol,
        bytes calldata params
    ) external;
}
