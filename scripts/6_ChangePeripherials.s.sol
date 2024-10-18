// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {DeployLendingPool} from "./1_DeployLendingPool.s.sol";
import {DataTypes} from "../contracts/protocol/libraries/types/DataTypes.sol";
import {ERC4626Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC4626Mock.sol";

contract ChangePeripherials is Script, DeploymentUtils, Test {
    using stdJson for string;

    function run() external returns (DeployedContracts memory) {
        console.log("6_ChangePeripherials");

        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/6_ChangePeripherials.json");
        console.log("PATH: ", path);
        string memory config = vm.readFile(path);

        NewPeripherial[] memory vault = abi.decode(config.parseRaw(".vault"), (NewPeripherial[]));
        NewPeripherial[] memory treasury =
            abi.decode(config.parseRaw(".treasury"), (NewPeripherial[]));
        NewPeripherial[] memory rewarder =
            abi.decode(config.parseRaw(".rewarder"), (NewPeripherial[]));

        Rehypothecation[] memory rehypothecation =
            abi.decode(config.parseRaw(".rehypothecation"), (Rehypothecation[]));

        require(treasury.length == rehypothecation.length, "Lengths settings must be the same");

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier [ARBITRUM] */
            string memory RPC = vm.envString("ARBITRUM_RPC_URL");
            uint256 FORK_BLOCK = 257827379;
            uint256 arbFork;
            arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

            /* Config fetching */
            DeployLendingPool deployLendingPool = new DeployLendingPool();
            contracts = deployLendingPool.run();

            vm.startPrank(FOUNDRY_DEFAULT);
            for (uint8 idx = 0; idx < vault.length; idx++) {
                vault[idx].newAddress = address(new ERC4626Mock(vault[idx].tokenAddress));
            }

            _changePeripherials(treasury, vault, rewarder);
            _turnOnRehypothecation(rehypothecation);
            vm.stopPrank();
        } else if (vm.envBool("TESTNET")) {
            console.log("Testnet");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            contracts.lendingPool = LendingPool(config.readAddress(".lendingPool"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(config.readAddress(".lendingPoolConfigurator"));

            /* Read all mocks deployed */
            string memory path = string.concat(root, "/scripts/outputs/0_MockedTokens.json");
            console.log("PATH: ", path);
            string memory config = vm.readFile(path);
            address[] memory mockedTokens = config.readAddressArray(".mockedTokens");

            require(
                mockedTokens.length >= vault.length,
                "There are not enough mocked tokens. Deploy mocks.. "
            );
            {
                for (uint8 idx = 0; idx < vault.length; idx++) {
                    for (uint8 i = 0; i < mockedTokens.length; i++) {
                        if (
                            keccak256(abi.encodePacked(ERC20(mockedTokens[i]).symbol()))
                                == keccak256(abi.encodePacked(vault[idx].symbol))
                        ) {
                            console.log(
                                "Assigning %s instead of %s",
                                address(mockedTokens[i]),
                                vault[idx].tokenAddress
                            );
                            vault[idx].tokenAddress = address(mockedTokens[i]);
                            rehypothecation[idx].tokenAddress = address(mockedTokens[i]);
                            treasury[idx].tokenAddress = address(mockedTokens[i]);
                            rewarder[idx].tokenAddress = address(mockedTokens[i]);
                            break;
                        }
                    }
                    require(vault[idx].tokenAddress != address(0), "Mocked token not assigned");
                    require(
                        rehypothecation[idx].tokenAddress != address(0), "Mocked token not assigned"
                    );
                    require(treasury[idx].tokenAddress != address(0), "Mocked token not assigned");
                    require(rewarder[idx].tokenAddress != address(0), "Mocked token not assigned");
                }
            }

            /* Change peripherials */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            for (uint8 idx = 0; idx < vault.length; idx++) {
                vault[idx].newAddress = address(new ERC4626Mock(vault[idx].tokenAddress));
            }
            _changePeripherials(treasury, vault, rewarder);
            _turnOnRehypothecation(rehypothecation);
            vm.stopBroadcast();
        } else if (vm.envBool("MAINNET")) {
            console.log("Mainnet");
            /* *********** Lending pool settings *********** */
            {
                string memory outputPath =
                    string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
                console.log("PATH: ", outputPath);
                config = vm.readFile(outputPath);
            }

            contracts.lendingPool = LendingPool(config.readAddress(".lendingPool"));
            contracts.lendingPoolConfigurator =
                LendingPoolConfigurator(config.readAddress(".lendingPoolConfigurator"));

            /* Change peripherials */
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            _changePeripherials(treasury, vault, rewarder);
            _turnOnRehypothecation(rehypothecation);
            vm.stopBroadcast();
        } else {
            console.log("No deployment type selected in .env");
        }
    }
}
