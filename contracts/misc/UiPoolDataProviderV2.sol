// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20Detailed} from "contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IUiPoolDataProviderV2} from "contracts/interfaces/IUiPoolDataProviderV2.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {IOracle} from "contracts/interfaces/IOracle.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {IChainlinkAggregator} from "contracts/interfaces/IChainlinkAggregator.sol";
import {DefaultReserveInterestRateStrategy} from
    "contracts/protocol/core/InterestRateStrategies/DefaultReserveInterestRateStrategy.sol";
import {IERC20DetailedBytes} from "contracts/interfaces/IERC20DetailedBytes.sol";

contract UiPoolDataProviderV2 is IUiPoolDataProviderV2 {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    IChainlinkAggregator public immutable networkBaseTokenPriceInUsdProxyAggregator;
    IChainlinkAggregator public immutable marketReferenceCurrencyPriceInUsdProxyAggregator;
    uint256 public constant ETH_CURRENCY_UNIT = 1 ether;
    address public constant MKRAddress = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    constructor(
        IChainlinkAggregator _networkBaseTokenPriceInUsdProxyAggregator,
        IChainlinkAggregator _marketReferenceCurrencyPriceInUsdProxyAggregator
    ) {
        networkBaseTokenPriceInUsdProxyAggregator = _networkBaseTokenPriceInUsdProxyAggregator;
        marketReferenceCurrencyPriceInUsdProxyAggregator =
            _marketReferenceCurrencyPriceInUsdProxyAggregator;
    }

    function getInterestRateStrategySlopes(DefaultReserveInterestRateStrategy interestRateStrategy)
        internal
        view
        returns (uint256, uint256)
    {
        return
            (interestRateStrategy.variableRateSlope1(), interestRateStrategy.variableRateSlope2());
    }

    function getReservesList(ILendingPoolAddressesProvider provider)
        public
        view
        override
        returns (address[] memory, bool[] memory)
    {
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
        address[] memory reserves = new address[](lendingPool.getReservesCount());
        bool[] memory reservesTypes = new bool[](lendingPool.getReservesCount());
        (reserves, reservesTypes) = lendingPool.getReservesList();
        return (reserves, reservesTypes);
    }

    function getReservesData(ILendingPoolAddressesProvider provider)
        public
        view
        override
        returns (AggregatedReserveData[] memory, BaseCurrencyInfo memory)
    {
        IOracle oracle = IOracle(provider.getPriceOracle());
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
        address[] memory reserves = new address[](lendingPool.getReservesCount());
        bool[] memory reservesTypes = new bool[](lendingPool.getReservesCount());
        (reserves, reservesTypes) = lendingPool.getReservesList();
        AggregatedReserveData[] memory reservesData = new AggregatedReserveData[](reserves.length);

        for (uint256 i = 0; i < reserves.length; i++) {
            AggregatedReserveData memory reserveData = reservesData[i];
            reserveData.underlyingAsset = reserves[i];
            reserveData.reserveType = reservesTypes[i];

            // reserve current state
            DataTypes.ReserveData memory baseData =
                lendingPool.getReserveData(reserveData.underlyingAsset, reserveData.reserveType);
            reserveData.liquidityIndex = baseData.liquidityIndex;
            reserveData.variableBorrowIndex = baseData.variableBorrowIndex;
            reserveData.liquidityRate = baseData.currentLiquidityRate;
            reserveData.variableBorrowRate = baseData.currentVariableBorrowRate;
            reserveData.lastUpdateTimestamp = baseData.lastUpdateTimestamp;
            reserveData.aTokenAddress = baseData.aTokenAddress;
            reserveData.variableDebtTokenAddress = baseData.variableDebtTokenAddress;
            reserveData.interestRateStrategyAddress = baseData.interestRateStrategyAddress;
            reserveData.priceInMarketReferenceCurrency =
                oracle.getAssetPrice(reserveData.underlyingAsset);

            reserveData.availableLiquidity =
                IAToken(reserveData.aTokenAddress).getTotalManagedAssets();
            reserveData.totalScaledVariableDebt =
                IVariableDebtToken(reserveData.variableDebtTokenAddress).scaledTotalSupply();

            if (address(reserveData.underlyingAsset) == address(MKRAddress)) {
                bytes32 symbol = IERC20DetailedBytes(reserveData.underlyingAsset).symbol();
                reserveData.symbol = bytes32ToString(symbol);
            } else {
                reserveData.symbol = IERC20Detailed(reserveData.underlyingAsset).symbol();
            }

            (
                reserveData.baseLTVasCollateral,
                reserveData.reserveLiquidationThreshold,
                reserveData.reserveLiquidationBonus,
                reserveData.decimals,
                reserveData.reserveFactor
            ) = baseData.configuration.getParamsMemory();
            (reserveData.isActive, reserveData.isFrozen, reserveData.borrowingEnabled) =
                baseData.configuration.getFlagsMemory();
            reserveData.usageAsCollateralEnabled = reserveData.baseLTVasCollateral != 0;
            (reserveData.variableRateSlope1, reserveData.variableRateSlope2) =
            getInterestRateStrategySlopes(
                DefaultReserveInterestRateStrategy(reserveData.interestRateStrategyAddress)
            );
        }

        BaseCurrencyInfo memory baseCurrencyInfo;
        baseCurrencyInfo.networkBaseTokenPriceInUsd =
            networkBaseTokenPriceInUsdProxyAggregator.latestAnswer();
        baseCurrencyInfo.networkBaseTokenPriceDecimals =
            networkBaseTokenPriceInUsdProxyAggregator.decimals();

        try oracle.BASE_CURRENCY_UNIT() returns (uint256 baseCurrencyUnit) {
            if (ETH_CURRENCY_UNIT == baseCurrencyUnit) {
                baseCurrencyInfo.marketReferenceCurrencyUnit = ETH_CURRENCY_UNIT;
                baseCurrencyInfo.marketReferenceCurrencyPriceInUsd =
                    marketReferenceCurrencyPriceInUsdProxyAggregator.latestAnswer();
            } else {
                baseCurrencyInfo.marketReferenceCurrencyUnit = baseCurrencyUnit;
                baseCurrencyInfo.marketReferenceCurrencyPriceInUsd = int256(baseCurrencyUnit);
            }
        } catch (bytes memory) /*lowLevelData*/ {
            baseCurrencyInfo.marketReferenceCurrencyUnit = ETH_CURRENCY_UNIT;
            baseCurrencyInfo.marketReferenceCurrencyPriceInUsd =
                marketReferenceCurrencyPriceInUsdProxyAggregator.latestAnswer();
        }

        return (reservesData, baseCurrencyInfo);
    }

    function getUserReservesData(ILendingPoolAddressesProvider provider, address user)
        external
        view
        override
        returns (UserReserveData[] memory)
    {
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
        address[] memory reserves = new address[](lendingPool.getReservesCount());
        bool[] memory reservesTypes = new bool[](lendingPool.getReservesCount());
        (reserves, reservesTypes) = lendingPool.getReservesList();
        DataTypes.UserConfigurationMap memory userConfig = lendingPool.getUserConfiguration(user);

        UserReserveData[] memory userReservesData =
            new UserReserveData[](user != address(0) ? reserves.length : 0);

        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveData memory baseData =
                lendingPool.getReserveData(reserves[i], reservesTypes[i]);

            // user reserve data
            userReservesData[i].underlyingAsset = reserves[i];
            userReservesData[i].reserveType = reservesTypes[i];
            userReservesData[i].scaledATokenBalance =
                IAToken(baseData.aTokenAddress).scaledBalanceOf(user);
            userReservesData[i].usageAsCollateralEnabledOnUser = userConfig.isUsingAsCollateral(i);

            if (userConfig.isBorrowing(i)) {
                userReservesData[i].scaledVariableDebt =
                    IVariableDebtToken(baseData.variableDebtTokenAddress).scaledBalanceOf(user);
            }
        }

        return (userReservesData);
    }

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
