// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {UserConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ReserveConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ReserveLogic} from "../../../../contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title MiniPoolStorage
 * @author Cod3x
 */
contract MiniPoolStorage {
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    IMiniPoolAddressesProvider internal _addressesProvider;
    ILendingPool internal _pool;
    uint256 internal _minipoolId;

    mapping(address => DataTypes.MiniPoolReserveData) internal _reserves;
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

    // the list of the available reserves, structured as a mapping for gas savings reasons
    mapping(uint256 => address) internal _reservesList;

    uint256 internal _reservesCount;

    bool internal _paused;

    uint256 internal _flashLoanPremiumTotal;

    uint256 internal _maxNumberOfReserves;
}
