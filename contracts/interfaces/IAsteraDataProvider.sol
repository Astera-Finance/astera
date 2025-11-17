// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";

struct UserReserveData {
    address aToken;
    address debtToken;
    uint256 currentATokenBalance;
    uint256 currentVariableDebt;
    uint256 scaledATokenBalance;
    uint256 scaledVariableDebt;
    bool usageAsCollateralEnabledOnUser;
    bool isBorrowing;
}

struct MiniPoolUserReserveData {
    address aErc6909Token;
    uint256 aTokenId;
    uint256 debtTokenId;
    uint256 scaledATokenBalance;
    uint256 scaledVariableDebt;
    bool usageAsCollateralEnabledOnUser;
    bool isBorrowing;
}

struct StaticData {
    string symbol;
    uint256 decimals;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    uint256 asteraReserveFactor;
    uint256 miniPoolOwnerReserveFactor;
    uint256 depositCap;
    bool borrowingEnabled;
    bool flashloanEnabled;
    bool isActive;
    bool isFrozen;
    bool usageAsCollateralEnabled;
}

struct DynamicData {
    address interestRateStrategyAddress;
    uint256 availableLiquidity;
    uint256 totalVariableDebt;
    uint256 liquidityRate;
    uint256 variableBorrowRate;
    uint256 liquidityIndex;
    uint256 variableBorrowIndex;
    uint256 priceInMarketReferenceCurrency;
    uint40 lastUpdateTimestamp;
    uint8 id;
}

struct BaseCurrencyInfo {
    uint256 marketReferenceCurrencyUnit;
    int256 marketReferenceCurrencyPriceInUsd;
    int256 networkBaseTokenPriceInUsd;
    uint8 networkBaseTokenPriceDecimals;
}

struct AllLpPoolData {
    string symbol;
    address reserve;
    address aToken;
    address debtToken;
    address interestRateStrategyAddress;
    uint256 decimals;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    uint256 asteraReserveFactor;
    uint256 miniPoolOwnerReserveFactor;
    uint256 depositCap;
    uint256 availableLiquidity;
    uint256 totalVariableDebt;
    uint256 liquidityRate;
    uint256 variableBorrowRate;
    uint256 liquidityIndex;
    uint256 variableBorrowIndex;
    uint256 priceInMarketReferenceCurrency;
    uint40 lastUpdateTimestamp;
    uint8 id;
    bool reserveType;
    bool borrowingEnabled;
    bool flashloanEnabled;
    bool isActive;
    bool isFrozen;
    bool usageAsCollateralEnabled;
}

struct AllMpPoolData {
    string symbol;
    address aErc6909Token;
    address reserve;
    address interestRateStrategyAddress;
    uint256 aTokenId;
    uint256 variableDebtTokenId;
    uint256 decimals;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    uint256 asteraReserveFactor;
    uint256 miniPoolOwnerReserveFactor;
    uint256 depositCap;
    uint256 availableLiquidity;
    uint256 totalVariableDebt;
    uint256 liquidityRate;
    uint256 variableBorrowRate;
    uint256 liquidityIndex;
    uint256 variableBorrowIndex;
    uint256 priceInMarketReferenceCurrency;
    uint40 lastUpdateTimestamp;
    uint8 id;
    bool borrowingEnabled;
    bool flashloanEnabled;
    bool isActive;
    bool isFrozen;
    bool usageAsCollateralEnabled;
}

interface IAsteraDataProvider {
    /*------ Only Owner ------*/
    function setLendingPoolAddressProvider(address _lendingPoolAddressProvider) external;
    function setMiniPoolAddressProvider(address _miniPoolAddressProvider) external;

    /* -------------- Lending Pool providers--------------*/
    /**
     * @notice Retrieves all data for a given asset in a main pool.
     * @return allLpPoolDataList all data related to main pool
     */
    function getAllLpData() external view returns (AllLpPoolData[] memory allLpPoolDataList);

    /**
     * @notice Retrieves static configuration data for a given reserve in the lending pool.
     * @param asset The address of the asset to retrieve data for
     * @param reserveType The type of reserve
     * @return staticData Struct containing static reserve configuration data
     */
    function getLpReserveStaticData(address asset, bool reserveType)
        external
        view
        returns (StaticData memory staticData);

    /**
     * @notice Retrieves dynamic reserve data for a given asset in the lending pool.
     * @param asset The address of the asset
     * @param reserveType The type of reserve
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
        returns (DynamicData memory dynamicData);

    /**
     * @notice Retrieves the addresses of all aTokens and debt tokens in the lending pool.
     * @return reserves Array of pool reserves
     * @return reserveTypes Array of the reserve types
     * @return aTokens Array of aToken addresses
     * @return debtTokens Array of debt token addresses
     */
    function getAllLpTokens()
        external
        view
        returns (
            address[] memory reserves,
            bool[] memory reserveTypes,
            address[] memory aTokens,
            address[] memory debtTokens
        );

