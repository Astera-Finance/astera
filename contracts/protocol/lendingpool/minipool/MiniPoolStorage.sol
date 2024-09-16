// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {UserConfiguration} from "contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ReserveLogic} from "contracts/protocol/libraries/logic/ReserveLogic.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";

contract MiniPoolStorage {
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    IMiniPoolAddressesProvider internal _addressesProvider;
    ILendingPool internal _pool;
    uint256 internal _minipoolId;

    mapping(address => DataTypes.MiniPoolReserveData) internal _reserves;
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;
    mapping(address => DataTypes.UserRecentBorrowMap) internal _usersRecentBorrow;

    // the list of the available reserves, structured as a mapping for gas savings reasons
    mapping(uint256 => DataTypes.ReserveReference) internal _reservesList;

    //      userAddr -> loanID -> LoanInfo
    mapping(address => mapping(uint256 => DataTypes.LoanInfo)) internal _userLoanInfo;
    //      userAddr -> numLoanIds (max uint8)
    mapping(address => uint8) internal _userLoanInfoCount;

    uint256 internal _reservesCount;

    bool internal _paused;

    uint256 internal _flashLoanPremiumTotal;

    uint256 internal _maxNumberOfReserves;

    uint256 internal _lendingUpdateTimestamp; // track the last update made to the protocol parameters relative to borrowing
}
