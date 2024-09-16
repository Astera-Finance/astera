// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20} from "contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {SafeERC20} from "contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IAToken} from "contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "contracts/interfaces/IVariableDebtToken.sol";
import {IReserveInterestRateStrategy} from "contracts/interfaces/IReserveInterestRateStrategy.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ReserveBorrowConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveBorrowConfiguration.sol";
import {MathUtils} from "contracts/protocol/libraries/math/MathUtils.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {Errors} from "contracts/protocol/libraries/helpers/Errors.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {UserConfiguration} from "contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {ValidationLogic} from "./ValidationLogic.sol";

/**
 * @title withdraw Logic library
 * @notice Implements the logic to withdraw assets into the protocol
 * @author Cod3x
 */
library WithdrawLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;
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
    }

    function withdraw(
        withdrawParams memory params,
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reservesData,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reserves,
        ILendingPoolAddressesProvider addressesProvider
    ) internal returns (uint256) {
        DataTypes.ReserveData storage reserve = reservesData[params.asset][params.reserveType];
        withdrawLocalVars memory localVars;

        {
            localVars.aToken = reserve.aTokenAddress;

            localVars.userBalance = IAToken(localVars.aToken).balanceOf(msg.sender);

            localVars.amountToWithdraw = params.amount;

            if (params.amount == type(uint256).max) {
                localVars.amountToWithdraw = localVars.userBalance;
            }
        }
        ValidationLogic.validateWithdraw(
            ValidationLogic.ValidateWithdrawParams(
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

        reserve.updateInterestRates(params.asset, localVars.aToken, 0, localVars.amountToWithdraw);

        if (localVars.amountToWithdraw == localVars.userBalance) {
            usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
            emit ReserveUsedAsCollateralDisabled(params.asset, msg.sender);
        }

        IAToken(localVars.aToken).burn(
            msg.sender, params.to, localVars.amountToWithdraw, reserve.liquidityIndex
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
        mapping(address => mapping(bool => DataTypes.ReserveData)) storage reserves,
        mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
        mapping(uint256 => DataTypes.ReserveReference) storage reservesList,
        ILendingPoolAddressesProvider addressesProvider
    ) internal {
        require(
            msg.sender == reserves[params.asset][params.reserveType].aTokenAddress,
            Errors.LP_CALLER_MUST_BE_AN_ATOKEN
        );

        ValidationLogic.validateTransfer(
            params.from,
            reserves,
            usersConfig[params.from],
            reservesList,
            params.reservesCount,
            addressesProvider.getPriceOracle()
        );

        uint256 reserveId = reserves[params.asset][params.reserveType].id;

        if (params.from != params.to) {
            if (params.balanceFromBefore - params.amount == 0) {
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
}
