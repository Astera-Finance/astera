// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IMiniPoolAddressesProvider} from "./IMiniPoolAddressesProvider.sol";
import {IMiniPool} from "./IMiniPool.sol";

/**
 * @title IMiniPoolConfigurator interface.
 * @author Cod3x
 */
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
     * @param aTokenId The ID of the associated aToken in the AERC6909 contract
     * @param debtTokenID The ID of the associated debt token in the AERC6909 contract
     * @param interestRateStrategyAddress The address of the interest rate strategy for the reserve
     */
    event ReserveInitialized(
        address indexed asset,
        uint256 indexed aTokenId,
        uint256 indexed debtTokenID,
        address interestRateStrategyAddress
    );

    /**
     * @dev Emitted when borrowing is enabled on a reserve
     * @param asset The address of the underlying asset of the reserve
     */
    event BorrowingEnabledOnReserve(address indexed asset);

    /**
     * @dev Emitted when borrowing is disabled on a reserve
     * @param asset The address of the underlying asset of the reserve
     */
    event BorrowingDisabledOnReserve(address indexed asset);

    /**
     * @dev Emitted when the collateralization risk parameters for the specified asset are updated.
     * @param asset The address of the underlying asset of the reserve
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset
     */
    event CollateralConfigurationChanged(
        address indexed asset, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus
    );

    /**
     * @dev Emitted when a reserve is activated
     * @param asset The address of the underlying asset of the reserve
     */
    event ReserveActivated(address indexed asset);

    /**
     * @dev Emitted when a reserve is deactivated
     * @param asset The address of the underlying asset of the reserve
     */
    event ReserveDeactivated(address indexed asset);

    /**
     * @dev Emitted when a reserve is frozen
     * @param asset The address of the underlying asset of the reserve
     */
    event ReserveFrozen(address indexed asset);

    /**
     * @dev Emitted when a reserve is unfrozen
     * @param asset The address of the underlying asset of the reserve
     */
    event ReserveUnfrozen(address indexed asset);

    /**
     * @dev Emitted when FL is enabled
     * @param asset The address of the underlying asset of the reserve
     */
    event EnableFlashloan(address indexed asset);

    /**
     * @dev Emitted when FL is disabled
     * @param asset The address of the underlying asset of the reserve
     */
    event DisableFlashloan(address indexed asset);

    /**
     * @dev Emitted when a Cod3x reserve factor is updated
     * @param asset The address of the underlying asset of the reserve
     * @param factor The new reserve factor
     */
    event Cod3xReserveFactorChanged(address indexed asset, uint256 factor);

    /**
     * @dev Emitted when a minipool owner reserve factor is updated
     * @param asset The address of the underlying asset of the reserve
     * @param factor The new reserve factor
     */
    event MinipoolOwnerReserveFactorChanged(address indexed asset, uint256 factor);

    /**
     * @dev Emitted when the reserve deposit cap is updated
     * @param asset The address of the underlying asset of the reserve
     * @param depositCap The new depositCap, a 0 means no deposit cap
     */
    event ReserveDepositCapChanged(address indexed asset, uint256 depositCap);

    /**
     * @dev Emitted when a reserve interest strategy contract is updated
     * @param asset The address of the underlying asset of the reserve
     * @param strategy The new address of the interest strategy contract
     */
    event ReserveInterestRateStrategyChanged(address indexed asset, address strategy);

    /**
     * @dev Emitted when the flow limit for a miniPool is updated
     * @param asset The address of the underlying asset
     * @param miniPool The address of the miniPool
     * @param limit The new flow limit amount
     */
    event FlowLimitUpdated(address indexed asset, address indexed miniPool, uint256 limit);

    /**
     * @dev Emitted when the total premium on flashloans is updated.
     * @param oldFlashloanPremiumTotal The old premium, expressed in bps
     * @param newFlashloanPremiumTotal The new premium, expressed in bps
     */
    event FlashloanPremiumTotalUpdated(
        uint128 oldFlashloanPremiumTotal, uint128 newFlashloanPremiumTotal
    );

    function initialize(IMiniPoolAddressesProvider provider) external;

    function batchInitReserve(InitReserveInput[] calldata input, IMiniPool pool) external;

    function setRewarderForReserve(address asset, address rewarder, IMiniPool pool) external;

    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal, IMiniPool pool)
        external;

    function setCod3xTreasury(address treasury) external;

    function setFlowLimit(address asset, address miniPool, uint256 limit) external;

    function setReserveInterestRateStrategyAddress(
        address asset,
        address rateStrategyAddress,
        IMiniPool pool
    ) external;

    function setCod3xReserveFactor(address asset, uint256 reserveFactor, IMiniPool pool) external;

    function setDepositCap(address asset, uint256 depositCap, IMiniPool pool) external;

    function setPoolPause(bool val, IMiniPool pool) external;

    function enableBorrowingOnReserve(address asset, IMiniPool pool) external;

    function disableBorrowingOnReserve(address asset, IMiniPool pool) external;

    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        IMiniPool pool
    ) external;

    function activateReserve(address asset, IMiniPool pool) external;

    function deactivateReserve(address asset, IMiniPool pool) external;

    function freezeReserve(address asset, IMiniPool pool) external;

    function unfreezeReserve(address asset, IMiniPool pool) external;

    function enableFlashloan(address asset, IMiniPool pool) external;

    function disableFlashloan(address asset, IMiniPool pool) external;

    function setPoolAdmin(address admin, IMiniPool pool) external;

    function setMinipoolOwnerTreasuryToMiniPool(address treasury, IMiniPool pool) external;

    function setMinipoolOwnerReserveFactor(address asset, uint256 reserveFactor, IMiniPool pool)
        external;
}
