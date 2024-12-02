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
import {Ownable} from "../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {Errors} from "../../contracts/protocol/libraries/helpers/Errors.sol";
import {IFlowLimiter} from "../../contracts/interfaces/base/IFlowLimiter.sol";
import {
    ICod3xLendDataProvider,
    DataTypes,
    StaticData,
    DynamicData,
    UserReserveData,
    MiniPoolUserReserveData,
    AllPoolData
} from "../../contracts/interfaces/ICod3xLendDataProvider.sol";

/**
 * @title Cod3xLendDataProvider
 * @dev This contract provides data access functions for lending pool and minipool information.
 * It retrieves static and dynamic configurations, user data, and token addresses from both types of pools.
 * @author Cod3x
 */
contract Cod3xLendDataProvider is Ownable, ICod3xLendDataProvider {
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

    /// @notice The address provider for the Lending Pool
    ILendingPoolAddressesProvider public lendingPoolAddressProvider;
    /// @notice The address provider for the Mini Pool
    IMiniPoolAddressesProvider public miniPoolAddressProvider;

    constructor() Ownable(msg.sender) {}

    /*------ Lending Pool data providers ------*/

    function setLendingPoolAddressProvider(address _lendingPoolAddressProvider) public onlyOwner {
        lendingPoolAddressProvider = ILendingPoolAddressesProvider(_lendingPoolAddressProvider);
    }

    function setMiniPoolAddressProvider(address _miniPoolAddressProvider) public onlyOwner {
        miniPoolAddressProvider = IMiniPoolAddressesProvider(_miniPoolAddressProvider);
    }

    /* -------------- Lending Pool providers--------------*/
    function getAllLpData(address asset, bool reserveType)
        external
        view
        lendingPoolSet
        returns (AllPoolData memory allPoolData)
    {
        allPoolData = _getAllLpData(asset, reserveType);
    }

    function _getAllLpData(address asset, bool reserveType)
        internal
        view
        returns (AllPoolData memory allPoolData)
    {
        StaticData memory staticData = _getLpReserveStaticData(asset, reserveType);
        DynamicData memory dynamicData = _getLpReserveDynamicData(asset, reserveType);
        allPoolData.ltv = staticData.ltv;
        allPoolData.liquidationThreshold = staticData.liquidationThreshold;
        allPoolData.liquidationBonus = staticData.liquidationBonus;
        allPoolData.decimals = staticData.decimals;
        allPoolData.cod3xReserveFactor = staticData.cod3xReserveFactor;
        allPoolData.miniPoolOwnerReserveFactor = staticData.miniPoolOwnerReserveFactor;
        allPoolData.depositCap = staticData.depositCap;

        allPoolData.availableLiquidity = dynamicData.availableLiquidity;
        allPoolData.totalVariableDebt = dynamicData.totalVariableDebt;
        allPoolData.liquidityRate = dynamicData.liquidityRate;
        allPoolData.variableBorrowRate = dynamicData.variableBorrowRate;
        allPoolData.liquidityIndex = dynamicData.liquidityIndex;
        allPoolData.variableBorrowIndex = dynamicData.variableBorrowIndex;
        allPoolData.lastUpdateTimestamp = dynamicData.lastUpdateTimestamp;
        allPoolData.interestRateStrategyAddress = dynamicData.interestRateStrategyAddress;
        allPoolData.id = dynamicData.id;
    }

    /**
     * @notice Retrieves static configuration data for a given reserve in the lending pool.
     * @param asset The address of the asset to retrieve data for
     * @param reserveType The type of reserve (true for type A, false for type B)
     * @return staticData Struct containing static reserve configuration data
     */
    function getLpReserveStaticData(address asset, bool reserveType)
        external
        view
        lendingPoolSet
        returns (StaticData memory staticData)
    {
        staticData = _getLpReserveStaticData(asset, reserveType);
    }

    function _getLpReserveStaticData(address asset, bool reserveType)
        internal
        view
        returns (StaticData memory staticData)
    {
        DataTypes.ReserveConfigurationMap memory configuration = ILendingPool(
            lendingPoolAddressProvider.getLendingPool()
        ).getConfiguration(asset, reserveType);

        (
            staticData.ltv,
            staticData.liquidationThreshold,
            staticData.liquidationBonus,
            staticData.decimals,
            staticData.cod3xReserveFactor,
            staticData.miniPoolOwnerReserveFactor,
            staticData.depositCap
        ) = configuration.getParamsMemory();

        (
            staticData.isActive,
            staticData.isFrozen,
            staticData.borrowingEnabled,
            staticData.flashloanEnabled
        ) = configuration.getFlagsMemory();
    }

    /**
     * @notice Retrieves dynamic reserve data for a given asset in the lending pool.
     * @param asset The address of the asset
     * @param reserveType The type of reserve (true for type A, false for type B)
     * @return dynamicData :
     * - availableLiquidity - Current liquidity available
     * - totalVariableDebt - Total outstanding variable debt
     * - liquidityRate - Current liquidity rate
     * - variableBorrowRate - Current variable borrow rate
     * - liquidityIndex - Current liquidity index
     * - variableBorrowIndex - Current variable borrow index
     * - lastUpdateTimestamp - Last timestamp of reserve data update
     */
    function getLpReserveDynamicData(address asset, bool reserveType)
        external
        view
        lendingPoolSet
        returns (DynamicData memory dynamicData)
    {
        dynamicData = _getLpReserveDynamicData(asset, reserveType);
    }

    function _getLpReserveDynamicData(address asset, bool reserveType)
        internal
        view
        returns (DynamicData memory dynamicData)
    {
        DataTypes.ReserveData memory reserve = ILendingPool(
            lendingPoolAddressProvider.getLendingPool()
        ).getReserveData(asset, reserveType);

        dynamicData.availableLiquidity = IERC20Detailed(asset).balanceOf(reserve.aTokenAddress);
        dynamicData.totalVariableDebt =
            IERC20Detailed(reserve.variableDebtTokenAddress).totalSupply();
        dynamicData.liquidityRate = reserve.currentLiquidityRate;
        dynamicData.variableBorrowRate = reserve.currentVariableBorrowRate;
        dynamicData.liquidityIndex = reserve.liquidityIndex;
        dynamicData.variableBorrowIndex = reserve.variableBorrowIndex;
        dynamicData.lastUpdateTimestamp = reserve.lastUpdateTimestamp;
        dynamicData.interestRateStrategyAddress = reserve.interestRateStrategyAddress;
        dynamicData.id = reserve.id;

        return dynamicData;
    }

    /**
     * @notice Retrieves the addresses of all aTokens and debt tokens in the lending pool.
     * @return aTokens Array of aToken addresses
     * @return debtTokens Array of debt token addresses
     */
    function getLpAllTokens()
        external
        view
        lendingPoolSet
        returns (address[] memory aTokens, address[] memory debtTokens)
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (address[] memory reserves, bool[] memory reserveTypes) = lendingPool.getReservesList();
        aTokens = new address[](reserves.length);
        debtTokens = new address[](reserves.length);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            (aTokens[idx], debtTokens[idx]) =
                _getLpTokens(reserves[idx], reserveTypes[idx], lendingPool);
        }
    }

    function getLpTokens(address asset, bool reserveType)
        external
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
     * @notice Retrieves user-specific reserve data in the lending pool.
     * @param user The address of the user
     */
    function getAllLpUserData(address user)
        external
        view
        lendingPoolSet
        returns (UserReserveData[] memory userReservesData)
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (address[] memory reserves, bool[] memory reserveTypes) = lendingPool.getReservesList();
        userReservesData = new UserReserveData[](user != address(0) ? reserves.length : 0);

        for (uint256 idx = 0; idx < reserves.length; idx++) {
            userReservesData[idx] =
                _getLpUserData(reserves[idx], reserveTypes[idx], user, lendingPool);
        }
    }

    /**
     * @notice Retrieves user-specific reserve data in the lending pool for specific asset.
     * @param asset Specified asset for which data should be retrieved
     * @param reserveType Type of reserve
     * @param user The address of the user
     */
    function getLpUserData(address asset, bool reserveType, address user)
        external
        view
        lendingPoolSet
        returns (UserReserveData memory userReservesData)
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        userReservesData = _getLpUserData(asset, reserveType, user, lendingPool);
    }

    /**
     * @notice Retrieves user-specific reserve data in the lending pool for specific asset.
     * @param asset Specified asset for which data should be retrieved
     * @param reserveType Type of reserve
     * @param user The address of the user
     * @param lendingPool Lending pool contract
     */
    function _getLpUserData(address asset, bool reserveType, address user, ILendingPool lendingPool)
        internal
        view
        returns (UserReserveData memory userReservesData)
    {
        DataTypes.UserConfigurationMap memory userConfig = lendingPool.getUserConfiguration(user);
        DataTypes.ReserveData memory data = lendingPool.getReserveData(asset, reserveType);
        userReservesData.aToken = data.aTokenAddress;
        userReservesData.debtToken = data.variableDebtTokenAddress;
        userReservesData.currentATokenBalance = IERC20Detailed(data.aTokenAddress).balanceOf(user);

        userReservesData.scaledATokenBalance = IAToken(data.aTokenAddress).scaledBalanceOf(user);
        userReservesData.usageAsCollateralEnabledOnUser = userConfig.isUsingAsCollateral(data.id);
        userReservesData.isBorrowing = userConfig.isBorrowing(data.id);
        if (userReservesData.isBorrowing) {
            userReservesData.currentVariableDebt =
                IERC20Detailed(data.variableDebtTokenAddress).balanceOf(user);
            userReservesData.scaledVariableDebt =
                IVariableDebtToken(data.variableDebtTokenAddress).scaledBalanceOf(user);
        }
    }

    /**
     * @notice Retrieves account summary data for a user in the lending pool.
     * @dev Idea is to have everything in the same contract, but the same function might be found in the LendingPool
     * @param user The address of the user
     * @return totalCollateralETH Total collateral in ETH
     * @return totalDebtETH Total debt in ETH
     * @return availableBorrowsETH Amount available to borrow in ETH
     * @return currentLiquidationThreshold Current liquidation threshold
     * @return ltv Current loan-to-value ratio
     * @return healthFactor Current health factor of user’s account
     */
    function getLpUserAccountData(address user)
        external
        view
        lendingPoolSet
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (
            totalCollateralETH,
            totalDebtETH,
            availableBorrowsETH,
            currentLiquidationThreshold,
            ltv,
            healthFactor
        ) = lendingPool.getUserAccountData(user);
    }

    /*------ Mini Pool data providers ------*/

    function getAllMpData(address asset, address miniPool)
        external
        view
        miniPoolSet
        returns (AllPoolData memory allPoolData)
    {
        allPoolData = _getAllMpData(asset, miniPool);
    }

    function getAllMpData(address asset, uint256 miniPoolId)
        external
        view
        miniPoolSet
        returns (AllPoolData memory allPoolData)
    {
        allPoolData = _getAllMpData(asset, miniPoolAddressProvider.getMiniPool(miniPoolId));
    }

    function _getAllMpData(address asset, address miniPool)
        internal
        view
        returns (AllPoolData memory allPoolData)
    {
        StaticData memory staticData = _getMpReserveStaticData(asset, miniPool);
        DynamicData memory dynamicData = _getMpReserveDynamicData(asset, miniPool);
        allPoolData.ltv = staticData.ltv;
        allPoolData.liquidationThreshold = staticData.liquidationThreshold;
        allPoolData.liquidationBonus = staticData.liquidationBonus;
        allPoolData.decimals = staticData.decimals;
        allPoolData.cod3xReserveFactor = staticData.cod3xReserveFactor;
        allPoolData.miniPoolOwnerReserveFactor = staticData.miniPoolOwnerReserveFactor;
        allPoolData.depositCap = staticData.depositCap;

        allPoolData.availableLiquidity = dynamicData.availableLiquidity;
        allPoolData.totalVariableDebt = dynamicData.totalVariableDebt;
        allPoolData.liquidityRate = dynamicData.liquidityRate;
        allPoolData.variableBorrowRate = dynamicData.variableBorrowRate;
        allPoolData.liquidityIndex = dynamicData.liquidityIndex;
        allPoolData.variableBorrowIndex = dynamicData.variableBorrowIndex;
        allPoolData.lastUpdateTimestamp = dynamicData.lastUpdateTimestamp;
        allPoolData.interestRateStrategyAddress = dynamicData.interestRateStrategyAddress;
        allPoolData.id = dynamicData.id;
    }

    /**
     * @notice Retrieves static configuration data for a given reserve in a mini pool.
     * @param asset The address of the asset to retrieve data for
     * @param miniPoolId The ID of the mini pool
     * @return staticData Struct containing static reserve configuration data
     */
    function getMpReserveStaticData(address asset, uint256 miniPoolId)
        external
        view
        miniPoolSet
        returns (StaticData memory staticData)
    {
        staticData = _getMpReserveStaticData(asset, miniPoolAddressProvider.getMiniPool(miniPoolId));
    }

    /**
     * @notice Retrieves static configuration data for a given reserve in a mini pool.
     * @param asset The address of the asset to retrieve data for
     * @param miniPool The address of the mini pool
     * @return staticData Struct containing static reserve configuration data
     */
    function getMpReserveStaticData(address asset, address miniPool)
        external
        view
        miniPoolSet
        returns (StaticData memory staticData)
    {
        staticData = _getMpReserveStaticData(asset, miniPool);
    }

    function _getMpReserveStaticData(address asset, address miniPool)
        internal
        view
        returns (StaticData memory staticData)
    {
        DataTypes.ReserveConfigurationMap memory configuration =
            IMiniPool(miniPool).getConfiguration(asset);

        (
            staticData.ltv,
            staticData.liquidationThreshold,
            staticData.liquidationBonus,
            staticData.decimals,
            staticData.cod3xReserveFactor,
            staticData.miniPoolOwnerReserveFactor,
            staticData.depositCap
        ) = configuration.getParamsMemory();

        (
            staticData.isActive,
            staticData.isFrozen,
            staticData.borrowingEnabled,
            staticData.flashloanEnabled
        ) = configuration.getFlagsMemory();
    }

    /**
     * @notice Retrieves dynamic reserve data for a given asset in a mini pool.
     * @param asset The address of the asset
     * @param miniPoolId The ID of the mini pool
     * @return dynamicData :
     * - availableLiquidity - Current liquidity available
     * - totalVariableDebt - Total outstanding variable debt
     * - liquidityRate - Current liquidity rate
     * - variableBorrowRate - Current variable borrow rate
     * - liquidityIndex - Current liquidity index
     * - variableBorrowIndex - Current variable borrow index
     * - lastUpdateTimestamp - Last timestamp of reserve data update
     */
    function getMpReserveDynamicData(address asset, uint256 miniPoolId)
        external
        view
        miniPoolSet
        returns (DynamicData memory dynamicData)
    {
        return _getMpReserveDynamicData(asset, miniPoolAddressProvider.getMiniPool(miniPoolId));
    }

    /**
     * @notice Retrieves dynamic reserve data for a given asset in a mini pool.
     * @param asset The address of the asset
     * @param miniPool The address of the mini pool
     * @return dynamicData :
     * - availableLiquidity - Current liquidity available
     * - totalVariableDebt - Total outstanding variable debt
     * - liquidityRate - Current liquidity rate
     * - variableBorrowRate - Current variable borrow rate
     * - liquidityIndex - Current liquidity index
     * - variableBorrowIndex - Current variable borrow index
     * - lastUpdateTimestamp - Last timestamp of reserve data update
     */
    function getMpReserveDynamicData(address asset, address miniPool)
        external
        view
        miniPoolSet
        returns (DynamicData memory dynamicData)
    {
        return _getMpReserveDynamicData(asset, miniPool);
    }

    function _getMpReserveDynamicData(address asset, address miniPool)
        internal
        view
        returns (DynamicData memory dynamicData)
    {
        (bool isReserveConfigured, DataTypes.MiniPoolReserveData memory reserve) =
            isMpReserveConfigured(asset, miniPool);

        require(isReserveConfigured, Errors.DP_RESERVE_NOT_CONFIGURED);

        dynamicData.availableLiquidity = IERC20Detailed(asset).balanceOf(reserve.aTokenAddress);
        dynamicData.totalVariableDebt =
            IAERC6909(reserve.aTokenAddress).scaledTotalSupply(reserve.variableDebtTokenID);
        dynamicData.liquidityRate = reserve.currentLiquidityRate;
        dynamicData.variableBorrowRate = reserve.currentVariableBorrowRate;
        dynamicData.liquidityIndex = reserve.liquidityIndex;
        dynamicData.variableBorrowIndex = reserve.variableBorrowIndex;
        dynamicData.lastUpdateTimestamp = reserve.lastUpdateTimestamp;
        dynamicData.interestRateStrategyAddress = reserve.interestRateStrategyAddress;
        dynamicData.id = reserve.id;

        return dynamicData;
    }

    /**
     * @dev Returns the addresses of multi tokens contracts, underlying reserves, aToken ids and debt token ids for a specific MiniPool.
     * @param miniPoolId The ID of the MiniPool from which the tokens are retrieved.
     * @return aErc6909Token An array of addresses of all multi tokens contracts in the MiniPool.
     * @return reserves An array of addresses of all underlying reserves in the MiniPool.
     * @return aTokenIds An array of IDs for all aTokens in the MiniPool.
     * @return variableDebtTokenIds An array of IDs for all variable debt tokens in the MiniPool.
     */
    function getMpAllTokenInfo(uint256 miniPoolId)
        external
        view
        miniPoolSet
        returns (
            address[] memory aErc6909Token,
            address[] memory reserves,
            uint256[] memory aTokenIds,
            uint256[] memory variableDebtTokenIds
        )
    {
        (aErc6909Token, reserves, aTokenIds, variableDebtTokenIds) =
            _getMpAllTokenInfo(miniPoolAddressProvider.getMiniPool(miniPoolId));
    }

    /**
     * @dev Returns the addresses of multi tokens contracts, underlying reserves, aToken ids and debt token ids for a specific MiniPool.
     * @param miniPool The address of the MiniPool from which the tokens are retrieved.
     * @return aErc6909Token An array of addresses of all multi tokens contracts in the MiniPool.
     * @return reserves An array of addresses of all underlying reserves in the MiniPool.
     * @return aTokenIds An array of IDs for all aTokens in the MiniPool.
     * @return variableDebtTokenIds An array of IDs for all variable debt tokens in the MiniPool.
     */
    function getMpAllTokenInfo(address miniPool)
        external
        view
        miniPoolSet
        returns (
            address[] memory aErc6909Token,
            address[] memory reserves,
            uint256[] memory aTokenIds,
            uint256[] memory variableDebtTokenIds
        )
    {
        (aErc6909Token, reserves, aTokenIds, variableDebtTokenIds) = _getMpAllTokenInfo(miniPool);
    }

    function _getMpAllTokenInfo(address miniPool)
        internal
        view
        returns (
            address[] memory aErc6909Token,
            address[] memory reserves,
            uint256[] memory aTokenIds,
            uint256[] memory variableDebtTokenIds
        )
    {
        IMiniPool miniPoolContract = IMiniPool(miniPool);
        (reserves,) = miniPoolContract.getReservesList();
        aErc6909Token = new address[](reserves.length);
        aTokenIds = new uint256[](reserves.length);
        variableDebtTokenIds = new uint256[](reserves.length);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            (bool isReserveConfigured, DataTypes.MiniPoolReserveData memory data) =
                isMpReserveConfigured(reserves[idx], address(miniPoolContract));
            require(isReserveConfigured, Errors.DP_RESERVE_NOT_CONFIGURED);
            aErc6909Token[idx] = data.aTokenAddress;
            aTokenIds[idx] = data.aTokenID;
            variableDebtTokenIds[idx] = data.variableDebtTokenID;
        }
    }

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param miniPool The address of the MiniPool from which the user's data is retrieved.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function getAllMpUserData(address user, address miniPool)
        external
        view
        miniPoolSet
        returns (MiniPoolUserReserveData[] memory userReservesData)
    {
        IMiniPool miniPoolContract = IMiniPool(miniPool);
        (address[] memory reserves,) = miniPoolContract.getReservesList();
        userReservesData = new MiniPoolUserReserveData[](user != address(0) ? reserves.length : 0);

        for (uint256 idx = 0; idx < reserves.length; idx++) {
            userReservesData[idx] = _getMpUserData(user, reserves[idx], miniPoolContract);
        }
    }

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param miniPoolId The ID of the MiniPool from which the user's data is retrieved.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function getAllMpUserData(address user, uint256 miniPoolId)
        external
        view
        miniPoolSet
        returns (MiniPoolUserReserveData[] memory userReservesData)
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId));
        (address[] memory reserves,) = miniPool.getReservesList();
        userReservesData = new MiniPoolUserReserveData[](user != address(0) ? reserves.length : 0);

        for (uint256 idx = 0; idx < reserves.length; idx++) {
            userReservesData[idx] = _getMpUserData(user, reserves[idx], miniPool);
        }
    }

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param miniPool The address of the MiniPool from which the user's data is retrieved.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function getMpUserData(address user, address miniPool, address reserve)
        external
        view
        miniPoolSet
        returns (MiniPoolUserReserveData memory userReservesData)
    {
        userReservesData = _getMpUserData(user, reserve, IMiniPool(miniPool));
    }

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param miniPoolId The ID of the MiniPool from which the user's data is retrieved.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function getMpUserData(address user, uint256 miniPoolId, address reserve)
        external
        view
        miniPoolSet
        returns (MiniPoolUserReserveData memory userReservesData)
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId));
        userReservesData = _getMpUserData(user, reserve, miniPool);
    }

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param reserve Reserve of the miniPool.
     * @param miniPool Mini pool contract.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function _getMpUserData(address user, address reserve, IMiniPool miniPool)
        internal
        view
        miniPoolSet
        returns (MiniPoolUserReserveData memory userReservesData)
    {
        DataTypes.UserConfigurationMap memory userConfig = miniPool.getUserConfiguration(user);

        (bool isReserveConfigured, DataTypes.MiniPoolReserveData memory data) =
            isMpReserveConfigured(reserve, address(miniPool));

        require(isReserveConfigured, Errors.DP_RESERVE_NOT_CONFIGURED);

        userReservesData.aErc6909Token = data.aTokenAddress;
        userReservesData.aTokenId = data.aTokenID;
        userReservesData.debtTokenId = data.variableDebtTokenID;
        (userReservesData.scaledATokenBalance,) =
            IAERC6909(data.aTokenAddress).getScaledUserBalanceAndSupply(user, data.aTokenID);
        userReservesData.usageAsCollateralEnabledOnUser = userConfig.isUsingAsCollateral(data.id);
        userReservesData.isBorrowing = userConfig.isBorrowing(data.id);
        if (userReservesData.isBorrowing) {
            (userReservesData.scaledVariableDebt,) = IAERC6909(data.aTokenAddress)
                .getScaledUserBalanceAndSupply(user, data.variableDebtTokenID);
        }
    }

    /**
     * @notice Returns the overall account data for a user in a specified MiniPool.
     *      Includes metrics such as collateral, debt, borrowing power, and health factor.
     * @dev Idea is to have everything in the same contract, but the same function might be found in the LendingPool
     * @param user The address of the user for whom the account data is retrieved.
     * @param miniPool The address of the MiniPool from which the user's account data is retrieved.
     * @return totalCollateralETH The total collateral amount in ETH.
     * @return totalDebtETH The total debt amount in ETH.
     * @return availableBorrowsETH The amount available for borrowing in ETH.
     * @return currentLiquidationThreshold The current liquidation threshold as a percentage.
     * @return ltv The current loan-to-value (LTV) ratio for the user's account.
     * @return healthFactor The current health factor of the user's account.
     */
    function getMpUserAccountData(address user, address miniPool)
        external
        view
        miniPoolSet
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        IMiniPool miniPoolContract = IMiniPool(miniPool);
        (
            totalCollateralETH,
            totalDebtETH,
            availableBorrowsETH,
            currentLiquidationThreshold,
            ltv,
            healthFactor
        ) = miniPoolContract.getUserAccountData(user);
    }

    /**
     * @notice Returns the overall account data for a user in a specified MiniPool.
     *      Includes metrics such as collateral, debt, borrowing power, and health factor.
     * @dev Idea is to have everything in the same contract, but the same function might be found in the LendingPool
     * @param user The address of the user for whom the account data is retrieved.
     * @param miniPoolId The ID of the MiniPool from which the user's account data is retrieved.
     * @return totalCollateralETH The total collateral amount in ETH.
     * @return totalDebtETH The total debt amount in ETH.
     * @return availableBorrowsETH The amount available for borrowing in ETH.
     * @return currentLiquidationThreshold The current liquidation threshold as a percentage.
     * @return ltv The current loan-to-value (LTV) ratio for the user's account.
     * @return healthFactor The current health factor of the user's account.
     */
    function getMpUserAccountData(address user, uint256 miniPoolId)
        external
        view
        miniPoolSet
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId));
        (
            totalCollateralETH,
            totalDebtETH,
            availableBorrowsETH,
            currentLiquidationThreshold,
            ltv,
            healthFactor
        ) = miniPool.getUserAccountData(user);
    }

    /**
     * @dev Returns the underlying balance of a specified ERC6909 token ID across all MiniPools.
     * @param tokenId The ID of the ERC6909 token for which the underlying balance is being calculated.
     * @return underlyingBalance The total underlying balance of the specified token across all MiniPools.
     */
    function getAllMpUnderlyingBalanceOf(uint256 tokenId)
        external
        view
        miniPoolSet
        returns (uint256 underlyingBalance)
    {
        uint256 miniPoolCount = miniPoolAddressProvider.getMiniPoolCount();
        for (uint256 miniPoolId = 0; miniPoolId < miniPoolCount; miniPoolId++) {
            underlyingBalance += getMpUnderlyingBalanceOf(tokenId, miniPoolId);
        }
    }

    /**
     * @dev Returns the underlying balance of a specified ERC6909 token in a MiniPool.
     * @param tokenId The ID of the ERC6909 token for which the balance is calculated.
     * @param miniPool The address of the MiniPool where the token's balance is calculated.
     * @return underlyingBalance The underlying balance of the specified token in the specified MiniPool.
     */
    function getMpUnderlyingBalanceOf(uint256 tokenId, address miniPool)
        public
        view
        miniPoolSet
        returns (uint256 underlyingBalance)
    {
        IAERC6909 aErc6909Token = IAERC6909(miniPoolAddressProvider.getMiniPoolToAERC6909(miniPool));
        underlyingBalance = IERC20Detailed(aErc6909Token.getUnderlyingAsset(tokenId)).balanceOf(
            address(aErc6909Token)
        );
    }

    /**
     * @dev Returns the underlying balance of a specified ERC6909 token in a MiniPool.
     * @param tokenId The ID of the ERC6909 token for which the balance is calculated.
     * @param miniPoolId The ID of the MiniPool where the token's balance is calculated.
     * @return underlyingBalance The underlying balance of the specified token in the specified MiniPool.
     */
    function getMpUnderlyingBalanceOf(uint256 tokenId, uint256 miniPoolId)
        public
        view
        miniPoolSet
        returns (uint256 underlyingBalance)
    {
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolAddressProvider.getMiniPoolToAERC6909(miniPoolId));
        underlyingBalance = IERC20Detailed(aErc6909Token.getUnderlyingAsset(tokenId)).balanceOf(
            address(aErc6909Token)
        );
    }

    /**
     * @dev Returns the address of the underlying asset for a specified ERC6909 token in a MiniPool.
     * @param tokenId The ID of the ERC6909 token for which the underlying asset address is retrieved.
     * @param miniPool The address of the MiniPool where the token's underlying asset is located.
     * @return underlyingAsset The address of the underlying asset.
     */
    function getUnderlyingAssetFromId(uint256 tokenId, address miniPool)
        external
        view
        miniPoolSet
        returns (address underlyingAsset)
    {
        IAERC6909 aErc6909Token = IAERC6909(miniPoolAddressProvider.getMiniPoolToAERC6909(miniPool));
        return aErc6909Token.getUnderlyingAsset(tokenId);
    }

    /**
     * @dev Returns the address of the underlying asset for a specified ERC6909 token in a MiniPool.
     * @param tokenId The ID of the ERC6909 token for which the underlying asset address is retrieved.
     * @param miniPoolId The ID of the MiniPool where the token's underlying asset is located.
     * @return underlyingAsset The address of the underlying asset.
     */
    function getUnderlyingAssetFromId(uint256 tokenId, uint256 miniPoolId)
        external
        view
        miniPoolSet
        returns (address underlyingAsset)
    {
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolAddressProvider.getMiniPoolToAERC6909(miniPoolId));
        return aErc6909Token.getUnderlyingAsset(tokenId);
    }

    /**
     * @dev Returns MiniPool addresses and IDs that support a given reserve.
     * @param reserve The address of the reserve to check for availability in MiniPools.
     * @return miniPools An array of addresses of MiniPools that contain the specified reserve.
     * @return miniPoolIds An array of IDs corresponding to MiniPools that contain the specified reserve.
     */
    function getMiniPoolsWithReserve(address reserve)
        external
        view
        miniPoolSet
        returns (address[] memory miniPools, uint256[] memory miniPoolIds)
    {
        uint256 miniPoolCount = miniPoolAddressProvider.getMiniPoolCount();
        address[] memory tmpMiniPools = new address[](miniPoolCount);
        uint256[] memory tmpMiniPoolIds = new uint256[](miniPoolCount);
        uint256 length = 0;
        /* Go through all mini pools and check whether reserve exists there */
        for (uint256 miniPoolId = 0; miniPoolId < miniPoolCount; miniPoolId++) {
            (bool isReserveAvailable, address miniPool) = isReserveInMiniPool(reserve, miniPoolId);
            if (isReserveAvailable == true) {
                tmpMiniPools[length] = miniPool;
                tmpMiniPoolIds[length] = miniPoolId;
                length++;
            }
        }
        /* Assign to the return arrays proper lengths */
        miniPools = new address[](length);
        miniPoolIds = new uint256[](length);
        /* Copy data from temporary array */
        for (uint256 idx = 0; idx < length; idx++) {
            miniPools[idx] = tmpMiniPools[idx];
            miniPoolIds[idx] = tmpMiniPoolIds[idx];
        }
    }

    /**
     * @dev Gets remaining flow from main pool for specified mini pool.
     * @param asset The address of the reserve to check for availability.
     * @param miniPool The address of the MiniPool where the reserve's availability is checked.
     * @return remainingFlow The address of the MiniPool being checked.
     */
    function getMpRemainingFlow(address asset, address miniPool)
        external
        view
        returns (uint256 remainingFlow)
    {
        IFlowLimiter flowLimiter = IFlowLimiter(miniPoolAddressProvider.getFlowLimiter());
        remainingFlow =
            flowLimiter.getFlowLimit(asset, miniPool) - flowLimiter.currentFlow(asset, miniPool);
    }

    /**
     * @dev Checks if a given reserve is available in a specific MiniPool.
     * @param reserve The address of the reserve to check for availability.
     * @param miniPoolId The ID of the MiniPool where the reserve's availability is checked.
     * @return isReserveAvailable True if the reserve is available in the MiniPool, false otherwise.
     * @return miniPool The address of the MiniPool being checked.
     */
    function isReserveInMiniPool(address reserve, uint256 miniPoolId)
        public
        view
        miniPoolSet
        returns (bool isReserveAvailable, address miniPool)
    {
        isReserveAvailable = false;
        miniPool = miniPoolAddressProvider.getMiniPool(miniPoolId);
        (address[] memory reserves,) = IMiniPool(miniPool).getReservesList();
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            if (reserves[idx] == reserve) {
                isReserveAvailable = true;
            }
        }
    }

    /**
     * @dev Checks if a given reserve is configured in a specific MiniPool.
     * @param reserve The address of the reserve to check for availability.
     * @param miniPool address of the minipool
     * @return isConfigured True if the reserve is configured in the MiniPool, false otherwise.
     * @return data reserve mini pool data.
     */
    function isMpReserveConfigured(address reserve, address miniPool)
        public
        view
        returns (bool isConfigured, DataTypes.MiniPoolReserveData memory data)
    {
        data = IMiniPool(miniPool).getReserveData(reserve);
        return ((data.aTokenAddress == address(0) ? false : true), data);
    }

    /* Copied from previous UI provider */
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
