// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PropertiesBase.sol";

// Users are defined in users
// Admin is address(this)
contract PropertiesMock is PropertiesBase {
    constructor() {}

    function randInitMiniPool() public {
        for (uint256 i = 0; i < totalNbMinipool; i++) {
            uint256 _minipoolId =
                miniPoolProvider.deployMiniPool(minipoolImpl, aToken6909Impl, address(this));
            ATokenERC6909 _aToken6909 = ATokenERC6909(miniPoolProvider.getAToken6909(_minipoolId));
            MiniPool _miniPool = MiniPool(miniPoolProvider.getMiniPool(_minipoolId));

            miniPoolId.push(_minipoolId);
            aToken6909.push(_aToken6909);
            miniPool.push(_miniPool);

            IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
                new IMiniPoolConfigurator.InitReserveInput[](totalNbTokens * 2); // classic assets + lendingpool aTokens

            for (uint256 j = 0; j < 1; /* totalNbTokens * 2 */ j++) {
                address token =
                    j < totalNbTokens ? address(assets[j]) : address(aTokensNonRebasing[j]);

                string memory tmpSymbol = ERC20(token).symbol();
                string memory tmpName = ERC20(token).name();

                address interestStrategy = address(minipoolDefaultRateStrategies);

                initInputParams[j] = IMiniPoolConfigurator.InitReserveInput({
                    underlyingAssetDecimals: ERC20(token).decimals(),
                    interestRateStrategyAddress: interestStrategy,
                    underlyingAsset: token,
                    underlyingAssetName: tmpName,
                    underlyingAssetSymbol: tmpSymbol
                });
            }
            miniPoolConfigurator.batchInitReserve(initInputParams, IMiniPool(address(_miniPool)));

            // for (uint256 j = 0; j < totalNbTokens * 2; j++) {
            //     miniPoolConfigurator.configureReserveAsCollateral(
            //         tokenToPrepare, DEFAULT_BASE_LTV, DEFAULT_LIQUIDATION_THRESHOLD, DEFAULT_LIQUIDATION_BONUS, IMiniPool(address(_miniPool))
            //     );
            //     miniPoolConfigurator.activateReserve(tokenToPrepare, IMiniPool(_miniPool));
            //     miniPoolConfigurator.enableBorrowingOnReserve(tokenToPrepare, IMiniPool(_miniPool));
            //     miniPoolConfigurator.setCod3xReserveFactor(address(assets[0]), 10000, IMiniPool(_miniPool));
            //     miniPoolConfigurator.setDepositCap(address(assets[0]), 10000, IMiniPool(address(_miniPool)));
            //    miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(address(this), IMiniPool(address(_miniPool)));
            //    miniPoolConfigurator.setMinipoolOwnerReserveFactor(address(assets[0]), 10000, IMiniPool(address(_miniPool)));
            // }
            assert(false);
        }
    }
}
