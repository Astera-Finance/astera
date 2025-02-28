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
    uint256 currentATokenBalance;
    uint256 scaledATokenBalance;
    uint256 currentVariableDebt;
    uint256 scaledVariableDebt;
    bool usageAsCollateralEnabledOnUser;
    bool isBorrowing;
}

struct BaseCurrencyInfo {
    uint256 marketReferenceCurrencyUnit;
    int256 marketReferenceCurrencyPriceInUsd;
    int256 networkBaseTokenPriceInUsd;
    uint8 networkBaseTokenPriceDecimals;
}

struct AggregatedMainPoolReservesData {
    // reserve data for lending pool
    // BasicReserveInfo
    address underlyingAsset;
    string name;
    string symbol;
    // ReserveConfiguration
    uint256 decimals;
    uint256 baseLTVasCollateral;
    uint256 reserveLiquidationThreshold;
    uint256 reserveLiquidationBonus;
    uint256 cod3xReserveFactor;
    uint256 miniPoolOwnerReserveFactor;
    uint256 depositCap;
    bool usageAsCollateralEnabled;
    bool borrowingEnabled;
    bool flashloanEnabled;
    bool isActive;
    bool isFrozen;
    bool reserveType;
    // ReserveData
    uint128 liquidityIndex;
    uint128 variableBorrowIndex;
    uint128 liquidityRate;
    uint128 variableBorrowRate;
    uint40 lastUpdateTimestamp;
    address aTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint256 id;
    uint256 availableLiquidity;
    uint256 totalScaledVariableDebt;
    uint256 priceInMarketReferenceCurrency;
    address ATokenNonRebasingAddress;
    // PiReserveInterestRateStrategy
    uint256 optimalUtilizationRate;
    uint256 kp;
    uint256 ki;
    uint256 lastPiReserveRateStrategyUpdate;
    int256 errI;
    int256 minControllerError;
    int256 maxErrIAmp;
}

struct MiniPoolData {
    uint256 id;
    address miniPoolAddress;
    address aToken6909Address;
    AggregatedMiniPoolReservesData[] reservesData;
}

struct AggregatedMiniPoolReservesData {
    // BasicReserveInfo
    address underlyingAsset;
    string name;
    string symbol;
    // ReserveConfiguration MiniPool
    uint256 aTokenId;
    uint256 debtTokenId;
    bool isTranche;
    address aTokenNonRebasingAddress;
    // ReserveConfiguration
    uint256 decimals;
    uint256 baseLTVasCollateral;
    uint256 reserveLiquidationThreshold;
    uint256 reserveLiquidationBonus;
    uint256 cod3xReserveFactor;
    uint256 miniPoolOwnerReserveFactor;
    uint256 depositCap;
    bool usageAsCollateralEnabled;
    bool borrowingEnabled;
    bool flashloanEnabled;
    bool isActive;
    bool isFrozen;
    // ReserveData
    uint128 liquidityIndex;
    uint128 variableBorrowIndex;
    uint128 liquidityRate;
    uint128 variableBorrowRate;
    uint40 lastUpdateTimestamp;
    address interestRateStrategyAddress;
    uint256 availableLiquidity;
    uint256 totalScaledVariableDebt;
    uint256 priceInMarketReferenceCurrency;
    // PiReserveInterestRateStrategy
    uint256 optimalUtilizationRate;
    uint256 kp;
    uint256 ki;
    uint256 lastPiReserveRateStrategyUpdate;
    int256 errI;
    int256 minControllerError;
    int256 maxErrIAmp;
    // flowLimiter
    uint256 availableFlow;
    uint256 flowLimit;
    uint256 currentFlow;
}

interface ICod3xLendDataProvider2 {}
