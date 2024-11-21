// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

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
import {IInitializableDebtToken} from "../../../../contracts/interfaces/IInitializableDebtToken.sol";
import {IInitializableAToken} from "../../../../contracts/interfaces/IInitializableAToken.sol";
import {IRewarder} from "../../../../contracts/interfaces/IRewarder.sol";
import {ILendingPoolConfigurator} from
    "../../../../contracts/interfaces/ILendingPoolConfigurator.sol";
import {IAToken} from "../../../../contracts/interfaces/IAToken.sol";

/**
 * @title LendingPoolConfigurator contract
 * @author Cod3x
 * @dev Implements the configuration methods for the Cod3x Lend protocol
 *
 */
contract LendingPoolConfigurator is VersionedInitializable, ILendingPoolConfigurator {
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ILendingPoolAddressesProvider internal addressesProvider;
    ILendingPool internal pool;

    modifier onlyPoolAdmin() {
        require(addressesProvider.getPoolAdmin() == msg.sender, Errors.CALLER_NOT_POOL_ADMIN);
        _;
    }

    modifier onlyEmergencyAdmin() {
        require(
            addressesProvider.getEmergencyAdmin() == msg.sender,
            Errors.LPC_CALLER_NOT_EMERGENCY_ADMIN
        );
        _;
    }

    uint256 internal constant CONFIGURATOR_REVISION = 0x1;

    function getRevision() internal pure override returns (uint256) {
        return CONFIGURATOR_REVISION;
    }

    function initialize(ILendingPoolAddressesProvider provider) public initializer {
        addressesProvider = provider;
        pool = ILendingPool(addressesProvider.getLendingPool());
    }

    /**
     * @dev Initializes reserves in batch
     *
     */
    function batchInitReserve(InitReserveInput[] calldata input) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;
        for (uint256 i = 0; i < input.length; i++) {
            _initReserve(cachedPool, input[i]);
        }
    }

    function _initReserve(ILendingPool pool_, InitReserveInput calldata input) internal {
        address aTokenProxyAddress = _initTokenWithProxy(
            input.aTokenImpl,
            abi.encodeWithSelector(
                IInitializableAToken.initialize.selector,
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
        );

        address variableDebtTokenProxyAddress = _initTokenWithProxy(
            input.variableDebtTokenImpl,
            abi.encodeWithSelector(
                IInitializableDebtToken.initialize.selector,
                pool,
                input.underlyingAsset,
                IRewarder(input.incentivesController),
                input.underlyingAssetDecimals,
                input.reserveType,
                input.variableDebtTokenName,
                input.variableDebtTokenSymbol,
                input.params
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

        emit ReserveInitialized(
            input.underlyingAsset,
            aTokenProxyAddress,
            input.reserveType,
            variableDebtTokenProxyAddress,
            input.interestRateStrategyAddress
        );
    }

    /**
     * @dev Updates the aToken implementation for the reserve
     *
     */
    function updateAToken(UpdateATokenInput calldata input) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;

        DataTypes.ReserveData memory reserveData =
            cachedPool.getReserveData(input.asset, input.reserveType);

        (,,, uint256 decimals,,) =
            cachedPool.getConfiguration(input.asset, input.reserveType).getParamsMemory();

        bytes memory encodedCall = abi.encodeWithSelector(
            IInitializableAToken.initialize.selector,
            cachedPool,
            input.treasury,
            input.asset,
            input.incentivesController,
            decimals,
            input.name,
            input.symbol,
            input.params
        );

        _upgradeTokenImplementation(reserveData.aTokenAddress, input.implementation, encodedCall);

        emit ATokenUpgraded(
            input.asset, reserveData.aTokenAddress, input.implementation, input.reserveType
        );
    }

    /**
     * @dev Updates the variable debt token implementation for the asset
     *
     */
    function updateVariableDebtToken(UpdateDebtTokenInput calldata input) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;

        DataTypes.ReserveData memory reserveData =
            cachedPool.getReserveData(input.asset, input.reserveType);

        (,,, uint256 decimals,,) =
            cachedPool.getConfiguration(input.asset, input.reserveType).getParamsMemory();

        bytes memory encodedCall = abi.encodeWithSelector(
            IInitializableDebtToken.initialize.selector,
            cachedPool,
            input.asset,
            input.incentivesController,
            decimals,
            input.name,
            input.symbol,
            input.params
        );

        _upgradeTokenImplementation(
            reserveData.variableDebtTokenAddress, input.implementation, encodedCall
        );

        emit VariableDebtTokenUpgraded(
            input.asset, reserveData.variableDebtTokenAddress, input.implementation
        );
    }

    /**
     * @dev Enables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function enableBorrowingOnReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setBorrowingEnabled(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit BorrowingEnabledOnReserve(asset, reserveType);
    }

    /**
     * @dev Disables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function disableBorrowingOnReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setBorrowingEnabled(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);
        emit BorrowingDisabledOnReserve(asset, reserveType);
    }

    /**
     * @dev Configures the reserve collateralization parameters
     * all the values are expressed in percentages with two decimals of precision. A valid value is 10000, which means 100.00%
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset. The values is always above 100%. A value of 105%
     * means the liquidator will receive a 5% bonus
     *
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

        //validation of the parameters: the LTV can
        //only be lower or equal than the liquidation threshold
        //(otherwise a loan against the asset would cause instantaneous liquidation)
        require(ltv <= liquidationThreshold, Errors.LPC_INVALID_CONFIGURATION);

        if (liquidationThreshold != 0) {
            //liquidation bonus must be bigger than 100.00%, otherwise the liquidator would receive less
            //collateral than needed to cover the debt
            require(
                liquidationBonus > PercentageMath.PERCENTAGE_FACTOR,
                Errors.LPC_INVALID_CONFIGURATION
            );

            //if threshold * bonus is less than PERCENTAGE_FACTOR, it's guaranteed that at the moment
            //a loan is taken there is enough collateral available to cover the liquidation bonus
            require(
                liquidationThreshold.percentMul(liquidationBonus)
                    <= PercentageMath.PERCENTAGE_FACTOR,
                Errors.LPC_INVALID_CONFIGURATION
            );
        } else {
            require(liquidationBonus == 0, Errors.LPC_INVALID_CONFIGURATION);
            //if the liquidation threshold is being set to 0,
            // the reserve is being disabled as collateral. To do so,
            //we need to ensure no liquidity is deposited
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
     * @dev Activates a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function activateReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setActive(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveActivated(asset, reserveType);
    }

    /**
     * @dev Deactivates a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
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
     * @dev Freezes a reserve. A frozen reserve doesn't allow any new deposit, or borrow
     *  but allows repayments, liquidations, and withdrawals
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function freezeReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFrozen(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveFrozen(asset, reserveType);
    }

    /**
     * @dev Unfreezes a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function unfreezeReserve(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFrozen(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveUnfrozen(asset, reserveType);
    }

    /**
     * @dev Enable Flash loan.
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function enableFlashloan(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFlashLoanEnabled(true);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit EnableFlashloan(asset, reserveType);
    }

    /**
     * @dev Disable Flash loan.
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     *
     */
    function disableFlashloan(address asset, bool reserveType) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setFlashLoanEnabled(false);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit DisableFlashloan(asset, reserveType);
    }

    /**
     * @dev Updates the reserve factor of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param reserveFactor The new reserve factor of the reserve
     *
     */
    function setCod3xReserveFactor(address asset, bool reserveType, uint256 reserveFactor)
        external
        onlyPoolAdmin
    {
        DataTypes.ReserveConfigurationMap memory currentConfig =
            pool.getConfiguration(asset, reserveType);

        currentConfig.setCod3xReserveFactor(reserveFactor);

        pool.setConfiguration(asset, reserveType, currentConfig.data);

        emit ReserveFactorChanged(asset, reserveType, reserveFactor);
    }

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
     * @dev Sets the interest rate strategy of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param rateStrategyAddress The new address of the interest strategy contract
     *
     */
    function setReserveInterestRateStrategyAddress(
        address asset,
        bool reserveType,
        address rateStrategyAddress
    ) external onlyPoolAdmin {
        pool.setReserveInterestRateStrategyAddress(asset, reserveType, rateStrategyAddress);
        emit ReserveInterestRateStrategyChanged(asset, reserveType, rateStrategyAddress);
    }

    /**
     * @dev pauses or unpauses all the actions of the protocol, including aToken transfers
     * @param val true if protocol needs to be paused, false otherwise
     *
     */
    function setPoolPause(bool val) external onlyEmergencyAdmin {
        pool.setPause(val);
    }

    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal) external onlyPoolAdmin {
        require(
            newFlashloanPremiumTotal <= PercentageMath.PERCENTAGE_FACTOR,
            Errors.LPC_FLASHLOAN_PREMIUM_INVALID
        );
        uint128 oldFlashloanPremiumTotal = pool.FLASHLOAN_PREMIUM_TOTAL();
        pool.updateFlashLoanFee(newFlashloanPremiumTotal);
        emit FlashloanPremiumTotalUpdated(oldFlashloanPremiumTotal, newFlashloanPremiumTotal);
    }

    function _initTokenWithProxy(address implementation, bytes memory initParams)
        internal
        returns (address)
    {
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            new InitializableImmutableAdminUpgradeabilityProxy(address(this));

        proxy.initialize(implementation, initParams);

        return address(proxy);
    }

    function _upgradeTokenImplementation(
        address proxyAddress,
        address implementation,
        bytes memory initParams
    ) internal {
        InitializableImmutableAdminUpgradeabilityProxy proxy =
            InitializableImmutableAdminUpgradeabilityProxy(payable(proxyAddress));

        proxy.upgradeToAndCall(implementation, initParams);
    }

    function _checkNoLiquidity(address asset, bool reserveType) internal view {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(asset, reserveType);

        uint256 availableLiquidity = IERC20Detailed(asset).balanceOf(reserveData.aTokenAddress);

        require(
            availableLiquidity == 0 && reserveData.currentLiquidityRate == 0,
            Errors.LPC_RESERVE_LIQUIDITY_NOT_0
        );
    }

    function setFarmingPct(address aTokenAddress, uint256 farmingPct) external onlyPoolAdmin {
        pool.setFarmingPct(aTokenAddress, farmingPct);
    }

    function setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)
        external
        onlyPoolAdmin
    {
        pool.setClaimingThreshold(aTokenAddress, claimingThreshold);
    }

    function setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift)
        external
        onlyPoolAdmin
    {
        pool.setFarmingPctDrift(aTokenAddress, _farmingPctDrift);
    }

    function setProfitHandler(address aTokenAddress, address _profitHandler)
        external
        onlyPoolAdmin
    {
        pool.setProfitHandler(aTokenAddress, _profitHandler);
    }

    function setVault(address aTokenAddress, address _vault) external onlyPoolAdmin {
        pool.setVault(aTokenAddress, _vault);
    }

    function rebalance(address aTokenAddress) external onlyEmergencyAdmin {
        pool.rebalance(aTokenAddress);
    }

    function getTotalManagedAssets(address aTokenAddress) external view returns (uint256) {
        return pool.getTotalManagedAssets(aTokenAddress);
    }

    function setRewarderForReserve(address asset, bool reserveType, address rewarder)
        external
        onlyPoolAdmin
    {
        pool.setRewarderForReserve(asset, reserveType, rewarder);
    }

    function setTreasury(address asset, bool reserveType, address rewarder)
        external
        onlyPoolAdmin
    {
        pool.setTreasury(asset, reserveType, rewarder);
    }
}
