// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./DeployDataTypes.sol";
import "./helpers/InitAndConfigurationHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console2.sol";

contract AddAssets is Script, InitAndConfigurationHelper, Test {
    using stdJson for string;

    DeployedContracts contractsWithStrats;

    function checkContracts(
        PoolReserversConfig[] memory lendingPoolReserversConfig,
        PoolReserversConfig[] memory miniPoolReserversConfig
    ) public {
        console2.log("Lending pool");
        for (uint256 idx = 0; idx < lendingPoolReserversConfig.length; idx++) {
            AggregatedMainPoolReservesData memory aggregatedMainPoolReservesData = contracts
                .asteraDataProvider
                .getAggregatedMainPoolReserveData(
                address(lendingPoolReserversConfig[idx].tokenAddress),
                lendingPoolReserversConfig[idx].reserveType
            );
            assertEq(
                aggregatedMainPoolReservesData.baseLTVasCollateral,
                lendingPoolReserversConfig[idx].baseLtv,
                "Wrong Ltv"
            );
            assertEq(
                aggregatedMainPoolReservesData.reserveLiquidationThreshold,
                lendingPoolReserversConfig[idx].liquidationThreshold,
                "Wrong liquidationThreshold"
            );
            assertEq(
                aggregatedMainPoolReservesData.reserveLiquidationBonus,
                lendingPoolReserversConfig[idx].liquidationBonus,
                "Wrong liquidationBonus"
            );
            assertEq(
                aggregatedMainPoolReservesData.symbol,
                lendingPoolReserversConfig[idx].symbol,
                "Wrong Symbol"
            );
            assertEq(aggregatedMainPoolReservesData.isActive, true, "reserve is not active");
            assertEq(aggregatedMainPoolReservesData.borrowingEnabled, true, "borrowing not enabled");
            assertEq(aggregatedMainPoolReservesData.flashloanEnabled, true, "floshloan not enabled");
            assertEq(aggregatedMainPoolReservesData.isFrozen, false, "reserve is frozen");
            assertEq(
                aggregatedMainPoolReservesData.usageAsCollateralEnabled,
                true,
                "collateral usage not enabled"
            );
            assertEq(
                aggregatedMainPoolReservesData.asteraReserveFactor,
                lendingPoolReserversConfig[idx].reserveFactor,
                "wrong asteraReserveFactor"
            );
            assertEq(
                aggregatedMainPoolReservesData.miniPoolOwnerReserveFactor,
                lendingPoolReserversConfig[idx].miniPoolOwnerFee,
                "wrong miniPoolOwnerReserveFactor"
            );
            assertEq(aggregatedMainPoolReservesData.depositCap, 0, "Wrong deposit cap");
        }

        console2.log("Mini pool");
        uint256 miniPoolCount = contracts.miniPoolAddressesProvider.getMiniPoolCount();
        for (uint256 i = 0; i < miniPoolCount; i++) {
            address mp = contracts.miniPoolAddressesProvider.getMiniPool(i);

            for (uint256 idx = 0; idx < miniPoolReserversConfig.length; idx++) {
                AggregatedMiniPoolReservesData memory aggregatedMiniPoolReservesData = contracts
                    .asteraDataProvider
                    .getReserveDataForAssetAtMiniPool(
                    address(miniPoolReserversConfig[idx].tokenAddress), mp
                );
                assertEq(
                    aggregatedMiniPoolReservesData.baseLTVasCollateral,
                    miniPoolReserversConfig[idx].baseLtv,
                    "Wrong Ltv"
                );
                assertEq(
                    aggregatedMiniPoolReservesData.reserveLiquidationThreshold,
                    miniPoolReserversConfig[idx].liquidationThreshold,
                    "Wrong liquidationThreshold"
                );
                assertEq(
                    aggregatedMiniPoolReservesData.reserveLiquidationBonus,
                    miniPoolReserversConfig[idx].liquidationBonus,
                    "Wrong liquidationBonus"
                );
                assertEq(
                    aggregatedMiniPoolReservesData.symbol,
                    miniPoolReserversConfig[idx].symbol,
                    "Wrong Symbol"
                );
                assertEq(aggregatedMiniPoolReservesData.isActive, true, "reserve is not active");
                assertEq(
                    aggregatedMiniPoolReservesData.borrowingEnabled, true, "borrowing not enabled"
                );
                assertEq(
                    aggregatedMiniPoolReservesData.flashloanEnabled, true, "floshloan not enabled"
                );
                assertEq(aggregatedMiniPoolReservesData.isFrozen, false, "reserve is frozen");
                assertEq(
                    aggregatedMiniPoolReservesData.usageAsCollateralEnabled,
                    true,
                    "collateral usage not enabled"
                );
                assertEq(
                    aggregatedMiniPoolReservesData.asteraReserveFactor,
                    miniPoolReserversConfig[idx].reserveFactor,
                    "wrong asteraReserveFactor"
                );
                assertEq(
                    aggregatedMiniPoolReservesData.miniPoolOwnerReserveFactor,
                    miniPoolReserversConfig[idx].miniPoolOwnerFee,
                    "wrong miniPoolOwnerReserveFactor"
                );
                assertEq(aggregatedMiniPoolReservesData.depositCap, 0, "Wrong deposit cap");
            }
        }
    }

    function writeJsonData(string memory path) internal {
        (,, address[] memory aTokens, address[] memory debtTokens) =
            contracts.asteraDataProvider.getAllLpTokens();

        {
            address[] memory wrappedTokens = new address[](aTokens.length);
            for (uint256 idx = 0; idx < aTokens.length; idx++) {
                wrappedTokens[idx] = AToken(aTokens[idx]).WRAPPER_ADDRESS();
            }
            vm.serializeAddress("addedAssets", "wrappedTokens", wrappedTokens);
        }

        vm.serializeAddress("addedAssets", "aTokens", aTokens);
        vm.serializeAddress("addedAssets", "debtTokens", debtTokens);
        vm.serializeAddress("addedAssets", "aTokenImpl", address(contracts.aToken));
        string memory output = vm.serializeAddress(
            "addedAssets", "variableDebtTokenImpl", address(contracts.variableDebtToken)
        );

        vm.writeJson(output, path);

        console2.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function readStratAddresses(string memory path) public {
        string memory deployedStrategies = vm.readFile(path);
        /* Pi miniPool strats */
        address[] memory tmpStrats = deployedStrategies.readAddressArray(".miniPoolPiStrategies");
        delete contracts.miniPoolPiStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolPiStrategies.push(
                MiniPoolPiReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Stable miniPool strats */
        tmpStrats = deployedStrategies.readAddressArray(".miniPoolStableStrategies");
        delete contracts.miniPoolStableStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolStableStrategies.push(
                MiniPoolDefaultReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Volatile miniPool strats */
        tmpStrats = deployedStrategies.readAddressArray(".miniPoolVolatileStrategies");
        delete contracts.miniPoolVolatileStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolVolatileStrategies.push(
                MiniPoolDefaultReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Pi strats */
        tmpStrats = deployedStrategies.readAddressArray(".piStrategies");
        delete contracts.piStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.piStrategies.push(PiReserveInterestRateStrategy(tmpStrats[idx]));
        }
        /* Stable strats */
        tmpStrats = deployedStrategies.readAddressArray(".stableStrategies");
        delete contracts.stableStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.stableStrategies.push(DefaultReserveInterestRateStrategy(tmpStrats[idx]));
        }
        /* Volatile strats */
        tmpStrats = deployedStrategies.readAddressArray(".volatileStrategies");
        delete contracts.volatileStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.volatileStrategies.push(DefaultReserveInterestRateStrategy(tmpStrats[idx]));
        }
    }

    function readLendingPoolAddresses(string memory path) public {
        string memory config = vm.readFile(path);

        contracts.aToken = AToken(config.readAddress(".aTokenImpl"));
        contracts.variableDebtToken =
            VariableDebtToken(config.readAddress(".variableDebtTokenImpl"));
        contracts.lendingPoolConfigurator =
            LendingPoolConfigurator(config.readAddress(".lendingPoolConfigurator"));
        contracts.lendingPoolAddressesProvider =
            LendingPoolAddressesProvider(config.readAddress(".lendingPoolAddressesProvider"));
        contracts.asteraDataProvider =
            AsteraDataProvider2(config.readAddress(".asteraDataProvider"));
        contracts.lendingPool = LendingPool(config.readAddress(".lendingPool"));
    }

    function run() external returns (DeployedContracts memory) {
        console2.log("4_AddAssets");

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/4_AssetsToAdd.json");
        console2.log("PATH: ", path);
        string memory config = vm.readFile(path);

        General memory general = abi.decode(config.parseRaw(".general"), (General));

        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            config.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );

        PoolReserversConfig[] memory lendingPoolReserversConfig =
            abi.decode(config.parseRaw(".lendingPoolReserversConfig"), (PoolReserversConfig[]));
        PoolReserversConfig[] memory miniPoolReserversConfig =
            abi.decode(config.parseRaw(".miniPoolReserversConfig"), (PoolReserversConfig[]));
        OracleConfig memory oracleConfig =
            abi.decode(config.parseRaw(".oracleConfig"), (OracleConfig));

        if (!vm.envBool("MAINNET")) {
            console2.log("Testnet");

            /* Lending pool settings */
            readLendingPoolAddresses(
                string.concat(root, "/scripts/outputs/testnet/1_LendingPoolContracts.json")
            );

            readStratAddresses(
                string.concat(root, "/scripts/outputs/testnet/3_DeployedStrategies.json")
            );

            /* Read all mocks deployed */
            path = string.concat(root, "/scripts/outputs/testnet/0_MockedTokens.json");
            console2.log("PATH: ", path);
            config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

            require(
                mockedTokens.length >= lendingPoolReserversConfig.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                // for (uint8 idx = 0; idx < lendingPoolReserversConfig.length; idx++) {
                //     for (uint8 i = 0; i < mockedTokens.length; i++) {
                //         if (
                //             keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                //                 == keccak256(abi.encodePacked(lendingPoolReserversConfig[idx].symbol))
                //         ) {
                //             lendingPoolReserversConfig[idx].tokenAddress = address(mockedTokens[i]);
                //             break;
                //         }
                //     }
                //     require(
                //         lendingPoolReserversConfig[idx].tokenAddress != address(0),
                //         "Mocked token not assigned"
                //     );
                // }
            }

            console2.log("Init and configuration");
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            contracts.oracle = Oracle(contracts.lendingPoolAddressesProvider.getPriceOracle());
            contracts.oracle.setAssetSources(
                oracleConfig.assets, oracleConfig.sources, oracleConfig.timeouts
            );
            _initAndConfigureReserves(contracts, lendingPoolReserversConfig, general);
            vm.stopBroadcast();

            /* Mini pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/testnet/2_MiniPoolContracts.json");
                console2.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            contracts.miniPoolAddressesProvider =
                MiniPoolAddressesProvider(config.readAddress(".miniPoolAddressesProvider"));
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(config.readAddress(".miniPoolConfigurator"));

            /* Mini pool mocks assignment */
            require(
                mockedTokens.length >= miniPoolReserversConfig.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                // for (uint8 idx = 0; idx < miniPoolReserversConfig.length; idx++) {
                //     for (uint8 i = 0; i < mockedTokens.length; i++) {
                //         if (
                //             keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                //                 == keccak256(abi.encodePacked(miniPoolReserversConfig[idx].symbol))
                //         ) {
                //             miniPoolReserversConfig[idx].tokenAddress = address(mockedTokens[i]);
                //             break;
                //         }
                //     }
                //     require(
                //         miniPoolReserversConfig[idx].tokenAddress != address(0),
                //         "Mocked token not assigned"
                //     );
                // }
            }

            console2.log("Mini pool init and configuration");
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console2.log("Configuration ");
            _initAndConfigureMiniPoolReserves(
                contracts,
                miniPoolReserversConfig,
                poolAddressesProviderConfig.poolId,
                general.usdBootstrapAmount
            );
            vm.stopBroadcast();
            path = string.concat(root, "/scripts/outputs/testnet/4_AddedAssets.json");
        } else if (vm.envBool("MAINNET")) {
            console2.log("Mainnet");
            /* Lending pool settings */
            readLendingPoolAddresses(
                string.concat(root, "/scripts/outputs/mainnet/1_LendingPoolContracts.json")
            );

            readStratAddresses(
                string.concat(root, "/scripts/outputs/mainnet/3_DeployedStrategies.json")
            );

            /* Configure reserve */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            contracts.oracle = Oracle(contracts.lendingPoolAddressesProvider.getPriceOracle());
            contracts.oracle.setAssetSources(
                oracleConfig.assets, oracleConfig.sources, oracleConfig.timeouts
            );
            _initAndConfigureReserves(contracts, lendingPoolReserversConfig, general);
            vm.stopBroadcast();

            /* Mini pool settings */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/mainnet/2_MiniPoolContracts.json");
                console2.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }
            /* Ready mini pool contracts settings */
            contracts.miniPoolAddressesProvider =
                MiniPoolAddressesProvider(config.readAddress(".miniPoolAddressesProvider"));
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(config.readAddress(".miniPoolConfigurator"));

            /* Configuration */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console2.log("Configuration ");
            _initAndConfigureMiniPoolReserves(
                contracts,
                miniPoolReserversConfig,
                poolAddressesProviderConfig.poolId,
                general.usdBootstrapAmount
            );
            vm.stopBroadcast();
            path = string.concat(root, "/scripts/outputs/mainnet/4_AddedAssets.json");
        } else {
            console2.log("No deployment type selected in .env");
        }
        checkContracts(lendingPoolReserversConfig, miniPoolReserversConfig);
        writeJsonData(path);
        return contracts;
    }
}
