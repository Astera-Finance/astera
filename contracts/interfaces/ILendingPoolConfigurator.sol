// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {ILendingPoolAddressesProvider} from "./ILendingPoolAddressesProvider.sol";

/**
 * @title ILendingPoolConfigurator interface.
 * @author Conclave
 */
interface ILendingPoolConfigurator {
    struct InitReserveInput {
        address aTokenImpl;
        address variableDebtTokenImpl;
        uint8 underlyingAssetDecimals;
        address interestRateStrategyAddress;
        address underlyingAsset;
        address treasury;
        address incentivesController;
        string underlyingAssetName;
        bool reserveType;
        string aTokenName;
        string aTokenSymbol;
        string variableDebtTokenName;
        string variableDebtTokenSymbol;
        bytes params;
    }

    struct UpdateATokenInput {
        address asset;
        bool reserveType;
        address treasury;
        address incentivesController;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    struct UpdateDebtTokenInput {
        address asset;
        bool reserveType;
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
     * @param reserveType Whether the reserve is boosted by a vault
     * @param variableDebtToken The address of the associated variable rate debt token
     * @param interestRateStrategyAddress The address of the interest rate strategy for the reserve
     */
    event ReserveInitialized(
        address indexed asset,
        address indexed aToken,
        bool reserveType,
        address variableDebtToken,
        address interestRateStrategyAddress
    );

    /**
     * @dev Emitted when borrowing is enabled on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event BorrowingEnabledOnReserve(address indexed asset, bool reserveType);

    /**
     * @dev Emitted when borrowing is disabled on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event BorrowingDisabledOnReserve(address indexed asset, bool reserveType);

    /**
     * @dev Emitted when the collateralization risk parameters for the specified asset are updated.
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset
     */
    event CollateralConfigurationChanged(
        address indexed asset,
        bool reserveType,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    );

    /**
     * @dev Emitted when a reserve is activated
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event ReserveActivated(address indexed asset, bool reserveType);

    /**
     * @dev Emitted when a reserve is deactivated
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event ReserveDeactivated(address indexed asset, bool reserveType);

    /**
     * @dev Emitted when a reserve is frozen
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event ReserveFrozen(address indexed asset, bool reserveType);

    /**
     * @dev Emitted when a reserve is unfrozen
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event ReserveUnfrozen(address indexed asset, bool reserveType);

    /**
     * @dev Emitted when FL is enabled
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event EnableFlashloan(address indexed asset, bool reserveType);

    /**
     * @dev Emitted when FL is disabled
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event DisableFlashloan(address indexed asset, bool reserveType);

    /**
     * @dev Emitted when a reserve factor is updated
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param factor The new reserve factor
     */
    event ReserveFactorChanged(address indexed asset, bool reserveType, uint256 factor);

    /**
     * @dev Emitted when the reserve deposit cap is updated
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param depositCap The new depositCap, a 0 means no deposit cap
     */
    event ReserveDepositCapChanged(address indexed asset, bool reserveType, uint256 depositCap);

    /**
     * @dev Emitted when a reserve interest strategy contract is updated
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param strategy The new address of the interest strategy contract
     */
    event ReserveInterestRateStrategyChanged(
        address indexed asset, bool reserveType, address strategy
    );

    /**
     * @dev Emitted when an aToken implementation is upgraded
     * @param asset The address of the underlying asset of the reserve
     * @param proxy The aToken proxy address
     * @param implementation The new aToken implementation
     * @param reserveType Whether the reserve is boosted by a vault
     */
    event ATokenUpgraded(
        address indexed asset,
        address indexed proxy,
        address indexed implementation,
        bool reserveType
    );

    /**
     * @dev Emitted when the implementation of a variable debt token is upgraded
     * @param asset The address of the underlying asset of the reserve
     * @param proxy The variable debt token proxy address
     * @param implementation The new variable debt token implementation
     */
    event VariableDebtTokenUpgraded(
        address indexed asset, address indexed proxy, address indexed implementation
    );

    /**
     * @dev Emitted when the total premium on flashloans is updated.
     * @param oldFlashloanPremiumTotal The old premium, expressed in bps
     * @param newFlashloanPremiumTotal The new premium, expressed in bps
     */
    event FlashloanPremiumTotalUpdated(
        uint128 oldFlashloanPremiumTotal, uint128 newFlashloanPremiumTotal
    );

    function batchInitReserve(InitReserveInput[] calldata input) external;

    function updateAToken(UpdateATokenInput calldata input) external;

    function updateVariableDebtToken(UpdateDebtTokenInput calldata input) external;

    function enableBorrowingOnReserve(address asset, bool reserveType) external;

    function disableBorrowingOnReserve(address asset, bool reserveType) external;

    function configureReserveAsCollateral(
        address asset,
        bool reserveType,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external;

    function activateReserve(address asset, bool reserveType) external;

    function deactivateReserve(address asset, bool reserveType) external;

    function freezeReserve(address asset, bool reserveType) external;

    function unfreezeReserve(address asset, bool reserveType) external;

    function enableFlashloan(address asset, bool reserveType) external;

    function disableFlashloan(address asset, bool reserveType) external;

    function setAsteraReserveFactor(address asset, bool reserveType, uint256 reserveFactor)
        external;

    function setDepositCap(address asset, bool reserveType, uint256 depositCap) external;

    function setReserveInterestRateStrategyAddress(
        address asset,
        bool reserveType,
        address rateStrategyAddress
    ) external;

    function setPoolPause(bool val) external;

    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal) external;

    function setFarmingPct(address aTokenAddress, uint256 farmingPct) external;

    function setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold) external;

    function setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift) external;

    function setProfitHandler(address aTokenAddress, address _profitHandler) external;

    function setVault(address aTokenAddress, address _vault) external;

    function rebalance(address aTokenAddress) external;

    function getTotalManagedAssets(address aTokenAddress) external view returns (uint256);

    function setRewarderForReserve(address asset, bool reserveType, address rewarder) external;

    function setTreasury(address asset, bool reserveType, address rewarder) external;

    function getIsAToken(address token) external view returns (bool);
}
