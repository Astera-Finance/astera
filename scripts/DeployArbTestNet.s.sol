// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/rewarder/Rewarder.sol";
import "contracts/misc/Oracle.sol";
import "contracts/misc/ProtocolDataProvider.sol";
import "contracts/misc/Treasury.sol";
import "contracts/misc/UiPoolDataProviderV2.sol";
import "contracts/misc/WETHGateway.sol";
import "contracts/protocol/libraries/logic/ReserveLogic.sol";
import "contracts/protocol/libraries/logic/GenericLogic.sol";
import "contracts/protocol/libraries/logic/ValidationLogic.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.sol";
import
    "contracts/protocol/lendingpool/InterestRateStrategies/DefaultReserveInterestRateStrategy.sol";
import "contracts/protocol/lendingpool/LendingPool.sol";
import "contracts/protocol/lendingpool/LendingPoolCollateralManager.sol";
import "contracts/protocol/lendingpool/LendingPoolConfigurator.sol";
import "contracts/protocol/lendingpool/minipool/MiniPool.sol";
import "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "contracts/protocol/lendingpool/minipool/MiniPoolConfigurator.sol";
import "contracts/protocol/lendingpool/minipool/FlowLimiter.sol";

import "contracts/deployments/ATokensAndRatesHelper.sol";
import "contracts/protocol/tokenization/AToken.sol";
import "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import "contracts/protocol/tokenization/VariableDebtToken.sol";
import "contracts/mocks/tokens/MintableERC20.sol";
import "contracts/mocks/tokens/WETH9Mocked.sol";
import "contracts/mocks/oracle/CLAggregators/MockAggregator.sol";
import "contracts/mocks/tokens/MockVault.sol";
import "contracts/mocks/tokens/MockStrat.sol";
import "contracts/mocks/tokens/ExternalContract.sol";
import "contracts/mocks/dependencies/IStrategy.sol";
import "contracts/mocks/dependencies/IExternalContract.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

import "contracts/protocol/lendingpool/minipool/MiniPoolDefaultReserveInterestRate.sol";
import "contracts/mocks/oracle/PriceOracle.sol";
import "contracts/protocol/lendingpool/minipool/MiniPoolCollateralManager.sol";

import "./DeployDataTypes.s.sol";

function _deployLendingPool(
    address admin,
    address[] memory mockTokens,
    Oracle oracle,
    uint[] memory sStrat,
    uint[] memory volStrat
) returns (DeployedContracts memory){
    DeployedContracts memory contracts;
    string memory marketId = "UV TestNet Market";
    contracts.rewarder = new Rewarder();
    contracts.lendingPoolAddressesProviderRegistry = new LendingPoolAddressesProviderRegistry();
    contracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider(marketId);
    contracts.lendingPoolAddressesProviderRegistry
        .registerAddressesProvider(address(contracts.lendingPoolAddressesProvider), 1);
    //here is where we would set admin but there is no safe on testnet, so we pass in an EOA
    contracts.lendingPoolAddressesProvider.setPoolAdmin(admin);
    contracts.lendingPoolAddressesProvider.setEmergencyAdmin(admin);
    contracts.lendingPool = new LendingPool();
    contracts.lendingPool.initialize(
        ILendingPoolAddressesProvider(contracts.lendingPoolAddressesProvider));
    contracts.lendingPoolAddressesProvider.setLendingPoolImpl(address(contracts.lendingPool));
    address lendingPoolProxy = address(contracts.lendingPoolAddressesProvider.getLendingPool());
    contracts.lendingPool = LendingPool(lendingPoolProxy);
    contracts.treasury = new Treasury(contracts.lendingPoolAddressesProvider);
    contracts.lendingPoolConfigurator = new LendingPoolConfigurator();
    contracts.lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(
        address(contracts.lendingPoolConfigurator));
    address lendingPoolConfiguratorProxy = contracts.lendingPoolAddressesProvider.getLendingPoolConfigurator();
    contracts.lendingPoolConfigurator = LendingPoolConfigurator(lendingPoolConfiguratorProxy);
    contracts.lendingPoolConfigurator.setPoolPause(true);
    contracts.aTokensAndRatesHelper = new ATokensAndRatesHelper(
            payable(lendingPoolProxy),
            address(contracts.lendingPoolAddressesProvider),
            lendingPoolConfiguratorProxy
        );
    contracts.aToken = new AToken();
    contracts.variableDebtToken = new VariableDebtToken();
    contracts.wETHGateway = new WETHGateway(mockTokens[0]); //we know weth is idx 0
    contracts.lendingPoolCollateralManager = new LendingPoolCollateralManager();
    contracts.lendingPoolAddressesProvider.setPriceOracle(address(oracle));
    contracts.protocolDataProvider = new ProtocolDataProvider(contracts.lendingPoolAddressesProvider);
    contracts.stableStrategy = new DefaultReserveInterestRateStrategy(
        contracts.lendingPoolAddressesProvider,
        sStrat[0],
        sStrat[1],
        sStrat[2],
        sStrat[3]);
    contracts.volatileStrategy = new DefaultReserveInterestRateStrategy(
        contracts.lendingPoolAddressesProvider,
        volStrat[0],
        volStrat[1],
        volStrat[2],
        volStrat[3]
    );
    contracts.aTokenErc6909 = new ATokenERC6909();
    contracts.miniPoolImpl = new MiniPool();
    contracts.miniPoolAddressesProvider = new MiniPoolAddressesProvider(
        ILendingPoolAddressesProvider(address(contracts.lendingPoolAddressesProvider))
    );
    contracts.flowLimiter = new flowLimiter(
        contracts.lendingPoolAddressesProvider,
        IMiniPoolAddressesProvider(address(contracts.miniPoolAddressesProvider)),
        contracts.lendingPool
    );
    contracts.miniPoolConfigurator = new MiniPoolConfigurator();
    contracts.miniPoolAddressesProvider.setMiniPoolConfigurator(
        address(contracts.miniPoolConfigurator)
    );
    contracts.miniPoolConfigurator = MiniPoolConfigurator(
        contracts.miniPoolAddressesProvider.getMiniPoolConfigurator()
    );
    contracts.miniPoolAddressesProvider.setMiniPoolImpl(address(contracts.miniPoolImpl));
    contracts.miniPoolAddressesProvider.setAToken6909Impl(address(contracts.aTokenErc6909));
    contracts.lendingPoolAddressesProvider.setMiniPoolAddressesProvider(
        address(contracts.miniPoolAddressesProvider)
    );
    contracts.lendingPoolAddressesProvider.setFlowLimiter(address(contracts.flowLimiter));


    return contracts;
}

