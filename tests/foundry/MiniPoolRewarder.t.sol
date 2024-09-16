// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import "contracts/misc/RewardsVault.sol";
import "contracts/rewarder/minipool/Rewarder6909.sol";
import "contracts/mocks/tokens/MintableERC20.sol";
import {DistributionTypes} from "contracts/rewarder/DistributionTypes.sol";
import {RewardForwarder} from "contracts/rewarder/lendingpool/RewardForwarder.sol";

import "forge-std/StdUtils.sol";

contract MiniPoolRewarderTest is Common {
    ERC20[] erc20Tokens;
    Rewarder6909 rewarder;
    RewardsVault[] miniPoolRewardsVaults;
    RewardsVault[] mainPoolRewardsVaults;
    MintableERC20[] rewardTokens;
    address[] rewardedTokens;
    DeployedContracts deployedContracts;
    DeployedMiniPoolContracts miniPoolContracts;

    ConfigAddresses configAddresses;
    address aTokensErc6909Addr;
    address miniPool;
    uint256 rewardingTokens = 3;

    uint256[] grainTokenIds = [1000, 1001, 1002, 1003];
    uint256[] tokenIds = [1128, 1129, 1130, 1131];

    function fixture_deployRewardTokens() public {
        for (uint256 idx = 0; idx < rewardingTokens; idx++) {
            rewardTokens.push(
                new MintableERC20(
                    string.concat("Token", uintToString(idx)),
                    string.concat("TKN", uintToString(idx)),
                    18
                )
            );
            vm.label(address(rewardTokens[idx]), string.concat("RewardToken ", uintToString(idx)));
        }
    }

    function fixture_deployMiniPoolRewarder() public {
        fixture_deployRewardTokens();
        rewarder = new Rewarder6909();
        for (uint256 idx = 0; idx < rewardTokens.length; idx++) {
            RewardsVault rewardsVault = new RewardsVault(
                address(rewarder),
                ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider),
                address(rewardTokens[idx])
            );
            vm.label(
                address(rewardsVault), string.concat("MiniPoolRewardsVault ", uintToString(idx))
            );
            vm.prank(address(deployedContracts.lendingPoolAddressesProvider.getPoolAdmin()));
            rewardsVault.approveIncentivesController(type(uint256).max);
            miniPoolRewardsVaults.push(rewardsVault);
            vm.prank(address(rewardsVault));
            rewardTokens[idx].mint(2000 ether);
            rewarder.setRewardsVault(address(rewardsVault), address(rewardTokens[idx]));
        }
    }

    function fixture_configureMiniPoolRewarder(
        address aTokensErc6909Addr,
        uint256 assetID,
        uint256 rewardTokenIndex,
        uint256 rewardTokenAMT,
        uint88 emissionsPerSecond,
        uint32 distributionEnd
    ) public {
        DistributionTypes.MiniPoolRewardsConfigInput[] memory configs =
            new DistributionTypes.MiniPoolRewardsConfigInput[](1);
        DistributionTypes.asset6909 memory asset =
            DistributionTypes.asset6909(aTokensErc6909Addr, assetID);
        configs[0] = DistributionTypes.MiniPoolRewardsConfigInput(
            emissionsPerSecond,
            1000 ether,
            distributionEnd,
            asset,
            address(rewardTokens[rewardTokenIndex])
        );
        rewarder.configureAssets(configs);
    }

    function fixture_configureMainPoolRewarder(
        address rewarder,
        uint256 rewardTokenIndex,
        uint256 rewardTokenAMT,
        uint88 emissionsPerSecond,
        uint32 distributionEnd,
        address miniPoolAddressesProvider
    ) public {
        DistributionTypes.RewardsConfigInput[] memory configs =
            new DistributionTypes.RewardsConfigInput[](erc20Tokens.length);
        for (uint256 idx = 0; idx < aTokens.length; idx++) {
            configs[idx] = DistributionTypes.RewardsConfigInput(
                emissionsPerSecond,
                1000 ether,
                distributionEnd,
                address(aTokens[idx]),
                address(rewardTokens[rewardTokenIndex])
            );
            rewardedTokens.push(address(aTokens[idx]));
        }

        for (uint256 idx = 0; idx < rewardTokens.length; idx++) {
            RewardsVault rewardsVault = new RewardsVault(
                address(deployedContracts.rewarder),
                ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider),
                address(rewardTokens[idx])
            );
            vm.label(
                address(rewardsVault), string.concat("MainPoolRewardsVault ", uintToString(idx))
            );
            vm.prank(address(deployedContracts.lendingPoolAddressesProvider.getPoolAdmin()));
            rewardsVault.approveIncentivesController(type(uint256).max);
            mainPoolRewardsVaults.push(rewardsVault);
            vm.prank(address(rewardsVault));
            rewardTokens[idx].mint(1000 ether);
            deployedContracts.rewarder.setRewardsVault(
                address(rewardsVault), address(rewardTokens[idx])
            );
        }

        deployedContracts.rewarder.configureAssets(configs);
        for (uint256 idx = 0; idx < variableDebtTokens.length; idx++) {
            configs[idx] = DistributionTypes.RewardsConfigInput(
                emissionsPerSecond,
                1000 ether,
                distributionEnd,
                address(variableDebtTokens[idx]),
                address(rewardTokens[rewardTokenIndex])
            );
            rewardedTokens.push(address(variableDebtTokens[idx]));
        }
        deployedContracts.rewarder.setMiniPoolAddressesProvider(miniPoolAddressesProvider);
    }

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.protocolDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
        miniPoolContracts = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool)
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        configAddresses.protocolDataProvider = address(miniPoolContracts.miniPoolAddressesProvider);
        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool = fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts);
        vm.label(miniPool, "MiniPool");

        aTokensErc6909Addr =
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool);
        fixture_deployMiniPoolRewarder();
        for (uint256 idx = 0; idx < grainTokenIds.length * 4; idx++) {
            // uint256[] grainTokenIds = [1000, 1001, 1002, 1003];
            //uint256[] tokenIds = [1128, 1129, 1130, 1131];
            uint256 assetID;
            if (idx < grainTokenIds.length * 2) {
                assetID = grainTokenIds[idx % grainTokenIds.length];
                if (idx > grainTokenIds.length) {
                    assetID += 1000;
                }
            } else {
                assetID = tokenIds[idx % tokenIds.length];
                if (idx > grainTokenIds.length * 3) {
                    assetID += 1000;
                }
            }
            console.log("assetID", assetID);
            fixture_configureMiniPoolRewarder(
                address(aTokensErc6909Addr), //aTokenMarket
                assetID, //assetID
                0, //rewardTokenIndex
                100 ether, //rewardTokenAMT
                1 ether, //emissionsPerSecond
                uint32(block.timestamp + 100) //distributionEnd
            );
            console.log("configured");
        }

        fixture_configureMainPoolRewarder(
            address(deployedContracts.rewarder), // The address of the rewarder contract
            0, // The index of the reward token
            100 ether, // The amount of reward tokens
            1 ether, // The emissions per second of the reward tokens
            uint32(block.timestamp + 100), // The end timestamp for the distribution of rewards
            address(miniPoolContracts.miniPoolAddressesProvider) // The address of the mini pool addresses provider
        );
    }

    function test_BasicRewarder() public {
        address user1;
        address user2;
        user1 = address(0x123);
        user2 = address(0x456);

        deal(address(erc20Tokens[2]), user1, 100 ether);
        deal(address(erc20Tokens[2]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 100 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 100 ether, user2);
        vm.stopPrank();

        vm.startPrank(user1);
        aTokensWrapper[2].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(address(aTokensWrapper[2]), 100 ether, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(aTokens[2]);

        address vault = deployedContracts.rewarder.getRewardsVault(address(rewardTokens[0]));
        console.log("vault", address(vault));

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        console.log("user1Rewards[0]", user1Rewards[0]);

        vm.startPrank(user2);
        (, uint256[] memory user2Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        assertEq(user1Rewards[0], 0 ether);
        assertEq(user2Rewards[0], 50 ether);

        uint256 miniPoolForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(
            aTokenAddresses, aTokensErc6909Addr, address(rewardTokens[0])
        );
        console.log("miniPoolForwardedRewards", miniPoolForwardedRewards);
        assertEq(miniPoolForwardedRewards, 50 ether);
    }

    function testRewarderMixedDepositFlow() public {
        address user1;
        address user2;
        user1 = address(0x123);
        user2 = address(0x456);

        deal(address(erc20Tokens[2]), user1, 100 ether); //100WETH
        deal(address(erc20Tokens[2]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 100 ether, user1);
        aTokensWrapper[2].approve(miniPool, 100 ether);
        IMiniPool(miniPool).deposit(address(aTokensWrapper[2]), 10 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 100 ether, user2);
        vm.stopPrank();

        address user3;
        user3 = address(0x789);
        deal(address(erc20Tokens[1]), user3, 5e9); //5BTC

        vm.startPrank(user3);
        erc20Tokens[1].approve(miniPool, 5e9);
        IMiniPool(miniPool).deposit(address(erc20Tokens[1]), 5e9, user3);
        vm.stopPrank();

        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider.owner()));
        miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(
            address(erc20Tokens[2]), miniPool, 100 ether
        );

        vm.prank(user3);
        IMiniPool(miniPool).borrow(address(aTokensWrapper[2]), 50 ether, user3);
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        // This is checking WETH rewards for the main pools aTokens and VariableDebtTokens
        address[] memory aTokenAddresses = new address[](2);
        aTokenAddresses[0] = address(aTokens[2]);
        aTokenAddresses[1] = address(variableDebtTokens[2]);

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        console.log("user1Rewards[0]", user1Rewards[0]);

        vm.startPrank(user2);
        (, uint256[] memory user2Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        assertLe(user1Rewards[0], 40 ether); // 100-10 / 250 +10 * 100
        assertGe(user2Rewards[0], 40 ether); // 100 / 250 +10 * 100

        uint256 aToken6909ForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(
            aTokenAddresses, aTokensErc6909Addr, address(rewardTokens[0])
        );
        console.log("aToken6909ForwardedRewards", aToken6909ForwardedRewards);
        assertEq(aToken6909ForwardedRewards, 0 ether);
        uint256 miniPoolForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(
            aTokenAddresses, miniPool, address(rewardTokens[0])
        );
        console.log("miniPoolForwardedRewards", miniPoolForwardedRewards);
        assertEq(miniPoolForwardedRewards, 0 ether);

        vm.startPrank(user3);
        (, uint256[] memory user3Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        assertGe(user3Rewards[0], 20 ether);

        // This is checking BTC rewards for the miniPool aTokens and VariableDebtTokens
        DistributionTypes.asset6909[] memory assets = new DistributionTypes.asset6909[](4);
        assets[0] = DistributionTypes.asset6909(aTokensErc6909Addr, 1129); //BTC
        assets[1] = DistributionTypes.asset6909(aTokensErc6909Addr, 2129); //BTC debt
        assets[2] = DistributionTypes.asset6909(aTokensErc6909Addr, 1002); //Wrapper WETH
        assets[3] = DistributionTypes.asset6909(aTokensErc6909Addr, 2002); //Wrapper WETH debt

        uint256 rewardsBalance =
            rewarder.getUserRewardsBalance(assets, user3, address(rewardTokens[0]));
        console.log("user3RewardsMiniPool", rewardsBalance);
        assertEq(rewardsBalance, 200 ether); // all btc deposits and weth borrows

        rewardsBalance =
            rewarder.getUserRewardsBalance(assets, aTokensErc6909Addr, address(rewardTokens[0]));
        console.log("miniPoolForwardedRewardsAToken6909", rewardsBalance);
        assertEq(rewardsBalance, 0 ether);

        rewardsBalance = rewarder.getUserRewardsBalance(assets, miniPool, address(rewardTokens[0]));
        console.log("miniPoolForwardedRewardsFlow", rewardsBalance);
        assertEq(rewardsBalance, 80 ether);

        rewardsBalance = rewarder.getUserRewardsBalance(assets, user1, address(rewardTokens[0]));
        console.log("user1RewardsMiniPool", rewardsBalance);
        assertEq(rewardsBalance, 20 ether); // 20% of 100 for 10WETH of 50WETH deposited
    }

    function testRewarderDoesNotPayMiniPoolFlow() public {
        address user1;
        address user2;
        user1 = address(0x123);
        user2 = address(0x456);

        deal(address(erc20Tokens[2]), user1, 100 ether); //100WETH
        deal(address(erc20Tokens[2]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 100 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 100 ether, user2);
        vm.stopPrank();

        address user3;
        user3 = address(0x789);
        deal(address(erc20Tokens[1]), user3, 5e9); //5BTC

        vm.startPrank(user3);
        erc20Tokens[1].approve(miniPool, 5e9);
        IMiniPool(miniPool).deposit(address(erc20Tokens[1]), 5e9, user3);
        vm.stopPrank();

        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider.owner()));
        miniPoolContracts.miniPoolAddressesProvider.setFlowLimit(
            address(erc20Tokens[2]), miniPool, 100 ether
        );

        vm.prank(user3);
        IMiniPool(miniPool).borrow(address(aTokensWrapper[2]), 50 ether, user3);
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        // This is checking WETH rewards for the main pools aTokens and VariableDebtTokens
        address[] memory aTokenAddresses = new address[](2);
        aTokenAddresses[0] = address(aTokens[2]);
        aTokenAddresses[1] = address(variableDebtTokens[2]);

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        console.log("user1Rewards[0]", user1Rewards[0]);

        vm.startPrank(user2);
        (, uint256[] memory user2Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        assertEq(user1Rewards[0], 40 ether); // 100 / 250 * 100
        assertEq(user2Rewards[0], 40 ether);

        uint256 aToken6909ForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(
            aTokenAddresses, aTokensErc6909Addr, address(rewardTokens[0])
        );
        console.log("aToken6909ForwardedRewards", aToken6909ForwardedRewards);
        assertEq(aToken6909ForwardedRewards, 0 ether);
        uint256 miniPoolForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(
            aTokenAddresses, miniPool, address(rewardTokens[0])
        );
        console.log("miniPoolForwardedRewards", miniPoolForwardedRewards);
        assertEq(miniPoolForwardedRewards, 0 ether);

        vm.startPrank(user3);
        (, uint256[] memory user3Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        assertEq(user3Rewards[0], 20 ether);

        // This is checking BTC rewards for the miniPool aTokens and VariableDebtTokens
        DistributionTypes.asset6909[] memory assets = new DistributionTypes.asset6909[](4);
        assets[0] = DistributionTypes.asset6909(aTokensErc6909Addr, 1129); //BTC
        assets[1] = DistributionTypes.asset6909(aTokensErc6909Addr, 2129); //BTC debt
        assets[2] = DistributionTypes.asset6909(aTokensErc6909Addr, 1002); //Wrapper WETH
        assets[3] = DistributionTypes.asset6909(aTokensErc6909Addr, 2002); //Wrapper WETH debt
        uint256 user3RewardsMiniPool =
            rewarder.getUserRewardsBalance(assets, user3, address(rewardTokens[0]));
        console.log("user3RewardsMiniPool", user3RewardsMiniPool);
        assertEq(user3RewardsMiniPool, 200 ether);
        uint256 miniPoolForwardedRewardsAToken6909 =
            rewarder.getUserRewardsBalance(assets, aTokensErc6909Addr, address(rewardTokens[0]));
        console.log("miniPoolForwardedRewardsAToken6909", miniPoolForwardedRewardsAToken6909);
        assertEq(miniPoolForwardedRewardsAToken6909, 0 ether);
    }

    function testRewarderForwarder() public {
        address forwardDestinationA = address(0xabcdef);
        vm.label(forwardDestinationA, "ForwardDestinationA");
        address forwardDestinationB = address(0xabcdef123);
        vm.label(forwardDestinationB, "ForwardDestinationB");
        RewardForwarder forwarder = new RewardForwarder(address(deployedContracts.rewarder));
        deployedContracts.rewarder.setRewardForwarder(address(forwarder));
        forwarder.setRewardTokens();
        forwarder.setRewardedTokens(rewardedTokens);
        forwarder.setForwarder(aTokensErc6909Addr, 0, forwardDestinationA);
        forwarder.setForwarder(miniPool, 0, forwardDestinationB);
        forwarder.registerClaimee(aTokensErc6909Addr);
        forwarder.registerClaimee(miniPool);
        console.log("forwarder", address(forwarder));
        console.log("rewarder", address(deployedContracts.rewarder));

        address user1;
        address user2;
        user1 = address(0x123);
        user2 = address(0x456);

        deal(address(erc20Tokens[2]), user1, 100 ether);
        deal(address(erc20Tokens[2]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 100 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 100 ether, user2);
        vm.stopPrank();

        vm.startPrank(user1);
        aTokensWrapper[2].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(address(aTokensWrapper[2]), 100 ether, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(aTokens[2]);

        address vault = deployedContracts.rewarder.getRewardsVault(address(rewardTokens[0]));
        console.log("vault", address(vault));

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        console.log("user1Rewards[0]", user1Rewards[0]);

        vm.startPrank(user2);
        (, uint256[] memory user2Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        assertEq(user1Rewards[0], 0 ether);
        assertEq(user2Rewards[0], 50 ether);

        uint256 aToken6909ForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(
            aTokenAddresses, aTokensErc6909Addr, address(rewardTokens[0])
        );
        console.log("miniPoolForwardedRewards", aToken6909ForwardedRewards);
        assertEq(aToken6909ForwardedRewards, 50 ether);
        uint256[] memory aToken6909ForwardedClaims =
            forwarder.claimRewardsFor(aTokensErc6909Addr, rewardedTokens[2]);
        console.log("aToken6909ForwardedClaims[0]", aToken6909ForwardedClaims[0]);
        assertEq(aToken6909ForwardedClaims[0], 50 ether);
        forwarder.forwardRewards(aTokensErc6909Addr, rewardedTokens[2], 0);
        assertEq(rewardTokens[0].balanceOf(forwardDestinationA), 50 ether);
    }
}
