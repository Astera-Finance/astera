// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {IReserveInterestRateStrategy} from
    "../../../contracts/interfaces/IReserveInterestRateStrategy.sol";
import {WadRayMath} from "../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {ILendingPoolAddressesProvider} from
    "../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IERC20} from "../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IAToken} from "../../../contracts/interfaces/IAToken.sol";
import {Errors} from "../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ILendingPool} from "../../../contracts/interfaces/ILendingPool.sol";
import {ReserveConfiguration} from
    "../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

/**
 * @title MockLendingpoolReserveInterestRateStrategy contract
 * @author Cod3x
 *
 */
contract MockLendingpoolReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    ILendingPoolAddressesProvider public immutable addressesProvider;

    uint256 public currentBorrowRate;
    uint256 public currentLiquidityRate;

    constructor(
        ILendingPoolAddressesProvider provider_,
        uint256 initialBorrowRate_,
        uint256 initialLiquidityRate_
    ) {
        addressesProvider = provider_;
        currentBorrowRate = initialBorrowRate_;
        currentLiquidityRate = initialLiquidityRate_;
    }

    function setRates(uint256 nextBorrowRate_, uint256 nextLiquidityRate_) public {
        currentBorrowRate = nextBorrowRate_;
        currentLiquidityRate = nextLiquidityRate_;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations
     * @param reserve The address of the reserve
     * @param liquidityAdded The liquidity added during the operation
     * @param liquidityTaken The liquidity taken during the operation
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return The liquidity rate and the variable borrow rate
     */
    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view returns (uint256, uint256) {
        uint256 availableLiquidity = IAToken(aToken).getTotalManagedAssets();
        if (availableLiquidity + liquidityAdded < liquidityTaken) {
            revert(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW);
        }
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return calculateInterestRates(reserve, availableLiquidity, totalVariableDebt, reserveFactor);
    }

    function calculateInterestRates(address, uint256, uint256, uint256)
        public
        view
        returns (uint256, uint256)
    {
        return (currentLiquidityRate, currentBorrowRate);
    }

    function getCod3xReserveFactor(address _asset) public view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory reserve = ILendingPool(
            ILendingPoolAddressesProvider(addressesProvider).getLendingPool()
        ).getConfiguration(_asset, true);
        return _getCod3xReserveFactor(reserve);
    }

    function _getCod3xReserveFactor(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (uint256)
    {
        return (self.data & ~ReserveConfiguration.COD3X_RESERVE_FACTOR_MASK)
            >> ReserveConfiguration.COD3X_RESERVE_FACTOR_START_BIT_POSITION;
    }
}
