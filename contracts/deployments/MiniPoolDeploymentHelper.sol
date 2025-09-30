// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {LendingPool} from "../../contracts/protocol/core/lendingpool/LendingPool.sol";
import {MiniPoolAddressesProvider} from
    "../../contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import {IMiniPoolConfigurator} from "../../contracts/interfaces/IMiniPoolConfigurator.sol";
import {IAERC6909} from "../../contracts/interfaces/IAERC6909.sol";
import {Ownable} from "../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {IMiniPool} from "../../contracts/interfaces/IMiniPool.sol";
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
    AggregatedMiniPoolReservesData
} from "contracts/misc/AsteraDataProvider2.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title MiniPoolDeploymentHelper
 * @notice Helper contract to deploy and configure MiniPools with reserves
 * @author Conclave - xRave110
 */
contract MiniPoolDeploymentHelper is Ownable {
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

    IOracle private oracle;
    MiniPoolAddressesProvider private miniPoolAddressesProvider;
    IMiniPoolConfigurator private miniPoolConfigurator;
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
    }

    constructor(
        address _oracle,
        address _miniPoolAddressesProvider,
        address _miniPoolConfigurator,
        address _dataProvider
    ) Ownable(msg.sender) {
        oracle = IOracle(_oracle);
        miniPoolAddressesProvider = MiniPoolAddressesProvider(_miniPoolAddressesProvider);
        miniPoolConfigurator = IMiniPoolConfigurator(_miniPoolConfigurator);
        dataProvider = AsteraDataProvider2(_dataProvider);
        transferOwnership(miniPoolAddressesProvider.getMainPoolAdmin());
    }

    function deployMiniPool(
        address miniPoolImpl,
        address aTokenImpl,
        address poolAdmin,
        address treasury,
        address poolOwnerTreasury
    ) external onlyOwner returns (address) {
        return _deployMiniPool(miniPoolImpl, aTokenImpl, poolAdmin, treasury, poolOwnerTreasury);
    }

    function _deployMiniPool(
        address miniPoolImpl,
        address aTokenImpl,
        address poolAdmin,
        address treasury,
        address poolOwnerTreasury
    ) internal returns (address miniPool) {
        uint256 miniPoolId =
            miniPoolAddressesProvider.deployMiniPool(miniPoolImpl, aTokenImpl, poolAdmin);
        miniPool = miniPoolAddressesProvider.getMiniPool(miniPoolId);
        if (
            treasury == address(0)
                && miniPoolAddressesProvider.getMiniPoolAsteraTreasury() == address(0)
        ) {
            revert("Treasury address not set!");
        } else if (
            miniPoolAddressesProvider.getMiniPoolAsteraTreasury() != treasury
                && treasury != address(0)
        ) {
            miniPoolConfigurator.setAsteraTreasury(treasury);
        }

        if (
            poolOwnerTreasury == address(0)
                && miniPoolAddressesProvider.getMiniPoolOwnerTreasury(miniPoolId) == address(0)
        ) {
            revert("Mini pool treasury address not set!");
        } else if (
            miniPoolAddressesProvider.getMiniPoolOwnerTreasury(miniPoolId) != poolOwnerTreasury
                && poolOwnerTreasury != address(0)
        ) {
            miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(
                poolOwnerTreasury, IMiniPool(miniPool)
            );
        }

        return miniPool;
    }

    function deployNewMiniPoolInitAndConfigure(
        address miniPoolImpl,
        address aTokenImpl,
        address poolAdmin,
        address treasury,
        address poolOwnerTreasury,
        IMiniPoolConfigurator.InitReserveInput[] calldata _initInputParams,
        HelperPoolReserversConfig[] calldata _reservesConfig,
        uint256 _usdBootstrapAmount
    ) external onlyOwner returns (address) {
        address miniPool =
            _deployMiniPool(miniPoolImpl, aTokenImpl, poolAdmin, treasury, poolOwnerTreasury);
        _initAndConfigureMiniPoolReserves(
            _initInputParams, _reservesConfig, miniPool, _usdBootstrapAmount
        );
        checkDeploymentParams(miniPool, _reservesConfig);
        return miniPool;
    }

    function initAndConfigureMiniPoolReserves(
        IMiniPoolConfigurator.InitReserveInput[] calldata _initInputParams,
        HelperPoolReserversConfig[] calldata _reservesConfig,
        address _miniPool,
        uint256 _usdBootstrapAmount
    ) external onlyOwner {
        _initAndConfigureMiniPoolReserves(
            _initInputParams, _reservesConfig, _miniPool, _usdBootstrapAmount
        );
        checkDeploymentParams(_miniPool, _reservesConfig);
    }

    function configureReserves(
        HelperPoolReserversConfig[] calldata _reservesConfig,
        address _miniPool,
        uint256 _usdBootstrapAmount
    ) external onlyOwner {
        _configureReserves(_reservesConfig, _miniPool, _usdBootstrapAmount);
        checkDeploymentParams(_miniPool, _reservesConfig);
    }

    function checkDeploymentParams(
        address _miniPool,
        HelperPoolReserversConfig[] memory _desiredConfig
    ) public view returns (uint256 errCode, uint8) {
        errCode = 0;
        AggregatedMiniPoolReservesData[] memory reservesData =
            dataProvider.getMiniPoolData(_miniPool).reservesData;

        if (reservesData.length != _desiredConfig.length) {
            errCode |= WRONG_LENGTH;
        }
        for (uint8 i = 0; i < _desiredConfig.length; i++) {
            if (
                reservesData[i].aTokenNonRebasingAddress != _desiredConfig[i].tokenAddress
                    && reservesData[i].underlyingAsset != _desiredConfig[i].tokenAddress
            ) {
                errCode |= WRONG_ORDER;
                // console2.log(
                //     "Order mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].aTokenNonRebasingAddress,
                //     _desiredConfig[i].tokenAddress
                // );
            }
            if (reservesData[i].baseLTVasCollateral != _desiredConfig[i].baseLtv) {
                errCode |= WRONG_LTV;
                // console2.log(
                //     "LTV mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].baseLTVasCollateral,
                //     _desiredConfig[i].baseLtv
                // );
            }
            if (reservesData[i].interestRateStrategyAddress != _desiredConfig[i].interestStrat) {
                errCode |= WRONG_STRAT;
                // console2.log(
                //     "Strat mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].interestRateStrategyAddress,
                //     _desiredConfig[i].interestStrat
                // );
            }
            if (reservesData[i].reserveLiquidationBonus != _desiredConfig[i].liquidationBonus) {
                errCode |= WRONG_LIQUIDATION_BONUS;
                // console2.log(
                //     "Liq bonus mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].reserveLiquidationBonus,
                //     _desiredConfig[i].liquidationBonus
                // );
            }
            if (
                reservesData[i].reserveLiquidationThreshold
                    != _desiredConfig[i].liquidationThreshold
            ) {
                errCode |= WRONG_LIQUIDATION_THRESHOLD;
                // console2.log(
                //     "Liq threshold mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].reserveLiquidationThreshold,
                //     _desiredConfig[i].liquidationThreshold
                // );
            }
            if (reservesData[i].miniPoolOwnerReserveFactor != _desiredConfig[i].miniPoolOwnerFee) {
                errCode |= WRONG_MINI_POOL_OWNER_FEE;
                // console2.log(
                //     "MiniPool owner fee mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].miniPoolOwnerReserveFactor,
                //     _desiredConfig[i].miniPoolOwnerFee
                // );
            }
            if (reservesData[i].asteraReserveFactor != _desiredConfig[i].reserveFactor) {
                errCode |= WRONG_RESERVE_FACTOR;
                // console2.log(
                //     "Reserve factor mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].asteraReserveFactor,
                //     _desiredConfig[i].reserveFactor
                // );
            }
            if (reservesData[i].depositCap != _desiredConfig[i].depositCap) {
                errCode |= WRONG_DEPOSIT_CAP;
                // console2.log(
                //     "Deposit cap mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].depositCap,
                //     _desiredConfig[i].depositCap
                // );
            }
            if (reservesData[i].asteraReserveFactor != _desiredConfig[i].reserveFactor) {
                errCode |= WRONG_RESERVE_FACTOR;
                // console2.log(
                //     "Reserve factor mismatch for asset %s, got %s, expected %s",
                //     reservesData[i].underlyingAsset,
                //     reservesData[i].asteraReserveFactor,
                //     _desiredConfig[i].reserveFactor
                // );
            }
            if (reservesData[i].borrowingEnabled != _desiredConfig[i].borrowingEnabled) {
                errCode |= WRONG_BORROWING_STATUS;
            }

            if (reservesData[i].isActive == false) {
                errCode |= ASSET_NOT_ACTIVE;
            }

            DataTypes.MiniPoolReserveData memory miniPoolReserveData =
                IMiniPool(_miniPool).getReserveData(_desiredConfig[i].tokenAddress);

            if (
                IAERC6909(miniPoolReserveData.aErc6909).totalSupply(miniPoolReserveData.aTokenID)
                    == 0
                    && IAERC6909(miniPoolReserveData.aErc6909).totalSupply(
                        miniPoolReserveData.variableDebtTokenID
                    ) == 0
            ) errCode |= NO_LIQUIDITY;
            if (errCode != 0) return (errCode, i);
        }
        return (errCode, 0);
    }

    function setReserveFactorsForAssets(
        address[] calldata _assets,
        uint256[] calldata _reserveFactors,
        address _miniPool
    ) external onlyOwner {
        require(_assets.length == _reserveFactors.length, "Array length mismatch!");

        for (uint8 i = 0; i < _assets.length; i++) {
            console2.log("address(miniPoolConfigurator)", address(miniPoolConfigurator));
            /* Can't do it because miniPoolConfigurator is a proxy */
            // (bool success, bytes memory returndata) = address(miniPoolConfigurator).delegatecall(
            //     abi.encodeWithSelector(
            //         IMiniPoolConfigurator.setAsteraReserveFactor.selector,
            //         _assets[i],
            //         _reserveFactors[i],
            //         _miniPool
            //     )
            // );
            // require(success, "delegatecall failed");
        }
    }

    function setInterestRateStartsForAssets(
        address[] calldata _assets,
        address[] calldata _interestStrats,
        address _miniPool
    ) external onlyOwner {
        for (uint8 i = 0; i < _assets.length; i++) {
            miniPoolConfigurator.setReserveInterestRateStrategyAddress(
                _assets[i], _interestStrats[i], IMiniPool(_miniPool)
            );
        }
    }

    function _initAndConfigureMiniPoolReserves(
        IMiniPoolConfigurator.InitReserveInput[] calldata _initInputParams,
        HelperPoolReserversConfig[] calldata _reservesConfig,
        address _miniPool,
        uint256 _usdBootstrapAmount
    ) internal {
        miniPoolConfigurator.batchInitReserve(_initInputParams, IMiniPool(_miniPool));
        _configureReserves(_reservesConfig, _miniPool, _usdBootstrapAmount);
    }

    function _configureReserves(
        HelperPoolReserversConfig[] calldata _reservesConfig,
        address _miniPool,
        uint256 _usdBootstrapAmount
    ) internal {
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            HelperPoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            miniPoolConfigurator.disableBorrowingOnReserve(
                reserveConfig.tokenAddress, IMiniPool(_miniPool)
            );

            miniPoolConfigurator.configureReserveAsCollateral(
                reserveConfig.tokenAddress,
                reserveConfig.baseLtv,
                reserveConfig.liquidationThreshold,
                reserveConfig.liquidationBonus,
                IMiniPool(_miniPool)
            );
            miniPoolConfigurator.activateReserve(reserveConfig.tokenAddress, IMiniPool(_miniPool));

            if (_usdBootstrapAmount > 0) {
                uint256 tokenAmount =
                    _getTokenAmount(_usdBootstrapAmount, reserveConfig.tokenAddress);

                // DataTypes.ReserveData memory reserveData = _contracts.lendingPool.getReserveData(
                //     reserveConfig.tokenAddress, reserveConfig.reserveType
                // );
                IERC20Detailed(reserveConfig.tokenAddress).approve(address(_miniPool), tokenAmount);
                IMiniPool(_miniPool).deposit(
                    reserveConfig.tokenAddress,
                    false,
                    tokenAmount,
                    miniPoolAddressesProvider.getPoolAdmin(
                        miniPoolAddressesProvider.getMiniPoolId(_miniPool)
                    )
                );
                DataTypes.MiniPoolReserveData memory miniPoolReserveData =
                    IMiniPool(_miniPool).getReserveData(reserveConfig.tokenAddress);
                require(
                    IAERC6909(miniPoolReserveData.aErc6909).totalSupply(
                        miniPoolReserveData.aTokenID
                    ) == tokenAmount,
                    "TotalSupply not equal to deposited amount!"
                );

                miniPoolConfigurator.enableBorrowingOnReserve(
                    reserveConfig.tokenAddress, IMiniPool(_miniPool)
                );
                IMiniPool(_miniPool).borrow(
                    reserveConfig.tokenAddress,
                    false,
                    tokenAmount / 2,
                    miniPoolAddressesProvider.getPoolAdmin(
                        miniPoolAddressesProvider.getMiniPoolId(_miniPool)
                    )
                );
                miniPoolReserveData =
                    IMiniPool(_miniPool).getReserveData(reserveConfig.tokenAddress);
                require(
                    IAERC6909(miniPoolReserveData.aErc6909).totalSupply(
                        miniPoolReserveData.variableDebtTokenID
                    ) == tokenAmount / 2,
                    "TotalSupply of debt not equal to borrowed amount!"
                );
            }

            if (!reserveConfig.borrowingEnabled) {
                miniPoolConfigurator.disableBorrowingOnReserve(
                    reserveConfig.tokenAddress, IMiniPool(_miniPool)
                );
            }
            if (reserveConfig.depositCap > 0) {
                miniPoolConfigurator.setDepositCap(
                    reserveConfig.tokenAddress, reserveConfig.depositCap, IMiniPool(_miniPool)
                );
            }
            if (reserveConfig.reserveFactor > 0) {
                miniPoolConfigurator.setAsteraReserveFactor(
                    reserveConfig.tokenAddress, reserveConfig.reserveFactor, IMiniPool(_miniPool)
                );
            }
            if (reserveConfig.miniPoolOwnerFee > 0) {
                miniPoolConfigurator.setMinipoolOwnerReserveFactor(
                    reserveConfig.tokenAddress, reserveConfig.miniPoolOwnerFee, IMiniPool(_miniPool)
                );
            }
            miniPoolConfigurator.enableFlashloan(reserveConfig.tokenAddress, IMiniPool(_miniPool));
        }
    }

    function _getTokenAmount(uint256 usdBootstrapAmount, address tokenAddress)
        internal
        view
        returns (uint256)
    {
        uint256 tokenPrice = oracle.getAssetPrice(tokenAddress);
        if (
            ILendingPoolConfigurator(
                ILendingPoolAddressesProvider(
                    miniPoolAddressesProvider.getLendingPoolAddressesProvider()
                ).getLendingPoolConfigurator()
            ).getIsAToken(tokenAddress)
        ) {
            return usdBootstrapAmount
                * 10
                    ** IChainlinkAggregator(
                        oracle.getSourceOfAsset(ATokenNonRebasing(tokenAddress).UNDERLYING_ASSET_ADDRESS())
                    ).decimals() * 10 ** IERC20Detailed(tokenAddress).decimals() / tokenPrice;
        } else {
            return usdBootstrapAmount
                * 10 ** IChainlinkAggregator(oracle.getSourceOfAsset(tokenAddress)).decimals()
                * 10 ** IERC20Detailed(tokenAddress).decimals() / tokenPrice;
        }
    }
}
