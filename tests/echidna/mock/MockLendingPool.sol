// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/logic/BorrowLogic.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/core/Oracle.sol";

contract MockLendingPool is LendingPool {

    constructor() {}

    function getUserMaxBorrowCapacity(address addUser, address addAsset, bool reserveType) public view returns(uint256) {
        DataTypes.ReserveData storage reserve = _reserves[addAsset][reserveType];

        address oracle = _addressesProvider.getPriceOracle();

        BorrowLogic.CalculateUserAccountDataVolatileParams memory params;
        params.user = addUser;
        params.reservesCount = _reservesCount;
        params.lendingUpdateTimestamp = _lendingUpdateTimestamp;
        params.oracle = oracle;

        (uint userCollateralBalanceETH, uint userBorrowBalanceETH,,,) 
            = BorrowLogic.calculateUserAccountDataVolatile(
                params,
                _reserves,
                _usersConfig[addUser],
                _usersRecentBorrow[addUser],
                _reservesList
        );

        require(userCollateralBalanceETH > 0);
        require(userCollateralBalanceETH >= userBorrowBalanceETH);

        uint amtEthAvailable = userCollateralBalanceETH - userBorrowBalanceETH;
        uint price = Oracle(oracle).getAssetPrice(addAsset); // price addAsset/ETH
        uint assetAmtAvailable = amtEthAvailable * 10**ERC20(addAsset).decimals() / price;

        return assetAmtAvailable;
    }
}