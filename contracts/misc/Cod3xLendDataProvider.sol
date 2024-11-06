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

import "forge-std/console.sol";

struct UserReserveData {
    address aToken;
    address debtToken;
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

/**
 * @title Cod3xLendDataProvider
 * @author Cod3x
 */
contract Cod3xLendDataProvider {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    ILendingPoolAddressesProvider public immutable lendingPoolAddressProvider;
    IMiniPoolAddressesProvider public immutable miniPoolAddressProvider;

    constructor(
        ILendingPoolAddressesProvider _lendingPoolAddressProvider,
        IMiniPoolAddressesProvider _miniPoolAddressProvider
    ) {
        lendingPoolAddressProvider = _lendingPoolAddressProvider;
        miniPoolAddressProvider = _miniPoolAddressProvider;
    }

    /*------ Lending Pool data providers ------*/

    struct StaticData {
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
        uint256 depositCap;
        bool borrowingEnabled;
        bool flashloanEnabled;
        bool isActive;
        bool isFrozen;
    }

    /**
     * @dev Returns all Lendingpool configuration data for reserve
     */
    function getLpReserveStaticData(address asset, bool reserveType)
        external
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
            staticData.reserveFactor,
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
     * @dev Returns all Lendingpool configuration data and state
     */
    function getLpData() external view {}

    /**
     * @dev Returns all Lendingpool reserve dynamic data
     */
    function getLpReserveDynamicData(address asset, bool reserveType)
        external
        view
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
     * @dev Returns all aTokens + debtTokens addresses
     */
    function getLpAllTokens()
        external
        view
        returns (address[] memory aTokens, address[] memory debtTokens)
    {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (address[] memory reserves, bool[] memory reserveTypes) = lendingPool.getReservesList();
        aTokens = new address[](reserves.length);
        debtTokens = new address[](reserves.length);
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            DataTypes.ReserveData memory data =
                lendingPool.getReserveData(reserves[idx], reserveTypes[idx]);
            aTokens[idx] = data.aTokenAddress;
            debtTokens[idx] = data.variableDebtTokenAddress;
        }
    }

    /**
     * @dev Returns all user aTokens + debtTokens addresses and balances
     */
    function getLpUserData(address user) external view {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddressProvider.getLendingPool());
        (address[] memory reserves, bool[] memory reserveTypes) = lendingPool.getReservesList();
        UserReserveData[] memory userReservesData =
            new UserReserveData[](user != address(0) ? reserves.length : 0);
        DataTypes.UserConfigurationMap memory userConfig = lendingPool.getUserConfiguration(user);

