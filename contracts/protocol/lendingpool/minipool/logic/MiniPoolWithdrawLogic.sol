// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {SafeMath} from "../../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {IAERC6909} from "../../../../interfaces/IAERC6909.sol";
import {IERC20} from "../../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {IMiniPoolAddressesProvider} from "../../../../interfaces/IMiniPoolAddressesProvider.sol";
import {SafeERC20} from "../../../../dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IReserveInterestRateStrategy} from "../../../../interfaces/IReserveInterestRateStrategy.sol";
import {ReserveConfiguration} from "../../../libraries/configuration/ReserveConfiguration.sol";
import {ReserveBorrowConfiguration} from
    "../../../libraries/configuration/ReserveBorrowConfiguration.sol";
import {MathUtils} from "../../../libraries/math/MathUtils.sol";
import {WadRayMath} from "../../../libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../../libraries/math/PercentageMath.sol";
import {Errors} from "../../../libraries/helpers/Errors.sol";
import {DataTypes} from "../../../libraries/types/DataTypes.sol";
import {MiniPoolReserveLogic} from "./MiniPoolReserveLogic.sol";
import {UserConfiguration} from "../../../libraries/configuration/UserConfiguration.sol";
import {MiniPoolValidationLogic} from "./MiniPoolValidationLogic.sol";

/**
 * @title withdraw Logic library
 * @notice Implements the logic to withdraw assets into the protocol
 */
library MiniPoolWithdrawLogic {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using MiniPoolReserveLogic for DataTypes.MiniPoolReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);
    event Withdraw(
        address indexed reserve, address indexed user, address indexed to, uint256 amount
    );
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    struct withdrawParams {
        address asset;
        bool reserveType;
        uint256 amount;
        address to;
        uint256 reservesCount;
    }

    struct withdrawLocalVars {
        uint256 userBalance;
        uint256 amountToWithdraw;
        address aToken;
        uint256 id;
    }

    function withdraw(
        withdrawParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage reservesData,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves,
        IMiniPoolAddressesProvider addressesProvider
    ) external returns (uint256) {
        DataTypes.MiniPoolReserveData storage reserve = reservesData[params.asset];
        withdrawLocalVars memory localVars;

        {
            localVars.aToken = reserve.aTokenAddress;
            localVars.id = reserve.aTokenID;

            localVars.userBalance = IAERC6909(localVars.aToken).balanceOf(msg.sender, localVars.id);

            localVars.amountToWithdraw = params.amount;

            if (params.amount == type(uint256).max) {
                localVars.amountToWithdraw = localVars.userBalance;
            }
        }
        MiniPoolValidationLogic.validateWithdraw(
            MiniPoolValidationLogic.ValidateWithdrawParams(
                params.asset,
                params.reserveType,
                localVars.amountToWithdraw,
                localVars.userBalance,
                params.reservesCount,
                addressesProvider.getPriceOracle()
            ),
            reservesData,
            usersConfig[msg.sender],
            reserves
        );

        reserve.updateState();

        reserve.updateInterestRates(params.asset, 0, localVars.amountToWithdraw);

        if (localVars.amountToWithdraw == localVars.userBalance) {
            usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
            emit ReserveUsedAsCollateralDisabled(params.asset, msg.sender);
        }

        IAERC6909(localVars.aToken).burn(
            msg.sender, params.to, localVars.id, localVars.amountToWithdraw, reserve.liquidityIndex
        );

        emit Withdraw(params.asset, msg.sender, params.to, localVars.amountToWithdraw);

        return localVars.amountToWithdraw;
    }

    struct finalizeTransferParams {
        address asset;
        bool reserveType;
        address from;
        address to;
        uint256 amount;
        uint256 balanceFromBefore;
        uint256 balanceToBefore;
        uint256 reservesCount;
    }

    function finalizeTransfer(
        finalizeTransferParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        IMiniPoolAddressesProvider addressesProvider
    ) external {
        require(
            msg.sender == reserves[params.asset].aTokenAddress, Errors.LP_CALLER_MUST_BE_AN_ATOKEN
        );

        MiniPoolValidationLogic.validateTransfer(
            params.from,
            reserves,
            usersConfig[params.from],
            reservesList,
            params.reservesCount,
            addressesProvider.getPriceOracle()
        );

        uint256 reserveId = reserves[params.asset].id;

        if (params.from != params.to) {
            if (params.balanceFromBefore.sub(params.amount) == 0) {
                DataTypes.UserConfigurationMap storage fromConfig = usersConfig[params.from];
                fromConfig.setUsingAsCollateral(reserveId, false);
                emit ReserveUsedAsCollateralDisabled(params.asset, params.from);
            }

            if (params.balanceToBefore == 0 && params.amount != 0) {
                DataTypes.UserConfigurationMap storage toConfig = usersConfig[params.to];
                toConfig.setUsingAsCollateral(reserveId, true);
                emit ReserveUsedAsCollateralEnabled(params.asset, params.to);
            }
        }
    }

    function internalWithdraw(
        withdrawParams memory params,
        mapping(address => DataTypes.MiniPoolReserveData) storage reservesData,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves,
        IMiniPoolAddressesProvider addressesProvider
    ) external returns (uint256) {
        DataTypes.MiniPoolReserveData storage reserve = reservesData[params.asset];
        withdrawLocalVars memory localVars;

        {
            localVars.aToken = reserve.aTokenAddress;
            localVars.id = reserve.aTokenID;

            localVars.userBalance =
                IAERC6909(localVars.aToken).balanceOf(address(this), localVars.id);

            localVars.amountToWithdraw = params.amount;

            if (params.amount == type(uint256).max) {
                localVars.amountToWithdraw = localVars.userBalance;
            }
            uint256 availableLiquidity = IERC20(params.asset).balanceOf(localVars.aToken);
            if (localVars.amountToWithdraw > availableLiquidity) {
                localVars.amountToWithdraw = availableLiquidity;
            }
        }
        MiniPoolValidationLogic.validateWithdraw(
            MiniPoolValidationLogic.ValidateWithdrawParams(
                params.asset,
                params.reserveType,
                localVars.amountToWithdraw,
                localVars.userBalance,
                params.reservesCount,
                addressesProvider.getPriceOracle()
            ),
            reservesData,
            usersConfig[address(this)],
            reserves
        );
        reserve.updateState();

        reserve.updateInterestRates(params.asset, 0, localVars.amountToWithdraw);

        IAERC6909(localVars.aToken).burn(
            address(this),
            params.to,
            localVars.id,
            localVars.amountToWithdraw,
            reserve.liquidityIndex
        );

        emit Withdraw(params.asset, address(this), params.to, localVars.amountToWithdraw);

        return localVars.amountToWithdraw;
    }
}
