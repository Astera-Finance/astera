// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {Address} from "contracts/dependencies/openzeppelin/contracts/Address.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {IFlashLoanReceiver} from "contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import {IPriceOracleGetter} from "contracts/interfaces/IPriceOracleGetter.sol";
import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";
import {VersionedInitializable} from
    "contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {Helpers} from "contracts/protocol/libraries/helpers/Helpers.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveLogic} from "contracts/protocol/libraries/logic/ReserveLogic.sol";
import {GenericLogic} from "contracts/protocol/libraries/logic/GenericLogic.sol";
import {ValidationLogic} from "contracts/protocol/libraries/logic/ValidationLogic.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {LendingPoolStorage} from "./LendingPoolStorage.sol";

import {DepositLogic} from "contracts/protocol/libraries/logic/DepositLogic.sol";
import {WithdrawLogic} from "contracts/protocol/libraries/logic/WithdrawLogic.sol";
import {BorrowLogic} from "contracts/protocol/libraries/logic/BorrowLogic.sol";
import {FlashLoanLogic} from "contracts/protocol/libraries/logic/FlashLoanLogic.sol";
import {LiquidationLogic} from "contracts/protocol/libraries/logic/LiquidationLogic.sol";

/**
 * @title LendingPool contract
 * @dev Main point of interaction with an Aave protocol's market
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Borrow
 *   # Repay
 *   # Enable/disable their deposits as collateral
 *   # Liquidate positions
 *   # Execute Flash Loans
 * - To be covered by a proxy contract, owned by the LendingPoolAddressesProvider of the specific market
 * - All admin functions are callable by the LendingPoolConfigurator contract defined also in the
 *   LendingPoolAddressesProvider
 * @author Aave
 *
 */
