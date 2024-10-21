// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Address} from "../../../../contracts/dependencies/openzeppelin/contracts/Address.sol";
import {IAERC6909} from "../../../../contracts/interfaces/IAERC6909.sol";
import {IERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "../../../../contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IMiniPoolAddressesProvider} from
    "../../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IFlowLimiter} from "../../../../contracts/interfaces/IFlowLimiter.sol";
import {IAToken} from "../../../../contracts/interfaces/IAToken.sol";
import {IFlashLoanReceiver} from "../../../../contracts/interfaces/IFlashLoanReceiver.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {VersionedInitializable} from
    "../../../../contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {Helpers} from "../../../../contracts/protocol/libraries/helpers/Helpers.sol";
import {Errors} from "../../../../contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "../../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {MiniPoolReserveLogic} from "./logic/MiniPoolReserveLogic.sol";
import {MiniPoolGenericLogic} from "./logic/MiniPoolGenericLogic.sol";
import {MiniPoolValidationLogic} from "./logic/MiniPoolValidationLogic.sol";
import {ReserveConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from
    "../../../../contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "../../../../contracts/protocol/libraries/types/DataTypes.sol";
import {MiniPoolStorage} from "./MiniPoolStorage.sol";
import {IMiniPool} from "../../../../contracts/interfaces/IMiniPool.sol";
import {ATokenNonRebasing} from
    "../../../../contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";

import {MiniPoolDepositLogic} from "./logic/MiniPoolDepositLogic.sol";
import {MiniPoolWithdrawLogic} from "./logic/MiniPoolWithdrawLogic.sol";
import {MiniPoolBorrowLogic} from "./logic/MiniPoolBorrowLogic.sol";
import {MiniPoolFlashLoanLogic} from "./logic/MiniPoolFlashLoanLogic.sol";
import {MiniPoolLiquidationLogic} from "./logic/MiniPoolLiquidationLogic.sol";

/**
 * @title MiniPool contract
 * @dev A highly correlated sub market that can borrow from the main lending pool and charge double interest rates on those loans
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Borrow
 *   # Repay
 *   # Enable/disable their deposits as collateral
 *   # Liquidate positions
 *   # Execute Flash Loans
 * - To be covered by a proxy contract, owned by the MiniPoolAddressesProvider of the specific market
 * - All admin functions are callable by the MiniPoolConfigurator contract defined also in the
 *   MiniPoolAddressesProvider
 * @author Cod3x
 *
 */
contract MiniPool is VersionedInitializable, IMiniPool, MiniPoolStorage {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant MINIPOOL_REVISION = 0x1;

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    modifier onlyMiniPoolConfigurator() {
        _onlyMiniPoolConfigurator();
        _;
    }

    function _whenNotPaused() internal view {
        require(!_paused, Errors.LP_IS_PAUSED);
    }

    function _onlyMiniPoolConfigurator() internal view {
        require(
            _addressesProvider.getMiniPoolConfigurator() == msg.sender,
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
    }

    function getRevision() internal pure override returns (uint256) {
        return MINIPOOL_REVISION;
    }

    /**
     * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
     * LendingPoolAddressesProvider of the market.
     * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
     *   on subsequent operations
     * @param provider The address of the LendingPoolAddressesProvider
     *
     */
    function initialize(IMiniPoolAddressesProvider provider, uint256 minipoolID)
        public
        initializer
    {
        _addressesProvider = provider;
        _minipoolId = minipoolID;
        _flashLoanPremiumTotal = 1;
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
    function deposit(address asset, uint256 amount, address onBehalfOf)
        public
        override
        whenNotPaused
    {
        MiniPoolDepositLogic.deposit(
            MiniPoolDepositLogic.DepositParams(asset, amount, onBehalfOf),
            _reserves,
            _usersConfig,
            _addressesProvider
        );
        _repayLendingPool(asset);
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     *
     */
    function withdraw(address asset, uint256 amount, address to)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        return MiniPoolWithdrawLogic.withdraw(
            MiniPoolWithdrawLogic.withdrawParams(asset, amount, to, _reservesCount),
            _reserves,
            _usersConfig,
            _reservesList,
            _addressesProvider
        );
    }

    struct borrowVars {
        uint256 availableLiquidity;
        uint256 amountRecieved;
        address onBehalfOf;
        address aTokenAddress;
        address LendingPool;
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

    function borrow(address asset, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
    {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];
        borrowVars memory vars;
        vars.aTokenAddress = reserve.aTokenAddress;
        require(vars.aTokenAddress != address(0), "Reserve not initialized");
        vars.availableLiquidity = IERC20(asset).balanceOf(vars.aTokenAddress);
        if (
            amount > vars.availableLiquidity
                && IAERC6909(reserve.aTokenAddress).isTranche(reserve.aTokenID)
        ) {
            address underlying = ATokenNonRebasing(asset).UNDERLYING_ASSET_ADDRESS();
            vars.LendingPool = _addressesProvider.getLendingPool();
            ILendingPool(vars.LendingPool).miniPoolBorrow(
                underlying,
                true,
                ATokenNonRebasing(asset).convertToAssets(amount - vars.availableLiquidity), // amount + availableLiquidity converted to asset
                address(this),
                ATokenNonRebasing(asset).ATOKEN_ADDRESS()
            );

            vars.amountRecieved = IERC20(underlying).balanceOf(address(this));

            IERC20(underlying).approve(vars.LendingPool, vars.amountRecieved);
            ILendingPool(vars.LendingPool).deposit(
                underlying, true, vars.amountRecieved, address(this)
            );

            vars.amountRecieved = IERC20(asset).balanceOf(address(this));
            MiniPoolDepositLogic.internalDeposit(
                MiniPoolDepositLogic.DepositParams(asset, vars.amountRecieved, address(this)),
                _reserves,
                _usersConfig,
                _addressesProvider
            );
        }

        MiniPoolBorrowLogic.executeBorrow(
            MiniPoolBorrowLogic.ExecuteBorrowParams(
                asset,
                msg.sender,
                onBehalfOf,
                amount,
                reserve.aTokenAddress,
                0,
                0,
                0,
                true,
                _addressesProvider,
                _reservesCount
            ),
            _reserves,
            _reservesList,
            _usersConfig
        );
    }

    struct repayVars {
        uint256 repayAmount;
        address aTokenAddress;
        address underlyingAsset;
        uint256 underlyingDebt;
    }

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * - E.g. User repays 100 USDC, burning 100 variable debt tokens of the `onBehalfOf` address
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset`
     * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
     * user calling the function if he wants to reduce/remove his own debt, or the address of any other
     * other borrower whose debt should be removed
     * @return The final amount repaid
     *
     */
    function repay(address asset, uint256 amount, address onBehalfOf)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        uint256 repayAmount = MiniPoolBorrowLogic.repay(
            MiniPoolBorrowLogic.repayParams(asset, amount, onBehalfOf, _addressesProvider),
            _reserves,
            _usersConfig
        );

        _repayLendingPool(asset);
        return repayAmount;
    }

    /**
     * @dev Allows depositors to enable/disable a specific deposited asset as collateral
     * @param asset The address of the underlying asset deposited
     * @param useAsCollateral `true` if the user wants to use the deposit as collateral, `false` otherwise
     *
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral)
        external
        override
        whenNotPaused
    {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];

        MiniPoolValidationLogic.validateSetUseReserveAsCollateral(
            reserve,
            asset,
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
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override whenNotPaused {
        MiniPoolLiquidationLogic.liquidationCall(
            _reserves,
            _usersConfig,
            _reservesList,
            MiniPoolLiquidationLogic.liquidationCallParams(
                address(_addressesProvider),
                _reservesCount,
                collateralAsset,
                debtAsset,
                user,
                debtToCover,
                receiveAToken
            )
        );
        _repayLendingPool(debtAsset);
    }

    function _repayLendingPool(address asset) internal {
        DataTypes.MiniPoolReserveData storage reserve = _reserves[asset];
        repayVars memory vars;
        vars.aTokenAddress = reserve.aTokenAddress;
        if (IAERC6909(reserve.aTokenAddress).isTranche(reserve.aTokenID)) {
            vars.underlyingAsset = ATokenNonRebasing(asset).UNDERLYING_ASSET_ADDRESS();
            vars.underlyingDebt = ATokenNonRebasing(asset).convertToShares(
                getCurrentLendingPoolDebt(vars.underlyingAsset)
            ); // share
            if (vars.underlyingDebt != 0) {
                uint256 amount = vars.underlyingDebt;

                MiniPoolWithdrawLogic.internalWithdraw(
                    MiniPoolWithdrawLogic.withdrawParams(
                        asset, amount, address(this), _reservesCount
                    ),
                    _reserves,
                    _usersConfig,
                    _reservesList,
                    _addressesProvider
                ); // MUST use share

                IERC20 aToken = IERC20(ATokenNonRebasing(asset).ATOKEN_ADDRESS());
                amount = aToken.balanceOf(address(this)); // asset
                aToken.approve(_addressesProvider.getLendingPool(), amount);
                ILendingPool(_addressesProvider.getLendingPool()).repayWithATokens(
                    vars.underlyingAsset, true, amount
                ); // MUST use asset

                IAERC6909 aToken6909 = IAERC6909(reserve.aTokenAddress);
                uint256 aTokenId = reserve.aTokenID;
                uint256 remainingBalance = aToken6909.balanceOf(address(this), aTokenId);
                if (getCurrentLendingPoolDebt(vars.underlyingAsset) == 0 && remainingBalance != 0) {
                    // Send the remaining AERC6909 to Treasury. This is due to Minipool IR > Lending IR.
                    aToken6909.transfer(
                        _addressesProvider.getMiniPoolTreasury(_minipoolId),
                        aTokenId,
                        aToken6909.balanceOf(address(this), aTokenId)
                    );
                }
            }
        }
    }

    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        address oracle;
        uint256 i;
        address currentAsset;
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
        MiniPoolFlashLoanLogic.flashLoan(
            MiniPoolFlashLoanLogic.FlashLoanParams(
                flashLoanParams.receiverAddress,
                flashLoanParams.assets,
                flashLoanParams.onBehalfOf,
                _addressesProvider,
                _reservesCount,
                _flashLoanPremiumTotal,
                amounts,
                modes,
                params
            ),
            _reservesList,
            _usersConfig,
            _reserves
        );
    }

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     *
     */
    function getReserveData(address asset)
        external
        view
        override
        returns (DataTypes.MiniPoolReserveData memory)
    {
        return _reserves[asset];
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
        MiniPoolGenericLogic.calculateUserAccountData(
            user,
            _reserves,
            _usersConfig[user],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        availableBorrowsETH =
            MiniPoolGenericLogic.calculateAvailableBorrowsETH(totalCollateralETH, totalDebtETH, ltv);
    }

    /**
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     *
     */
    function getConfiguration(address asset)
        external
        view
        override
        returns (DataTypes.ReserveConfigurationMap memory)
    {
        return _reserves[asset].configuration;
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
    function getReserveNormalizedIncome(address asset)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _reserves[asset].getNormalizedIncome();
    }

    /**
     * @dev Returns the normalized variable debt per unit of asset
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve normalized variable debt
     */
    function getReserveNormalizedVariableDebt(address asset)
        external
        view
        override
        returns (uint256)
    {
        return _reserves[asset].getNormalizedDebt();
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
            _activeReservesTypes[i] = false;
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

    function getAddressesProvider() external view override returns (IMiniPoolAddressesProvider) {
        return _addressesProvider;
    }

    /**
     * @dev Returns the fee on flash loans
     */
    function FLASHLOAN_PREMIUM_TOTAL() public view returns (uint256) {
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
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external override whenNotPaused {
        MiniPoolWithdrawLogic.finalizeTransfer(
            MiniPoolWithdrawLogic.finalizeTransferParams(
                asset, from, to, amount, balanceFromBefore, balanceToBefore, _reservesCount
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
     * @param aTokenAddress Whether the reserve is boosted by a vault
     * @param aTokenID The address of the aToken that will be assigned to the reserve
     * @param variableDebtTokenID The address of the VariableDebtToken that will be assigned to the reserve
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     *
     */
    function initReserve(
        address asset,
        IAERC6909 aTokenAddress,
        uint256 aTokenID,
        uint256 variableDebtTokenID,
        address interestRateStrategyAddress
    ) external override onlyMiniPoolConfigurator {
        require(Address.isContract(asset), Errors.LP_NOT_CONTRACT);
        _reserves[asset].init(
            asset, aTokenAddress, aTokenID, variableDebtTokenID, interestRateStrategyAddress
        );
        _addReserveToList(asset);
    }

    /**
     * @dev Updates the address of the interest rate strategy contract
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param rateStrategyAddress The address of the interest rate strategy contract
     *
     */
    function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress)
        external
        override
        onlyMiniPoolConfigurator
    {
        _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
    }

    /**
     * @dev Sets the configuration bitmap of the reserve as a whole
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param configuration The new configuration bitmap
     *
     */
    function setConfiguration(address asset, uint256 configuration)
        external
        override
        onlyMiniPoolConfigurator
    {
        _reserves[asset].configuration.data = configuration;
    }

    /**
     * @dev Set the _pause state of a reserve
     * - Only callable by the LendingPoolConfigurator contract
     * @param val `true` to pause the reserve, `false` to un-pause it
     */
    function setPause(bool val) external override onlyMiniPoolConfigurator {
        _paused = val;
        if (_paused) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }

    function _addReserveToList(address asset) internal {
        uint256 reservesCount = _reservesCount;

        require(reservesCount < _maxNumberOfReserves, Errors.LP_NO_MORE_RESERVES_ALLOWED);

        bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0].asset == asset;

        if (!reserveAlreadyAdded) {
            _reserves[asset].id = uint8(reservesCount);
            _reservesList[reservesCount] = DataTypes.ReserveReference(asset, false);

            _reservesCount = reservesCount + 1;
        }
    }

    function getCurrentLendingPoolDebt(address asset) public view returns (uint256) {
        return IFlowLimiter(_addressesProvider.getFlowLimiter()).currentFlow(asset, address(this));
    }
}
