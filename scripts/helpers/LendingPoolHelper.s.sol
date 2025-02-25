// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/core/Oracle.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";
// import "contracts/misc/Treasury.sol";

// import "contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
// import "contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
// import "contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";
import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";

import "contracts/protocol/tokenization/ERC20/AToken.sol";
import "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
// import "contracts/mocks/oracle/PriceOracle.sol";
import "../DeployDataTypes.sol";

import "forge-std/console.sol";

contract LendingPoolHelper {
    address constant FOUNDRY_DEFAULT = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    uint256 constant PRICE_FEED_DECIMALS = 8;
    DeployedContracts contracts;

    function deployLendingPoolInfra(
        General memory _general,
        LinearStrategy[] memory _volatileStrats,
        LinearStrategy[] memory _stableStrats,
        PiStrategy[] memory _piStrategies,
        PoolReserversConfig[] memory _poolReserversConfig,
        OracleConfig memory _oracleConfig,
        address _deployer,
        address _wethGateway
    ) public {
        _deployLendingPoolContracts(_deployer, _general, _wethGateway, _oracleConfig);

        _deployStrategies(
            contracts.lendingPoolAddressesProvider, _volatileStrats, _stableStrats, _piStrategies
        );
        _deployTokensAndUtils(contracts.lendingPoolAddressesProvider);

        _initAndConfigureReserves(contracts, _poolReserversConfig, _general);
    }

    function _deployLendingPoolContracts(
        address deployer,
        General memory general,
        address wethGateway,
        OracleConfig memory _oracleConfig
    ) internal {
        contracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider();
        console.log("provider's owner: ", contracts.lendingPoolAddressesProvider.owner());

        contracts.lendingPool = new LendingPool();
        // contracts.lendingPool.initialize(
        //     ILendingPoolAddressesProvider(contracts.lendingPoolAddressesProvider)
        // );
        contracts.lendingPoolAddressesProvider.setLendingPoolImpl(address(contracts.lendingPool));
        address lendingPoolProxy = address(contracts.lendingPoolAddressesProvider.getLendingPool());
        contracts.lendingPool = LendingPool(lendingPoolProxy);

        contracts.lendingPoolConfigurator = new LendingPoolConfigurator();
        contracts.lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(
            address(contracts.lendingPoolConfigurator)
        );
        address lendingPoolConfiguratorProxy =
            contracts.lendingPoolAddressesProvider.getLendingPoolConfigurator();
        contracts.lendingPoolConfigurator = LendingPoolConfigurator(lendingPoolConfiguratorProxy);

        /* Pause the pool for the time of the deployment */
        contracts.lendingPoolAddressesProvider.setEmergencyAdmin(deployer); // temporary the deployer
        contracts.lendingPoolAddressesProvider.setPoolAdmin(deployer);

        contracts.oracle = _deployOracle(_oracleConfig);
        contracts.lendingPoolAddressesProvider.setPriceOracle(address(contracts.oracle));
        contracts.cod3xLendDataProvider = new Cod3xLendDataProvider(
            general.networkBaseTokenAggregator, general.marketReferenceCurrencyAggregator
        );
        contracts.cod3xLendDataProvider.setLendingPoolAddressProvider(
            address(contracts.lendingPoolAddressesProvider)
        );
        contracts.wethGateway = new WETHGateway(wethGateway);
        contracts.wethGateway.authorizeLendingPool(address(contracts.lendingPool));
    }

    function _deployStrategies(
        ILendingPoolAddressesProvider _provider,
        LinearStrategy[] memory _volatileStrats,
        LinearStrategy[] memory _stableStrats,
        PiStrategy[] memory _piStrats
    ) internal {
        for (uint8 idx = 0; idx < _volatileStrats.length; idx++) {
            contracts.volatileStrategies.push(
                _deployDefaultStrategy(_provider, _volatileStrats[idx])
            );
        }
        for (uint8 idx = 0; idx < _stableStrats.length; idx++) {
            contracts.stableStrategies.push(_deployDefaultStrategy(_provider, _stableStrats[idx]));
        }
        for (uint8 idx = 0; idx < _piStrats.length; idx++) {
            contracts.piStrategies.push(_deployPiInterestStrategy(_provider, _piStrats[idx]));
        }
    }

    function _deployDefaultStrategy(
        ILendingPoolAddressesProvider _provider,
        LinearStrategy memory _strat
    ) internal returns (DefaultReserveInterestRateStrategy) {
        return new DefaultReserveInterestRateStrategy(
            _provider,
            _strat.optimalUtilizationRate,
            _strat.baseVariableBorrowRate,
            _strat.variableRateSlope1,
            _strat.variableRateSlope2
        );
    }

    function _deployPiInterestStrategy(
        ILendingPoolAddressesProvider _provider,
        PiStrategy memory _strategy
    ) internal returns (PiReserveInterestRateStrategy) {
        return new PiReserveInterestRateStrategy(
            address(_provider),
            _strategy.tokenAddress,
            _strategy.assetReserveType,
            _strategy.minControllerError,
            _strategy.maxITimeAmp,
            _strategy.optimalUtilizationRate,
            _strategy.kp,
            _strategy.ki
        );
    }

    function _deployTokensAndUtils(LendingPoolAddressesProvider lendingPoolAddressesProvider)
        internal
    {
        contracts.aToken = new AToken();
        contracts.variableDebtToken = new VariableDebtToken();
        // contracts.treasury = new Treasury(lendingPoolAddressesProvider);
    }

    function _initAndConfigureReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        General memory _general
    ) internal {
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](_reservesConfig.length);

        if (_contracts.lendingPool.paused()) {
            _contracts.lendingPoolConfigurator.setPoolPause(false);
        }

        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            bool assetExist = false;
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];
            require(
                contracts.oracle.getSourceOfAsset(reserveConfig.tokenAddress) != address(0),
                "Oracle config not compliant"
            );
            string memory tmpSymbol = ERC20(reserveConfig.tokenAddress).symbol();

            address interestStrategy = _determineInterestStrat(_contracts, reserveConfig);

            initInputParams[idx] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(_contracts.aToken),
                variableDebtTokenImpl: address(_contracts.variableDebtToken),
                underlyingAssetDecimals: ERC20(reserveConfig.tokenAddress).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: reserveConfig.tokenAddress,
                reserveType: reserveConfig.reserveType,
                treasury: _general.treasury,
                incentivesController: address(0),
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat(_general.aTokenNamePrefix, tmpSymbol),
                aTokenSymbol: string.concat(_general.aTokenSymbolPrefix, tmpSymbol),
                variableDebtTokenName: string.concat(_general.debtTokenNamePrefix, tmpSymbol),
                variableDebtTokenSymbol: string.concat(_general.debtTokenSymbolPrefix, tmpSymbol),
                params: bytes(reserveConfig.params)
            });
        }
        console.log("Batch init");
        _contracts.lendingPoolConfigurator.batchInitReserve(initInputParams);

        _configureReserves(_contracts, _reservesConfig, _general.usdBootstrapAmount);

        if (!_contracts.lendingPool.paused()) {
            _contracts.lendingPoolConfigurator.setPoolPause(true);
        }
    }

    function _determineInterestStrat(
        DeployedContracts memory _contracts,
        PoolReserversConfig memory _reserveConfig
    ) internal returns (address) {
        address interestStrategy;
        if (keccak256(bytes(_reserveConfig.interestStrat)) == keccak256(bytes("PI"))) {
            require(
                _contracts.piStrategies[_reserveConfig.interestStratId]._asset()
                    == _reserveConfig.tokenAddress,
                "Pi strat has different asset address than reserve"
            );
            interestStrategy = address(_contracts.piStrategies[_reserveConfig.interestStratId]);
        } else {
            interestStrategy = keccak256(bytes(_reserveConfig.interestStrat))
                == keccak256(bytes("VOLATILE"))
                ? address(_contracts.volatileStrategies[_reserveConfig.interestStratId])
                : address(_contracts.stableStrategies[_reserveConfig.interestStratId]);
        }
        return interestStrategy;
    }

    function _configureReserves(
        DeployedContracts memory _contracts,
        PoolReserversConfig[] memory _reservesConfig,
        uint256 usdBootstrapAmount
    ) internal {
        for (uint8 idx = 0; idx < _reservesConfig.length; idx++) {
            PoolReserversConfig memory reserveConfig = _reservesConfig[idx];

            _contracts.lendingPoolConfigurator.disableBorrowingOnReserve(
                reserveConfig.tokenAddress, reserveConfig.reserveType
            );
            _contracts.lendingPoolConfigurator.configureReserveAsCollateral(
                reserveConfig.tokenAddress,
                reserveConfig.reserveType,
                reserveConfig.baseLtv,
                reserveConfig.liquidationThreshold,
                reserveConfig.liquidationBonus
            );

            uint256 tokenPrice = _contracts.oracle.getAssetPrice(reserveConfig.tokenAddress);

            uint256 tokenAmount = (usdBootstrapAmount * 10 ** PRICE_FEED_DECIMALS) / tokenPrice
                / (10 ** (18 - IERC20Detailed(reserveConfig.tokenAddress).decimals()));
            console.log(
                "Bootstrap amount: %s %s for price: %s",
                tokenAmount,
                IERC20Detailed(reserveConfig.tokenAddress).symbol(),
                tokenPrice
            );
            IERC20Detailed(reserveConfig.tokenAddress).approve(
                address(_contracts.lendingPool), tokenAmount
            );
            if (msg.sender != FOUNDRY_DEFAULT) {
                _contracts.lendingPool.deposit(
                    reserveConfig.tokenAddress,
                    reserveConfig.reserveType,
                    tokenAmount,
                    _contracts.lendingPoolAddressesProvider.getPoolAdmin()
                );
                DataTypes.ReserveData memory reserveData = _contracts.lendingPool.getReserveData(
                    reserveConfig.tokenAddress, reserveConfig.reserveType
                );
                require(
                    IERC20Detailed(reserveData.aTokenAddress).totalSupply() == tokenAmount,
                    "TotalSupply not equal to deposited amount!"
                );
                if (reserveConfig.borrowingEnabled) {
                    _contracts.lendingPoolConfigurator.enableBorrowingOnReserve(
                        reserveConfig.tokenAddress, reserveConfig.reserveType
                    );
                    _contracts.lendingPool.borrow(
                        reserveConfig.tokenAddress,
                        reserveConfig.reserveType,
                        tokenAmount / 2,
                        _contracts.lendingPoolAddressesProvider.getPoolAdmin()
                    );
                    reserveData = _contracts.lendingPool.getReserveData(
                        reserveConfig.tokenAddress, reserveConfig.reserveType
                    );
                    require(
                        IERC20Detailed(reserveData.variableDebtTokenAddress).totalSupply()
                            == tokenAmount / 2,
                        "TotalSupply of debt not equal to borrowed amount!"
                    );
                }
            }

            _contracts.lendingPoolConfigurator.setCod3xReserveFactor(
                reserveConfig.tokenAddress, reserveConfig.reserveType, reserveConfig.reserveFactor
            );

            _contracts.lendingPoolConfigurator.enableFlashloan(
                reserveConfig.tokenAddress, reserveConfig.reserveType
            );
        }
    }

    function _deployOracle(OracleConfig memory oracleConfig) internal returns (Oracle) {
        Oracle oracle = new Oracle(
            oracleConfig.assets,
            oracleConfig.sources,
            oracleConfig.timeouts,
            oracleConfig.fallbackOracle,
            oracleConfig.baseCurrency,
            oracleConfig.baseCurrencyUnit,
            address(contracts.lendingPoolConfigurator)
        );
        return oracle;
    }
}
