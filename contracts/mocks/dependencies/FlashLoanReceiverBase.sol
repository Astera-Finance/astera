// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IERC20} from "../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IFlashLoanReceiver} from "../../../contracts/interfaces/IFlashLoanReceiver.sol";
import {ILendingPoolAddressesProvider} from
    "../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IMiniPoolAddressesProvider} from
    "../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {ILendingPool} from "../../../contracts/interfaces/ILendingPool.sol";
import {IMiniPool} from "../../../contracts/interfaces/IMiniPool.sol";

abstract contract FlashLoanReceiverBase is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    ILendingPoolAddressesProvider public immutable override LENDING_POOL_ADDRESSES_PROVIDER;
    IMiniPoolAddressesProvider public immutable override MINI_POOL_ADDRESSES_PROVIDER;
    ILendingPool public immutable override LENDING_POOL;

    constructor(ILendingPoolAddressesProvider provider) {
        LENDING_POOL_ADDRESSES_PROVIDER = provider;
        LENDING_POOL = ILendingPool(provider.getLendingPool());
        MINI_POOL_ADDRESSES_PROVIDER =
            IMiniPoolAddressesProvider(provider.getMiniPoolAddressesProvider());
    }
}
