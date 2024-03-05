// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {UserConfiguration} from '../../libraries/configuration/UserConfiguration.sol';
import {ReserveConfiguration} from '../../libraries/configuration/ReserveConfiguration.sol';
import {ReserveLogic} from '../../libraries/logic/ReserveLogic.sol';
import {ILendingPoolAddressesProvider} from '../../../interfaces/ILendingPoolAddressesProvider.sol';
import {ILendingPool} from '../../../interfaces/ILendingPool.sol';
import {DataTypes} from '../../libraries/types/DataTypes.sol';
import {IAERC6909} from '../../../interfaces/IAERC6909.sol';
contract MiniPoolStorage {
  using ReserveLogic for DataTypes.ReserveData;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using UserConfiguration for DataTypes.UserConfigurationMap;

  ILendingPoolAddressesProvider internal _addressesProvider;
  ILendingPool internal _pool;
  IAERC6909 internal _marketToken;
  uint256 internal _minipoolId;
  address internal _interestCollector;


  mapping(address => mapping(bool => DataTypes.ReserveData)) internal _reserves;
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
