// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";

contract DeployMocks is Script, DeploymentUtils, Test {
    using stdJson for string;

    function run() external returns (DeployedContracts memory) {
        // Config fetching
        if (vm.envBool("TESTNET") || vm.envBool("MAINNET")) {
            console.log("Testnet Deployment");
            //deploy to testnet
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/scripts/inputs/0_MockedTokens.json");
            console.log("PATH: ", path);
            string memory config = vm.readFile(path);
            MockedToken[] memory mockedTokensSettings =
                abi.decode(config.parseRaw(".mockedToken"), (MockedToken[]));

            address[] memory mockedTokens;
            {
                string[] memory symbols = new string[](mockedTokensSettings.length);
                uint8[] memory decimals = new uint8[](mockedTokensSettings.length);
                int256[] memory prices = new int256[](mockedTokensSettings.length);

                for (uint8 idx = 0; idx < mockedTokensSettings.length; idx++) {
                    symbols[idx] = mockedTokensSettings[idx].symbol;
                    decimals[idx] = uint8(mockedTokensSettings[idx].decimals);
                    prices[idx] = int256(mockedTokensSettings[idx].prices);
                }

                // Deployment
                console.log("Broadcasting....");
                vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
                (mockedTokens,) = _deployERC20Mocks(symbols, symbols, decimals, prices);
                vm.stopBroadcast();
            }

            /* Write mocked tokens */
            {
                string memory out;
                out = vm.serializeAddress("mockedContracts", "mockedTokens", mockedTokens);

                vm.writeJson(out, "./scripts/outputs/0_MockedTokens.json");
            }
        }
    }
}