        for (uint256 idx = 0; idx < reserves.length; idx++) {
            DataTypes.ReserveData memory data =
                lendingPool.getReserveData(reserves[idx], reserveTypes[idx]);
            userReservesData[idx].aToken = data.aTokenAddress;
            userReservesData[idx].debtToken = data.variableDebtTokenAddress;
            userReservesData[idx].scaledATokenBalance =
                IAToken(data.aTokenAddress).scaledBalanceOf(user);
            userReservesData[idx].usageAsCollateralEnabledOnUser =
                userConfig.isUsingAsCollateral(data.id);
            userReservesData[idx].isBorrowing = userConfig.isBorrowing(data.id);
            if (userReservesData[idx].isBorrowing) {
                userReservesData[idx].scaledVariableDebt =
                    IVariableDebtToken(data.variableDebtTokenAddress).scaledBalanceOf(user);
            }
        }
    }

    /* Idea is to have everything in the same contract, but the same function might be found in the LendingPool */
    function getLpUserAccountData(address user)
        public
        view
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
     * @dev Returns all Mini pool configuration data for reserve
     */
    function getMpReserveStaticData(address asset, uint256 miniPoolId)
        external
        view
        returns (StaticData memory staticData)
    {
        DataTypes.ReserveConfigurationMap memory configuration =
            IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId)).getConfiguration(asset);

        (
            staticData.ltv,
            staticData.liquidationThreshold,
            staticData.liquidationBonus,
            staticData.decimals,
            staticData.reserveFactor,
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
     * @dev Returns all MiniPool configuration data and state
     */
    function getMpData() external view {}

    /**
     * @dev Returns all MiniPool reserve configuration data and state
     */
    function getMpReserveDynamicData(address asset, uint256 miniPoolId)
        external
        view
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

        console.log("Total balance: ", IERC20Detailed(asset).balanceOf(reserve.aTokenAddress));
        console.log(
            "Total balance by ID: ",
            IAERC6909(reserve.aTokenAddress).scaledTotalSupply(reserve.aTokenID)
        );

        return (
            IERC20Detailed(asset).balanceOf(reserve.aTokenAddress),
            IAERC6909(reserve.aTokenAddress).scaledTotalSupply(reserve.variableDebtTokenID),
            reserve.currentLiquidityRate,
            reserve.currentVariableBorrowRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex,
            reserve.lastUpdateTimestamp
        );
    }

    /**
     * @dev Returns return all aTokens + debtTokens addresses
     */
    function getMpAllTokenIds(uint256 miniPoolId)
        external
        view
        returns (
            address[] memory aErc6909Token,
            uint256[] memory aTokenIds,
            uint256[] memory variableDebtTokenIds
        )
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId));
        (address[] memory reserves,) = miniPool.getReservesList();
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
     * @dev Returns all user aTokens + debtTokens addresses and balances
     */
    function getMpUserData(address user, uint256 miniPoolId)
        external
        view
        returns (MiniPoolUserReserveData[] memory userReservesData)
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId));
        (address[] memory reserves,) = miniPool.getReservesList();
        userReservesData = new MiniPoolUserReserveData[](user != address(0) ? reserves.length : 0);
        DataTypes.UserConfigurationMap memory userConfig = miniPool.getUserConfiguration(user);

        for (uint256 idx = 0; idx < reserves.length; idx++) {
            DataTypes.MiniPoolReserveData memory data = miniPool.getReserveData(reserves[idx]);
            userReservesData[idx].aErc6909Token = data.aTokenAddress;
            userReservesData[idx].aTokenId = data.aTokenID;
            userReservesData[idx].debtTokenId = data.variableDebtTokenID;
            (userReservesData[idx].scaledATokenBalance,) =
                IAERC6909(data.aTokenAddress).getScaledUserBalanceAndSupply(user, data.aTokenID);
            userReservesData[idx].usageAsCollateralEnabledOnUser =
                userConfig.isUsingAsCollateral(data.id);
            userReservesData[idx].isBorrowing = userConfig.isBorrowing(data.id);
            if (userReservesData[idx].isBorrowing) {
                (userReservesData[idx].scaledVariableDebt,) = IAERC6909(data.aTokenAddress)
                    .getScaledUserBalanceAndSupply(user, data.variableDebtTokenID);
            }
        }
    }

    /* Idea is to have everything in the same contract, but the same function might be found in the LendingPool */
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
     * @dev Returns the underlying asset balance given a erc6909 tokenId.
     */
    function getAllMpUnderlyingBalanceOf(uint256 tokenId)
        external
        view
        returns (uint256 underlyingBalance)
    {
        uint256 miniPoolCount = miniPoolAddressProvider.getMiniPoolCount();
        for (uint256 miniPoolId = 0; miniPoolId < miniPoolCount; miniPoolId++) {
            underlyingBalance += getMpUnderlyingBalanceOf(tokenId, miniPoolId);
        }
    }

    function getMpUnderlyingBalanceOf(uint256 tokenId, uint256 miniPoolId)
        public
        view
        returns (uint256 underlyingBalance)
    {
        IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(miniPoolId));
        (address[] memory reserves,) = miniPool.getReservesList();
        for (uint256 idx = 0; idx < reserves.length; idx++) {
            DataTypes.MiniPoolReserveData memory data = miniPool.getReserveData(reserves[idx]);
            if (data.aTokenID == tokenId) {
                underlyingBalance += IERC20Detailed(reserves[idx]).balanceOf(data.aTokenAddress);
            }
        }
    }
}
