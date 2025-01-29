// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {ILendingPoolAddressesProvider} from
    "../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title ILendingPool interface.
 * @author Cod3x
 */
interface ILendingPool {
    /**
     * @dev Emitted on deposit()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address initiating the deposit
     * @param onBehalfOf The beneficiary of the deposit, receiving the aTokens
     * @param amount The amount deposited
     */
    event Deposit(
        address indexed reserve, address user, address indexed onBehalfOf, uint256 amount
    );

    /**
     * @dev Emitted on withdraw()
     * @param reserve The address of the underlyng asset being withdrawn
     * @param user The address initiating the withdrawal, owner of aTokens
     * @param to Address that will receive the underlying
     * @param amount The amount to be withdrawn
     */
    event Withdraw(
        address indexed reserve, address indexed user, address indexed to, uint256 amount
    );

    /**
     * @dev Emitted on borrow() and flashLoan() when debt needs to be opened
     * @param reserve The address of the underlying asset being borrowed
     * @param user The address of the user initiating the borrow(), receiving the funds on borrow() or just
     * initiator of the transaction on flashLoan()
     * @param onBehalfOf The address that will be getting the debt
     * @param amount The amount borrowed out
     * @param borrowRate The numeric rate at which the user has borrowed
     */
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );

    /**
     * @dev Emitted on repay()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The beneficiary of the repayment, getting his debt reduced
     * @param repayer The address of the user initiating the repay(), providing the funds
     * @param amount The amount repaid
     */
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount
    );

    /**
     * @dev Emitted on setUserUseReserveAsCollateral()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address of the user enabling the usage as collateral
     */
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted on setUserUseReserveAsCollateral()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address of the user enabling the usage as collateral
     */
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted on flashLoan()
     * @param target The address of the flash loan receiver contract
     * @param initiator The address initiating the flash loan
     * @param asset The address of the asset being flash borrowed
     * @param interestRateMode The interest rate mode selected for the flash loan:
     *   0 -> Don't open any debt, just revert if funds can't be transferred from the receiver
     *   != 0 -> Open debt at variable rate for the value of the amount flash-borrowed
     * @param amount The amount flash borrowed
     * @param premium The fee charged for the flash loan
     */
    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed asset,
        DataTypes.InterestRateMode interestRateMode,
        uint256 amount,
        uint256 premium
    );

    /**
     * @dev Emitted when the pause is triggered.
     */
    event Paused();

    /**
     * @dev Emitted when the pause is lifted.
     */
    event Unpaused();

    /**
     * @dev Emitted when a borrower is liquidated. This event is emitted by the LendingPool via
     * LendingPoolCollateral manager using a DELEGATECALL
     * This allows to have the events in the generated ABI for LendingPool.
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param liquidatedCollateralAmount The amount of collateral received by the liiquidator
     * @param liquidator The address of the liquidator
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     */
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken
    );

    /**
     * @dev Emitted when the state of a reserve is updated. NOTE: This event is actually declared
     * in the ReserveLogic library and emitted in the updateInterestRates() function. Since the function is internal,
     * the event will actually be fired by the LendingPool contract. The event is therefore replicated here so it
     * gets added to the LendingPool ABI
     * @param reserve The address of the underlying asset of the reserve
     * @param liquidityRate The new liquidity rate
     * @param variableBorrowRate The new variable borrow rate
     * @param liquidityIndex The new liquidity index
     * @param variableBorrowIndex The new variable borrow index
     */
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    /**
     * @dev Emitted when the flash loan fee is updated.
     * @param flashLoanPremiumTotal The new flash loan fee.
     */
    event FlashLoanFeeUpdated(uint128 flashLoanPremiumTotal);

    function deposit(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external;

    function withdraw(address asset, bool reserveType, uint256 amount, address to)
        external
        returns (uint256);

    function borrow(address asset, bool reserveType, uint256 amount, address onBehalfOf) external;

    function repay(address asset, bool reserveType, uint256 amount, address onBehalfOf)
        external
        returns (uint256);

    function miniPoolBorrow(address asset, bool reserveType, uint256 amount, address aTokenAddress)
        external;

    function repayWithATokens(address asset, bool reserveType, uint256 amount)
        external
        returns (uint256);

    function setUserUseReserveAsCollateral(address asset, bool reserveType, bool useAsCollateral)
        external;

    function liquidationCall(
        address collateralAsset,
        bool collateralAssetType,
        address debtAsset,
        bool debtAssetType,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    struct FlashLoanParams {
        address receiverAddress;
        address[] assets;
        bool[] reserveTypes;
        address onBehalfOf;
    }

    function flashLoan(
        FlashLoanParams memory flashLoanParams,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        bytes calldata params
    ) external;

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    function initReserve(
        address reserve,
        bool reserveType,
        address aTokenAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external;

    function setReserveInterestRateStrategyAddress(
        address reserve,
        bool reserveType,
        address rateStrategyAddress
    ) external;

    function setConfiguration(address reserve, bool reserveType, uint256 configuration) external;

    function getConfiguration(address asset, bool reserveType)
        external
        view
        returns (DataTypes.ReserveConfigurationMap memory);

    function getUserConfiguration(address user)
        external
        view
        returns (DataTypes.UserConfigurationMap memory);

    function getReserveNormalizedIncome(address asset, bool reserveType)
        external
        view
        returns (uint256);

    function getReserveNormalizedVariableDebt(address asset, bool reserveType)
        external
        view
        returns (uint256);

    function getReserveData(address asset, bool reserveType)
        external
        view
        returns (DataTypes.ReserveData memory);

    function finalizeTransfer(
        address asset,
        bool reserveType,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external;

    function getReservesList() external view returns (address[] memory, bool[] memory);

    function getReservesCount() external view returns (uint256);

    function getAddressesProvider() external view returns (ILendingPoolAddressesProvider);

    function MAX_NUMBER_RESERVES() external view returns (uint256);

    function setPause(bool val) external;

    function paused() external view returns (bool);

    function setFarmingPct(address aTokenAddress, uint256 farmingPct) external;

    function setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold) external;

    function setFarmingPctDrift(address aTokenAddress, uint256 farmingPctDrift) external;

    function setProfitHandler(address aTokenAddress, address profitHandler) external;

    function setVault(address aTokenAddress, address vault) external;

    function rebalance(address aTokenAddress) external;

    function getTotalManagedAssets(address aTokenAddress) external view returns (uint256);

    function updateFlashLoanFee(uint128 flashLoanPremiumTotal) external;

    function setRewarderForReserve(address asset, bool reserveType, address rewarder) external;

    function setTreasury(address asset, bool reserveType, address treasury) external;

    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);

    function getATokenNonRebasingFromAtoken(address aToken) external view returns (address);

    function syncIndexesState(address asset, bool reserveType) external;

    function syncRatesState(address asset, bool reserveType) external;
}
