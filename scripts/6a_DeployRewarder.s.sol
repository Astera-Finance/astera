// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
// import "lib/forge-std/src/Test.sol";
import {RewardedTokenConfig} from "./DeployDataTypes.sol";
import {DistributionTypes} from "contracts/protocol/libraries/types/DistributionTypes.sol";
import "lib/forge-std/src/console2.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPoolConfigurator} from "contracts/interfaces/IMiniPoolConfigurator.sol";
import {IAsteraDataProvider2} from "contracts/interfaces/IAsteraDataProvider2.sol";
import {Rewarder6909} from "contracts/protocol/rewarder/minipool/Rewarder6909.sol";
import {ATokenERC6909} from "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import {RewardsVault} from "contracts/misc/RewardsVault.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";

contract DeployRewarder is Script {
    using stdJson for string;

    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
    ILendingPoolAddressesProvider lendingPoolAddressesProvider =
        ILendingPoolAddressesProvider(0x9a460e7BD6D5aFCEafbE795e05C48455738fB119);
    IMiniPoolAddressesProvider miniPoolAddressesProvider =
        IMiniPoolAddressesProvider(0x9399aF805e673295610B17615C65b9d0cE1Ed306);
    IMiniPoolConfigurator miniPoolConfigurator =
        IMiniPoolConfigurator(0x41296B58279a81E20aF1c05D32b4f132b72b1B01);
    IAsteraDataProvider2 dataProvider =
        IAsteraDataProvider2(0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e);

    Rewarder6909 miniPoolRewarder;
    RewardsVault[] rewardsVaults;

    function run() external {
        // Config fetching
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/inputs/6a_Rewarder.json");
        console2.log("PATH: ", path);
        string memory deploymentConfig = vm.readFile(path);

        RewardedTokenConfig[] memory rewardedTokenConfigs =
            abi.decode(deploymentConfig.parseRaw(".rewardedTokenConfigs"), (RewardedTokenConfig[]));

        vm.startBroadcast();
        miniPoolRewarder = new Rewarder6909();
        vm.stopBroadcast();

        for (uint256 idx = 0; idx < rewardedTokenConfigs.length; idx++) {
            console2.log("rewarded Token: ", rewardedTokenConfigs[idx].rewardedToken);
            console2.log("reward Token: ", rewardedTokenConfigs[idx].rewardToken);
            vm.startBroadcast();
            rewardsVaults.push(
                new RewardsVault(
                    address(miniPoolRewarder),
                    ILendingPoolAddressesProvider(lendingPoolAddressesProvider),
                    address(rewardedTokenConfigs[idx].rewardToken)
                )
            );
            vm.stopBroadcast();
            require(
                rewardedTokenConfigs[idx].incentivesAmount
                    >= rewardedTokenConfigs[idx].distributionTime
                        * rewardedTokenConfigs[idx].emissionPerSecond,
                "Too small incentives amount"
            );
            /* TODO via multisig !! */
            // rewardsVaults[idx].approveIncentivesController(
            //     rewardedTokenConfigs[idx].incentivesAmount
            // );
            vm.startBroadcast();
            miniPoolRewarder.setRewardsVault(
                address(rewardsVaults[idx]), address(rewardedTokenConfigs[idx].rewardToken)
            );
            vm.stopBroadcast();

            DistributionTypes.MiniPoolRewardsConfigInput[] memory configs =
                new DistributionTypes.MiniPoolRewardsConfigInput[](1);
            address aTokensErc6909Addr =
                miniPoolAddressesProvider.getMiniPoolToAERC6909(rewardedTokenConfigs[idx].miniPool);
            DistributionTypes.Asset6909 memory asset =
                DistributionTypes.Asset6909(aTokensErc6909Addr, rewardedTokenConfigs[idx].assetId);
            require(
                type(uint88).max >= rewardedTokenConfigs[idx].emissionPerSecond,
                "Wrong emissionPerSecond value"
            );
            require(
                type(uint32).max >= rewardedTokenConfigs[idx].distributionTime,
                "Wrong distributionTime value"
            );
            configs[0] = DistributionTypes.MiniPoolRewardsConfigInput(
                uint88(rewardedTokenConfigs[idx].emissionPerSecond),
                uint32(block.timestamp + rewardedTokenConfigs[idx].distributionTime),
                asset,
                address(rewardedTokenConfigs[idx].rewardToken)
            );
            console2.log("%s Configuring assetID: %s", idx, rewardedTokenConfigs[idx].assetId);
            vm.startBroadcast();
            miniPoolRewarder.configureAssets(configs);
            vm.stopBroadcast();

            console2.log(
                "underlying from id: %s vs rewardedToken %s",
                ATokenERC6909(aTokensErc6909Addr).getUnderlyingAsset(
                    rewardedTokenConfigs[idx].assetId
                ),
                rewardedTokenConfigs[idx].rewardedToken
            );
            require(
                ATokenERC6909(aTokensErc6909Addr).getUnderlyingAsset(
                    rewardedTokenConfigs[idx].assetId
                ) == rewardedTokenConfigs[idx].rewardedToken,
                "Wrong asset or id"
            );

            {
                (uint256 aTokenId, uint256 debtTokenId,) = ATokenERC6909(aTokensErc6909Addr)
                    .getIdForUnderlying(rewardedTokenConfigs[idx].rewardedToken);

                require(
                    aTokenId == rewardedTokenConfigs[idx].assetId
                        || debtTokenId == rewardedTokenConfigs[idx].assetId,
                    "Wrong id or asset"
                );
            }

            /* TODO via multisig !! */
            // miniPoolConfigurator.setRewarderForReserve(
            //     rewardedTokenConfigs[idx].rewardedToken,
            //     address(miniPoolRewarder),
            //     IMiniPool(rewardedTokenConfigs[idx].miniPool)
            // );
        }

        console2.log("Deployed Rewarder: ", address(miniPoolRewarder));
        console2.log("Deployed Vaults:");
        for (uint256 i = 0; i < rewardsVaults.length; i++) {
            console2.log(address(rewardsVaults[i]));
        }
    }
}
