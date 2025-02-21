// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./DeployDataTypes.sol";
import "./helpers/LendingPoolHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console2.sol";

contract DeployLendingPool is Script, LendingPoolHelper, Test {
    using stdJson for string;

    function checkOwnerships() internal {
        assertEq(contracts.aTokensAndRatesHelper.owner(), vm.addr(vm.envUint("PRIVATE_KEY")));
        assertEq(contracts.cod3xLendDataProvider.owner(), vm.addr(vm.envUint("PRIVATE_KEY")));
        assertEq(contracts.lendingPoolAddressesProvider.owner(), vm.addr(vm.envUint("PRIVATE_KEY")));
        assertEq(
            contracts.lendingPoolAddressesProvider.getEmergencyAdmin(),
            vm.addr(vm.envUint("PRIVATE_KEY"))
        );
        assertEq(
            contracts.lendingPoolAddressesProvider.getPoolAdmin(),
            vm.addr(vm.envUint("PRIVATE_KEY"))
        );
        assertEq(contracts.oracle.owner(), vm.addr(vm.envUint("PRIVATE_KEY")));
        assertEq(contracts.wethGateway.owner(), vm.addr(vm.envUint("PRIVATE_KEY")));
        for (uint8 idx = 0; idx < contracts.piStrategies.length; idx++) {
            assertEq(contracts.piStrategies[idx].owner(), vm.addr(vm.envUint("PRIVATE_KEY")));
        }
    }

    function checkContractAddresses(PoolReserversConfig[] memory poolReserversConfig) internal {
        assertEq(
            contracts.lendingPoolAddressesProvider.getLendingPool(),
            address(contracts.lendingPool),
            "Wrong lending pool"
        );
        assertEq(
            contracts.lendingPoolAddressesProvider.getLendingPoolConfigurator(),
            address(contracts.lendingPoolConfigurator),
            "wrong pool configurator"
        );
        assertEq(
            contracts.lendingPoolAddressesProvider.getPriceOracle(),
            address(contracts.oracle),
            "wrong oracle"
        );
        assertEq(
            contracts.lendingPoolAddressesProvider.getFlowLimiter(),
            address(contracts.flowLimiter),
            "wrong flow limiter"
        );

        (address[] memory reserveList, bool[] memory reserveTypes) =
            contracts.lendingPool.getReservesList();
        for (uint256 idx = 0; idx < reserveList.length; idx++) {
            DataTypes.ReserveData memory data =
                contracts.lendingPool.getReserveData(reserveList[idx], reserveTypes[idx]);
            assertEq(
                AToken(data.aTokenAddress).UNDERLYING_ASSET_ADDRESS(),
                address(poolReserversConfig[idx].tokenAddress),
                "Wrong underlying token"
            );
            StaticData memory staticData = contracts.cod3xLendDataProvider.getLpReserveStaticData(
                address(poolReserversConfig[idx].tokenAddress), reserveTypes[idx]
            );
            assertEq(staticData.ltv, poolReserversConfig[idx].baseLtv, "Wrong Ltv");
            assertEq(
                staticData.liquidationThreshold,
                poolReserversConfig[idx].liquidationThreshold,
                "Wrong liquidationThreshold"
            );
            assertEq(
                staticData.liquidationBonus,
                poolReserversConfig[idx].liquidationBonus,
                "Wrong liquidationBonus"
            );
            assertEq(staticData.symbol, poolReserversConfig[idx].symbol, "Wrong Symbol");
        }
    }

    function writeJsonData(string memory path) internal {
        vm.serializeAddress("lendingPoolContracts", "oracle", address(contracts.oracle));
        {
            address[] memory stableAddresses = new address[](contracts.stableStrategies.length);
            for (uint256 idx = 0; idx < contracts.stableStrategies.length; idx++) {
                stableAddresses[idx] = address(contracts.stableStrategies[idx]);
            }
            vm.serializeAddress("lendingPoolContracts", "stableStrategies", stableAddresses);
        }
        {
            address[] memory volatileAddresses = new address[](contracts.stableStrategies.length);
            for (uint256 idx = 0; idx < contracts.volatileStrategies.length; idx++) {
                volatileAddresses[idx] = address(contracts.volatileStrategies[idx]);
            }
            vm.serializeAddress("lendingPoolContracts", "volatileStrategies", volatileAddresses);
        }
        {
            address[] memory piAddresses = new address[](contracts.piStrategies.length);
            for (uint256 idx = 0; idx < contracts.piStrategies.length; idx++) {
                piAddresses[idx] = address(contracts.piStrategies[idx]);
            }
            vm.serializeAddress("lendingPoolContracts", "piStrategies", piAddresses);
        }

        (,, address[] memory aTokens, address[] memory debtTokens) =
            contracts.cod3xLendDataProvider.getAllLpTokens();

        vm.serializeAddress("lendingPoolContracts", "aTokens", aTokens);

        {
            address[] memory wrappedTokens = new address[](aTokens.length);
            for (uint256 idx = 0; idx < aTokens.length; idx++) {
                wrappedTokens[idx] = AToken(aTokens[idx]).WRAPPER_ADDRESS();
            }
            vm.serializeAddress("lendingPoolContracts", "wrappedTokens", wrappedTokens);
        }

        // vm.serializeAddress("lendingPoolContracts", "aTokensWrappers", AToken(aTokens))
        vm.serializeAddress("lendingPoolContracts", "wethGateway", address(contracts.wethGateway));
        vm.serializeAddress("lendingPoolContracts", "debtTokens", debtTokens);
        vm.serializeAddress("lendingPoolContracts", "aTokenImpl", address(contracts.aToken));
        vm.serializeAddress(
            "lendingPoolContracts", "variableDebtTokenImpl", address(contracts.variableDebtToken)
        );

        vm.serializeAddress(
            "lendingPoolContracts",
            "cod3xLendDataProvider",
            address(contracts.cod3xLendDataProvider)
        );
        vm.serializeAddress(
            "lendingPoolContracts",
            "aTokensAndRatesHelper",
            address(contracts.aTokensAndRatesHelper)
        );

        vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPool",
            contracts.lendingPoolAddressesProvider.getLendingPool()
        );
        vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPoolAddressesProvider",
            address(contracts.lendingPoolAddressesProvider)
        );
        string memory output = vm.serializeAddress(
            "lendingPoolContracts",
            "lendingPoolConfigurator",
            address(contracts.lendingPoolConfigurator)
        );

        vm.writeJson(output, path);

        console2.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function run() external returns (DeployedContracts memory) {
        console2.log("1_DeployLendingPool");
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/1_DeploymentConfig.json");
        console2.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);
        General memory general = abi.decode(deploymentConfig.parseRaw(".general"), (General));

        PoolReserversConfig[] memory poolReserversConfig =
            abi.decode(deploymentConfig.parseRaw(".poolReserversConfig"), (PoolReserversConfig[]));
        LinearStrategy[] memory volatileStrategies =
            abi.decode(deploymentConfig.parseRaw(".volatileStrategies"), (LinearStrategy[]));
        LinearStrategy[] memory stableStrategies =
            abi.decode(deploymentConfig.parseRaw(".stableStrategies"), (LinearStrategy[]));
        PiStrategy[] memory piStrategies =
            abi.decode(deploymentConfig.parseRaw(".piStrategies"), (PiStrategy[]));
        OracleConfig memory oracleConfig =
            abi.decode(deploymentConfig.parseRaw(".oracleConfig"), (OracleConfig));

        address wethGateway = deploymentConfig.readAddress(".wethGateway");

        if (!vm.envBool("MAINNET")) {
            console2.log("Testnet Deployment");
            if (!vm.exists(string.concat(root, "/scripts/outputs/testnet"))) {
                vm.createDir(string.concat(root, "/scripts/outputs/testnet"), true);
            }
            /* Read all mocks deployed */
            path = string.concat(root, "/scripts/outputs/testnet/0_MockedTokens.json");
            console2.log("PATH: ", path);
            string memory config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

            require(
                mockedTokens.length >= poolReserversConfig.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                // for (uint8 idx = 0; idx < poolReserversConfig.length; idx++) {
                //     for (uint8 i = 0; i < mockedTokens.length; i++) {
                //         if (
                //             keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                //                 == keccak256(abi.encodePacked(poolReserversConfig[idx].symbol))
                //         ) {
                //             poolReserversConfig[idx].tokenAddress = address(mockedTokens[i]);
                //             if (piStrategies.length > i) {
                //                 piStrategies[idx].tokenAddress = address(mockedTokens[i]);
                //             }
                //             break;
                //         }
                //     }
                //     require(
                //         poolReserversConfig[idx].tokenAddress != address(0),
                //         "Mocked token not assigned"
                //     );
                // }
            }
            /* Deploy to testnet */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            console2.log("Deploying lending pool infra");
            deployLendingPoolInfra(
                general,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolReserversConfig,
                oracleConfig,
                vm.addr(vm.envUint("PRIVATE_KEY")),
                wethGateway
            );
            vm.stopBroadcast();

            path = string.concat(root, "/scripts/outputs/testnet/1_LendingPoolContracts.json");
        } else if (vm.envBool("MAINNET")) {
            console2.log("Mainnet Deployment");
            if (!vm.exists(string.concat(root, "/scripts/outputs/mainnet"))) {
                vm.createDir(string.concat(root, "/scripts/outputs/mainnet"), true);
            }
            /* Deploy to the mainnet */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            deployLendingPoolInfra(
                general,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                poolReserversConfig,
                oracleConfig,
                vm.addr(vm.envUint("PRIVATE_KEY")),
                wethGateway
            );
            vm.stopBroadcast();

            path = string.concat(root, "/scripts/outputs/mainnet/1_LendingPoolContracts.json");
        } else {
            console2.log("No deployment type selected in .env");
        }
        checkOwnerships();
        checkContractAddresses(poolReserversConfig);
        /* Write data to json */
        writeJsonData(path);

        return contracts;
    }
}