    function getLpTokens(address asset, bool reserveType)
        external
        view
        returns (address aToken, address debtToken);

    /**
     * @notice Retrieves user-specific reserve data in the lending pool.
     * @param user The address of the user
     */
    function getAllLpUserData(address user)
        external
        view
        returns (UserReserveData[] memory userReservesData);

    /**
     * @notice Retrieves user-specific reserve data in the lending pool for specific asset.
     * @param asset Specified asset for which data should be retrieved
     * @param reserveType Type of reserve
     * @param user The address of the user
     */
    function getLpUserData(address asset, bool reserveType, address user)
        external
        view
        returns (UserReserveData memory userReservesData);

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
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /*------ Mini Pool data providers ------*/
    /**
     * @notice Retrieves dynamic reserve data for a given asset in a mini pool.
     * @param miniPool The address of the mini pool
     * @return allMpPoolDataList all data related to mini pool
     */
    function getAllMpData(address miniPool)
        external
        view
        returns (AllMpPoolData[] memory allMpPoolDataList);

    /**
     * @notice Retrieves dynamic reserve data for a given asset in a mini pool.
     * @param miniPoolId The ID of the mini pool
     * @return allMpPoolDataList all data related to mini pool
     */
    function getAllMpData(uint256 miniPoolId)
        external
        view
        returns (AllMpPoolData[] memory allMpPoolDataList);

    /**
     * @notice Retrieves static configuration data for a given reserve in a mini pool.
     * @param asset The address of the asset to retrieve data for
     * @param miniPoolId The ID of the mini pool
     * @return staticData Struct containing static reserve configuration data
     */
    function getMpReserveStaticData(address asset, uint256 miniPoolId)
        external
        view
        returns (StaticData memory staticData);

    /**
     * @notice Retrieves static configuration data for a given reserve in a mini pool.
     * @param asset The address of the asset to retrieve data for
     * @param miniPool The address of the mini pool
     * @return staticData Struct containing static reserve configuration data
     */
    function getMpReserveStaticData(address asset, address miniPool)
        external
        view
        returns (StaticData memory staticData);

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
        returns (DynamicData memory dynamicData);

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
        returns (DynamicData memory dynamicData);

    /**
     * @dev Returns the addresses of multi tokens contracts, underlying reserves, aToken ids and debt token ids for a specific MiniPool.
     * @param miniPool The address of the MiniPool from which the tokens are retrieved.
     * @return aErc6909Token An array of addresses of all multi tokens contracts in the MiniPool.
     * @return reserves An array of addresses of all underlying reserves in the MiniPool.
     * @return aTokenIds An array of IDs for all aTokens in the MiniPool.
     * @return variableDebtTokenIds An array of IDs for all variable debt tokens in the MiniPool.
     */
    function getAllMpTokenInfo(address miniPool)
        external
        view
        returns (
            address[] memory aErc6909Token,
            address[] memory reserves,
            uint256[] memory aTokenIds,
            uint256[] memory variableDebtTokenIds
        );

    /**
     * @dev Returns the addresses of multi tokens contracts, underlying reserves, aToken ids and debt token ids for a specific MiniPool.
     * @param miniPoolId The ID of the MiniPool from which the tokens are retrieved.
     * @return aErc6909Token An array of addresses of all multi tokens contracts in the MiniPool.
     * @return reserves An array of addresses of all underlying reserves in the MiniPool.
     * @return aTokenIds An array of IDs for all aTokens in the MiniPool.
     * @return variableDebtTokenIds An array of IDs for all variable debt tokens in the MiniPool.
     */
    function getAllMpTokenInfo(uint256 miniPoolId)
        external
        view
        returns (
            address[] memory aErc6909Token,
            address[] memory reserves,
            uint256[] memory aTokenIds,
            uint256[] memory variableDebtTokenIds
        );

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param miniPool The address of the MiniPool from which the user's data is retrieved.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function getAllMpUserData(address user, address miniPool)
        external
        view
        returns (MiniPoolUserReserveData[] memory userReservesData);

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param miniPoolId The ID of the MiniPool from which the user's data is retrieved.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function getAllMpUserData(address user, uint256 miniPoolId)
        external
        view
        returns (MiniPoolUserReserveData[] memory userReservesData);

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param miniPool The address of the MiniPool from which the user's data is retrieved.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function getMpUserData(address user, address miniPool, address reserve)
        external
        view
        returns (MiniPoolUserReserveData memory userReservesData);