contract LendingPool is VersionedInitializable, ILendingPool, LendingPoolStorage {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant LENDINGPOOL_REVISION = 0x2;

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    modifier onlyLendingPoolConfigurator() {
        _onlyLendingPoolConfigurator();
        _;
    }

    function _whenNotPaused() internal view {
        require(!_paused, Errors.LP_IS_PAUSED);
    }

    function _onlyLendingPoolConfigurator() internal view {
        require(
            _addressesProvider.getLendingPoolConfigurator() == msg.sender,
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
    }

    function getRevision() internal pure override returns (uint256) {
        return LENDINGPOOL_REVISION;
    }

    /**
     * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
     * LendingPoolAddressesProvider of the market.
     * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
     *   on subsequent operations
     * @param provider The address of the LendingPoolAddressesProvider
     *
     */
    function initialize(ILendingPoolAddressesProvider provider) public initializer {
        _addressesProvider = provider;
        _updateFlashLoanFee(9);
        _maxNumberOfReserves = 128;
    }

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     *
     */
    function deposit(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
    {
        DepositLogic.deposit(
            DepositLogic.DepositParams(asset, reserveType, amount, onBehalfOf),
            _reserves,
            _usersConfig,
            _addressesProvider
        );
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param reserveType Whether the reserve is boosted by a vault
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     *
     */
    function withdraw(address asset, bool reserveType, uint256 amount, address to)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        return WithdrawLogic.withdraw(
            WithdrawLogic.withdrawParams(asset, reserveType, amount, to, _reservesCount),
            _reserves,
            _usersConfig,
            _reservesList,
            _addressesProvider
        );
    }

    /**
     * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already deposited enough collateral, or he was given enough allowance by a credit delegator on the VariableDebtToken
     * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
     *   and 100 variable debt tokens
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance
     *
     */
    function borrow(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
    {
        DataTypes.ReserveData storage reserve = _reserves[asset][reserveType];

        BorrowLogic.executeBorrow(
            BorrowLogic.ExecuteBorrowParams(
                asset,
                reserveType,
                msg.sender,
                onBehalfOf,
                amount,
                reserve.aTokenAddress,
                true,
                _addressesProvider,
                _reservesCount
            ),
            _reserves,
            _reservesList,
            _usersConfig,
            _usersRecentBorrow
        );
    }

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * - E.g. User repays 100 USDC, burning 100 variable debt tokens of the `onBehalfOf` address
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param reserveType Whether the reserve is boosted by a vault
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset`
     * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
     * user calling the function if he wants to reduce/remove his own debt, or the address of any other
     * other borrower whose debt should be removed
     * @return The final amount repaid
     *
     */
    function repay(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        return BorrowLogic.repay(
            BorrowLogic.repayParams(asset, reserveType, amount, onBehalfOf, _addressesProvider),
            _reserves,
            _usersConfig
        );
    }

    function repayWithATokens(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        return BorrowLogic.repayWithAtokens(
            BorrowLogic.repayParams(asset, reserveType, amount, onBehalfOf, _addressesProvider),
            _reserves,
            _usersConfig
        );
    }

    /**
     * @dev Allows depositors to enable/disable a specific deposited asset as collateral
     * @param asset The address of the underlying asset deposited
     * @param reserveType Whether the reserve is boosted by a vault
     * @param useAsCollateral `true` if the user wants to use the deposit as collateral, `false` otherwise
     *
     */
    function setUserUseReserveAsCollateral(address asset, bool reserveType, bool useAsCollateral)
        external
        override
        whenNotPaused
    {
        DataTypes.ReserveData storage reserve = _reserves[asset][reserveType];

        ValidationLogic.validateSetUseReserveAsCollateral(
            reserve,
            asset,
            reserveType,
            useAsCollateral,
            _reserves,
            _usersConfig[msg.sender],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, useAsCollateral);

        if (useAsCollateral) {
            emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
        } else {
            emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
        }
    }

    /**
     * @dev Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     *
     */
    function liquidationCall(
        address collateralAsset,
        bool collateralAssetType,
        address debtAsset,
        bool debtAssetType,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override whenNotPaused {
        if (_miniPoolsWithActiveLoans[user]) {
            revert();
        }
        LiquidationLogic.liquidationCall(
            LiquidationLogic.liquidationCallParams(
                collateralAsset,
                collateralAssetType,
                debtAsset,
                debtAssetType,
                user,
                debtToCover,
                receiveAToken,
                address(_addressesProvider)
            )
        );
    }

    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        address oracle;
        uint256 i;
        address currentAsset;
        bool currentType;
        address currentATokenAddress;
        uint256 currentAmount;
        uint256 currentPremium;
        uint256 currentAmountPlusPremium;
        address debtToken;
    }

    /**
     * @dev Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
     * For further details please visit https://developers.aave.com
     * @param flashLoanParams struct containing receiverAddress, onBehalfOf, assets, amounts
     * @param modes Types of the debt to open if the flash loan is not returned:
     *   0 -> Don't open any debt, just revert if funds can't be transferred from the receiver
     *   2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     * @param params Variadic packed params to pass to the receiver as extra information
     *
     */
    function flashLoan(
        FlashLoanParams memory flashLoanParams,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        bytes calldata params
    ) external override whenNotPaused {
        FlashLoanLogic.flashLoan(
            FlashLoanLogic.FlashLoanParams({
                receiverAddress: flashLoanParams.receiverAddress,
                assets: flashLoanParams.assets,
                reserveTypes: flashLoanParams.reserveTypes,
                onBehalfOf: flashLoanParams.onBehalfOf,
                addressesProvider: _addressesProvider,
                reservesCount: _reservesCount,
                flashLoanPremiumTotal: _flashLoanPremiumTotal,
                amounts: amounts,
                modes: modes,
                params: params
            }),
            _reservesList,
            _usersConfig,
            _usersRecentBorrow,
            _reserves
        );
    }

    function miniPoolBorrow(
        address asset,
        bool reserveType,
        uint256 amount,
        address miniPoolAddress,
        address aTokenAddress
    ) external override whenNotPaused {
        require(msg.sender == miniPoolAddress, Errors.LP_CALLER_NOT_MINIPOOL);
        DataTypes.ReserveData storage reserve = _reserves[asset][reserveType];

        BorrowLogic.executeMiniPoolBorrow(
            BorrowLogic.ExecuteMiniPoolBorrowParams(
                asset,
                reserveType,
                amount,
                msg.sender,
                aTokenAddress,
                _addressesProvider,
                _reservesCount
            ),
            _reserves
        );
        _miniPoolsWithActiveLoans[miniPoolAddress] = true;
    }

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     *
     */
    function getReserveData(address asset, bool reserveType)
        external
        view
        override
        returns (DataTypes.ReserveData memory)
    {
        return _reserves[asset][reserveType];
    }

    /**
     * @dev Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     *
     */
    function getUserAccountData(address user)
        external
        view
        override
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        (totalCollateralETH, totalDebtETH, ltv, currentLiquidationThreshold, healthFactor) =
        GenericLogic.calculateUserAccountData(
            user,
            _reserves,
            _usersConfig[user],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        availableBorrowsETH =
            GenericLogic.calculateAvailableBorrowsETH(totalCollateralETH, totalDebtETH, ltv);
    }

    /**
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     *
     */
    function getConfiguration(address asset, bool reserveType)
        external
        view
        override
        returns (DataTypes.ReserveConfigurationMap memory)
    {
        return _reserves[asset][reserveType].configuration;
    }

    /**
     * @dev Returns the borrow configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType The type of the reserve
     * @return The borrow configuration of the reserve
     *
     */
    function getBorrowConfiguration(address asset, bool reserveType)
        external
        view
        override
        returns (DataTypes.ReserveBorrowConfigurationMap memory)
    {
        return _reserves[asset][reserveType].borrowConfiguration;
    }

    /**
     * @dev Returns the configuration of the user across all the reserves
     * @param user The user address
     * @return The configuration of the user
     *
     */
    function getUserConfiguration(address user)
        external
        view
        override
        returns (DataTypes.UserConfigurationMap memory)
    {
        return _usersConfig[user];
    }

    /**
     * @dev Returns the normalized income per unit of asset
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve's normalized income
     */
    function getReserveNormalizedIncome(address asset, bool reserveType)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _reserves[asset][reserveType].getNormalizedIncome();
    }

    /**
     * @dev Returns the normalized variable debt per unit of asset
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve normalized variable debt
     */
    function getReserveNormalizedVariableDebt(address asset, bool reserveType)
        external
        view
        override
        returns (uint256)
    {
        return _reserves[asset][reserveType].getNormalizedDebt();
    }

    /**
     * @dev Returns if the LendingPool is paused
     */
    function paused() external view override returns (bool) {
        return _paused;
    }

    /**
     * @dev Returns the list of the initialized reserves
     *
     */
    function getReservesList() external view override returns (address[] memory, bool[] memory) {
        address[] memory _activeReserves = new address[](_reservesCount);
        bool[] memory _activeReservesTypes = new bool[](_reservesCount);

        for (uint256 i = 0; i < _reservesCount; i++) {
            _activeReserves[i] = _reservesList[i].asset;
            _activeReservesTypes[i] = _reservesList[i].reserveType;
        }
        return (_activeReserves, _activeReservesTypes);
    }

    function getReservesCount() external view override returns (uint256) {
        return _reservesCount;
    }
    /**
     * @dev Returns the cached LendingPoolAddressesProvider connected to this contract
     *
     */

    function getAddressesProvider()
        external
        view
        override
        returns (ILendingPoolAddressesProvider)
    {
        return _addressesProvider;
    }

    /**
     * @dev Returns the fee on flash loans
     */
    function FLASHLOAN_PREMIUM_TOTAL() public view returns (uint128) {
        return _flashLoanPremiumTotal;
    }

    /**
     * @dev Returns the maximum number of reserves supported to be listed in this LendingPool
     */
    function MAX_NUMBER_RESERVES() public view returns (uint256) {
        return _maxNumberOfReserves;
    }

    /**
     * @dev Validates and finalizes an aToken transfer
     * - Only callable by the overlying aToken of the `asset`
     * @param asset The address of the underlying asset of the aToken
     * @param from The user from which the aTokens are transferred
     * @param to The user receiving the aTokens
     * @param amount The amount being transferred/withdrawn
     * @param balanceFromBefore The aToken balance of the `from` user before the transfer
     * @param balanceToBefore The aToken balance of the `to` user before the transfer
     */
    function finalizeTransfer(
        address asset,
        bool reserveType,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external override whenNotPaused {
        WithdrawLogic.finalizeTransfer(
            WithdrawLogic.finalizeTransferParams(
                asset,
                reserveType,
                from,
                to,
                amount,
                balanceFromBefore,
                balanceToBefore,
                _reservesCount
            ),
            _reserves,
            _usersConfig,
            _reservesList,
            _addressesProvider
        );
    }

    /**
     * @dev Initializes a reserve, activating it, assigning an aToken and debt tokens and an
     * interest rate strategy
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param aTokenAddress The address of the aToken that will be assigned to the reserve
     * @param aTokenAddress The address of the VariableDebtToken that will be assigned to the reserve
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     *
     */
    function initReserve(
        address asset,
        bool reserveType,
        address aTokenAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external override onlyLendingPoolConfigurator {
        require(Address.isContract(asset), Errors.LP_NOT_CONTRACT);
        _reserves[asset][reserveType].init(
            aTokenAddress, variableDebtAddress, interestRateStrategyAddress
        );
        _addReserveToList(asset, reserveType);
    }

    /**
     * @dev Updates the address of the interest rate strategy contract
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param rateStrategyAddress The address of the interest rate strategy contract
     *
     */
    function setReserveInterestRateStrategyAddress(
        address asset,
        bool reserveType,
        address rateStrategyAddress
    ) external override onlyLendingPoolConfigurator {
        _reserves[asset][reserveType].interestRateStrategyAddress = rateStrategyAddress;
    }

    /**
     * @dev Sets the configuration bitmap of the reserve as a whole
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param reserveType Whether the reserve is boosted by a vault
     * @param configuration The new configuration bitmap
     *
     */
    function setConfiguration(address asset, bool reserveType, uint256 configuration)
        external
        override
        onlyLendingPoolConfigurator
    {
        _reserves[asset][reserveType].configuration.data = configuration;
    }

    /**
     * @dev Sets the borrow configuration bitmap of the reserve as a whole
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param borrowConfiguration The new borrow configuration bitmap
     *
     */
    function setBorrowConfiguration(address asset, bool reserveType, uint256 borrowConfiguration)
        external
        override
        onlyLendingPoolConfigurator
    {
        _reserves[asset][reserveType].borrowConfiguration.data = borrowConfiguration;
        _lendingUpdateTimestamp = block.timestamp;
    }

    /**
     * @dev Set the _pause state of a reserve
     * - Only callable by the LendingPoolConfigurator contract
     * @param val `true` to pause the reserve, `false` to un-pause it
     */
    function setPause(bool val) external override onlyLendingPoolConfigurator {
        _paused = val;
        if (_paused) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }

    function setFarmingPct(address aTokenAddress, uint256 farmingPct)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setFarmingPct(farmingPct);
    }

    function setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setClaimingThreshold(claimingThreshold);
    }

    function setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setFarmingPctDrift(_farmingPctDrift);
    }

    function setProfitHandler(address aTokenAddress, address _profitHandler)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setProfitHandler(_profitHandler);
    }

    function setVault(address aTokenAddress, address _vault)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(aTokenAddress).setVault(_vault);
    }

    function rebalance(address aTokenAddress) external override onlyLendingPoolConfigurator {
        IAToken(aTokenAddress).rebalance();
    }

    function getTotalManagedAssets(address aTokenAddress)
        external
        view
        override
        onlyLendingPoolConfigurator
        returns (uint256)
    {
        return IAToken(aTokenAddress).getTotalManagedAssets();
    }

    function _addReserveToList(address asset, bool reserveType) internal {
        uint256 reservesCount = _reservesCount;

        require(reservesCount < _maxNumberOfReserves, Errors.LP_NO_MORE_RESERVES_ALLOWED);

        bool reserveAlreadyAdded =
            _reserves[asset][reserveType].id != 0 || _reservesList[0].asset == asset;

        if (!reserveAlreadyAdded) {
            _reserves[asset][reserveType].id = uint8(reservesCount);
            _reservesList[reservesCount] = DataTypes.ReserveReference(asset, reserveType);

            _reservesCount = reservesCount + 1;
        }
    }

    function updateFlashLoanFee(uint128 flashLoanPremiumTotal)
        external
        override
        onlyLendingPoolConfigurator
    {
        _updateFlashLoanFee(flashLoanPremiumTotal);
    }

    function _updateFlashLoanFee(uint128 flashLoanPremiumTotal) internal {
        _flashLoanPremiumTotal = flashLoanPremiumTotal;
    }

    function setRewarderForReserve(address asset, bool reserveType, address rewarder)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(_reserves[asset][reserveType].aTokenAddress).setIncentivesController(rewarder);
        IVariableDebtToken(_reserves[asset][reserveType].variableDebtTokenAddress)
            .setIncentivesController(rewarder);
    }

    function setTreasury(address asset, bool reserveType, address treasury)
        external
        override
        onlyLendingPoolConfigurator
    {
        IAToken(_reserves[asset][reserveType].aTokenAddress).setTreasury(treasury);
    }
}
