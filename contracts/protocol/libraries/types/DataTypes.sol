// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

library DataTypes {
    // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
    struct ReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //stores the reserve borrow configuration
        ReserveBorrowConfigurationMap borrowConfiguration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address aTokenAddress;
        address variableDebtTokenAddress;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    struct MiniPoolReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //stores the reserve borrow configuration
        ReserveBorrowConfigurationMap borrowConfiguration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current amount available to borrow from the lending pool
        uint256 availableMLPLiquidity;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address aTokenAddress;
        uint256 aTokenID;
        uint256 variableDebtTokenID;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    struct ReserveConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: Reserve is active
        //bit 57: reserve is frozen
        //bit 58: borrowing is enabled
        //bit 59: stable rate borrowing enabled
        //bit 60-63: reserved
        //bit 64-79: reserve factor
        uint256 data;
    }

    struct ReserveReference {
        address asset; // underlying asset
        bool reserveType; // if the reserve is vault-boosted
    }

    struct ReserveBorrowConfigurationMap {
        //bit 0-15: Low LTV
        //bit 16-31: Low Liq. Threshold
        //bit 32-47: Medium LTV
        //bit 48-63: Medium Liq. Threshold
        //bit 64-79: High LTV
        //bit 80-95: High Liq. Threshold
        //bit 96-98: Volatility tier
        uint256 data;
    }

    // struct UserData {
    //   UserConfigurationMap userConfiguration;
    //   UserRecentBorrowMap userRecentBorrow;
    // }

    struct UserConfigurationMap {
        uint256 data;
    }

    struct UserRecentBorrowMap {
        uint256 data;
    }

    enum InterestRateMode {
        NONE,
        VARIABLE
    }

    struct snapshot {
        uint8 reserveID;
        uint16 usedLTV;
        uint16 usedLiquidationThreshold;
        uint128 index;
        uint256 amount;
    }

    struct collSnapshot {
        snapshot[] collateralSnapshots;
        uint8 numCollateral;
    }

    struct debtSnapshot {
        snapshot[] debtSnapshots;
        uint8 numDebt;
    }

    struct LoanInfo {
        collSnapshot collateralInfo;
        debtSnapshot debtInfo;
        bool relation;
    }
}
