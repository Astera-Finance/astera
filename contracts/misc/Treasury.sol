// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {Ownable} from "contracts/dependencies/openzeppelin/contracts/Ownable.sol";

contract Treasury is Ownable {
    ILendingPoolAddressesProvider public ADDRESSES_PROVIDER;
    ILendingPool public LENDING_POOL;
    address private currentTreasury = address(this);
    address private multisig;

    modifier onlyPoolAdmin() {
        require(ADDRESSES_PROVIDER.getPoolAdmin() == _msgSender(), Errors.CALLER_NOT_POOL_ADMIN);
        _;
    }

    constructor(ILendingPoolAddressesProvider provider) Ownable(msg.sender) {
        ADDRESSES_PROVIDER = provider;
        LENDING_POOL = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
        multisig = _msgSender();
    }

    function withdrawAllReserves() external returns (bool) {
        address[] memory _activeReserves = new address[](LENDING_POOL.getReservesCount());
        bool[] memory _activeReservesTypes = new bool[](LENDING_POOL.getReservesCount());
        (_activeReserves, _activeReservesTypes) = LENDING_POOL.getReservesList();
        withdrawReserves(_activeReserves, _activeReservesTypes);
        return true;
    }

    function withdrawReserves(address[] memory assets, bool[] memory reservesTypes)
        public
        returns (bool)
    {
        for (uint256 i = 0; i < assets.length; i++) {
            DataTypes.ReserveData memory reserveData =
                LENDING_POOL.getReserveData(assets[i], reservesTypes[i]);
            uint256 balance = IAToken(reserveData.aTokenAddress).balanceOf(address(this));
            if (balance != 0) {
                LENDING_POOL.withdraw(assets[i], reservesTypes[i], balance, currentTreasury);
            }
        }
        return true;
    }

    function transferToMultisig(address asset, uint256 value) external onlyOwner {
        IERC20(asset).transfer(multisig, value);
    }

    function setTreasury(address newTreasury) external onlyPoolAdmin {
        currentTreasury = newTreasury;
    }

    function setMultisig(address newMultisig) external onlyOwner {
        multisig = newMultisig;
    }
}
