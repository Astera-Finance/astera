// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "lib/forge-std/src/Test.sol";
import {RewardedTokenConfig} from "./DeployDataTypes.sol";
import {DistributionTypes} from "contracts/protocol/libraries/types/DistributionTypes.sol";
import "lib/forge-std/src/console2.sol";
import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IMiniPoolAddressesProvider} from "contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {IMiniPoolConfigurator} from "contracts/interfaces/IMiniPoolConfigurator.sol";
import {
    IAsteraDataProvider2,
    AggregatedMiniPoolReservesData
} from "contracts/interfaces/IAsteraDataProvider2.sol";
import {Rewarder6909} from "contracts/protocol/rewarder/minipool/Rewarder6909.sol";
import {ATokenERC6909} from "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import {RewardsVault} from "contracts/misc/RewardsVault.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {AsteraDataProvider2} from "contracts/misc/AsteraDataProvider2.sol";

contract DeployRewarder is Script, Test {
    using stdJson for string;

    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
    ILendingPoolAddressesProvider lendingPoolAddressesProvider =
        ILendingPoolAddressesProvider(0x9a460e7BD6D5aFCEafbE795e05C48455738fB119);
    IMiniPoolAddressesProvider miniPoolAddressesProvider =
        IMiniPoolAddressesProvider(0x9399aF805e673295610B17615C65b9d0cE1Ed306);
    IMiniPoolConfigurator miniPoolConfigurator =
        IMiniPoolConfigurator(0x41296B58279a81E20aF1c05D32b4f132b72b1B01);
    AsteraDataProvider2 dataProvider =
        AsteraDataProvider2(0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e);

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

        address[] memory rewardTokens =
            abi.decode(deploymentConfig.parseRaw(".rewardTokens"), (address[]));

        vm.startBroadcast();
        miniPoolRewarder = new Rewarder6909();
        vm.stopBroadcast();

        for (uint256 idx = 0; idx < rewardTokens.length; idx++) {
            require(
                contains(rewardTokens, address(rewardedTokenConfigs[idx].rewardToken)),
                "Not allowed reward token"
            );
            vm.startBroadcast();
            rewardsVaults.push(
                new RewardsVault(
                    address(miniPoolRewarder),
                    ILendingPoolAddressesProvider(lendingPoolAddressesProvider),
                    address(rewardTokens[idx])
                )
            );

            /* TODO via multisig !! */
            // rewardsVaults[idx].approveIncentivesController(
            //     rewardedTokenConfigs[idx].incentivesAmount
            // );

            miniPoolRewarder.setRewardsVault(address(rewardsVaults[idx]), rewardTokens[idx]);
            rewardsVaults[idx].transferOwnership(miniPoolAddressesProvider.getMainPoolAdmin());
            vm.stopBroadcast();
        }

        for (uint256 idx = 0; idx < rewardedTokenConfigs.length; idx++) {
            console2.log("rewarded Token: ", rewardedTokenConfigs[idx].rewardedToken);
            console2.log("reward Token: ", rewardedTokenConfigs[idx].rewardToken);
            console2.log(
                "incentivesAmount : %s vs emissionPerSecond * distributionTime %s",
                rewardedTokenConfigs[idx].incentivesAmount,
                rewardedTokenConfigs[idx].distributionTime
                    * rewardedTokenConfigs[idx].emissionPerSecond
            );
            console2.log("emissionPerSecond: ", rewardedTokenConfigs[idx].emissionPerSecond);
            console2.log("distributionTime: ", rewardedTokenConfigs[idx].distributionTime);

            /* Incentive amount shall be within 1% margin */
            require(
                rewardedTokenConfigs[idx].incentivesAmount
                    <= rewardedTokenConfigs[idx].distributionTime
                        * rewardedTokenConfigs[idx].emissionPerSecond * 101 / 100
                    && rewardedTokenConfigs[idx].incentivesAmount
                        >= rewardedTokenConfigs[idx].distributionTime
                            * rewardedTokenConfigs[idx].emissionPerSecond * 99 / 100,
                "Too small incentives amount"
            );
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

        vm.startBroadcast();
        miniPoolRewarder.transferOwnership(miniPoolAddressesProvider.getMainPoolAdmin());
        vm.stopBroadcast();

        console2.log("Deployed Rewarder: ", address(miniPoolRewarder));
        console2.log("Deployed Vaults:");
        for (uint256 i = 0; i < rewardsVaults.length; i++) {
            console2.log(address(rewardsVaults[i]));
        }
        test_basicRewarder6909(miniPoolRewarder); // Enable it to test it in dry run !!
    }

    function contains(address[] memory arr, address addr) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] == addr) return true;
        }
        return false;
    }

    function test_basicRewarder6909(Rewarder6909 miniPoolRewarder) public {
        address user1;
        user1 = makeAddr("user1");
        address aTokensErc6909Addr = miniPoolAddressesProvider.getMiniPoolToAERC6909(2);
        // ILendingPool lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());
        IMiniPool miniPool = IMiniPool(miniPoolAddressesProvider.getMiniPool(2));

        ERC20 weth = ERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f);
        ERC20 usdc = ERC20(0x176211869cA2b568f2A7D4EE941E073a821EE1ff);
        // ERC20 wasWeth = ERC20(0x9A4cA144F38963007cFAC645d77049a1Dd4b209A);
        console2.log("Dealing tokens");
        AggregatedMiniPoolReservesData memory wethAggregatedMiniPoolReservesData = dataProvider
            .getReserveDataForAssetAtMiniPool(
            0x9A4cA144F38963007cFAC645d77049a1Dd4b209A, address(miniPool)
        );

        deal(
            address(weth),
            user1,
            2
                * (
                    wethAggregatedMiniPoolReservesData.availableLiquidity
                        + wethAggregatedMiniPoolReservesData.totalScaledVariableDebt
                )
        );
        console2.log(
            "weth available liquidity: %s vs balance: %s",
            wethAggregatedMiniPoolReservesData.availableLiquidity
                + wethAggregatedMiniPoolReservesData.totalScaledVariableDebt,
            weth.balanceOf(user1)
        );

        AggregatedMiniPoolReservesData memory usdcAggregatedMiniPoolReservesData = dataProvider
            .getReserveDataForAssetAtMiniPool(
            0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944, address(miniPool)
        );
        console2.log(
            "usdc available liquidity: ",
            usdcAggregatedMiniPoolReservesData.availableLiquidity
                + usdcAggregatedMiniPoolReservesData.totalScaledVariableDebt
        );
        deal(
            address(usdc),
            user1,
            2
                * (
                    usdcAggregatedMiniPoolReservesData.availableLiquidity
                        + usdcAggregatedMiniPoolReservesData.totalScaledVariableDebt
                )
        );

        console2.log("Getting rewards vault");
        RewardsVault vault = RewardsVault(
            miniPoolRewarder.getRewardsVault(address(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4))
        );
        console2.log("vault", address(vault));

        /* ACTION AFTER DEPLOYMENT */
        vm.startPrank(miniPoolAddressesProvider.getMainPoolAdmin());
        vault.approveIncentivesController(20000 ether);
        miniPoolConfigurator.setRewarderForReserve(
            0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
            address(miniPoolRewarder),
            IMiniPool(0x65559abECD1227Cc1779F500453Da1f9fcADd928)
        );
        /* Transfer REX33 into the vault */
        ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4).transfer(address(vault), 20000 ether);
        vm.stopPrank();

        // vm.startPrank(user1);
        // weth.approve(address(lendingPool), 100 ether);
        // lendingPool.deposit(address(weth), true, 100 ether, user1);
        // assertGt(wasWeth.balanceOf(user1), 90 ether);
        // vm.stopPrank();

        console2.log("User1 depositing");
        vm.startPrank(user1);
        weth.approve(address(miniPool), weth.balanceOf(user1));
        IMiniPool(miniPool).deposit(
            0x9A4cA144F38963007cFAC645d77049a1Dd4b209A, true, weth.balanceOf(user1) / 2, user1
        );
        IMiniPool(miniPool).borrow(
            0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
            true,
            wethAggregatedMiniPoolReservesData.totalScaledVariableDebt,
            user1
        );

        usdc.approve(address(miniPool), usdc.balanceOf(user1));
        IMiniPool(miniPool).deposit(
            0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944, true, usdc.balanceOf(user1) / 2, user1
        );
        IMiniPool(miniPool).borrow(
            0xAD7b51293DeB2B7dbCef4C5c3379AfaF63ef5944,
            true,
            usdcAggregatedMiniPoolReservesData.totalScaledVariableDebt,
            user1
        );
        vm.stopPrank();

        console2.log("28 days %s vs %s ", 28 days, 2419200);
        vm.warp(block.timestamp + 28 days);
        vm.roll(block.number + 1);

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](1);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1001);

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) = miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("1. user1Rewards[0]", user1Rewards[0]);

        assertApproxEqRel(user1Rewards[0], 2500e18, 1e16, "wrong user1 rewards0 for weth");
        assertEq(
            user1Rewards[0],
            ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4).balanceOf(user1),
            "wrong user1 rewards0 for weth"
        );
        // uint256 tmpRewardsAmount = user1Rewards[0];

        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2001);
        vm.startPrank(user1);
        (, user1Rewards) = miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("2. user1Rewards[0]", user1Rewards[0]);
        assertApproxEqRel(user1Rewards[0], 2500e18, 1e16, "wrong user1 rewards0 for weth");
        assertApproxEqRel(
            ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4).balanceOf(user1),
            5000e18,
            1e16,
            "Wrong user balance for weth"
        );

        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1002);

        vm.startPrank(user1);
        (, user1Rewards) = miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("3. user1Rewards[0]", user1Rewards[0]);

        assertApproxEqRel(user1Rewards[0], 2500e18, 1e16, "wrong user1 rewards0 for usdc");
        assertApproxEqRel(
            ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4).balanceOf(user1),
            7500e18,
            1e16,
            "wrong user1 balance for usdc"
        );

        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2002);
        vm.startPrank(user1);
        (, user1Rewards) = miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("4. user1Rewards[0]", user1Rewards[0]);
        assertApproxEqRel(user1Rewards[0], 2500e18, 1e16, "wrong user1 rewards0 for usdc");
        assertApproxEqRel(
            ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4).balanceOf(user1),
            10000e18,
            1e16,
            "wrong user1 balance for usdc"
        );
    }
}