function _configureReserves(
    DeployedContracts memory contracts,
    address[] memory tokens,
    ConfigParams memory configParams,
    address admin
) {
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](tokens.length);
        ATokensAndRatesHelper.ConfigureReserveInput[] memory inputConfigParams =
            new ATokensAndRatesHelper.ConfigureReserveInput[](tokens.length);

        for (uint8 idx = 0; idx < tokens.length; idx++) {
            string memory tmpSymbol = ERC20(tokens[idx]).symbol();
            address interestStrategy = configParams.isStableStrategy[idx] != false
                ? address(contracts.stableStrategy)
                : address(contracts.volatileStrategy);
            initInputParams[idx] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(contracts.aToken),
                variableDebtTokenImpl: address(contracts.variableDebtToken),
                underlyingAssetDecimals: ERC20(tokens[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: tokens[idx],
                reserveType: configParams.reserveTypes[idx],
                treasury: address(contracts.treasury),
                incentivesController: address(contracts.rewarder),
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat("Cod3x Lend ", tmpSymbol),
                aTokenSymbol: string.concat("cl", tmpSymbol),
                variableDebtTokenName: string.concat("Cod3x Lend variable debt bearing ", tmpSymbol),
                variableDebtTokenSymbol: string.concat("variableDebt", tmpSymbol),
                params: "0x10"
            });
        }

        contracts.lendingPoolConfigurator.batchInitReserve(initInputParams);

        for (uint8 idx = 0; idx < tokens.length; idx++) {
            inputConfigParams[idx] = ATokensAndRatesHelper.ConfigureReserveInput({
                asset: tokens[idx],
                reserveType: configParams.reserveTypes[idx],
                baseLTV: configParams.baseLTVs[idx],
                liquidationThreshold: configParams.liquidationThresholds[idx],
                liquidationBonus: configParams.liquidationBonuses[idx],
                reserveFactor: configParams.reserveFactors[idx],
                borrowingEnabled: configParams.borrowingEnabled[idx]
            });
        }
        contracts.lendingPoolAddressesProvider.setPoolAdmin(address(contracts.aTokensAndRatesHelper));
        contracts.aTokensAndRatesHelper.configureReserves(inputConfigParams);
        contracts.lendingPoolAddressesProvider.setPoolAdmin(admin);
}


