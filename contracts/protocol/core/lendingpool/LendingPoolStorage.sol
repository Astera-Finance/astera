// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {
    ILendingPoolAddressesProvider
} from "../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {
    EnumerableSet
} from "../../../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title LendingPoolStorage
 * @author Conclave
 * @dev Contract containing storage variables for the LendingPool contract.
 */
contract LendingPoolStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev The addresses provider contract reference.
    ILendingPoolAddressesProvider internal _addressesProvider;

    /**
     * @dev Mapping of reserves data, keyed by asset address and reserve type.
     * The bool indicates if the reserve is boosted by a vault (`true`) or not (`false`).
     */
    mapping(address => mapping(bool => DataTypes.ReserveData)) internal _reserves;

    /// @dev Mapping of user configuration data, keyed by user address.
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

    /**
     * @dev Mapping of reserve references by index for gas optimization.
     * Used to track the list of all reserves in the protocol.
     */
    mapping(uint256 => DataTypes.ReserveReference) internal _reservesList;

    /// @dev Mapping of asset addresses to minipool addresses that are borrowing from them.
    /// No need to track the `reserveType` because flow borrowing only support for the `true` reserve type.
    mapping(address => EnumerableSet.AddressSet) internal _assetToMinipoolFlowBorrowing;

    /// @dev Counter for the number of initialized reserves.
    uint256 internal _reservesCount;

    /// @dev Flag for pausing/unpausing protocol actions.
    bool internal _paused;

    /// @dev Total premium for flash loans, expressed in basis points.
    uint128 internal _flashLoanPremiumTotal;

    /// @dev Maximum number of reserves that can be initialized.
    uint256 internal _maxNumberOfReserves;
}
