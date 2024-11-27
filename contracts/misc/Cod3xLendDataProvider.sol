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
import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";

import {IMiniPoolAddressesProvider} from "../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPool} from "../../contracts/interfaces/IMiniPool.sol";

import {IAERC6909} from "../../contracts/interfaces/IAERC6909.sol";
import {Ownable} from "../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {Errors} from "../../contracts/protocol/libraries/helpers/Errors.sol";
import {IFlowLimiter} from "../../contracts/interfaces/IFlowLimiter.sol";

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
    uint256 decimals;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    uint256 cod3xReserveFactor;
    uint256 miniPoolOwnerReserveFactor;
    uint256 depositCap;
    bool borrowingEnabled;
    bool flashloanEnabled;
    bool isActive;
    bool isFrozen;
}

/**
 * @title Cod3xLendDataProvider
 * @dev This contract provides data access functions for lending pool and minipool information.
 * It retrieves static and dynamic configurations, user data, and token addresses from both types of pools.
 * @author Cod3x
 */
contract Cod3xLendDataProvider is Ownable {
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
     * @return availableLiquidity Current liquidity available
     * @return totalVariableDebt Total outstanding variable debt
     * @return liquidityRate Current liquidity rate
     * @return variableBorrowRate Current variable borrow rate
     * @return liquidityIndex Current liquidity index
     * @return variableBorrowIndex Current variable borrow index
     * @return lastUpdateTimestamp Last timestamp of reserve data update
     */
    function getLpReserveDynamicData(address asset, bool reserveType)
        external
        view
        lendingPoolSet
        returns (
            uint256 availableLiquidity,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        )
    {
        DataTypes.ReserveData memory reserve = ILendingPool(
            lendingPoolAddressProvider.getLendingPool()
        ).getReserveData(asset, reserveType);

        return (
            IERC20Detailed(asset).balanceOf(reserve.aTokenAddress),
            IERC20Detailed(reserve.variableDebtTokenAddress).totalSupply(),
            reserve.currentLiquidityRate,
            reserve.currentVariableBorrowRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex,
            reserve.lastUpdateTimestamp
        );
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
                getLpUserData(reserves[idx], reserveTypes[idx], user, lendingPool);
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
        userReservesData = getLpUserData(asset, reserveType, user, lendingPool);
    }

    /**
     * @notice Retrieves user-specific reserve data in the lending pool for specific asset.
     * @param asset Specified asset for which data should be retrieved
     * @param reserveType Type of reserve
     * @param user The address of the user
     * @param lendingPool Lending pool contract
     */
    function getLpUserData(address asset, bool reserveType, address user, ILendingPool lendingPool)
        internal
        view
        lendingPoolSet
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
        DataTypes.ReserveConfigurationMap memory configuration =
            IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId)).getConfiguration(asset);

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
     * @return availableLiquidity Current liquidity available
     * @return totalVariableDebt Total outstanding variable debt
     * @return liquidityRate Current liquidity rate
     * @return variableBorrowRate Current variable borrow rate
     * @return liquidityIndex Current liquidity index
     * @return variableBorrowIndex Current variable borrow index
     * @return lastUpdateTimestamp Last timestamp of reserve data update
     */
    function getMpReserveDynamicData(address asset, uint256 miniPoolId)
        external
        view
        miniPoolSet
        returns (
            uint256 availableLiquidity,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        )
    {
        DataTypes.MiniPoolReserveData memory reserve =
            IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId)).getReserveData(asset);

        return (
            IERC20Detailed(asset).balanceOf(reserve.aTokenAddress), // or scaledTotalSupply ?
            IAERC6909(reserve.aTokenAddress).scaledTotalSupply(reserve.variableDebtTokenID),
            reserve.currentLiquidityRate,
            reserve.currentVariableBorrowRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex,
            reserve.lastUpdateTimestamp
        );
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
        IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId));
        (reserves,) = miniPool.getReservesList();
        aErc6909Token = new address[](reserves.length);
        aTokenIds = new uint256[](reserves.length);
        variableDebtTokenIds = new uint256[](reserves.length);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            DataTypes.MiniPoolReserveData memory data = miniPool.getReserveData(reserves[idx]);
            aErc6909Token[idx] = data.aTokenAddress;
            aTokenIds[idx] = data.aTokenID;
            variableDebtTokenIds[idx] = data.variableDebtTokenID;
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

        DataTypes.MiniPoolReserveData memory data = miniPool.getReserveData(reserve);
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
     * @dev Checks if a given reserve is available in a specific MiniPool.
     * @param asset The address of the reserve to check for availability.
     * @param miniPoolId The ID of the MiniPool where the reserve's availability is checked.
     * @return remainingFlow The address of the MiniPool being checked.
     */
    function getMpRemainingFlow(address asset, uint256 miniPoolId)
        external
        view
        returns (uint256 remainingFlow)
    {
        address miniPool = miniPoolAddressProvider.getMiniPool(miniPoolId);
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
