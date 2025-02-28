// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20Detailed} from
    "../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {IAToken} from "../../contracts/interfaces/IAToken.sol";
import {ILendingPoolAddressesProvider} from
    "../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "../../contracts/interfaces/ILendingPool.sol";
import {IVariableDebtToken} from "../../contracts/interfaces/IVariableDebtToken.sol";
import {ReserveConfiguration} from
    "../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {IMiniPoolAddressesProvider} from "../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPool} from "../../contracts/interfaces/IMiniPool.sol";
import {IAERC6909} from "../../contracts/interfaces/IAERC6909.sol";
import {ATokenNonRebasing} from "../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";
import {Ownable} from "../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {Errors} from "../../contracts/protocol/libraries/helpers/Errors.sol";
import {IFlowLimiter} from "../../contracts/interfaces/base/IFlowLimiter.sol";
import {IPiReserveInterestRateStrategy} from
    "../../contracts/interfaces/IPiReserveInterestRateStrategy.sol";
import {DefaultReserveInterestRateStrategy} from
    "../../contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import {MiniPoolDefaultReserveInterestRateStrategy} from
    "../../contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import {
    ICod3xLendDataProvider2,
    DataTypes,
    AggregatedMainPoolReservesData,
    AggregatedMiniPoolReservesData,
    MiniPoolData,
    UserReserveData,
    MiniPoolUserReserveData,
    BaseCurrencyInfo
} from "../../contracts/interfaces/ICod3xLendDataProvider2.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IChainlinkAggregator} from "../../contracts/interfaces/base/IChainlinkAggregator.sol";

/**
 * @title Cod3xLendDataProvider
 * @dev This contract provides data access functions for lending pool and minipool information.
 * It retrieves static and dynamic configurations, user data, and token addresses from both types of pools.
 * @author Cod3x
 */
