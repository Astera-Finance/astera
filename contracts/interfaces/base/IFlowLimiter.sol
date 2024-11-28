// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IMiniPool} from "../../../contracts/interfaces/IMiniPool.sol";

/**
 * @title IFlowLimiter interface.
 * @author Cod3x
 */
interface IFlowLimiter {
    /**
     * @dev Emitted when the flow limit for a miniPool is updated
     * @param asset The address of the underlying asset
     * @param miniPool The address of the miniPool
     * @param limit The new flow limit amount
     */
    event FlowLimitUpdated(address indexed asset, address indexed miniPool, uint256 limit);

    function setFlowLimit(address asset, address miniPool, uint256 limit) external;

    function getFlowLimit(address asset, address miniPool) external view returns (uint256);

    function currentFlow(address asset, address miniPool) external view returns (uint256);
}
