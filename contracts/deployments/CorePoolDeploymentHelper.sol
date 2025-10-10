// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {LendingPool} from "../../contracts/protocol/core/lendingpool/LendingPool.sol";
import {LendingPoolAddressesProvider} from
    "../../contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../../contracts/interfaces/ILendingPoolConfigurator.sol";
import {IAToken} from "../../contracts/interfaces/IAToken.sol";
import {Ownable} from "../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {ILendingPool} from "../../contracts/interfaces/ILendingPool.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IERC20Detailed} from
    "../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";
import {ILendingPoolConfigurator} from "contracts/interfaces/ILendingPoolConfigurator.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IChainlinkAggregator} from "contracts/interfaces/base/IChainlinkAggregator.sol";
import {ATokenNonRebasing} from "contracts/protocol/tokenization/ERC20/ATokenNonRebasing.sol";
import {
    AsteraDataProvider2,
    AggregatedMainPoolReservesData
} from "contracts/misc/AsteraDataProvider2.sol";

import {IPiReserveInterestRateStrategy} from
    "contracts/interfaces/IPiReserveInterestRateStrategy.sol";

import {console2} from "forge-std/console2.sol";

/**
 * NOT AUDITED !! -> ONLY FOR TEST PURPOSE - CHECK ALL MINI POOLS PARAMS
 */

/**
 * @title CorePoolDeploymentHelper
 * @notice Helper contract to deploy and configure MiniPools with reserves and check params
 * @author Conclave - xRave110
 */
