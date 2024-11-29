// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IWETHGateway interface.
 * @author Cod3x
 */
interface IWETHGateway {
    function depositETH(address lendingPool, bool reserveType, address onBehalfOf)
        external
        payable;

    function withdrawETH(address lendingPool, bool reserveType, uint256 amount, address onBehalfOf)
        external;

    function repayETH(address lendingPool, bool reserveType, uint256 amount, address onBehalfOf)
        external
        payable;

    function borrowETH(address lendingPool, bool reserveType, uint256 amount) external;
}