function _deployERC20Mocks(string[] memory names, string[] memory symbols, uint8[] memory decimals, int256[] memory prices)
    returns (address[] memory, Oracle) {
        address[] memory tokens = new address[](names.length);
        address[] memory aggregators = new address[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            if (keccak256(abi.encodePacked(symbols[i])) == keccak256(abi.encodePacked("WETH"))) {
                tokens[i] = address(_deployWETH9Mocked());
                
            }
            else {
                tokens[i] = address(_deployERC20Mock(names[i], symbols[i], decimals[i]));
            }
            aggregators[i] = address(_deployMockAggregator(tokens[i], prices[i]));

        }
                        //mock tokens, mock aggregators, fallbackOracle, baseCurrency, baseCurrencyUnit
        Oracle oracle = _deployOracle(tokens, aggregators, address(0), address(0), 100000000);
        return (tokens, oracle);
}

function _deployERC20Mock(
    string memory name, string memory symbol, uint8 decimals)
    returns (MintableERC20) {
        MintableERC20 token = new MintableERC20(name, symbol, decimals);
        return token;
}

function _deployWETH9Mocked() returns (WETH9Mocked) {
    WETH9Mocked weth = new WETH9Mocked();
    return weth;
}

/*function _deployMockVault() returns (MockVault) {
    MockVault vault = new MockVault();
    return vault;
}*/

function _deployMockAggregator(address token, int256 price) returns (MockAggregator) {
    MockAggregator aggregator = new MockAggregator(price, int256(int8(MintableERC20(token).decimals())));
    return aggregator;
}

function _deployOracle( 
    address[] memory assets,
    address[] memory sources,
    address fallbackOracle,
    address baseCurrency,
    uint256 baseCurrencyUnit
    ) returns (Oracle) {
    Oracle oracle = new Oracle(assets, sources, fallbackOracle, baseCurrency, baseCurrencyUnit);
    return oracle;
}

function _updateOracle(
    Oracle oracle, 
    address[] memory assets, 
    address[] memory sources
    ) 
{
    oracle.setAssetSources(assets, sources);
}

function _deployERC20MocksAndUpdateOracle(
    string[] memory names, 
    string[] memory symbols, 
    uint8[] memory decimals, 
    int256[] memory prices, 
    Oracle oracle
)returns (address[] memory) {
    address[] memory tokens = new address[](names.length);
    address[] memory aggregators = new address[](names.length);
    for (uint256 i = 0; i < names.length; i++) {
        
        tokens[i] = address(_deployERC20Mock(names[i], symbols[i], decimals[i]));
        
        aggregators[i] = address(_deployMockAggregator(tokens[i], prices[i]));
    }
    _updateOracle(oracle, tokens, aggregators);
    return tokens;
}