contract CorePoolDeploymentHelper is Ownable {
    // @issue - add delegateCalls !!
    uint256 public constant WRONG_LENGTH = 0x1;
    uint256 public constant WRONG_ORDER = 0x2;
    uint256 public constant WRONG_LTV = 0x4;
    uint256 public constant WRONG_STRAT = 0x8;
    uint256 public constant WRONG_LIQUIDATION_BONUS = 0x10;
    uint256 public constant WRONG_LIQUIDATION_THRESHOLD = 0x20;
    uint256 public constant WRONG_MINI_POOL_OWNER_FEE = 0x40;
    uint256 public constant WRONG_RESERVE_FACTOR = 0x80;
    uint256 public constant WRONG_DEPOSIT_CAP = 0x100;
    uint256 public constant WRONG_BORROWING_STATUS = 0x200;
    uint256 public constant ASSET_NOT_ACTIVE = 0x400;
    uint256 public constant NO_LIQUIDITY = 0x800;
    uint256 public constant WRONG_MIN_CONTROLLER_ERROR = 0x1000;
    uint256 public constant WRONG_OPTIMAL_UTILIZATION_RATE = 0x2000;
    uint256 public constant WRONG_KP = 0x4000;
    uint256 public constant WRONG_KI = 0x8000;
    uint256 public constant WRONG_MAX_ERR_I_AMP = 0x10000;
    uint256 public constant WRONG_RESERVE_TYPE = 0x20000;

    IOracle private oracle;
    LendingPoolAddressesProvider private lendingPoolAddressesProvider;
    ILendingPoolConfigurator private lendingPoolConfigurator;
    AsteraDataProvider2 private dataProvider;

    struct HelperPoolReserversConfig {
        uint256 baseLtv;
        bool borrowingEnabled;
        address interestStrat;
        uint256 liquidationBonus;
        uint256 liquidationThreshold;
        uint256 miniPoolOwnerFee;
        uint256 reserveFactor;
        uint256 depositCap;
        address tokenAddress;
        int256 minControllerError;
        uint256 optimalUtilizationRate;
        uint256 kp;
        uint256 ki;
        int256 maxErrIAmp;
        bool reserveType;
    }

    constructor(
        address _oracle,
        address _lendingPoolAddressesProvider,
        address _lendingPoolConfigurator,
        address _dataProvider
    ) Ownable(msg.sender) {
        oracle = IOracle(_oracle);
        lendingPoolAddressesProvider = LendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        lendingPoolConfigurator = ILendingPoolConfigurator(_lendingPoolConfigurator);
        dataProvider = AsteraDataProvider2(_dataProvider);
        transferOwnership(lendingPoolAddressesProvider.getLendingPool());
    }

    function checkDeploymentParams(HelperPoolReserversConfig[] memory _desiredConfig)
        public
        view
        returns (uint256 errCode, uint8)
    {
        address lendingPool = lendingPoolAddressesProvider.getLendingPool();
        errCode = 0;
        AggregatedMainPoolReservesData[] memory reservesData =
            dataProvider.getMainPoolReservesData();

        if (reservesData.length != _desiredConfig.length) {
            errCode |= WRONG_LENGTH;
            console2.log(
                "WrongLength, got %s, expected %s", reservesData.length, _desiredConfig.length
            );
        }
        console2.log("---- Test for miniPool %s -----", lendingPool);
        for (uint8 i = 0; i < _desiredConfig.length; i++) {
            IPiReserveInterestRateStrategy strat =
                IPiReserveInterestRateStrategy(reservesData[i].interestRateStrategyAddress);
            if (reservesData[i].underlyingAsset != _desiredConfig[i].tokenAddress) {
                errCode |= WRONG_ORDER;
                console2.log(
                    "Order mismatch for asset %s, got %s, expected %s",
                    reservesData[i].underlyingAsset,
                    _desiredConfig[i].tokenAddress
                );
            }

            if (address(strat) != _desiredConfig[i].interestStrat) {
                errCode |= WRONG_STRAT;
                console2.log(
                    "Strat mismatch for asset %s, got %s, expected %s",
                    reservesData[i].underlyingAsset,
                    reservesData[i].interestRateStrategyAddress,
                    _desiredConfig[i].interestStrat
                );
            }
            if (
                reservesData[i].underlyingAsset == 0xa500000000e482752f032eA387390b6025a2377b
                    && reservesData[i].reserveType == false
            ) {} else {
                if (reservesData[i].baseLTVasCollateral != _desiredConfig[i].baseLtv) {
                    errCode |= WRONG_LTV;
                    console2.log(
                        "LTV mismatch for asset %s, got %s, expected %s",
                        reservesData[i].underlyingAsset,
                        reservesData[i].baseLTVasCollateral,
                        _desiredConfig[i].baseLtv
                    );
                }
                if (reservesData[i].reserveLiquidationBonus != _desiredConfig[i].liquidationBonus) {
                    errCode |= WRONG_LIQUIDATION_BONUS;
                    console2.log(
                        "Liq bonus mismatch for asset %s, got %s, expected %s",
                        reservesData[i].underlyingAsset,
                        reservesData[i].reserveLiquidationBonus,
                        _desiredConfig[i].liquidationBonus
                    );
                }

                if (
                    reservesData[i].reserveLiquidationThreshold
                        != _desiredConfig[i].liquidationThreshold
                ) {
                    errCode |= WRONG_LIQUIDATION_THRESHOLD;
                    console2.log(
                        "Liq threshold mismatch for asset %s, got %s, expected %s",
                        reservesData[i].underlyingAsset,
                        reservesData[i].reserveLiquidationThreshold,
                        _desiredConfig[i].liquidationThreshold
                    );
                }
            }
            if (reservesData[i].miniPoolOwnerReserveFactor != _desiredConfig[i].miniPoolOwnerFee) {
                errCode |= WRONG_MINI_POOL_OWNER_FEE;
                console2.log(
                    "MiniPool owner fee mismatch for asset %s, got %s, expected %s",
                    reservesData[i].underlyingAsset,
                    reservesData[i].miniPoolOwnerReserveFactor,
                    _desiredConfig[i].miniPoolOwnerFee
                );
            }
            if (reservesData[i].asteraReserveFactor != _desiredConfig[i].reserveFactor) {
                errCode |= WRONG_RESERVE_FACTOR;
                console2.log(
                    "Reserve factor mismatch for asset %s, got %s, expected %s",
                    reservesData[i].underlyingAsset,
                    reservesData[i].asteraReserveFactor,
                    _desiredConfig[i].reserveFactor
                );
            }
            if (reservesData[i].depositCap != _desiredConfig[i].depositCap) {
                errCode |= WRONG_DEPOSIT_CAP;
                console2.log(
                    "Deposit cap mismatch for asset %s, got %s, expected %s",
                    reservesData[i].underlyingAsset,
                    reservesData[i].depositCap,
                    _desiredConfig[i].depositCap
                );
            }
            if (reservesData[i].borrowingEnabled != _desiredConfig[i].borrowingEnabled) {
                errCode |= WRONG_BORROWING_STATUS;
                console2.log(
                    "Borrowing status mismatch for asset %s, got %s, expected %s",
                    reservesData[i].underlyingAsset,
                    reservesData[i].borrowingEnabled,
                    _desiredConfig[i].borrowingEnabled
                );
            }

            if (reservesData[i].isActive == false) {
                errCode |= ASSET_NOT_ACTIVE;
                console2.log("Asset not active %s", reservesData[i].underlyingAsset);
            }
            if (reservesData[i].reserveType != _desiredConfig[i].reserveType) {
                errCode |= WRONG_RESERVE_TYPE;
                console2.log(
                    "Wrong reserveType for asset %s: %s",
                    reservesData[i].underlyingAsset,
                    reservesData[i].reserveType
                );
            }

            try strat._minControllerError() returns (int256 _minControllerError) {
                if (_minControllerError != _desiredConfig[i].minControllerError) {
                    errCode |= WRONG_MIN_CONTROLLER_ERROR;
                    console2.log(
                        "Wrong min controller error for asset %s", reservesData[i].underlyingAsset
                    );
                    console2.log("got %s,", strat._minControllerError());

                    console2.log(" expected %s", _desiredConfig[i].minControllerError);
                }

                if (strat._optimalUtilizationRate() != _desiredConfig[i].optimalUtilizationRate) {
                    errCode |= WRONG_OPTIMAL_UTILIZATION_RATE;
                    console2.log(
                        "Wrong Uo error for asset %s, got %s, expected %s",
                        reservesData[i].underlyingAsset,
                        strat._optimalUtilizationRate(),
                        _desiredConfig[i].optimalUtilizationRate
                    );
                }

                if (strat._kp() != _desiredConfig[i].kp) {
                    errCode |= WRONG_KP;
                    console2.log(
                        "Wrong kp error for asset %s, got %s, expected %s",
                        reservesData[i].underlyingAsset,
                        strat._kp(),
                        _desiredConfig[i].kp
                    );
                }

                if (strat._ki() != _desiredConfig[i].ki) {
                    errCode |= WRONG_KI;
                    console2.log(
                        "Wrong ki error for asset %s, got %s, expected %s",
                        reservesData[i].underlyingAsset,
                        strat._ki(),
                        _desiredConfig[i].ki
                    );
                }
            } catch {
                console2.log("STRAT different than PI !!", reservesData[i].underlyingAsset);
            }

            // if (strat._maxErrIAmp() != _desiredConfig[i].maxErrIAmp) {
            //     errCode |= WRONG_MAX_ERR_I_AMP;
            //     console2.log(
            //         "Wrong _maxErrIAmp error for asset %s, got %s, expected %s",
            //         reservesData[i].underlyingAsset,
            //         uint256(strat._maxErrIAmp()),
            //         uint256(_desiredConfig[i].maxErrIAmp)
            //     );
            // }

            DataTypes.ReserveData memory reserveData = ILendingPool(lendingPool).getReserveData(
                _desiredConfig[i].tokenAddress, reservesData[i].reserveType
            );

            if (
                IAToken(reserveData.aTokenAddress).totalSupply() == 0
                    && IAToken(reserveData.variableDebtTokenAddress).totalSupply() == 0
            ) errCode |= NO_LIQUIDITY;
            if (errCode != 0) return (errCode, i);
        }
        return (errCode, 0);
    }
}
