// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./DeployDataTypes.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console2.sol";
import {StratsHelper} from "./helpers/StratsHelper.s.sol";

contract AddStrats is Script, StratsHelper, Test {
    using stdJson for string;

    function writeJsonData(string memory path) internal {
        string memory output;
        {
            address[] memory stableAddresses = new address[](
                contracts.stableStrategies.length
            );
            for (
                uint256 idx = 0;
                idx < contracts.stableStrategies.length;
                idx++
            ) {
                stableAddresses[idx] = address(contracts.stableStrategies[idx]);
            }
            vm.serializeAddress(
                "strategies",
                "stableStrategies",
                stableAddresses
            );
        }
        {
            address[] memory volatileAddresses = new address[](
                contracts.volatileStrategies.length
            );
            for (
                uint256 idx = 0;
                idx < contracts.volatileStrategies.length;
                idx++
            ) {
                volatileAddresses[idx] = address(
                    contracts.volatileStrategies[idx]
                );
            }
            vm.serializeAddress(
                "strategies",
                "volatileStrategies",
                volatileAddresses
            );
        }
        {
            address[] memory piAddresses = new address[](
                contracts.piStrategies.length
            );
            string[] memory symbols = new string[](
                contracts.piStrategies.length
            );
            for (uint256 idx = 0; idx < contracts.piStrategies.length; idx++) {
                symbols[idx] = ERC20(contracts.piStrategies[idx]._asset())
                    .symbol();
                piAddresses[idx] = address(contracts.piStrategies[idx]);
            }
            console2.log("Serializing");
            vm.serializeString("strategies", "piStrategiesSymbols", symbols);
            vm.serializeAddress("strategies", "piStrategies", piAddresses);
        }

        {
            console2.log("Stable");
            address[] memory stableAddresses = new address[](
                contracts.miniPoolStableStrategies.length
            );
            for (
                uint256 idx = 0;
                idx < contracts.miniPoolStableStrategies.length;
                idx++
            ) {
                stableAddresses[idx] = address(
                    contracts.miniPoolStableStrategies[idx]
                );
            }
            vm.serializeAddress(
                "strategies",
                "miniPoolStableStrategies",
                stableAddresses
            );
        }
        {
            console2.log("Volatile");
            address[] memory volatileAddresses = new address[](
                contracts.miniPoolVolatileStrategies.length
            );
            for (
                uint256 idx = 0;
                idx < contracts.miniPoolVolatileStrategies.length;
                idx++
            ) {
                volatileAddresses[idx] = address(
                    contracts.miniPoolVolatileStrategies[idx]
                );
            }
            vm.serializeAddress(
                "strategies",
                "miniPoolVolatileStrategies",
                volatileAddresses
            );
        }
        {
            console2.log("PiAddresses");
            address[] memory piAddresses = new address[](
                contracts.miniPoolPiStrategies.length
            );
            string[] memory symbols = new string[](
                contracts.miniPoolPiStrategies.length
            );
            for (
                uint256 idx = 0;
                idx < contracts.miniPoolPiStrategies.length;
                idx++
            ) {
                symbols[idx] = ERC20(
                    contracts.miniPoolPiStrategies[idx]._asset()
                ).symbol();
                piAddresses[idx] = address(contracts.miniPoolPiStrategies[idx]);
            }
            vm.serializeString(
                "strategies",
                "miniPoolPiStrategiesSymbols",
                symbols
            );
            output = vm.serializeAddress(
                "strategies",
                "miniPoolPiStrategies",
                piAddresses
            );
        }

        vm.writeJson(output, path);

        console2.log("PROTOCOL DEPLOYED (check out addresses on %s)", path);
    }

    function addStratsLendingPool(
        string memory outputPath,
        LinearStrategy[] memory volatileStrategies,
        LinearStrategy[] memory stableStrategies,
        PiStrategy[] memory piStrategies,
        Factors memory factors
    ) public {
        /* ****** Lending pool settings */

        console2.log("PATH: ", outputPath);
        string memory config = vm.readFile(outputPath);

        contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
            config.readAddress(".lendingPoolAddressesProvider")
        );

        uint256 initialPoolIndex = piStrategies.length;
        /* Deploy on the mainnet */
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _deployStrategies(
            contracts.lendingPoolAddressesProvider,
            volatileStrategies,
            stableStrategies,
            piStrategies
        );
        vm.stopBroadcast();
        /* Pi pool strats */
        for (uint256 idx = initialPoolIndex; idx < piStrategies.length; idx++) {
            require(
                uint256(contracts.piStrategies[idx].M_FACTOR()) ==
                    factors.m_factor,
                "Wrong M_FACTOR"
            );
            require(
                uint256(contracts.piStrategies[idx].N_FACTOR()) ==
                    factors.n_factor,
                "Wrong N_FACTOR"
            );
        }
    }

    function addStratsMiniPool(
        string memory outputPath,
        uint256 miniPoolId,
        LinearStrategy[] memory miniPoolVolatileStrategies,
        LinearStrategy[] memory miniPoolStableStrategies,
        PiStrategy[] memory miniPoolPiStrategies,
        Factors memory factors
    ) public {
        /* ******* Mini pool settings */

        console2.log("PATH: ", outputPath);
        string memory config = vm.readFile(outputPath);
        if (vm.exists(outputPath)) {
            config = vm.readFile(outputPath);
            {
                address[] memory miniStableStrats = config.readAddressArray(
                    ".miniPoolStableStrategies"
                );
                for (uint8 idx = 0; idx < miniStableStrats.length; idx++) {
                    contracts.miniPoolStableStrategies.push(
                        MiniPoolDefaultReserveInterestRateStrategy(
                            miniStableStrats[idx]
                        )
                    );
                }
            }

            {
                address[] memory miniVolatileStrats = config.readAddressArray(
                    ".miniPoolVolatileStrategies"
                );
                for (uint8 idx = 0; idx < miniVolatileStrats.length; idx++) {
                    contracts.miniPoolVolatileStrategies.push(
                        MiniPoolDefaultReserveInterestRateStrategy(
                            miniVolatileStrats[idx]
                        )
                    );
                }
            }

            {
                address[] memory miniPiStrats = config.readAddressArray(
                    ".miniPoolPiStrategies"
                );
                for (uint8 idx = 0; idx < miniPiStrats.length; idx++) {
                    contracts.miniPoolPiStrategies.push(
                        MiniPoolPiReserveInterestRateStrategy(miniPiStrats[idx])
                    );
                }
            }

            contracts.miniPoolAddressesProvider = MiniPoolAddressesProvider(
                config.readAddress(".miniPoolAddressesProvider")
            );
        }
        uint256 initialMiniPoolIndex = miniPoolPiStrategies.length;
        /* Deploy on the mainnet */

        if (
            vm.exists(outputPath) &&
            (miniPoolPiStrategies.length > 0 ||
                miniPoolVolatileStrategies.length > 0 ||
                miniPoolStableStrategies.length > 0)
        ) {
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _deployMiniPoolStrategies(
                contracts.miniPoolAddressesProvider,
                miniPoolId,
                miniPoolVolatileStrategies,
                miniPoolStableStrategies,
                miniPoolPiStrategies
            );
            vm.stopBroadcast();
            /* Pi miniPool strats */
            for (
                uint256 idx = initialMiniPoolIndex;
                idx < miniPoolPiStrategies.length;
                idx++
            ) {
                require(
                    uint256(contracts.miniPoolPiStrategies[idx].M_FACTOR()) ==
                        factors.m_factor,
                    "Wrong M_FACTOR"
                );
                require(
                    uint256(contracts.miniPoolPiStrategies[idx].N_FACTOR()) ==
                        factors.n_factor,
                    "Wrong N_FACTOR"
                );
            }
        }
    }

    function run() external returns (DeployedContracts memory) {
        console2.log("3_AddStrats");

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/scripts/inputs/3_StratsToAdd.json"
        );
        console2.log("PATH: ", path);
        string memory config = vm.readFile(path);
        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi
            .decode(
                config.parseRaw(".poolAddressesProviderConfig"),
                (PoolAddressesProviderConfig)
            );
        Factors memory factors = abi.decode(
            config.parseRaw(".factors"),
            (Factors)
        );
        uint256 miniPoolId = poolAddressesProviderConfig.poolId;
        LinearStrategy[] memory volatileStrategies = abi.decode(
            config.parseRaw(".volatileStrategies"),
            (LinearStrategy[])
        );
        LinearStrategy[] memory stableStrategies = abi.decode(
            config.parseRaw(".stableStrategies"),
            (LinearStrategy[])
        );
        PiStrategy[] memory piStrategies = abi.decode(
            config.parseRaw(".piStrategies"),
            (PiStrategy[])
        );

        LinearStrategy[] memory miniPoolVolatileStrategies = abi.decode(
            config.parseRaw(".miniPoolVolatileStrategies"),
            (LinearStrategy[])
        );
        LinearStrategy[] memory miniPoolStableStrategies = abi.decode(
            config.parseRaw(".miniPoolStableStrategies"),
            (LinearStrategy[])
        );
        PiStrategy[] memory miniPoolPiStrategies = abi.decode(
            config.parseRaw(".miniPoolPiStrategies"),
            (PiStrategy[])
        );

        if (!vm.envBool("MAINNET")) {
            /* ****** Lending pool settings */

            string memory outputPath = string.concat(
                root,
                "/scripts/outputs/testnet/1_LendingPoolContracts.json"
            );
            addStratsLendingPool(
                outputPath,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                factors
            );
            /* ******* Mini pool settings */

            outputPath = string.concat(
                root,
                "/scripts/outputs/testnet/2_MiniPoolContracts.json"
            );
            addStratsMiniPool(
                outputPath,
                miniPoolId,
                miniPoolVolatileStrategies,
                miniPoolStableStrategies,
                miniPoolPiStrategies,
                factors
            );
            path = string.concat(
                root,
                "/scripts/outputs/testnet/3_DeployedStrategies.json"
            );
        } else if (vm.envBool("MAINNET")) {
            /* ****** Lending pool settings */

            string memory outputPath = string.concat(
                root,
                "/scripts/outputs/mainnet/1_LendingPoolContracts.json"
            );
            addStratsLendingPool(
                outputPath,
                volatileStrategies,
                stableStrategies,
                piStrategies,
                factors
            );

            /* ******* Mini pool settings */

            outputPath = string.concat(
                root,
                "/scripts/outputs/mainnet/2_MiniPoolContracts.json"
            );
            addStratsMiniPool(
                outputPath,
                miniPoolId,
                miniPoolVolatileStrategies,
                miniPoolStableStrategies,
                miniPoolPiStrategies,
                factors
            );

            path = string.concat(
                root,
                "/scripts/outputs/mainnet/3_DeployedStrategies.json"
            );
        }
        writeJsonData(path);
        return contracts;
    }
}