function _deployMiniPool(
    DeployedContracts memory contracts,
    MiniPoolConfigParams memory miniPoolConfigParams,
    address admin,
    uint256 miniPoolID
) returns (address aToken, address miniPool)
{
        IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
        new IMiniPoolConfigurator.InitReserveInput[](miniPoolConfigParams.miniPoolAssets.length);
        
        uint256[] memory ssStrat = new uint256[](4);
        ssStrat[0] = uint256(0.75e27);
        ssStrat[1] = uint256(0e27);
        ssStrat[2] = uint256(0.01e27);
        ssStrat[3] = uint256(0.1e27);

        MiniPoolDefaultReserveInterestRateStrategy IRS = new MiniPoolDefaultReserveInterestRateStrategy(
            IMiniPoolAddressesProvider(address(contracts.miniPoolAddressesProvider)),
            ssStrat[0],
            ssStrat[1],
            ssStrat[2],
            ssStrat[3]
        );

        contracts.miniPoolAddressesProvider.deployMiniPool();
        address mp = contracts.miniPoolAddressesProvider.getMiniPool(miniPoolID);
        address aTokensErc6909Addr = contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp);
        //FIRST START WITH MINIPOOL EXCLUSIVE ASSETS
        for (uint8 idx = 0; idx < miniPoolConfigParams.miniPoolAssets.length; idx++) {
            string memory tmpSymbol = ERC20(miniPoolConfigParams.miniPoolAssets[idx]).symbol();
            string memory tmpName = ERC20(miniPoolConfigParams.miniPoolAssets[idx]).name();

            address interestStrategy = miniPoolConfigParams.miniPoolConfig.isStableStrategy[idx] != false
                ? address(contracts.stableStrategy)
                : address(contracts.volatileStrategy);

            initInputParams[idx] = IMiniPoolConfigurator.InitReserveInput({
                underlyingAssetDecimals: ERC20(miniPoolConfigParams.miniPoolAssets[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: miniPoolConfigParams.miniPoolAssets[idx],
                underlyingAssetName: tmpName,
                underlyingAssetSymbol: tmpSymbol
            });
        }
        contracts.miniPoolConfigurator.batchInitReserve(initInputParams, IMiniPool(mp));

        for (uint8 idx = 0; idx < miniPoolConfigParams.miniPoolAssets.length; idx++) {
            contracts.miniPoolConfigurator.configureReserveAsCollateral(
                miniPoolConfigParams.miniPoolAssets[idx], 
                miniPoolConfigParams.miniPoolConfig.reserveTypes[idx], 
                miniPoolConfigParams.miniPoolConfig.baseLTVs[idx], 
                miniPoolConfigParams.miniPoolConfig.liquidationThresholds[idx], 
                miniPoolConfigParams.miniPoolConfig.liquidationBonuses[idx], 
                IMiniPool(mp)
            );

            contracts.miniPoolConfigurator.activateReserve(
                miniPoolConfigParams.miniPoolAssets[idx], 
                miniPoolConfigParams.miniPoolConfig.reserveTypes[idx], 
                IMiniPool(mp)
            );

            contracts.miniPoolConfigurator.enableBorrowingOnReserve(
                miniPoolConfigParams.miniPoolAssets[idx], 
                miniPoolConfigParams.miniPoolConfig.reserveTypes[idx], 
                IMiniPool(mp)
            );

            contracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
                miniPoolConfigParams.miniPoolAssets[idx], 
                miniPoolConfigParams.miniPoolConfig.reserveTypes[idx], 
                address(contracts.stableStrategy), 
                IMiniPool(mp)
            );
        }
        //THEN ADD MAIN POOL ASSETS
        initInputParams =
        new IMiniPoolConfigurator.InitReserveInput[](miniPoolConfigParams.mainPoolAssets.length);
        for (uint8 idx = 0; idx < miniPoolConfigParams.mainPoolAssets.length; idx++) {
            string memory tmpSymbol = ERC20(miniPoolConfigParams.mainPoolAssets[idx]).symbol();
            string memory tmpName = ERC20(miniPoolConfigParams.mainPoolAssets[idx]).name();

            address interestStrategy = miniPoolConfigParams.mainPoolConfig.isStableStrategy[idx] != false
                ? address(contracts.stableStrategy)
                : address(contracts.volatileStrategy);

            initInputParams[idx] = IMiniPoolConfigurator.InitReserveInput({
                underlyingAssetDecimals: ERC20(miniPoolConfigParams.mainPoolAssets[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: miniPoolConfigParams.mainPoolAssets[idx],
                underlyingAssetName: tmpName,
                underlyingAssetSymbol: tmpSymbol
            });
        }
        contracts.miniPoolConfigurator.batchInitReserve(initInputParams, IMiniPool(mp));

        for (uint8 idx = 0; idx < miniPoolConfigParams.mainPoolAssets.length; idx++) {
            contracts.miniPoolConfigurator.configureReserveAsCollateral(
                miniPoolConfigParams.mainPoolAssets[idx], 
                miniPoolConfigParams.mainPoolConfig.reserveTypes[idx], 
                miniPoolConfigParams.mainPoolConfig.baseLTVs[idx], 
                miniPoolConfigParams.mainPoolConfig.liquidationThresholds[idx], 
                miniPoolConfigParams.mainPoolConfig.liquidationBonuses[idx], 
                IMiniPool(mp)
            );

            contracts.miniPoolConfigurator.activateReserve(
                miniPoolConfigParams.mainPoolAssets[idx], 
                miniPoolConfigParams.mainPoolConfig.reserveTypes[idx], 
                IMiniPool(mp)
            );

            contracts.miniPoolConfigurator.enableBorrowingOnReserve(
                miniPoolConfigParams.mainPoolAssets[idx], 
                miniPoolConfigParams.mainPoolConfig.reserveTypes[idx], 
                IMiniPool(mp)
            );

            contracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
                miniPoolConfigParams.mainPoolAssets[idx], 
                miniPoolConfigParams.mainPoolConfig.reserveTypes[idx], 
                address(IRS), 
                IMiniPool(mp)
            );
        }
        return (aTokensErc6909Addr, mp);
}