    /**
     * @dev Returns all aToken and debt token data and balances for a user in a specified MiniPool.
     * @param user The address of the user for whom the data is being retrieved.
     * @param miniPoolId The ID of the MiniPool from which the user's data is retrieved.
     * @return userReservesData An array of `MiniPoolUserReserveData` structures containing the user's reserve data.
     */
    function getMpUserData(address user, uint256 miniPoolId, address reserve)
        external
        view
        returns (MiniPoolUserReserveData memory userReservesData);

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
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

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
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /**
     * @dev Returns the underlying balance of a specified ERC6909 token ID across all MiniPools.
     * @param tokenId The ID of the ERC6909 token for which the underlying balance is being calculated.
     * @return underlyingBalance The total underlying balance of the specified token across all MiniPools.
     */
    function getAllMpUnderlyingBalanceOf(uint256 tokenId)
        external
        view
        returns (uint256 underlyingBalance);

    /**
     * @dev Returns the underlying balance of a specified ERC6909 token in a MiniPool.
     * @param tokenId The ID of the ERC6909 token for which the balance is calculated.
     * @param miniPool The address of the MiniPool where the token's balance is calculated.
     * @return underlyingBalance The underlying balance of the specified token in the specified MiniPool.
     */
    function getMpUnderlyingBalanceOf(uint256 tokenId, address miniPool)
        external
        view
        returns (uint256 underlyingBalance);

    /**
     * @dev Returns the underlying balance of a specified ERC6909 token in a MiniPool.
     * @param tokenId The ID of the ERC6909 token for which the balance is calculated.
     * @param miniPoolId The ID of the MiniPool where the token's balance is calculated.
     * @return underlyingBalance The underlying balance of the specified token in the specified MiniPool.
     */
    function getMpUnderlyingBalanceOf(uint256 tokenId, uint256 miniPoolId)
        external
        view
        returns (uint256 underlyingBalance);

    /**
     * @dev Returns the address of the underlying asset for a specified ERC6909 token in a MiniPool.
     * @param tokenId The ID of the ERC6909 token for which the underlying asset address is retrieved.
     * @param miniPool The address of the MiniPool where the token's underlying asset is located.
     * @return underlyingAsset The address of the underlying asset.
     */
    function getUnderlyingAssetFromId(uint256 tokenId, address miniPool)
        external
        view
        returns (address underlyingAsset);

    /**
     * @dev Returns the address of the underlying asset for a specified ERC6909 token in a MiniPool.
     * @param tokenId The ID of the ERC6909 token for which the underlying asset address is retrieved.
     * @param miniPoolId The ID of the MiniPool where the token's underlying asset is located.
     * @return underlyingAsset The address of the underlying asset.
     */
    function getUnderlyingAssetFromId(uint256 tokenId, uint256 miniPoolId)
        external
        view
        returns (address underlyingAsset);

    /**
     * @dev Returns MiniPool addresses and IDs that support a given reserve.
     * @param reserve The address of the reserve to check for availability in MiniPools.
     * @return miniPools An array of addresses of MiniPools that contain the specified reserve.
     * @return miniPoolIds An array of IDs corresponding to MiniPools that contain the specified reserve.
     */
    function getMiniPoolsWithReserve(address reserve)
        external
        view
        returns (address[] memory miniPools, uint256[] memory miniPoolIds);

    /**
     * @dev Gets remaining flow from main pool for specified mini pool.
     * @param asset The address of the reserve to check for availability.
     * @param miniPool The address of the MiniPool where the reserve's availability is checked.
     * @return remainingFlow The address of the MiniPool being checked.
     */
    function getMpRemainingFlow(address asset, address miniPool)
        external
        view
        returns (uint256 remainingFlow);

    /**
     * @dev Checks if a given reserve is available in a specific MiniPool.
     * @param reserve The address of the reserve to check for availability.
     * @param miniPoolId The ID of the MiniPool where the reserve's availability is checked.
     * @return isReserveAvailable True if the reserve is available in the MiniPool, false otherwise.
     * @return miniPool The address of the MiniPool being checked.
     */
    function isReserveInMiniPool(address reserve, uint256 miniPoolId)
        external
        view
        returns (bool isReserveAvailable, address miniPool);

    /**
     * @dev Checks if a given reserve is configured in a specific MiniPool.
     * @param reserve The address of the reserve to check for availability.
     * @param miniPool address of the minipool
     * @return isConfigured True if the reserve is configured in the MiniPool, false otherwise.
     * @return data reserve mini pool data.
     */
    function isMpReserveConfigured(address reserve, address miniPool)
        external
        view
        returns (bool isConfigured, DataTypes.MiniPoolReserveData memory data);

    function getBaseCurrencyInfo()
        external
        view
        returns (BaseCurrencyInfo memory baseCurrencyInfo);
}
