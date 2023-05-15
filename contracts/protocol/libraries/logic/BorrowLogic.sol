// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {IStableDebtToken} from '../../../interfaces/IStableDebtToken.sol';
import {IVariableDebtToken} from '../../../interfaces/IVariableDebtToken.sol';
import {IAToken} from '../../../interfaces/IAToken.sol';
import {ILendingPool} from '../../interfaces/ILendingPool';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {UserConfiguration} from '../configuration/UserConfiguration.sol';
import {Errors} from '../helpers/Errors.sol';
import {Helpers} from '../helpers/Helpers.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {ValidationLogic} from './ValidationLogic.sol';
import {ReserveLogic} from './ReserveLogic.sol';

/**
 * @title BorrowLogic library
 * @author Granary
 * @notice Implements functions to validate actions related to borrowing
 */

 library BorrowLogic {
    using ReserveLogic for DataTypes.ReserveData;
    // TODO: Compile all the changes in this contract

    // Note: There are now isolatedReserves and regularReserves
    // Borrowing from an isolatedAsset means that the user's balance derived from isolatedReserves is what validates the borrow
    // Borrowing from a regularAsset means that the user's overall balance dervide from all reserves is what validates the borrow
    // Isolated Reserves are basically a subset of the reserves
    // More params can be added to the reserve config if we want to play around ltvs, liquidation thresholds...
    //
    // Thoughts: When borrowing (both regular and isolated), should we still look at the other 'type', to check that we are not breaking a threshold? Probably, right?
    // So, now matter which borrow is undergoing, we end up looking at all the data
 }