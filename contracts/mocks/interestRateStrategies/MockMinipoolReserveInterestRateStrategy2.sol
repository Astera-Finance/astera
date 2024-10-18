// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IMiniPoolReserveInterestRateStrategy} from
    "../../../contracts/interfaces/IMiniPoolReserveInterestRateStrategy.sol";
import {WadRayMath} from "../../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../contracts/protocol/libraries/math/PercentageMath.sol";
import {ILendingPoolAddressesProvider} from
    "../../../contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IERC20} from "../../../contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IMiniPoolAddressesProvider} from
    "../../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IFlowLimiter} from "../../../contracts/interfaces/IFlowLimiter.sol";
import {IAToken} from "../../../contracts/interfaces/IAToken.sol";
import {IAERC6909} from "../../../contracts/interfaces/IAERC6909.sol";
import {Errors} from "../../../contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "../../../contracts/protocol/libraries/types/DataTypes.sol";
import {ILendingPool} from "../../../contracts/interfaces/ILendingPool.sol";
import {ReserveConfiguration} from
    "../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {IMiniPool} from "../../../contracts/interfaces/IMiniPool.sol";

/**
 * @title MockMinipoolReserveInterestRateStrategy2 contract
 * @author Cod3x
 *
 */
contract MockMinipoolReserveInterestRateStrategy2 {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    IMiniPoolAddressesProvider public immutable addressesProvider;

    uint256 public currentBorrowRate;
    uint256 public currentLiquidityRate;

    constructor(
        IMiniPoolAddressesProvider provider_,
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
     *
     */
    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view returns (uint256, uint256) {
        uint256 availableLiquidity;
        (,, bool isTranched) = IAERC6909(aToken).getIdForUnderlying(reserve);
        if (isTranched) {
            IFlowLimiter flowLimiter = IFlowLimiter(addressesProvider.getFlowLimiter());
            address underlying = IAToken(reserve).UNDERLYING_ASSET_ADDRESS();
            address minipool = IAERC6909(aToken).MINIPOOL_ADDRESS();

            availableLiquidity = IERC20(reserve).balanceOf(aToken)
                + IAToken(reserve).convertToShares(flowLimiter.getFlowLimit(underlying, minipool))
                - IAToken(reserve).convertToShares(flowLimiter.currentFlow(underlying, minipool));
        } else {
            availableLiquidity = IERC20(reserve).balanceOf(aToken);
        }

        if (availableLiquidity + liquidityAdded < liquidityTaken) {
            revert(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW);
        }

        //avoid stack too deep
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return calculateInterestRates(reserve, availableLiquidity, totalVariableDebt, reserveFactor);
    }

    function calculateInterestRates(address, uint256, uint256, uint256)
        public
        view
        returns (uint256, uint256)
    {
        // // Here we make sure that BR_Asset(LP) / LR_Asset(LP) <= LR_aAsset(MP) if minipool has Flow.
        // if (currentFlow != 0) {
        //     DataTypes.ReserveData memory r =
        //         ILendingPool(_addressesProvider.getLendingPool()).getReserveData(underlying, true);
        //     uint40 timeDelta = uint40(block.timestamp - DELTA_TIME_MARGIN);
        //     uint256 irDelta = r.currentVariableBorrowRate - r.currentLiquidityRate;
        //     uint256 irMargin = IR_MULTIPLIER
        //         * (
        //             MathUtils.calculateCompoundedInterest(irDelta, timeDelta)
        //                 - MathUtils.calculateLinearInterest(irDelta, timeDelta)
        //         );
        //     uint256 minVariableBorrowRate = irDelta + irMargin;
        //     if (vars.currentVariableBorrowRate < minVariableBorrowRate) {
        //         vars.currentVariableBorrowRate = minVariableBorrowRate;
        //     }
        // }
        return (currentLiquidityRate, currentBorrowRate);
    }

    function getReserveFactor(address _asset, uint256 _minipoolId) public view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory reserve = IMiniPool(
            IMiniPoolAddressesProvider(addressesProvider).getMiniPool(_minipoolId)
        ).getConfiguration(_asset);
        return getReserveFactor(reserve);
    }

    function getReserveFactor(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (uint256)
    {
        return (self.data & ~ReserveConfiguration.RESERVE_FACTOR_MASK)
            >> ReserveConfiguration.RESERVE_FACTOR_START_BIT_POSITION;
    }
}
