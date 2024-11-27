// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface IMiniPoolConfigurator {
    struct InitReserveInput {
        uint8 underlyingAssetDecimals;
        address interestRateStrategyAddress;
        address underlyingAsset;
        string underlyingAssetName;
        string underlyingAssetSymbol;
    }

    struct UpdateATokenInput {
        address asset;
        address treasury;
        address incentivesController;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    struct UpdateDebtTokenInput {
        address asset;
        address incentivesController;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    /**
     * @dev Emitted when a reserve is initialized.
     * @param asset The address of the underlying asset of the reserve
     * @param aToken The address of the associated aToken contract
     * @param variableDebtToken The address of the associated variable rate debt token
     * @param interestRateStrategyAddress The address of the interest rate strategy for the reserve
     *
     */
    event ReserveInitialized(
        address indexed asset,
        address indexed aToken,
        address variableDebtToken,
        address interestRateStrategyAddress
    );

    /**
     * @dev Emitted when borrowing is enabled on a reserve
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event BorrowingEnabledOnReserve(address indexed asset);

    /**
     * @dev Emitted when borrowing is disabled on a reserve
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event BorrowingDisabledOnReserve(address indexed asset);

    /**
     * @dev Emitted when the collateralization risk parameters for the specified asset are updated.
     * @param asset The address of the underlying asset of the reserve
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset
     *
     */
    event CollateralConfigurationChanged(
        address indexed asset, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus
    );

    /**
     * @dev Emitted when a reserve is activated
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event ReserveActivated(address indexed asset);

    /**
     * @dev Emitted when a reserve is deactivated
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event ReserveDeactivated(address indexed asset);

    /**
     * @dev Emitted when a reserve is frozen
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event ReserveFrozen(address indexed asset);

    /**
     * @dev Emitted when a reserve is unfrozen
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event ReserveUnfrozen(address indexed asset);

    /**
     * @dev Emitted when a reserve is paused
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event ReservePaused(address indexed asset);

    /**
     * @dev Emitted when a reserve is unpaused
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event ReserveUnpaused(address indexed asset);

    /**
     * @dev Emitted when FL is enabled
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event EnableFlashloan(address indexed asset);

    /**
     * @dev Emitted when FL is disabled
     * @param asset The address of the underlying asset of the reserve
     *
     */
    event DisableFlashloan(address indexed asset);

    /**
     * @dev Emitted when a Cod3x reserve factor is updated
     * @param asset The address of the underlying asset of the reserve
     * @param factor The new reserve factor
     *
     */
    event Cod3xReserveFactorChanged(address indexed asset, uint256 factor);

    /**
     * @dev Emitted when a minipool owner reserve factor is updated
     * @param asset The address of the underlying asset of the reserve
     * @param factor The new reserve factor
     *
     */
    event MinipoolOwnerReserveFactorChanged(address indexed asset, uint256 factor);

    /**
     * @dev Emitted when a reserve volatility tier is updated
     * @param asset The address of the underlying asset of the reserve
     * @param tier The new volatility tier
     *
     */
    event ReserveVolatilityTierChanged(address indexed asset, uint256 tier);

    /**
     * @dev Emitted when a reserve's ltv is updated for a volatility tier
     * @param asset The address of the underlying asset of the reserve
     * @param ltv The LTV for that tier
     */
    event ReserveLowVolatilityLtvChanged(address indexed asset, uint256 ltv);
    event ReserveMediumVolatilityLtvChanged(address indexed asset, uint256 ltv);
    event ReserveHighVolatilityLtvChanged(address indexed asset, uint256 ltv);

    /**
     * @dev Emitted when the reserve decimals are updated
     * @param asset The address of the underlying asset of the reserve
     * @param decimals The new decimals
     *
     */
    event ReserveDecimalsChanged(address indexed asset, uint256 decimals);

    /**
     * @dev Emitted when the reserve deposit cap is updated
     * @param asset The address of the underlying asset of the reserve
     * @param depositCap The new depositCap, a 0 means no deposit cap
     *
     */
    event ReserveDepositCapChanged(address indexed asset, uint256 depositCap);

    /**
     * @dev Emitted when a reserve interest strategy contract is updated
     * @param asset The address of the underlying asset of the reserve
     * @param strategy The new address of the interest strategy contract
     *
     */
    event ReserveInterestRateStrategyChanged(address indexed asset, address strategy);

    /**
     * @dev Emitted when an aToken implementation is upgraded
     * @param asset The address of the underlying asset of the reserve
     * @param proxy The aToken proxy address
     * @param implementation The new aToken implementation
     *
     */
    event ATokenUpgraded(
        address indexed asset, address indexed proxy, address indexed implementation
    );

    /**
     * @dev Emitted when the implementation of a variable debt token is upgraded
     * @param asset The address of the underlying asset of the reserve
     * @param proxy The variable debt token proxy address
     * @param implementation The new aToken implementation
     *
     */
    event VariableDebtTokenUpgraded(
        address indexed asset, address indexed proxy, address indexed implementation
    );
}
