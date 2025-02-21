// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.sol";
import "./helpers/MocksHelper.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console2.sol";

contract DeployMocks is Script, MocksHelper, Test {
    using stdJson for string;

    function run() external returns (DeployedContracts memory) {
        // Config fetching
        console2.log("CHAIN ID: ", block.chainid);

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/0_MockedTokens.json");
        console2.log("PATH: ", path);
        string memory config = vm.readFile(path);
        MockedToken[] memory mockedTokensSettings =
            abi.decode(config.parseRaw(".mockedToken"), (MockedToken[]));

        address[] memory mockedTokens;
        {
            string[] memory symbols = new string[](mockedTokensSettings.length);
            uint8[] memory decimals = new uint8[](mockedTokensSettings.length);

            for (uint8 idx = 0; idx < mockedTokensSettings.length; idx++) {
                symbols[idx] = mockedTokensSettings[idx].symbol;
                decimals[idx] = uint8(mockedTokensSettings[idx].decimals);
            }

            // Deployment
            console2.log("Broadcasting....");
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            mockedTokens = _deployERC20Mocks(symbols, symbols, decimals);
            for (uint8 idx = 0; idx < mockedTokens.length; idx++) {
                MintableERC20(mockedTokens[idx]).mint(100 ether);
            }
            vm.stopBroadcast();
        }

        /* Write mocked tokens */
        {
            string memory out;
            out = vm.serializeAddress("mockedContracts", "mockedTokens", mockedTokens);
            if (!vm.exists(string.concat(root, "/scripts/outputs"))) {
                vm.createDir(string.concat(root, "/scripts/outputs"), false);
            }
            if (!vm.envBool("MAINNET")) {
                if (!vm.exists(string.concat(root, "/scripts/outputs/testnet"))) {
                    vm.createDir(string.concat(root, "/scripts/outputs/testnet"), false);
                }
                vm.writeJson(out, "./scripts/outputs/testnet/0_MockedTokens.json");
            } else {
                if (!vm.exists(string.concat(root, "/scripts/outputs/mainnet"))) {
                    vm.createDir(string.concat(root, "/scripts/outputs/mainnet"), false);
                }
                vm.writeJson(out, "./scripts/outputs/mainnet/0_MockedTokens.json");
            }
        }
    }
}
