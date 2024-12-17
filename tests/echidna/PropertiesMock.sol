// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PropertiesBase.sol";

// Users are defined in users
// Admin is address(this)
contract PropertiesMock is PropertiesBase {
    // constructor() {}

    function randMiniPoolMock() public {
        assert(false);
        uint256 randAmt = 1e18;
        MintableERC20 asset = assets[0];
        User user = users[0];

        //deposit
        (bool success,) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.deposit.selector, address(asset), true, randAmt, address(user)
            )
        );
        assert(success);

        //borrow
        (success,) = user.proxy(
            address(pool),
            abi.encodeWithSelector(
                pool.borrow.selector, address(assets[1]), true, randAmt / 2, address(user)
            )
        );
        assert(success);

        // check solvency
        uint256 valueColl;
        uint256 valueDebt;
        for (uint256 i = 0; i < aTokens.length; i++) {
            AToken aToken = aTokens[i];
            VariableDebtToken vToken = debtTokens[i];
            MintableERC20 asset = assets[i];
            uint256 price = oracle.getAssetPrice(address(asset));
            uint256 decimals = MintableERC20(asset).decimals();

            valueColl += aToken.totalSupply() * price / (10 ** decimals);

            valueDebt += vToken.totalSupply() * price / (10 ** decimals);
        }

        emit LogUint256("valueColl", valueColl);
        emit LogUint256("valueDebt", valueDebt);

        assert(false);
        assertGte(valueColl, valueDebt * 100, "215");
    }
}
