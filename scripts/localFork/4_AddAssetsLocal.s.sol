// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../DeployDataTypes.sol";
import "../helpers/InitAndConfigurationHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployMiniPoolLocal} from "./2_DeployMiniPoolLocal.s.sol";
import {AddStratsLocal} from "./3_AddStratsLocal.s.sol";

contract AddAssetsLocal is Script, InitAndConfigurationHelper, Test {
    using stdJson for string;

    DeployedContracts contractsWithStrats;

    function readAddressesToContracts(string memory root) public {
        string memory path =
            string.concat(root, "/scripts/localFork/outputs/3_DeployedStrategies.json");
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

    function run() external returns (DeployedContracts memory) {
        console.log("4_AddAssets");

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/4_AssetsToAdd.json");
        console.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        General memory general = abi.decode(deploymentConfig.parseRaw(".general"), (General));

        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            deploymentConfig.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );

        PoolReserversConfig[] memory lendingPoolReserversConfig = abi.decode(
            deploymentConfig.parseRaw(".lendingPoolReserversConfig"), (PoolReserversConfig[])
        );
        PoolReserversConfig[] memory miniPoolReserversConfig = abi.decode(
            deploymentConfig.parseRaw(".miniPoolReserversConfig"), (PoolReserversConfig[])
        );
        OracleConfig memory oracleConfig =
            abi.decode(deploymentConfig.parseRaw(".oracleConfig"), (OracleConfig));

        console.log("Local fork deployment");
        /* Fork Identifier */
        string memory RPC = vm.envString("BASE_RPC_URL");
        uint256 FORK_BLOCK = 21838058;
        uint256 fork;
        fork = vm.createSelectFork(RPC, FORK_BLOCK);

        /* Config fetching */
        DeployMiniPoolLocal deployMiniPool = new DeployMiniPoolLocal();
        contracts = deployMiniPool.run();
        AddStratsLocal addStrats = new AddStratsLocal();

        contracts = addStrats.run();

        vm.startPrank(FOUNDRY_DEFAULT);
        contracts.oracle.setAssetSources(
            oracleConfig.assets, oracleConfig.sources, oracleConfig.timeouts
        );
        _initAndConfigureReserves(contracts, lendingPoolReserversConfig, general);
        _initAndConfigureMiniPoolReserves(
            contracts,
            miniPoolReserversConfig,
            poolAddressesProviderConfig.poolId,
            general.usdBootstrapAmount
        );
        vm.stopPrank();

        return contracts;
    }
}
