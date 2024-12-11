// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PropertiesBase.sol";

// Users are defined in users
// Admin is address(this)
contract PropertiesMock is PropertiesBase {
    constructor() {}

    function randRebalance(uint8 seedUser) public {
        User user = users[clampBetween(seedUser, 0, users.length - 1)];

        address[] memory assetsFl = new address[](1);
        assetsFl[0] = address(assets[0]);

        bool[] memory reserveTypesFl = new bool[](1);
        reserveTypesFl[0] = true;

        uint256[] memory amountsFl = new uint256[](1);
        amountsFl[0] = aTokens[0].getTotalManagedAssets() / 2;

        uint256[] memory modesFl = new uint256[](1);
        modesFl[0] = 0;

        bytes memory params = new bytes(0);

        ILendingPool.FlashLoanParams memory flp = ILendingPool.FlashLoanParams({
            receiverAddress: address(user),
            assets: assetsFl,
            reserveTypes: reserveTypesFl,
            onBehalfOf: address(user)
        });

        user.execFl(flp, amountsFl, modesFl, params);

        AToken aToken = aTokens[0];

        emit LogUint256("aToken._farmingBal()", aToken._farmingBal());
        emit LogUint256("aToken._underlyingAmount()", aToken._underlyingAmount());
        emit LogUint256("aToken._farmingPct()", aToken._farmingPct());
        emit LogUint256("aToken._farmingPctDrift()", aToken._farmingPctDrift());
        emit LogUint256(
            "aToken._underlyingAmount() * aToken._farmingPct() / 10000",
            aToken._underlyingAmount() * aToken._farmingPct() / 10000
        );

        assertEqApproxPct(
            aToken._farmingBal(),
            aToken._underlyingAmount() * aToken._farmingPct() / BPS,
            aToken._farmingPctDrift() * 11000 / BPS, // +10% margin
            "228"
        );

        assert(false);
    }
}