contract Cod3xLendDataProvider2 is Ownable, ICod3xLendDataProvider2 {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    modifier lendingPoolSet() {
        require(address(lendingPoolAddressProvider) != address(0), Errors.DP_LENDINGPOOL_NOT_SET);
        _;
    }

    modifier miniPoolSet() {
        require(address(miniPoolAddressProvider) != address(0), Errors.DP_LENDINGPOOL_NOT_SET);
        _;
    }

    uint256 constant ETH_CURRENCY_UNIT = 1 ether;

    /// @notice The address provider for the Lending Pool
    ILendingPoolAddressesProvider public lendingPoolAddressProvider;
    /// @notice The address provider for the Mini Pool
    IMiniPoolAddressesProvider public miniPoolAddressProvider;

    IChainlinkAggregator public immutable networkBaseTokenPriceInUsdProxyAggregator;
    IChainlinkAggregator public immutable marketReferenceCurrencyPriceInUsdProxyAggregator;

    constructor(
        address _networkBaseTokenPriceInUsdProxyAggregator,
        address _marketReferenceCurrencyPriceInUsdProxyAggregator
    ) Ownable(msg.sender) {
        networkBaseTokenPriceInUsdProxyAggregator =
            IChainlinkAggregator(_networkBaseTokenPriceInUsdProxyAggregator);
        marketReferenceCurrencyPriceInUsdProxyAggregator =
            IChainlinkAggregator(_marketReferenceCurrencyPriceInUsdProxyAggregator);
    }

    /*------ Lending Pool data providers ------*/

    function setLendingPoolAddressProvider(address _lendingPoolAddressProvider) public onlyOwner {
        lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProvider);
    }

    function setMiniPoolAddressProvider(address _miniPoolAddressProvider) public onlyOwner {
        miniPoolAddressProvider = IMiniPoolAddressesProvider(_miniPoolAddressProvider);
    }
    /*------ System Mega Function ------*/

    function getAllMarketData()
        public
        view
        returns (
            AggregatedMainPoolReservesData[] memory mainPoolReservesData,
            MiniPoolData[] memory miniPoolData
        )
    {
        mainPoolReservesData = getMainPoolReservesData();
        miniPoolData = getAllMiniPoolData();
    }

    /* -------------- Lending Pool providers--------------*/
    function getLendingPoolData() public view returns (AggregatedMainPoolReservesData[] memory) {
        return getMainPoolReservesData();
    }

    /**
     * @notice Retrieves the addresses of all aTokens and debt tokens in the lending pool.
     * @return reserves Array of pool reserves
     * @return reserveTypes Array of the reserve types
     * @return aTokens Array of aToken addresses
     * @return debtTokens Array of debt token addresses
     */
    function getAllLpTokens()
        public
        view
        lendingPoolSet
        returns (
            address[] memory reserves,
            bool[] memory reserveTypes,
            address[] memory aTokens,
            address[] memory debtTokens
        )
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (reserves, reserveTypes) = lendingPool.getReservesList();
        aTokens = new address[](reserves.length);
        debtTokens = new address[](reserves.length);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            (aTokens[idx], debtTokens[idx]) =
                _getLpTokens(reserves[idx], reserveTypes[idx], lendingPool);
        }
    }

    function getLpTokens(address asset, bool reserveType)
        public
        view
        lendingPoolSet
        returns (address aToken, address debtToken)
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (aToken, debtToken) = _getLpTokens(asset, reserveType, lendingPool);
    }

    function _getLpTokens(address asset, bool reserveType, ILendingPool lendingPool)
        internal
        view
        lendingPoolSet
        returns (address aToken, address debtToken)
    {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(asset, reserveType);
        aToken = data.aTokenAddress;
        debtToken = data.variableDebtTokenAddress;
    }

    /**
     * @notice Retrieves the aggregated data of all main pool reserves.
     * @return reservesData Array of aggregated data for each main pool reserve.
     */
    function getMainPoolReservesData()
        public
        view
        returns (AggregatedMainPoolReservesData[] memory)
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (address[] memory reserves, bool[] memory reserveTypes) = lendingPool.getReservesList();
        AggregatedMainPoolReservesData[] memory reservesData =
            new AggregatedMainPoolReservesData[](reserves.length);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            reservesData[idx] = getAggregatedMainPoolReserveData(reserves[idx], reserveTypes[idx]);
        }
        return reservesData;
    }
    /**
     * @notice Returns the aggregated data of a main pool reserve.
     * @param asset The address of the asset.
     * @param reserveType The type of the reserve.
     * @return reserveData The aggregated data of the reserve.
     */

    function getAggregatedMainPoolReserveData(address asset, bool reserveType)
        public
        view
        returns (AggregatedMainPoolReservesData memory reserveData)
    {
        DataTypes.ReserveData memory reserve;
        DataTypes.ReserveConfigurationMap memory reserveConfig;
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        reserve = lendingPool.getReserveData(asset, reserveType);
        reserveConfig = reserve.configuration;
        reserveData.underlyingAsset = asset;
        reserveData.reserveType = reserveType;
        {
            // setting all of these at once incurs a stack too deep error
            (
                reserveData.baseLTVasCollateral,
                reserveData.reserveLiquidationThreshold,
                reserveData.reserveLiquidationBonus,
                reserveData.decimals,
                reserveData.cod3xReserveFactor,
                , // miniPoolOwnerReserveFactor
                reserveData.depositCap
            ) = _decodeConfig(reserveConfig);
            reserveData.miniPoolOwnerReserveFactor = reserveConfig.getMinipoolOwnerReserveMemory();
        }
        {
            (
                reserveData.isActive,
                reserveData.isFrozen,
                reserveData.borrowingEnabled,
                reserveData.flashloanEnabled
            ) = _decodeFlags(reserveConfig);
            reserveData.usageAsCollateralEnabled =
                (reserveData.baseLTVasCollateral != 0) ? true : false;
        }
        {
            reserveData.name = IERC20Detailed(asset).name();
            reserveData.symbol = IERC20Detailed(asset).symbol();
            reserveData.decimals = IERC20Detailed(asset).decimals();
        }
        {
            reserveData.liquidityIndex = reserve.liquidityIndex;
            reserveData.variableBorrowIndex = reserve.variableBorrowIndex;
            reserveData.liquidityRate = reserve.currentLiquidityRate;
            reserveData.variableBorrowRate = reserve.currentVariableBorrowRate;
            reserveData.lastUpdateTimestamp = reserve.lastUpdateTimestamp;
        }
        {
            reserveData.aTokenAddress = reserve.aTokenAddress;
            reserveData.variableDebtTokenAddress = reserve.variableDebtTokenAddress;
            reserveData.interestRateStrategyAddress = reserve.interestRateStrategyAddress;
            reserveData.id = reserve.id;
        }
        {
            reserveData.availableLiquidity =
                IERC20Detailed(asset).balanceOf(address(reserve.aTokenAddress));
            reserveData.totalScaledVariableDebt =
                IVariableDebtToken(reserve.variableDebtTokenAddress).scaledTotalSupply();
            reserveData.priceInMarketReferenceCurrency =
                IOracle(lendingPoolAddressProvider.getPriceOracle()).getAssetPrice(asset);
            reserveData.ATokenNonRebasingAddress = IAToken(reserve.aTokenAddress).WRAPPER_ADDRESS();
        }
        {
            IPiReserveInterestRateStrategy strat =
                IPiReserveInterestRateStrategy(reserve.interestRateStrategyAddress);
            try strat._optimalUtilizationRate() {
                reserveData.optimalUtilizationRate = IPiReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                )._optimalUtilizationRate();
                reserveData.kp =
                    IPiReserveInterestRateStrategy(reserve.interestRateStrategyAddress)._kp();
                reserveData.ki =
                    IPiReserveInterestRateStrategy(reserve.interestRateStrategyAddress)._ki();
                reserveData.lastPiReserveRateStrategyUpdate = IPiReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                )._lastTimestamp();
                reserveData.errI =
                    IPiReserveInterestRateStrategy(reserve.interestRateStrategyAddress)._errI();
                reserveData.minControllerError = IPiReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                )._minControllerError();
                reserveData.maxErrIAmp = IPiReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                )._maxErrIAmp();
            } catch {
                reserveData.optimalUtilizationRate = DefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).OPTIMAL_UTILIZATION_RATE();
                reserveData.baseVariableBorrowRate = DefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).baseVariableBorrowRate();
                reserveData.variableRateSlope1 = DefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).variableRateSlope1();
                reserveData.variableRateSlope2 = DefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).variableRateSlope2();
                reserveData.maxVariableBorrowRate = DefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).getMaxVariableBorrowRate();
            }
        }
        return reserveData;
    }

    /// @notice Returns the user's main pool reserves data.
    /// @param user The address of the user.
    /// @return userReservesData The user's main pool reserves data.
    function getUserMainPoolReservesData(address user)
        public
        view
        lendingPoolSet
        returns (UserReserveData[] memory userReservesData)
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (address[] memory reserves, bool[] memory reserveTypes) = lendingPool.getReservesList();
        userReservesData = new UserReserveData[](user != address(0) ? reserves.length : 0);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            userReservesData[idx] =
                getUserMainPoolReserveData(reserves[idx], reserveTypes[idx], user, lendingPool);
        }
        return userReservesData;
    }
    /// @notice Returns the user's main pool reserves data.
    /// @param asset The address of the asset.
    /// @param reserveType The type of the reserve.
    /// @param user The address of the user.
    /// @param lendingPool The lending pool.
    /// @return userReserveData The user's main pool reserves data.

    function getUserMainPoolReserveData(
        address asset,
        bool reserveType,
        address user,
        ILendingPool lendingPool
    ) public view returns (UserReserveData memory userReserveData) {
        DataTypes.UserConfigurationMap memory userConfig = lendingPool.getUserConfiguration(user);
        DataTypes.ReserveData memory data = lendingPool.getReserveData(asset, reserveType);
        userReserveData.aToken = data.aTokenAddress;
        userReserveData.debtToken = data.variableDebtTokenAddress;
        userReserveData.currentATokenBalance = IERC20Detailed(data.aTokenAddress).balanceOf(user);

        userReserveData.scaledATokenBalance = IAToken(data.aTokenAddress).scaledBalanceOf(user);
        userReserveData.usageAsCollateralEnabledOnUser = userConfig.isUsingAsCollateral(data.id);
        userReserveData.isBorrowing = userConfig.isBorrowing(data.id);
        if (userReserveData.isBorrowing) {
            userReserveData.currentVariableDebt =
                IERC20Detailed(data.variableDebtTokenAddress).balanceOf(user);
            userReserveData.scaledVariableDebt =
                IVariableDebtToken(data.variableDebtTokenAddress).scaledBalanceOf(user);
        }
    }

    /* -------------- Mini Pool providers--------------*/

    function getAllMiniPoolData() public view returns (MiniPoolData[] memory miniPoolData) {
        (uint256[] memory miniPoolIDs, address[] memory miniPoolAddresses) =
            getMiniPoolAddressesAndIDs();
        miniPoolData = new MiniPoolData[](miniPoolAddresses.length);
        for (uint256 idx = 0; idx < miniPoolAddresses.length; idx++) {
            miniPoolData[idx].id = miniPoolIDs[idx];
            miniPoolData[idx].miniPoolAddress = miniPoolAddresses[idx];
            miniPoolData[idx].aToken6909Address =
                miniPoolAddressProvider.getMiniPoolToAERC6909(miniPoolAddresses[idx]);
            miniPoolData[idx].reservesData = getMiniPoolReservesData(miniPoolAddresses[idx]);
        }
        return miniPoolData;
    }

    function getMiniPoolData(address miniPoolAddress)
        public
        view
        returns (MiniPoolData memory miniPoolData)
    {
        miniPoolData.id = miniPoolAddressProvider.getMiniPoolId(miniPoolAddress);
        miniPoolData.miniPoolAddress = miniPoolAddress;
        miniPoolData.aToken6909Address =
            miniPoolAddressProvider.getMiniPoolToAERC6909(miniPoolAddress);
        miniPoolData.reservesData = getMiniPoolReservesData(miniPoolAddress);
        return miniPoolData;
    }

    function getMiniPoolData(uint256 miniPoolID)
        public
        view
        returns (MiniPoolData memory miniPoolData)
    {
        miniPoolData.id = miniPoolID;
        miniPoolData.miniPoolAddress = miniPoolAddressProvider.getMiniPool(miniPoolID);
        miniPoolData.aToken6909Address = miniPoolAddressProvider.getMiniPoolToAERC6909(miniPoolID);
        miniPoolData.reservesData = getMiniPoolReservesData(miniPoolData.miniPoolAddress);
    }

    function getMiniPoolAddressesAndIDs()
        public
        view
        returns (uint256[] memory miniPoolIDs, address[] memory miniPoolAddresses)
    {
        //IMiniPoolAddressesProvider miniPoolAddressProvider = IMiniPoolAddressesProvider(miniPoolAddressProvider);
        miniPoolAddresses = miniPoolAddressProvider.getMiniPoolList();
        miniPoolIDs = new uint256[](miniPoolAddresses.length);
        for (uint256 idx = 0; idx < miniPoolAddresses.length; idx++) {
            miniPoolIDs[idx] = miniPoolAddressProvider.getMiniPoolId(miniPoolAddresses[idx]);
        }
        return (miniPoolIDs, miniPoolAddresses);
    }

    function getMiniPoolReservesData(address miniPoolAddress)
        public
        view
        returns (AggregatedMiniPoolReservesData[] memory)
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddress);
        (address[] memory reserves, /*all types are false*/ ) = miniPool.getReservesList();
        AggregatedMiniPoolReservesData[] memory reservesData =
            new AggregatedMiniPoolReservesData[](reserves.length);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            reservesData[idx] = getReserveDataForAssetAtMiniPool(reserves[idx], miniPoolAddress);
        }
        return reservesData;
    }

    function getReserveDataForAssetAtMiniPool(address asset, address miniPoolAddress)
        public
        view
        returns (AggregatedMiniPoolReservesData memory reserveData)
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddress);
        DataTypes.MiniPoolReserveData memory reserve = miniPool.getReserveData(asset);
        IAERC6909 aErc6909 = IAERC6909(reserve.aErc6909);
        DataTypes.ReserveConfigurationMap memory reserveConfig = reserve.configuration;
        reserveData.underlyingAsset = asset;
        {
            // setting all of these at once incurs a stack too deep error
            (
                reserveData.baseLTVasCollateral,
                reserveData.reserveLiquidationThreshold,
                reserveData.reserveLiquidationBonus,
                reserveData.decimals,
                reserveData.cod3xReserveFactor,
                , // miniPoolOwnerReserveFactor
                reserveData.depositCap
            ) = _decodeConfig(reserveConfig);
            reserveData.miniPoolOwnerReserveFactor = reserveConfig.getMinipoolOwnerReserveMemory();
        }
        {
            (
                reserveData.isActive,
                reserveData.isFrozen,
                reserveData.borrowingEnabled,
                reserveData.flashloanEnabled
            ) = _decodeFlags(reserveConfig);
            reserveData.usageAsCollateralEnabled =
                (reserveData.baseLTVasCollateral != 0) ? true : false;
        }
        {
            reserveData.name = IERC20Detailed(asset).name();
            reserveData.symbol = IERC20Detailed(asset).symbol();
            reserveData.decimals = IERC20Detailed(asset).decimals();
        }
        {
            reserveData.aTokenId = reserve.aTokenID;
            reserveData.debtTokenId = reserve.variableDebtTokenID;
            reserveData.isTranche = reserveData.aTokenId % 1000 < 256 ? true : false;
            if (reserveData.isTranche) {
                reserveData.aTokenNonRebasingAddress = asset;
                reserveData.underlyingAsset = ATokenNonRebasing(asset).UNDERLYING_ASSET_ADDRESS();
            }
        }
        {
            reserveData.liquidityIndex = reserve.liquidityIndex;
            reserveData.variableBorrowIndex = reserve.variableBorrowIndex;
            reserveData.liquidityRate = reserve.currentLiquidityRate;
            reserveData.variableBorrowRate = reserve.currentVariableBorrowRate;
            reserveData.lastUpdateTimestamp = reserve.lastUpdateTimestamp;
            reserveData.interestRateStrategyAddress = reserve.interestRateStrategyAddress;
        }
        {
            reserveData.availableLiquidity = IERC20Detailed(asset).balanceOf(address(aErc6909));
            reserveData.totalScaledVariableDebt =
                aErc6909.scaledTotalSupply(reserveData.debtTokenId);
            reserveData.priceInMarketReferenceCurrency =
                IOracle(lendingPoolAddressProvider.getPriceOracle()).getAssetPrice(asset);
        }
        {
            IPiReserveInterestRateStrategy strat =
                IPiReserveInterestRateStrategy(reserve.interestRateStrategyAddress);
            try strat._optimalUtilizationRate() {
                reserveData.optimalUtilizationRate = IPiReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                )._optimalUtilizationRate();
                reserveData.kp =
                    IPiReserveInterestRateStrategy(reserve.interestRateStrategyAddress)._kp();
                reserveData.ki =
                    IPiReserveInterestRateStrategy(reserve.interestRateStrategyAddress)._ki();
                reserveData.lastPiReserveRateStrategyUpdate = IPiReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                )._lastTimestamp();
                reserveData.errI =
                    IPiReserveInterestRateStrategy(reserve.interestRateStrategyAddress)._errI();
                reserveData.minControllerError = IPiReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                )._minControllerError();
                reserveData.maxErrIAmp = IPiReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                )._maxErrIAmp();
            } catch {
                reserveData.optimalUtilizationRate = MiniPoolDefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).OPTIMAL_UTILIZATION_RATE();
                reserveData.baseVariableBorrowRate = MiniPoolDefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).baseVariableBorrowRate();
                reserveData.variableRateSlope1 = MiniPoolDefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).variableRateSlope1();
                reserveData.variableRateSlope2 = MiniPoolDefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).variableRateSlope2();
                reserveData.maxVariableBorrowRate = MiniPoolDefaultReserveInterestRateStrategy(
                    reserve.interestRateStrategyAddress
                ).getMaxVariableBorrowRate();
            }
        }
        {
            if (reserveData.isTranche) {
                IFlowLimiter flowLimiter = IFlowLimiter(miniPoolAddressProvider.getFlowLimiter());
                reserveData.flowLimit =
                    flowLimiter.getFlowLimit(reserveData.underlyingAsset, miniPoolAddress);
                reserveData.currentFlow =
                    flowLimiter.currentFlow(reserveData.underlyingAsset, miniPoolAddress);
                reserveData.availableFlow = reserveData.flowLimit > reserveData.currentFlow
                    ? reserveData.flowLimit - reserveData.currentFlow
                    : 0;
            }
        }
        return reserveData;
    }

    function getUserAllMiniPoolReservesData(address user)
        public
        view
        returns (MiniPoolUserReserveData[][] memory userReservesData)
    {
        (uint256[] memory miniPoolIDs, address[] memory miniPoolAddresses) =
            getMiniPoolAddressesAndIDs();
        userReservesData = new MiniPoolUserReserveData[][](miniPoolAddresses.length);
        for (uint256 idx = 0; idx < miniPoolAddresses.length; idx++) {
            userReservesData[idx] = getUserMiniPoolReservesData(user, miniPoolAddresses[idx]);
        }
    }

    function getUserMiniPoolReservesData(address user, address miniPoolAddress)
        public
        view
        returns (MiniPoolUserReserveData[] memory userReservesData)
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddress);
        (address[] memory reserves, /*all types are false*/ ) = miniPool.getReservesList();
        userReservesData = new MiniPoolUserReserveData[](reserves.length);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            userReservesData[idx] = getUserMiniPoolReserveData(
                reserves[idx],
                user,
                miniPool,
                IAERC6909(miniPool.getReserveData(reserves[idx]).aErc6909)
            );
        }
    }
    /// @notice Returns the user's main pool reserves data.
    /// @param asset The address of the asset.
    /// @param user The address of the user.
    /// @param miniPool The mini pool.
    /// @param aErc6909 The aErc6909 token.
    /// @return userReserveData The user's main pool reserves data.

    function getUserMiniPoolReserveData(
        address asset,
        address user,
        IMiniPool miniPool,
        IAERC6909 aErc6909
    ) public view returns (MiniPoolUserReserveData memory userReserveData) {
        DataTypes.UserConfigurationMap memory userConfig = miniPool.getUserConfiguration(user);
        DataTypes.MiniPoolReserveData memory data = miniPool.getReserveData(asset);
        userReserveData.aErc6909Token = data.aErc6909;
        userReserveData.aTokenId = data.aTokenID;
        userReserveData.debtTokenId = data.variableDebtTokenID;

        userReserveData.currentATokenBalance =
            IAERC6909(aErc6909).balanceOf(user, userReserveData.aTokenId);
        (userReserveData.scaledATokenBalance,) =
            IAERC6909(aErc6909).getScaledUserBalanceAndSupply(user, userReserveData.aTokenId);
        userReserveData.usageAsCollateralEnabledOnUser = userConfig.isUsingAsCollateral(data.id);
        userReserveData.isBorrowing = userConfig.isBorrowing(data.id);
        if (userReserveData.isBorrowing) {
            userReserveData.currentVariableDebt =
                IAERC6909(aErc6909).balanceOf(user, userReserveData.debtTokenId);
            (userReserveData.scaledVariableDebt,) =
                IAERC6909(aErc6909).getScaledUserBalanceAndSupply(user, userReserveData.debtTokenId);
        }
    }

    function getAllUserMiniPoolAccountDatas(address user)
        public
        view
        returns (
            uint256[] memory totalCollateralETH,
            uint256[] memory totalDebtETH,
            uint256[] memory availableBorrowsETH,
            uint256[] memory currentLiquidationThreshold,
            uint256[] memory ltv,
            uint256[] memory healthFactor
        )
    {
        (uint256[] memory miniPoolIDs, address[] memory miniPoolAddresses) =
            getMiniPoolAddressesAndIDs();
        totalCollateralETH = new uint256[](miniPoolAddresses.length);
        totalDebtETH = new uint256[](miniPoolAddresses.length);
        availableBorrowsETH = new uint256[](miniPoolAddresses.length);
        currentLiquidationThreshold = new uint256[](miniPoolAddresses.length);
        ltv = new uint256[](miniPoolAddresses.length);
        healthFactor = new uint256[](miniPoolAddresses.length);
        for (uint256 idx = 0; idx < miniPoolAddresses.length; idx++) {
            (
                totalCollateralETH[idx],
                totalDebtETH[idx],
                availableBorrowsETH[idx],
                currentLiquidationThreshold[idx],
                ltv[idx],
                healthFactor[idx]
            ) = IMiniPool(miniPoolAddresses[idx]).getUserAccountData(user);
        }
    }

    /* -------------- Special Helper functions--------------*/

    function getAllMiniPoolsContainingReserve(address reserve)
        public
        view
        returns (address[] memory foundMiniPoolAddresses, bool[] memory isTranche)
    {
        (uint256[] memory miniPoolIDs, address[] memory miniPoolAddresses) =
            getMiniPoolAddressesAndIDs();
        foundMiniPoolAddresses = new address[](miniPoolAddresses.length);
        isTranche = new bool[](miniPoolAddresses.length);
        bool isReserveAvailable;
        bool _isTranche;
        address miniPool;
        uint256 idx = 0;
        for (idx = 0; idx < miniPoolAddresses.length; idx++) {
            (isReserveAvailable, _isTranche, miniPool) =
                isReserveInMiniPool(reserve, miniPoolIDs[idx]);
            if (isReserveAvailable) {
                foundMiniPoolAddresses[idx] = miniPool;
                isTranche[idx] = _isTranche;
            }
        }
        return (foundMiniPoolAddresses, isTranche);
    }

    /**
     * @dev Checks if a given reserve is available in a specific MiniPool.
     * @notice This function supports reserves of rebasing aTokens.
     * @param reserve The address of the reserve to check for availability.
     * @param miniPoolId The ID of the MiniPool where the reserve's availability is checked.
     * @return isReserveAvailable True if the reserve is available in the MiniPool, false otherwise.
     * @return isTranche True if the reserve is a tranche, false otherwise.
     * @return miniPool The address of the MiniPool being checked.
     */
    function isReserveInMiniPool(address reserve, uint256 miniPoolId)
        public
        view
        miniPoolSet
        returns (bool isReserveAvailable, bool isTranche, address miniPool)
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(reserve, true); //should always be true
        address aToken = reserveData.aTokenAddress;
        address aTokenWrapper = IAToken(aToken).WRAPPER_ADDRESS();
        isReserveAvailable = false;
        miniPool = miniPoolAddressProvider.getMiniPool(miniPoolId);
        (address[] memory reserves,) = IMiniPool(miniPool).getReservesList();
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            if (reserves[idx] == reserve) {
                isReserveAvailable = true;
            }
            if (reserves[idx] == aTokenWrapper) {
                isReserveAvailable = true;
                isTranche = true;
            }
        }
    }

    function getBaseCurrencyInfo()
        external
        view
        returns (BaseCurrencyInfo memory baseCurrencyInfo)
    {
        baseCurrencyInfo.networkBaseTokenPriceInUsd =
            networkBaseTokenPriceInUsdProxyAggregator.latestAnswer();
        baseCurrencyInfo.networkBaseTokenPriceDecimals =
            networkBaseTokenPriceInUsdProxyAggregator.decimals();
        IOracle oracle = IOracle(lendingPoolAddressProvider.getPriceOracle()); //Oracle is the same so can be retrieved only from main pool
        try oracle.BASE_CURRENCY_UNIT() returns (uint256 baseCurrencyUnit) {
            if (ETH_CURRENCY_UNIT == baseCurrencyUnit) {
                baseCurrencyInfo.marketReferenceCurrencyUnit = ETH_CURRENCY_UNIT;
                // baseCurrencyInfo.marketReferenceCurrencyPriceInUsd =
                //     marketReferenceCurrencyPriceInUsdProxyAggregator.latestAnswer();
            } else {
                baseCurrencyInfo.marketReferenceCurrencyUnit = baseCurrencyUnit;
                // baseCurrencyInfo.marketReferenceCurrencyPriceInUsd = int256(baseCurrencyUnit);
            }
        } catch (bytes memory) /*lowLevelData*/ {
            baseCurrencyInfo.marketReferenceCurrencyUnit = ETH_CURRENCY_UNIT;
            // baseCurrencyInfo.marketReferenceCurrencyPriceInUsd =
            //     marketReferenceCurrencyPriceInUsdProxyAggregator.latestAnswer();
        }
        (uint80 roundId, int256 price, uint256 startedAt, uint256 timestamp,) =
            marketReferenceCurrencyPriceInUsdProxyAggregator.latestRoundData();

        require(
            (
                roundId != 0 && timestamp == 0 && timestamp > block.timestamp && price <= 0
                    && startedAt == 0
            ),
            Errors.O_PRICE_FEED_INCONSISTENCY
        );

        baseCurrencyInfo.marketReferenceCurrencyPriceInUsd = price;
    }

    /* -------------- Decoding functions--------------*/

    function _decodeConfig(DataTypes.ReserveConfigurationMap memory config)
        internal
        pure
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return config.getParamsMemory();
    }

    function _decodeFlags(DataTypes.ReserveConfigurationMap memory config)
        internal
        pure
        returns (bool, bool, bool, bool)
    {
        return config.getFlagsMemory();
    }
}
