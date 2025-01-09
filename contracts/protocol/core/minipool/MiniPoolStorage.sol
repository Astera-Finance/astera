// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title MiniPoolStorage
 * @notice Contract that stores the state and configuration for a MiniPool.
 * @dev Contains mappings and variables used across the MiniPool system.
 * @author Cod3x
 */
contract MiniPoolStorage {
    /// @dev The addresses provider contract managing this MiniPool's addresses.
    IMiniPoolAddressesProvider internal _addressesProvider;

    /// @dev Reference to the main lending pool contract.
    ILendingPool internal _pool;

    /// @dev Unique identifier for this MiniPool.
    uint256 internal _minipoolId;

    /// @dev Mapping of reserve data for each asset address.
    mapping(address => DataTypes.MiniPoolReserveData) internal _reserves;

    /// @dev Mapping of user configurations for each user address.
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

    /// @dev The list of the available reserves.
    mapping(uint256 => address) internal _reservesList;

    /// @dev Count of initialized reserves.
    uint256 internal _reservesCount;

    /// @dev Flag indicating if the MiniPool is paused.
    bool internal _paused;

    /// @dev Total premium percentage charged for flash loans.
    uint256 internal _flashLoanPremiumTotal;

    /// @dev Maximum number of reserves that can be initialized.
    uint256 internal _maxNumberOfReserves;
}
