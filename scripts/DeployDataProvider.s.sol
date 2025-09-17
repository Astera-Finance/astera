//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AsteraDataProvider2} from "contracts/misc/AsteraDataProvider2.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {console2} from "lib/forge-std/src/console2.sol";
import {IncentiveDataProvider} from "contracts/misc/IncentiveDataProvider.sol";

contract DeployDataProvider is Script {
    address public marketReferenceCurrencyAggregator = 0xAADAa473C1bDF7317ec07c915680Af29DeBfdCb5;
    address public networkBaseTokenAggregator = 0x3c6Cd9Cc7c7a4c2Cf5a82734CD249D7D593354dA;
    address public lendingPool = 0x17d8a5305A37fe93E13a28f09c46db5bE24E1B9E;
    address public miniPool = address(0);
    AsteraDataProvider2 public asteraDataProvider;

    address miniPoolAddressesProvider = 0x9399aF805e673295610B17615C65b9d0cE1Ed306;

    function run() external {
        vm.startBroadcast();
        // Deploy WethGateway
        asteraDataProvider =
            new AsteraDataProvider2(networkBaseTokenAggregator, marketReferenceCurrencyAggregator);
        // Set the LendingPool
        if (lendingPool != address(0)) {
            asteraDataProvider.setLendingPoolAddressProvider(lendingPool);
        }
        // Set the MiniPool
        if (miniPool != address(0)) {
            asteraDataProvider.setMiniPoolAddressProvider(miniPool);
        }

        console2.log("AsteraDataProvider2 deployed at:", address(asteraDataProvider));

        IncentiveDataProvider incentiveDataProvider =
            new IncentiveDataProvider(address(miniPoolAddressesProvider));

        console2.log("incentiveDataProvider deployed at:", address(incentiveDataProvider));
        vm.stopBroadcast();
    }
}
