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
    RewardsVault[] rewardsVaults;
    MintableERC20[] rewardTokens;
    DeployedContracts deployedContracts;
    DeployedMiniPoolContracts miniPoolContracts;

    ConfigAddresses configAddresses;
    address aTokensErc6909Addr;
    address miniPool;



    uint256[] grainTokenIds = [1000, 1001, 1002, 1003];
    uint256[] tokenIds = [1128, 1129, 1130, 1131];

    function fixture_deployRewardTokens(uint256 tokens) public {
        for (uint256 idx = 0; idx < tokens; idx++) {
            rewardTokens.push(new MintableERC20(
                string.concat("Token", uintToString(idx)),
                string.concat("TKN", uintToString(idx)),
                18)
            );

        }
    }

    function fixture_deployMiniPoolRewarder(uint256 tokens) public {
        fixture_deployRewardTokens(tokens);
        rewarder = new Rewarder6909();
        for (uint256 idx = 0; idx < tokens; idx++) {
            RewardsVault rewardsVault = new RewardsVault(
                address(rewarder),
                ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider),
                address(rewardTokens[idx])
            );
            rewardsVault.approveIncentivesController(type(uint256).max);
            rewardsVaults[idx] = rewardsVault;
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
        for(uint256 idx = 0; idx < erc20Tokens.length; idx++) {
            configs[idx] = DistributionTypes.RewardsConfigInput(
                emissionsPerSecond,
                1000 ether,
                distributionEnd,
                address(erc20Tokens[idx]),
                address(rewardTokens[rewardTokenIndex])
            );    
        }

        deployedContracts.rewarder.configureAssets(configs);
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
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
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
        fixture_deployMiniPoolRewarder(3);
        fixture_configureMiniPoolRewarder(
            address(aTokensErc6909[0]), //aTokenMarket
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

    function test_rewarder() public {
        address user1;
        address user2;
        user1 = address(0x123);
        user2 = address(0x456);

        deal(address(erc20Tokens[0]), user1, 100 ether);
        deal(address(erc20Tokens[0]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[0].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[0]), true, 100 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[0].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[0]), true, 100 ether, user2);
        vm.stopPrank();
        
    }




}
