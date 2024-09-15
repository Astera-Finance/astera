// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import "contracts/misc/RewardsVault.sol";
import "contracts/rewarder/Rewarder6909.sol";
import "contracts/mocks/tokens/MintableERC20.sol";
import {DistributionTypes} from "contracts/rewarder/libraries/DistributionTypes.sol";


import "forge-std/StdUtils.sol";

contract MiniPoolRewarderTest is Common {
    ERC20[] erc20Tokens;
    Rewarder6909 rewarder;
    RewardsVault[] miniPoolRewardsVaults;
    RewardsVault[] mainPoolRewardsVaults;
    MintableERC20[] rewardTokens;
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
            rewardTokens.push(new MintableERC20(
                string.concat("Token", uintToString(idx)),
                string.concat("TKN", uintToString(idx)),
                18)
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
            vm.label(address(rewardsVault), string.concat("MiniPoolRewardsVault ", uintToString(idx)));
            vm.prank(address(deployedContracts.lendingPoolAddressesProvider.getPoolAdmin()));
            rewardsVault.approveIncentivesController(type(uint256).max);
            miniPoolRewardsVaults.push(rewardsVault);
            vm.prank(address(rewardsVault));
            rewardTokens[idx].mint(1000 ether);
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
        DistributionTypes.MiniPoolRewardsConfigInput[] memory configs = new DistributionTypes.MiniPoolRewardsConfigInput[](1);
        DistributionTypes.asset6909 memory asset = DistributionTypes.asset6909(aTokensErc6909Addr, assetID);
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
        DistributionTypes.RewardsConfigInput[] memory configs = new DistributionTypes.RewardsConfigInput[](erc20Tokens.length);
        for(uint256 idx = 0; idx < aTokens.length; idx++) {
            configs[idx] = DistributionTypes.RewardsConfigInput(
                emissionsPerSecond,
                1000 ether,
                distributionEnd,
                address(aTokens[idx]),
                address(rewardTokens[rewardTokenIndex])
            );    
        }
        

        for (uint256 idx = 0; idx < rewardTokens.length; idx++) {
            RewardsVault rewardsVault = new RewardsVault(
                address(deployedContracts.rewarder),
                ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider),
                address(rewardTokens[idx])
            );
            vm.label(address(rewardsVault), string.concat("MainPoolRewardsVault ", uintToString(idx)));
            vm.prank(address(deployedContracts.lendingPoolAddressesProvider.getPoolAdmin()));
            rewardsVault.approveIncentivesController(type(uint256).max);
            mainPoolRewardsVaults.push(rewardsVault);
            vm.prank(address(rewardsVault));
            rewardTokens[idx].mint(1000 ether);
            deployedContracts.rewarder.setRewardsVault(address(rewardsVault), address(rewardTokens[idx]));
        }

        deployedContracts.rewarder.configureAssets(configs);
        for(uint256 idx = 0; idx < variableDebtTokens.length; idx++) {
            configs[idx] = DistributionTypes.RewardsConfigInput(
                emissionsPerSecond,
                1000 ether,
                distributionEnd,
                address(variableDebtTokens[idx]),
                address(rewardTokens[rewardTokenIndex])
            );    
        }

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
                reserves[idx] = address(aTokens[idx - tokens.length]);
            }
        }

        miniPool = fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts);
        vm.label(miniPool, "MiniPool");

        aTokensErc6909Addr =
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool);
        fixture_deployMiniPoolRewarder();
        fixture_configureMiniPoolRewarder(
            address(aTokensErc6909Addr), //aTokenMarket
            1001, //assetID
            0, //rewardTokenIndex
            100 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );
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
        aTokens[2].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(address(aTokens[2]), true, 100 ether, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(aTokens[2]);

        address vault = deployedContracts.rewarder.getRewardsVault(address(rewardTokens[0]));
        console.log("vault", address(vault));

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) = deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        console.log("user1Rewards[0]", user1Rewards[0]);

        vm.startPrank(user2);
        (, uint256[] memory user2Rewards) = deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        assertEq(user1Rewards[0], 0 ether);
        assertEq(user2Rewards[0], 50 ether);

        uint256 miniPoolForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(aTokenAddresses, aTokensErc6909Addr, address(rewardTokens[0]));
        console.log("miniPoolForwardedRewards", miniPoolForwardedRewards);
        assertEq(miniPoolForwardedRewards, 50 ether);
   
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
        IMiniPool(miniPool).deposit(address(erc20Tokens[1]), true, 5e9, user3);
        vm.stopPrank();

        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin()));
        IFlowLimiter(miniPoolContracts.miniPoolAddressesProvider.getFlowLimiter()).setFlowLimit(address(aTokens[2]), miniPool, 100 ether);
    
        vm.prank(user3);
        IMiniPool(miniPool).borrow(address(aTokens[2]), true, 50 ether, user3);
        /*vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);



        address[] memory aTokenAddresses = new address[](2);
        aTokenAddresses[0] = address(aTokens[2]);
        aTokenAddresses[1] = address(variableDebtTokens[2]);

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) = deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        console.log("user1Rewards[0]", user1Rewards[0]);

        vm.startPrank(user2);
        (, uint256[] memory user2Rewards) = deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();

        assertEq(user1Rewards[0], 50 ether);
        assertEq(user2Rewards[0], 50 ether);

        uint256 aToken6909ForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(aTokenAddresses, aTokensErc6909Addr, address(rewardTokens[0]));
        console.log("aToken6909ForwardedRewards", aToken6909ForwardedRewards);
        //assertEq(aToken6909ForwardedRewards, 50 ether);
        uint256 miniPoolForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(aTokenAddresses, miniPool, address(rewardTokens[0]));
        console.log("miniPoolForwardedRewards", miniPoolForwardedRewards);
        //assertEq(miniPoolForwardedRewards, 0 ether);*/
    }




}
