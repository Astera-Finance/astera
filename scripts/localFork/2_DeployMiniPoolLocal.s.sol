// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../DeployDataTypes.sol";
import "../helpers/MiniPoolHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployLendingPoolLocal} from "./1_DeployLendingPoolLocal.s.sol";

contract DeployMiniPoolLocal is Script, Test, MiniPoolHelper {
    using stdJson for string;

    function readPreviousDeployments(string memory root) internal returns (bool readPrevious) {
        string memory path =
            string.concat(root, "/scripts/localFork/outputs/2_MiniPoolContracts.json");
        console.log("PREVIOUS DEPLOYMENT PATH: ", path);
        try vm.readFile(path) returns (string memory previousContracts) {
            address[] memory tmpContracts;
            contracts.miniPoolImpl = MiniPool(previousContracts.readAddress(".miniPoolImpl"));
            // tmpContracts = previousContracts.readAddressArray(".miniPoolProxy");
            // for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
            //     contracts.miniPools.push(MiniPool(tmpContracts[idx]));
            // }
            contracts.aTokenErc6909Impl =
                ATokenERC6909(previousContracts.readAddress(".aTokenErc6909Impl"));
            // for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
            //     contracts.aTokenErc6909.push(ATokenERC6909(tmpContracts[idx]));
            // }
            tmpContracts = previousContracts.readAddressArray(".miniPoolPiStrategies");
            for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
                contracts.miniPoolPiStrategies.push(
                    MiniPoolPiReserveInterestRateStrategy(tmpContracts[idx])
                );
            }
            tmpContracts = previousContracts.readAddressArray(".miniPoolStableStrategies");
            for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
                contracts.miniPoolStableStrategies.push(
                    MiniPoolDefaultReserveInterestRateStrategy(tmpContracts[idx])
                );
            }
            tmpContracts = previousContracts.readAddressArray(".miniPoolVolatileStrategies");
            for (uint256 idx = 0; idx < tmpContracts.length; idx++) {
                contracts.miniPoolVolatileStrategies.push(
                    MiniPoolDefaultReserveInterestRateStrategy(tmpContracts[idx])
                );
            }
            contracts.flowLimiter = FlowLimiter(previousContracts.readAddress(".flowLimiter"));
            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                previousContracts.readAddress(".miniPoolAddressesProvider")
            );
            contracts.miniPoolConfigurator =
                MiniPoolConfigurator(previousContracts.readAddress(".miniPoolConfigurator"));

            return true;
        } catch {
            return false;
        }
    }

    function writeJsonData(string memory path) internal {
        /* Write important contracts into the file */
        uint256 nrOfMiniPools = contracts.miniPoolAddressesProvider.getMiniPoolCount();
        address[] memory miniPools = new address[](nrOfMiniPools);
        address[] memory aErc6909s = new address[](nrOfMiniPools);
        for (uint256 idx = 0; idx < nrOfMiniPools; idx++) {
            miniPools[idx] = contracts.miniPoolAddressesProvider.getMiniPool(idx);
        }
        vm.serializeAddress("miniPoolContracts", "miniPoolProxy", miniPools);
        vm.serializeAddress("miniPoolContracts", "miniPoolImpl", address(contracts.miniPoolImpl));
        for (uint256 idx = 0; idx < nrOfMiniPools; idx++) {
            aErc6909s[idx] = contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(idx);
        }
        vm.serializeAddress("miniPoolContracts", "aTokenErc6909Proxy", aErc6909s);
        vm.serializeAddress(
            "miniPoolContracts", "aTokenErc6909Impl", address(contracts.aTokenErc6909Impl)
        );

        vm.serializeAddress(
            "miniPoolContracts",
            "miniPoolAddressesProvider",
            address(contracts.miniPoolAddressesProvider)
        );
        vm.serializeAddress("miniPoolContracts", "flowLimiter", address(contracts.flowLimiter));

        {
            address[] memory stableAddresses =
                new address[](contracts.miniPoolStableStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolStableStrategies.length; idx++) {
                stableAddresses[idx] = address(contracts.miniPoolStableStrategies[idx]);
            }
            vm.serializeAddress("miniPoolContracts", "miniPoolStableStrategies", stableAddresses);
        }
        {
            address[] memory volatileAddresses =
                new address[](contracts.miniPoolVolatileStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolVolatileStrategies.length; idx++) {
                volatileAddresses[idx] = address(contracts.miniPoolVolatileStrategies[idx]);
            }
            vm.serializeAddress(
                "miniPoolContracts", "miniPoolVolatileStrategies", volatileAddresses
            );
        }
        {
            address[] memory piAddresses = new address[](contracts.miniPoolPiStrategies.length);
            for (uint256 idx = 0; idx < contracts.miniPoolPiStrategies.length; idx++) {
                piAddresses[idx] = address(contracts.miniPoolPiStrategies[idx]);
            }
            vm.serializeAddress("miniPoolContracts", "miniPoolPiStrategies", piAddresses);
        }

        string memory output = vm.serializeAddress(
            "miniPoolContracts", "miniPoolConfigurator", address(contracts.miniPoolConfigurator)
        );

        vm.writeJson(output, path);

        console.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function run() external returns (DeployedContracts memory) {
        console.log("2_DeployMiniPool");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/2_DeploymentConfig.json");
        console.log("PATH: ", path);
        string memory config = vm.readFile(path);

        General memory general = abi.decode(config.parseRaw(".general"), (General));

        PoolReserversConfig[] memory poolReserversConfig =
            abi.decode(config.parseRaw(".poolReserversConfig"), (PoolReserversConfig[]));
        LinearStrategy[] memory volatileStrategies =
            abi.decode(config.parseRaw(".volatileStrategies"), (LinearStrategy[]));
        LinearStrategy[] memory stableStrategies =
            abi.decode(config.parseRaw(".stableStrategies"), (LinearStrategy[]));

        PiStrategy[] memory piStrategies =
            abi.decode(config.parseRaw(".piStrategies"), (PiStrategy[]));

        OracleConfig memory oracleConfig =
            abi.decode(config.parseRaw(".oracleConfig"), (OracleConfig));

        bool usePreviousStrats = config.readBool(".usePreviousStrats");
        bool readPreviousContracts = config.readBool(".readPreviousContracts");

        /* Fork Identifier */
        {
            string memory RPC = vm.envString("BASE_RPC_URL");
            uint256 FORK_BLOCK = 21838058;
            uint256 fork;
            fork = vm.createSelectFork(RPC, FORK_BLOCK);
        }

        /* Config fetching */
        DeployLendingPoolLocal deployLendingPool = new DeployLendingPoolLocal();
        contracts = deployLendingPool.run();

        /* Deployment */
        vm.startPrank(FOUNDRY_DEFAULT);
        contracts.oracle.setAssetSources(
            oracleConfig.assets, oracleConfig.sources, oracleConfig.timeouts
        );
        deployMiniPoolInfra(
            general,
            volatileStrategies,
            stableStrategies,
            piStrategies,
            poolReserversConfig,
            FOUNDRY_DEFAULT,
            false
        );
        vm.stopPrank();

        /* Write important contracts into the file */
        writeJsonData(string.concat(root, "/scripts/localFork/outputs/2_MiniPoolContracts.json"));
        return contracts;
    }
}
