// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

/**
 * @title IOracle interface
 * @notice Interface for the oracle.
 **/

interface IOracle {
  function BASE_CURRENCY() external view returns (address); // if usd returns 0x0, if eth returns weth address
  function BASE_CURRENCY_UNIT() external view returns (uint256);

  /***********
    @dev returns the asset price in ETH
     */
  function getAssetPrice(address asset) external view returns (uint256);
}