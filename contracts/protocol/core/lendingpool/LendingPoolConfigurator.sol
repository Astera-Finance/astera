// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {VersionedInitializable} from
    "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {InitializableImmutableAdminUpgradeabilityProxy} from
    "../../../../contracts/protocol/libraries/upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";
import {ReserveConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ILendingPoolAddressesProvider} from
    "../../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {IERC20Detailed} from
    "../../../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {PercentageMath} from "../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {IInitializableDebtToken} from
    "../../../../contracts/interfaces/base/IInitializableDebtToken.sol";
import {IInitializableAToken} from "../../../../contracts/interfaces/base/IInitializableAToken.sol";
import {IRewarder} from "../../../../contracts/interfaces/IRewarder.sol";
import {ILendingPoolConfigurator} from
    "../../../../contracts/interfaces/ILendingPoolConfigurator.sol";
import {IAToken} from "../../../../contracts/interfaces/IAToken.sol";
import {IAddressProviderUpdatable} from
    "../../../../contracts/interfaces/IAddressProviderUpdatable.sol";

/**
 * @title LendingPoolConfigurator contract
 * @author Conclave
 * @dev Implements the configuration methods for the Astera protocol.
 * @notice This contract handles the configuration of reserves and other protocol parameters.
 */
contract LendingPoolConfigurator is
    VersionedInitializable,
    ILendingPoolConfigurator,
    IAddressProviderUpdatable
{
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /// @dev The revision number for this contract implementation.
    uint256 internal constant CONFIGURATOR_REVISION = 0x1;

    /// @dev The addresses provider contract reference.
    ILendingPoolAddressesProvider internal addressesProvider;

    /// @dev The main lending pool contract reference.
    ILendingPool internal pool;

    /// @dev Mapping to track if an address is a registered aToken or NonRebasingAToken.
    mapping(address => bool) internal isAToken;

    constructor() {
        _blockInitializing();
    }

    /**
     * @dev Throws if the caller is not the pool admin.
     * @notice Restricts function access to only the configured pool admin address.
     */
    modifier onlyPoolAdmin() {
        require(addressesProvider.getPoolAdmin() == msg.sender, Errors.VL_CALLER_NOT_POOL_ADMIN);
        _;
    }

    /**
     * @dev Throws if the caller is not the emergency admin.
     * @notice Restricts function access to only the configured emergency admin address.
     */
    modifier onlyEmergencyAdmin() {
        require(
            addressesProvider.getEmergencyAdmin() == msg.sender,
            Errors.VL_CALLER_NOT_EMERGENCY_ADMIN
        );
        _;
    }

    /**
     * @dev Returns the revision number of this contract implementation.
     * @return The revision number.
     */
    function getRevision() internal pure override returns (uint256) {
        return CONFIGURATOR_REVISION;
    }

    /**
     * @dev Initializes the lending pool configurator contract.
     * @param provider The address of the `ILendingPoolAddressesProvider` contract.
     */
    function initialize(address provider) public initializer {
        addressesProvider = ILendingPoolAddressesProvider(provider);
        pool = ILendingPool(addressesProvider.getLendingPool());
    }

    /**
     * @dev Initializes multiple reserves in a single transaction.
     * @param input An array of `InitReserveInput` structs containing initialization parameters for each reserve.
     */
    function batchInitReserve(InitReserveInput[] calldata input) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;
        for (uint256 i = 0; i < input.length; i++) {
            _initReserve(cachedPool, input[i]);
        }
    }

    /**
     * @dev Internal function to initialize a single reserve.
     * @param pool_ The `ILendingPool` contract instance.
     * @param input The `InitReserveInput` struct containing initialization parameters.
     * @notice Creates aToken and variable debt token proxies, initializes the reserve, and sets its configuration.
     */
    function _initReserve(ILendingPool pool_, InitReserveInput calldata input) internal {
        address aTokenProxyAddress = _initTokenWithProxy(
            input.aTokenImpl,
            abi.encodeCall(
                IInitializableAToken.initialize,
                (
                    pool_,
                    input.treasury,
                    input.underlyingAsset,
                    IRewarder(input.incentivesController),
                    input.underlyingAssetDecimals,
                    input.reserveType,
                    input.aTokenName,
                    input.aTokenSymbol,
                    input.params
                )
            )
        );

        address variableDebtTokenProxyAddress = _initTokenWithProxy(
            input.variableDebtTokenImpl,
            abi.encodeCall(
                IInitializableDebtToken.initialize,
                (
                    pool,
                    input.underlyingAsset,
                    IRewarder(input.incentivesController),
                    input.underlyingAssetDecimals,
                    input.reserveType,
                    input.variableDebtTokenName,
                    input.variableDebtTokenSymbol,
                    input.params
                )
            )
        );

        pool.initReserve(
            input.underlyingAsset,
            input.reserveType,
            aTokenProxyAddress,
            variableDebtTokenProxyAddress,
            input.interestRateStrategyAddress
        );

        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(input.underlyingAsset, input.reserveType);

        currentConfig.setDecimals(input.underlyingAssetDecimals);
        currentConfig.setActive(true);
        currentConfig.setFrozen(false);
        currentConfig.setFlashLoanEnabled(true);
        currentConfig.setReserveType(input.reserveType);

        pool.setConfiguration(input.underlyingAsset, input.reserveType, currentConfig.data);

        isAToken[aTokenProxyAddress] = true;
        // `getATokenNonRebasingFromAtoken()` because call fallback function from the proxy admin reverts.
        isAToken[pool.getATokenNonRebasingFromAtoken(aTokenProxyAddress)] = true;

        emit ReserveInitialized(
            input.underlyingAsset,
            aTokenProxyAddress,
            input.reserveType,
            variableDebtTokenProxyAddress,
            input.interestRateStrategyAddress
        );
    }

    /**
     * @dev Updates the aToken implementation for a specific reserve.
     * @param input The `UpdateATokenInput` struct containing update parameters.
     * @notice This function can only be called by the pool admin.
     */
    function updateAToken(UpdateATokenInput calldata input) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;

        DataTypes.ReserveData memory reserveData =
            cachedPool.getReserveData(input.asset, input.reserveType);

        (,,, uint256 decimals,,,) =
            cachedPool.getConfiguration(input.asset, input.reserveType).getParamsMemory();

        bytes memory encodedCall = abi.encodeCall(
            IInitializableAToken.initialize,
            (
                cachedPool,
                input.treasury,
                input.asset,
                IRewarder(input.incentivesController),
                uint8(decimals),
                input.reserveType,
                input.name,
                input.symbol,
                input.params
            )
        );

        _upgradeTokenImplementation(reserveData.aTokenAddress, input.implementation, encodedCall);

        emit ATokenUpgraded(
            input.asset, reserveData.aTokenAddress, input.implementation, input.reserveType
        );
    }

    /**
     * @dev Updates the variable debt token implementation for a specific reserve.
     * @param input The `UpdateDebtTokenInput` struct containing update parameters.
     * @notice This function can only be called by the pool admin.
     */
    function updateVariableDebtToken(UpdateDebtTokenInput calldata input) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;

        DataTypes.ReserveData memory reserveData =
            cachedPool.getReserveData(input.asset, input.reserveType);

        (,,, uint256 decimals,,,) =
            cachedPool.getConfiguration(input.asset, input.reserveType).getParamsMemory();

        bytes memory encodedCall = abi.encodeCall(
            IInitializableDebtToken.initialize,
            (
                cachedPool,
                input.asset,
                IRewarder(input.incentivesController),
                uint8(decimals),
                input.reserveType,
                input.name,
                input.symbol,
                input.params
            )
        );

        _upgradeTokenImplementation(
            reserveData.variableDebtTokenAddress, input.implementation, encodedCall
        );

        emit VariableDebtTokenUpgraded(
            input.asset, reserveData.variableDebtTokenAddress, input.implementation
        );
    }

    /**
     * @dev Enables borrowing functionality on a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Only callable by pool admin.
     * @notice Emits a `BorrowingEnabledOnReserve` event.
     */
    function enableBorrowingOnReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setBorrowingEnabled(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit BorrowingEnabledOnReserve(asset, reserveType);
    }

    /**
     * @dev Disables borrowing functionality on a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Only callable by pool admin.
     * @notice Emits a `BorrowingDisabledOnReserve` event.
     */
    function disableBorrowingOnReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setBorrowingEnabled(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);
        emit BorrowingDisabledOnReserve(asset, reserveType);
    }

    /**
     * @dev Configures the collateralization parameters for a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @param ltv The loan to value ratio, expressed in basis points. A value of 10000 means 100.00%.
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized, expressed in basis points.
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset, expressed in basis points. Must be above 100.00%.
     * @notice Only callable by pool admin.
     * @notice All percentage values are expressed with 2 decimals of precision (10000 = 100.00%).
     * @notice The `ltv` must be less than or equal to the `liquidationThreshold`.
     * @notice If `liquidationThreshold` is 0, the asset cannot be used as collateral.
     * @notice Emits a `CollateralConfigurationChanged` event.
     */
    function configureReserveAsCollateral(
        address asset,
        bool reserveType,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        // Validation of the parameters: the `ltv` can
        // only be lower or equal than the `liquidationThreshold`
        // (otherwise a loan against the asset would cause instantaneous liquidation).
        require(ltv <= liquidationThreshold, Errors.VL_INVALID_CONFIGURATION);

        if (liquidationThreshold != 0) {
            // Liquidation bonus must be bigger than 100.00%, otherwise the liquidator would receive less
            // collateral than needed to cover the debt.
            require(
                liquidationBonus > PercentageMath.PERCENTAGE_FACTOR, Errors.VL_INVALID_CONFIGURATION
            );

            // If `threshold` * `bonus` is less than `PERCENTAGE_FACTOR`, it's guaranteed that at the moment
            // a loan is taken there is enough collateral available to cover the liquidation bonus.
            require(
                liquidationThreshold.percentMul(liquidationBonus)
                    <= PercentageMath.PERCENTAGE_FACTOR,
                Errors.VL_INVALID_CONFIGURATION
            );
        } else {
            require(liquidationBonus == 0, Errors.VL_INVALID_CONFIGURATION);
            // If the `liquidationThreshold` is being set to 0,
            // the reserve is being disabled as collateral. To do so,
            // we need to ensure no liquidity is deposited.
            _checkNoLiquidity(asset, reserveType);
        }

        currentConfig.setLtv(ltv);
        currentConfig.setLiquidationThreshold(liquidationThreshold);
        currentConfig.setLiquidationBonus(liquidationBonus);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit CollateralConfigurationChanged(
            asset, reserveType, ltv, liquidationThreshold, liquidationBonus
        );
    }

    /**
     * @dev Activates a reserve, allowing it to be used in the protocol.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Only callable by pool admin.
     * @notice Emits a `ReserveActivated` event.
     */
    function activateReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setActive(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveActivated(asset, reserveType);
    }

    /**
     * @dev Deactivates a reserve, preventing it from being used in the protocol.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Only callable by pool admin.
     * @notice Requires the reserve to have no liquidity.
     * @notice Emits a `ReserveDeactivated` event.
     */
    function deactivateReserve(address asset, bool reserveType) external onlyPoolAdmin {
        _checkNoLiquidity(asset, reserveType);

        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setActive(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveDeactivated(asset, reserveType);
    }

    /**
     * @dev Freezes a reserve, preventing new deposits and borrows while allowing repayments, liquidations, and withdrawals.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Only callable by pool admin.
     * @notice Emits a `ReserveFrozen` event.
     */
    function freezeReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFrozen(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveFrozen(asset, reserveType);
    }

    /**
     * @dev Unfreezes a reserve, re-enabling deposits and borrows.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Only callable by pool admin.
     * @notice Emits a `ReserveUnfrozen` event.
     */
    function unfreezeReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFrozen(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveUnfrozen(asset, reserveType);
    }

    /**
     * @dev Enables flash loan functionality for a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Only callable by pool admin.
     * @notice Emits an `EnableFlashloan` event.
     */
    function enableFlashloan(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFlashLoanEnabled(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit EnableFlashloan(asset, reserveType);
    }

    /**
     * @dev Disables flash loan functionality for a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Only callable by pool admin.
     * @notice Emits a `DisableFlashloan` event.
     */
    function disableFlashloan(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFlashLoanEnabled(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit DisableFlashloan(asset, reserveType);
    }

    /**
     * @dev Updates the reserve factor for a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @param reserveFactor The new reserve factor, expressed in basis points.
     * @notice Only callable by pool admin.
     * @notice The reserve factor determines the portion of interest that goes to the protocol.
     * @notice Emits a `ReserveFactorChanged` event.
     */
    function setAsteraReserveFactor(address asset, bool reserveType, uint256 reserveFactor)
        external
        onlyPoolAdmin
    {
        pool.syncIndexesState(asset, reserveType);

        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setAsteraReserveFactor(reserveFactor);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        pool.syncRatesState(asset, reserveType);

        emit ReserveFactorChanged(asset, reserveType, reserveFactor);
    }

    /**
     * @dev Sets the deposit cap for a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @param depositCap The maximum amount of underlying asset that can be deposited.
     * @notice Only callable by pool admin.
     * @notice Emits a `ReserveDepositCapChanged` event.
     */
    function setDepositCap(address asset, bool reserveType, uint256 depositCap)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setDepositCap(depositCap);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveDepositCapChanged(asset, reserveType, depositCap);
    }

    /**
     * @dev Sets the interest rate strategy for a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @param rateStrategyAddress The address of the new interest rate strategy contract.
     * @notice Only callable by pool admin.
     * @notice Emits a `ReserveInterestRateStrategyChanged` event.
     */
    function setReserveInterestRateStrategyAddress(
        address asset,
        bool reserveType,
        address rateStrategyAddress
    ) external onlyPoolAdmin {
        pool.syncIndexesState(asset, reserveType);

        pool.setReserveInterestRateStrategyAddress(asset, reserveType, rateStrategyAddress);

        pool.syncRatesState(asset, reserveType);

        emit ReserveInterestRateStrategyChanged(asset, reserveType, rateStrategyAddress);
    }

    /**
     * @dev Pauses or unpauses all protocol actions, including aToken transfers.
     * @param val `true` to pause the protocol, `false` to unpause.
     * @notice Only callable by emergency admin.
     */
    function setPoolPause(bool val) external onlyEmergencyAdmin {
        pool.setPause(val);
    }

    /**
     * @dev Updates the total flash loan premium.
     * @param newFlashloanPremiumTotal The new total flash loan premium, expressed in basis points.
     * @notice Only callable by pool admin.
     * @notice Must not exceed 100%.
     * @notice Emits a `FlashloanPremiumTotalUpdated` event.
     */
    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal) external onlyPoolAdmin {
        require(
            newFlashloanPremiumTotal <= PercentageMath.PERCENTAGE_FACTOR,
            Errors.VL_FLASHLOAN_PREMIUM_INVALID
        );
        uint128 oldFlashloanPremiumTotal = pool.FLASHLOAN_PREMIUM_TOTAL();
        pool.updateFlashLoanFee(newFlashloanPremiumTotal);
        emit FlashloanPremiumTotalUpdated(oldFlashloanPremiumTotal, newFlashloanPremiumTotal);
    }

    /**
     * @dev Initializes a new proxy with implementation and initialization parameters.
     * @param implementation The address of the implementation contract.
     * @param initParams The initialization parameters for the proxy.
     * @return The address of the newly created proxy.
     */
    function _initTokenWithProxy(address implementation, bytes memory initParams)
        internal
        returns (address)
    {
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            new InitializableImmutableAdminUpgradeabilityProxy(address(this));

        proxy.initialize(implementation, initParams);

        return address(proxy);
    }

    /**
     * @dev Upgrades a proxy's implementation and calls initialization function.
     * @param proxyAddress The address of the proxy to upgrade.
     * @param implementation The address of the new implementation.
     * @param initParams The parameters for the initialization call.
     */
    function _upgradeTokenImplementation(
        address proxyAddress,
        address implementation,
        bytes memory initParams
    ) internal {
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            InitializableImmutableAdminUpgradeabilityProxy(payable(proxyAddress));

        proxy.upgradeToAndCall(implementation, initParams);
    }

    /**
     * @dev Checks that a reserve has no liquidity.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @notice Reverts if there is any liquidity or active interest.
     */
    function _checkNoLiquidity(address asset, bool reserveType) internal view {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(asset, reserveType);

        uint256 availableLiquidity = IERC20Detailed(asset).balanceOf(reserveData.aTokenAddress);

        require(
            availableLiquidity == 0 && reserveData.currentLiquidityRate == 0,
            Errors.VL_RESERVE_LIQUIDITY_NOT_0
        );
    }

    /**
     * @dev Sets the farming percentage for an aToken.
     * @param aTokenAddress The address of the aToken.
     * @param farmingPct The new farming percentage.
     * @notice Only callable by pool admin.
     */
    function setFarmingPct(address aTokenAddress, uint256 farmingPct) external onlyPoolAdmin {
        pool.setFarmingPct(aTokenAddress, farmingPct);
    }

    /**
     * @dev Sets the claiming threshold for an aToken.
     * @param aTokenAddress The address of the aToken.
     * @param claimingThreshold The new claiming threshold.
     * @notice Only callable by pool admin.
     */
    function setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)
        external
        onlyPoolAdmin
    {
        pool.setClaimingThreshold(aTokenAddress, claimingThreshold);
    }

    /**
     * @dev Sets the farming percentage drift for an aToken.
     * @param aTokenAddress The address of the aToken.
     * @param _farmingPctDrift The new farming percentage drift.
     * @notice Only callable by pool admin.
     */
    function setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift)
        external
        onlyPoolAdmin
    {
        pool.setFarmingPctDrift(aTokenAddress, _farmingPctDrift);
    }

    /**
     * @dev Sets the profit handler for an aToken.
     * @param aTokenAddress The address of the aToken.
     * @param _profitHandler The address of the new profit handler.
     * @notice Only callable by pool admin.
     */
    function setProfitHandler(address aTokenAddress, address _profitHandler)
        external
        onlyPoolAdmin
    {
        pool.setProfitHandler(aTokenAddress, _profitHandler);
    }

    /**
     * @dev Sets the vault for an aToken.
     * @param aTokenAddress The address of the aToken.
     * @param _vault The address of the new vault.
     * @notice Only callable by pool admin.
     */
    function setVault(address aTokenAddress, address _vault) external onlyPoolAdmin {
        pool.setVault(aTokenAddress, _vault);
    }

    /**
     * @dev Triggers a rebalance for an aToken.
     * @param aTokenAddress The address of the aToken to rebalance.
     * @notice Only callable by emergency admin.
     */
    function rebalance(address aTokenAddress) external onlyEmergencyAdmin {
        pool.rebalance(aTokenAddress);
    }

    /**
     * @dev Gets the total managed assets for an aToken.
     * @param aTokenAddress The address of the aToken.
     * @return The total amount of managed assets.
     */
    function getTotalManagedAssets(address aTokenAddress) external view returns (uint256) {
        return pool.getTotalManagedAssets(aTokenAddress);
    }

    /**
     * @dev Sets the rewarder contract for a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @param rewarder The address of the new rewarder contract.
     * @notice Only callable by pool admin.
     */
    function setRewarderForReserve(address asset, bool reserveType, address rewarder)
        external
        onlyPoolAdmin
    {
        pool.setRewarderForReserve(asset, reserveType, rewarder);
    }

    /**
     * @dev Sets the treasury address for a reserve.
     * @param asset The address of the underlying asset of the reserve.
     * @param reserveType Whether the reserve is boosted by a vault (`true`) or not (`false`).
     * @param rewarder The address of the new treasury.
     * @notice Only callable by pool admin.
     */
    function setTreasury(address asset, bool reserveType, address rewarder)
        external
        onlyPoolAdmin
    {
        pool.setTreasury(asset, reserveType, rewarder);
    }

    /**
     * @dev Checks if an address is a registered aToken or nonRebasingAToken.
     * This function is mainly for the Oracle.
     * @param token The address to check.
     * @return bool True if the address is a registered aToken, false otherwise.
     */
    function getIsAToken(address token) external view returns (bool) {
        return isAToken[token];
    }
}
