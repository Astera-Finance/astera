// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/logic/BorrowLogic.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/core/Oracle.sol";

contract MockLendingPool is LendingPool {
    constructor() {}

    function getUserMaxBorrowCapacity(address addUser, address addAsset)
        public
        view
        returns (uint256)
    {
        address oracle = _addressesProvider.getPriceOracle();

        BorrowLogic.CalculateUserAccountDataVolatileParams memory params;
        params.user = addUser;
        params.reservesCount = _reservesCount;
        params.oracle = oracle;

        (uint256 userCollateralBalanceETH, uint256 userBorrowBalanceETH,,,) = BorrowLogic
            .calculateUserAccountDataVolatile(params, _reserves, _usersConfig[addUser], _reservesList);

        require(userCollateralBalanceETH > 0);
        require(userCollateralBalanceETH >= userBorrowBalanceETH);

        uint256 amtEthAvailable = userCollateralBalanceETH - userBorrowBalanceETH;
        uint256 price = Oracle(oracle).getAssetPrice(addAsset); // price addAsset/ETH
        uint256 assetAmtAvailable = amtEthAvailable * 10 ** ERC20(addAsset).decimals() / price;

        return assetAmtAvailable;
    }

    function getDebtInterestRate(address asset, bool reserveType) public view returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset][reserveType];
        return reserve.currentVariableBorrowRate;
    }

    function getLiquidityInterestRate(address asset, bool reserveType) public view returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset][reserveType];
        return reserve.currentLiquidityRate;
    }
}
