// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import "contracts/misc/RewardsVault.sol";
import "contracts/protocol/rewarder/minipool/Rewarder6909.sol";
import "contracts/mocks/tokens/MintableERC20.sol";
import {DistributionTypes} from "contracts/protocol/libraries/types/DistributionTypes.sol";
import {RewardForwarder} from "contracts/protocol/rewarder/lendingpool/RewardForwarder.sol";
import "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";

import "forge-std/StdUtils.sol";

contract MiniPoolRewarderTest is Common {
    ERC20[] erc20Tokens;
    Rewarder6909 miniPoolRewarder;
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

    uint256[] aTokenIds = [1000, 1001, 1002, 1003];
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
        miniPoolRewarder = new Rewarder6909();
        for (uint256 idx = 0; idx < rewardTokens.length; idx++) {
            RewardsVault rewardsVault = new RewardsVault(
                address(miniPoolRewarder),
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
            rewardTokens[idx].mint(600 ether);
            miniPoolRewarder.setRewardsVault(address(rewardsVault), address(rewardTokens[idx]));
        }
    }

    function fixture_configureMiniPoolRewarder(
        address aTokensErc6909Addr,
        uint256 assetID,
        uint256 rewardTokenIndex,
        uint256 rewardTokenAmount,
        uint88 emissionsPerSecond,
        uint32 distributionEnd
    ) public {
        DistributionTypes.MiniPoolRewardsConfigInput[] memory configs =
            new DistributionTypes.MiniPoolRewardsConfigInput[](1);
        DistributionTypes.Asset6909 memory asset =
            DistributionTypes.Asset6909(aTokensErc6909Addr, assetID);
        console.log("rewardTokenAmount: ", rewardTokenAmount);
        configs[0] = DistributionTypes.MiniPoolRewardsConfigInput(
            emissionsPerSecond, distributionEnd, asset, address(rewardTokens[rewardTokenIndex])
        );
        miniPoolRewarder.configureAssets(configs);

        IMiniPool _miniPool = IMiniPool(ATokenERC6909(aTokensErc6909Addr).getMinipoolAddress());
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setRewarderForReserve(
            ATokenERC6909(aTokensErc6909Addr).getUnderlyingAsset(assetID),
            address(miniPoolRewarder),
            _miniPool
        );
        vm.stopPrank();
    }

    function fixture_configureMainPoolRewarder(
        address rewarder,
        uint256 rewardTokenIndex,
        uint256 rewardTokenAmount,
        uint88 emissionsPerSecond,
        uint32 distributionEnd,
        address miniPoolAddressesProvider
    ) public {
        DistributionTypes.RewardsConfigInput[] memory configs =
            new DistributionTypes.RewardsConfigInput[](erc20Tokens.length);
        for (uint256 idx = 0; idx < commonContracts.aTokens.length; idx++) {
            configs[idx] = DistributionTypes.RewardsConfigInput(
                emissionsPerSecond,
                rewardTokenAmount,
                distributionEnd,
                address(commonContracts.aTokens[idx]),
                address(rewardTokens[rewardTokenIndex])
            );
            rewardedTokens.push(address(commonContracts.aTokens[idx]));
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
            rewardTokens[idx].mint(rewardTokenAmount);
            deployedContracts.rewarder.setRewardsVault(
                address(rewardsVault), address(rewardTokens[idx])
            );
        }

        deployedContracts.rewarder.configureAssets(configs);
        for (uint256 idx = 0; idx < commonContracts.variableDebtTokens.length; idx++) {
            configs[idx] = DistributionTypes.RewardsConfigInput(
                emissionsPerSecond,
                rewardTokenAmount,
                distributionEnd,
                address(commonContracts.variableDebtTokens[idx]),
                address(rewardTokens[rewardTokenIndex])
            );
            rewardedTokens.push(address(commonContracts.variableDebtTokens[idx]));
        }
        deployedContracts.rewarder.setMiniPoolAddressesProvider(miniPoolAddressesProvider);
    }

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.cod3xLendDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(commonContracts.aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000 ether, address(this));
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            miniPoolContracts
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] =
                    address(commonContracts.aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
            console.log("reserves[idx] : ", reserves[idx]);
        }
        configAddresses.cod3xLendDataProvider = address(miniPoolContracts.miniPoolAddressesProvider);
        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts, 0);
        vm.label(miniPool, "MiniPool");
        aTokensErc6909Addr =
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool);
        fixture_deployMiniPoolRewarder();
        for (uint256 idx = 0; idx < aTokenIds.length * 4; idx++) {
            // uint256[] aTokenIds = [1000, 1001, 1002, 1003];
            //uint256[] tokenIds = [1128, 1129, 1130, 1131];
            uint256 assetID;
            if (idx < aTokenIds.length * 2) {
                assetID = aTokenIds[idx % aTokenIds.length];
                if (idx > aTokenIds.length) {
                    assetID += 1000; // debtToken
                }
            } else {
                assetID = tokenIds[idx % tokenIds.length];
                if (idx > aTokenIds.length * 3) {
                    assetID += 1000; // debtToken
                }
            }
            console.log("assetID", assetID);
            fixture_configureMiniPoolRewarder(
                address(aTokensErc6909Addr), //aTokenMarket
                assetID, //assetID
                0, //rewardTokenIndex
                3 ether, //rewardTokenAMT
                1 ether, //emissionsPerSecond
                uint32(block.timestamp + 100) //distributionEnd
            );
            console.log("configured");
        }

        fixture_configureMainPoolRewarder(
            address(deployedContracts.rewarder), // The address of the rewarder contract
            0, // The index of the reward token
            200 ether, // The amount of reward tokens
            1 ether, // The emissions per second of the reward tokens
            uint32(block.timestamp + 100), // The end timestamp for the distribution of rewards
            address(miniPoolContracts.miniPoolAddressesProvider) // The address of the mini pool addresses provider
        );

        // for (uint8 idx = 0; idx < reserves.length; idx++) {
        //     console.log(idx);
        //     (uint256 aTokenID, uint256 debtTokenID, bool isTrancheRet) =
        //         ATokenERC6909(aTokensErc6909Addr).getIdForUnderlying(reserves[idx]);
        //     console.log("getIdForUnderlying[idx] :: ", aTokenID);
        // }
    }

    function test_BasicRewarder() public {
        address user1;
        address user2;
        user1 = address(0x123);
        user2 = address(0x456);

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user1
        );
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user2
        );
        vm.stopPrank();

        vm.startPrank(user1);
        commonContracts.aTokensWrapper[WETH_OFFSET].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, 100 ether, user1
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);

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

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether); //100WETH
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user1
        );
        commonContracts.aTokensWrapper[WETH_OFFSET].approve(miniPool, 100 ether);
        IMiniPool(miniPool).deposit(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, 10 ether, user1
        );
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user2
        );
        vm.stopPrank();

        address user3;
        user3 = address(0x789);
        deal(address(erc20Tokens[WBTC_OFFSET]), user3, 5e9); //5BTC

        vm.startPrank(user3);
        erc20Tokens[WBTC_OFFSET].approve(miniPool, 5e9);
        IMiniPool(miniPool).deposit(address(erc20Tokens[WBTC_OFFSET]), false, 5e9, user3);
        vm.stopPrank();

        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin()));
        miniPoolContracts.miniPoolConfigurator.setFlowLimit(
            address(erc20Tokens[WETH_OFFSET]), miniPool, 100 ether
        );

        vm.prank(user3);
        IMiniPool(miniPool).borrow(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, 50 ether, user3
        );
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        // This is checking WETH rewards for the main pools aTokens and VariableDebtTokens
        address[] memory aTokenAddresses = new address[](2);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);
        aTokenAddresses[1] = address(commonContracts.variableDebtTokens[WETH_OFFSET]);

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
        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](4);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1129); //BTC
        assets[1] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2129); //BTC debt
        assets[2] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1002); //Wrapper WETH
        assets[3] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2002); //Wrapper WETH debt

        uint256 rewardsBalance =
            miniPoolRewarder.getUserRewardsBalance(assets, user3, address(rewardTokens[0]));
        console.log("user3RewardsMiniPool", rewardsBalance);
        assertEq(rewardsBalance, 200 ether); // all btc deposits and weth borrows

        rewardsBalance = miniPoolRewarder.getUserRewardsBalance(
            assets, aTokensErc6909Addr, address(rewardTokens[0])
        );
        console.log("miniPoolForwardedRewardsAToken6909", rewardsBalance);
        assertEq(rewardsBalance, 0 ether);

        rewardsBalance =
            miniPoolRewarder.getUserRewardsBalance(assets, miniPool, address(rewardTokens[0]));
        console.log("miniPoolForwardedRewardsFlow", rewardsBalance);
        assertEq(rewardsBalance, 80 ether);

        rewardsBalance =
            miniPoolRewarder.getUserRewardsBalance(assets, user1, address(rewardTokens[0]));
        console.log("user1RewardsMiniPool", rewardsBalance);
        assertEq(rewardsBalance, 20 ether); // 20% of 100 for 10WETH of 50WETH deposited
    }

    function testRewarderDoesNotPayMiniPoolFlow() public {
        address user1;
        address user2;
        user1 = address(0x123);
        user2 = address(0x456);

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether); //100WETH
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user1
        );
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user2
        );
        vm.stopPrank();

        address user3;
        user3 = address(0x789);
        deal(address(erc20Tokens[WBTC_OFFSET]), user3, 5e9); //5BTC

        vm.startPrank(user3);
        erc20Tokens[WBTC_OFFSET].approve(miniPool, 5e9);
        IMiniPool(miniPool).deposit(address(erc20Tokens[WBTC_OFFSET]), false, 5e9, user3);
        vm.stopPrank();

        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin()));
        miniPoolContracts.miniPoolConfigurator.setFlowLimit(
            address(erc20Tokens[WETH_OFFSET]), miniPool, 100 ether
        );

        vm.prank(user3);
        IMiniPool(miniPool).borrow(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, 50 ether, user3
        );
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        // This is checking WETH rewards for the main pools aTokens and VariableDebtTokens
        address[] memory aTokenAddresses = new address[](2);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);
        aTokenAddresses[1] = address(commonContracts.variableDebtTokens[WETH_OFFSET]);

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
        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](4);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1129); //BTC
        assets[1] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2129); //BTC debt
        assets[2] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1002); //Wrapper WETH
        assets[3] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2002); //Wrapper WETH debt
        uint256 user3RewardsMiniPool =
            miniPoolRewarder.getUserRewardsBalance(assets, user3, address(rewardTokens[0]));
        console.log("user3RewardsMiniPool", user3RewardsMiniPool);
        assertEq(user3RewardsMiniPool, 200 ether);
        uint256 miniPoolForwardedRewardsAToken6909 = miniPoolRewarder.getUserRewardsBalance(
            assets, aTokensErc6909Addr, address(rewardTokens[0])
        );
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

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user1
        );
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user2
        );
        vm.stopPrank();

        vm.startPrank(user1);
        commonContracts.aTokensWrapper[WETH_OFFSET].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, 100 ether, user1
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);

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
            forwarder.claimRewardsFor(aTokensErc6909Addr, rewardedTokens[WETH_OFFSET]);
        console.log("aToken6909ForwardedClaims[0]", aToken6909ForwardedClaims[0]);
        assertEq(aToken6909ForwardedClaims[0], 50 ether);
        forwarder.forwardRewards(aTokensErc6909Addr, rewardedTokens[WETH_OFFSET], 0);
        assertEq(rewardTokens[0].balanceOf(forwardDestinationA), 50 ether);
    }

    function testClaimingRewards() public {
        address villain = makeAddr("villain");
        for (uint256 idx = 0; idx < rewardTokens.length; idx++) {
            address rewardsVault =
                deployedContracts.rewarder.getRewardsVault(address(rewardTokens[idx]));
            console.log(rewardsVault);
        }
        // vm.label(forwardDestinationA, "ForwardDestinationA");
        // address forwardDestinationB = address(0xabcdef123);
        // vm.label(forwardDestinationB, "ForwardDestinationB");
        // RewardForwarder forwarder = new RewardForwarder(address(deployedContracts.rewarder));
        // deployedContracts.rewarder.setRewardForwarder(address(forwarder));
        // forwarder.setRewardTokens();
        // forwarder.setRewardedTokens(rewardedTokens);
        // forwarder.setForwarder(aTokensErc6909Addr, 0, forwardDestinationA);
        // forwarder.setForwarder(miniPool, 0, forwardDestinationB);
        // forwarder.registerClaimee(aTokensErc6909Addr);
        // forwarder.registerClaimee(miniPool);
        // console.log("forwarder", address(forwarder));
        // console.log("rewarder", address(deployedContracts.rewarder));

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        vm.startPrank(user1);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user1
        );
        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), 100 ether);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, 100 ether, user2
        );
        vm.stopPrank();

        vm.startPrank(user1);
        commonContracts.aTokensWrapper[WETH_OFFSET].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, 100 ether, user1
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);

        address vault = deployedContracts.rewarder.getRewardsVault(address(rewardTokens[0]));
        console.log("vault", address(vault));

        vm.startPrank(villain);
        uint256 retVal = deployedContracts.rewarder.claimRewardsToSelf(
            aTokenAddresses, 1 ether, address(rewardTokens[0])
        );
        assertEq(retVal, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        retVal = deployedContracts.rewarder.claimRewards(
            aTokenAddresses, 1 ether, user2, address(rewardTokens[0])
        );

        assertEq(retVal, 1 ether);
        assertEq(ERC20(rewardTokens[0]).balanceOf(user2), 1 ether);

        (, uint256[] memory user2Rewards) =
            deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        assertEq(ERC20(rewardTokens[0]).balanceOf(user2), 50 ether);

        vm.stopPrank();

        // console.log("user1Rewards[0]", user1Rewards[0]);

        // vm.startPrank(user2);
        // (, uint256[] memory user2Rewards) =
        //     deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        // vm.stopPrank();

        // assertEq(user1Rewards[0], 0 ether);

        // uint256 aToken6909ForwardedRewards = deployedContracts.rewarder.getUserRewardsBalance(
        //     aTokenAddresses, aTokensErc6909Addr, address(rewardTokens[0])
        // );
        // console.log("miniPoolForwardedRewards", aToken6909ForwardedRewards);
        // assertEq(aToken6909ForwardedRewards, 50 ether);
        // uint256[] memory aToken6909ForwardedClaims =
        //     forwarder.claimRewardsFor(aTokensErc6909Addr, rewardedTokens[WETH_OFFSET]);
        // console.log("aToken6909ForwardedClaims[0]", aToken6909ForwardedClaims[0]);
        // assertEq(aToken6909ForwardedClaims[0], 50 ether);
        // forwarder.forwardRewards(aTokensErc6909Addr, rewardedTokens[WETH_OFFSET], 0);
        // assertEq(rewardTokens[0].balanceOf(forwardDestinationA), 50 ether);
    }

    function testClaimRewardsOnBehalf() public {
        /**
         * Necessary deposits
         * Move forward in time
         * GetRewardsOnBehalf without setting claimer - revert expected
         * SetClaimer
         * GetRewardsOnBehalf - rewards shall be distributed
         *
         */
        address villain = makeAddr("villain");
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        uint256 amount = 100 * 10 ** erc20Tokens[WETH_OFFSET].decimals();
        vm.startPrank(user1);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, amount, user1
        );

        vm.stopPrank();

        // amount = 100 * 10 ** erc20Tokens[WBTC_OFFSET].decimals();
        // vm.startPrank(user2);
        // erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), amount);
        // deployedContracts.lendingPool.deposit(address(erc20Tokens[WBTC_OFFSET]), true, 100 ether, user2);
        // vm.stopPrank();

        vm.warp(block.timestamp + 50);
        vm.roll(block.number + 1);

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);

        vm.startPrank(villain);
        vm.expectRevert(bytes("CLAIMER_UNAUTHORIZED"));
        deployedContracts.rewarder.claimRewardsOnBehalf(
            aTokenAddresses, 1 ether, user1, villain, address(rewardTokens[0])
        );
        vm.stopPrank();

        vm.prank(deployedContracts.rewarder.owner());
        deployedContracts.rewarder.setClaimer(user1, villain);

        vm.startPrank(villain);
        uint256 retVal = deployedContracts.rewarder.claimRewardsOnBehalf(
            aTokenAddresses, 1 ether, user1, villain, address(rewardTokens[0])
        );

        assertEq(retVal, 1 ether);
        assertEq(ERC20(rewardTokens[0]).balanceOf(villain), 1 ether);
        vm.stopPrank();

        /* --- Mini Pool --- */
        vm.startPrank(user1);
        commonContracts.aTokensWrapper[WETH_OFFSET].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, 100 ether, user1
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 50);
        vm.roll(block.number + 1);

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](1);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1000 + WETH_OFFSET); //Wrapper WETH

        vm.startPrank(villain);
        vm.expectRevert(bytes("CLAIMER_UNAUTHORIZED"));
        miniPoolRewarder.claimRewardsOnBehalf(
            assets, 1 ether, user1, villain, address(rewardTokens[0])
        );
        vm.stopPrank();

        vm.prank(miniPoolRewarder.owner());
        miniPoolRewarder.setClaimer(user1, villain);

        vm.startPrank(villain);
        miniPoolRewarder.claimRewardsOnBehalf(
            assets, 1 ether, user1, villain, address(rewardTokens[0])
        );
        vm.stopPrank();

        assertEq(ERC20(rewardTokens[0]).balanceOf(villain), 2 ether, "Wrong balance");
    }

    function testClaimAllRewardsOnBehalf() public {
        /**
         * Necessary deposits
         * Move forward in time
         * GetRewardsOnBehalf without setting claimer - revert expected
         * SetClaimer
         * GetRewardsOnBehalf - rewards shall be distributed
         *
         */
        address villain = makeAddr("villain");
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        uint256 amount = 100 * 10 ** erc20Tokens[WETH_OFFSET].decimals();
        vm.startPrank(user1);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, amount, user1
        );

        vm.stopPrank();

        vm.startPrank(user2);
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, amount, user2
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 50);
        vm.roll(block.number + 1);

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);

        vm.startPrank(villain);
        vm.expectRevert(bytes("CLAIMER_UNAUTHORIZED"));
        deployedContracts.rewarder.claimAllRewardsOnBehalf(aTokenAddresses, user1, villain);
        vm.stopPrank();

        vm.prank(deployedContracts.rewarder.owner());
        deployedContracts.rewarder.setClaimer(user1, villain);

        vm.startPrank(villain);
        deployedContracts.rewarder.claimAllRewardsOnBehalf(aTokenAddresses, user1, villain);

        // assertEq(
        //     ERC20(rewardTokens[0]).balanceOf(villain),
        //     50 ether,
        //     "Wrong balance of ether after first deposit"
        // );
        vm.stopPrank();

        /* TEST */
        vm.startPrank(user2);
        deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();
        console.log(
            "1. Villain balance %s vs user2 balance %s",
            ERC20(rewardTokens[0]).balanceOf(villain),
            ERC20(rewardTokens[0]).balanceOf(user2)
        );

        /* --- Mini Pool --- */
        vm.startPrank(user1);
        commonContracts.aTokensWrapper[WETH_OFFSET].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, 100 ether, user1
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 50);
        vm.roll(block.number + 1);

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](1);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1000 + WETH_OFFSET); //Wrapper WETH

        vm.startPrank(villain);
        vm.expectRevert(bytes("CLAIMER_UNAUTHORIZED"));
        miniPoolRewarder.claimAllRewardsOnBehalf(assets, user1, villain);
        vm.stopPrank();

        vm.prank(miniPoolRewarder.owner());
        miniPoolRewarder.setClaimer(user1, villain);

        vm.startPrank(villain);
        (address[] memory rewardTokens, uint256[] memory claimedAmounts) =
            miniPoolRewarder.claimAllRewardsOnBehalf(assets, user1, villain);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            console.log("rewardTokens[%s]: %s", rewardTokens[i]);
            console.log("claimedAmounts[%s]: %s", claimedAmounts[i]);
        }
        vm.stopPrank();

        assertEq(
            ERC20(rewardTokens[0]).balanceOf(villain),
            75 ether, // 50 from minipool after 50 secs staking and 25 from main pool for 50 secs staking half of the liquidity
            "Wrong villain balance after second deposit"
        );

        /* TEST */
        vm.startPrank(user2);
        deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        vm.stopPrank();
        console.log(
            "2. Villain balance %s vs user2 balance %s",
            ERC20(rewardTokens[0]).balanceOf(villain),
            ERC20(rewardTokens[0]).balanceOf(user2)
        );

        assertEq(
            ERC20(rewardTokens[0]).balanceOf(user2),
            50 ether, // 50 from main pool for 100 secs staking half of the liquidity
            "Wrong user2 balance after second deposit"
        );
    }

    function testFirstDepositAdvantage() public {
        /**
         *
         *
         *
         */
        console.log("INITIAL BLOCK TIMESTAMP: ", block.timestamp);
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        uint256 amount = 10 * 10 ** erc20Tokens[WETH_OFFSET].decimals();

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](1);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1000 + WETH_OFFSET); //Wrapper WETH

        console.log("Time travel 1");
        vm.warp(block.timestamp + 40);
        vm.roll(block.number + 1);

        vm.startPrank(user1);
        console.log("User1 deposits");
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, amount, user1
        );
        vm.stopPrank();
        console.log("Time travel 2");
        vm.warp(block.timestamp + 40);
        vm.roll(block.number + 1);

        vm.startPrank(user1);
        deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        // miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        assertEq(rewardTokens[0].balanceOf(user1), 40 ether, "1. Wrong amount of reward tokens");

        amount = 90 * 10 ** erc20Tokens[WETH_OFFSET].decimals();
        vm.startPrank(user2);
        console.log("User2 deposits");
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, amount, user2
        );
        vm.stopPrank();

        console.log("Time travel 3");
        vm.warp(block.timestamp + 20);
        vm.roll(block.number + 1);

        vm.startPrank(user1);
        deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        // miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        vm.startPrank(user2);
        deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        // miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();
        console.log(
            "1. User1 balance %s vs user2 balance %s",
            ERC20(rewardTokens[0]).balanceOf(user1),
            ERC20(rewardTokens[0]).balanceOf(user2)
        );

        assertEq(
            rewardTokens[0].balanceOf(user1), 42 ether, "2. Wrong amount of reward tokens (user1)"
        );
        assertEq(
            rewardTokens[0].balanceOf(user2), 18 ether, "2. Wrong amount of reward tokens (user2)"
        );
    }

    function testMiniPoolFirstDepositAdvantage() public {
        /**
         *
         *
         *
         */
        console.log("INITIAL BLOCK TIMESTAMP: ", block.timestamp);
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);
        deal(address(erc20Tokens[WETH_OFFSET]), user2, 100 ether);

        uint256 amount = 10 * 10 ** erc20Tokens[WETH_OFFSET].decimals();

        address[] memory aTokenAddresses = new address[](1);
        aTokenAddresses[0] = address(commonContracts.aTokens[WETH_OFFSET]);

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](1);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1000 + WETH_OFFSET); //Wrapper WETH

        console.log("Time travel 1");
        vm.warp(block.timestamp + 40);
        vm.roll(block.number + 1);

        vm.startPrank(user1);
        console.log("User1 deposits to main pool");
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, amount, user1
        );
        console.log("User1 deposits to mini pool");
        commonContracts.aTokensWrapper[WETH_OFFSET].approve(address(miniPool), amount);
        IMiniPool(miniPool).deposit(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, amount, user1
        );
        vm.stopPrank();

        console.log("Time travel 2");
        vm.warp(block.timestamp + 40);
        vm.roll(block.number + 1);

        vm.startPrank(user1);
        // deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();
        assertEq(rewardTokens[0].balanceOf(user1), 40 ether, "1. Wrong amount of reward tokens");

        amount = 90 * 10 ** erc20Tokens[WETH_OFFSET].decimals();
        vm.startPrank(user2);
        console.log("User2 deposits to main pool");
        erc20Tokens[WETH_OFFSET].approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(
            address(erc20Tokens[WETH_OFFSET]), true, amount, user2
        );
        console.log("User2 deposits to mini pool");
        commonContracts.aTokensWrapper[WETH_OFFSET].approve(address(miniPool), 100 ether);
        IMiniPool(miniPool).deposit(
            address(commonContracts.aTokensWrapper[WETH_OFFSET]), false, amount, user2
        );
        vm.stopPrank();

        console.log("Time travel 3");
        vm.warp(block.timestamp + 20);
        vm.roll(block.number + 1);

        vm.startPrank(user1);
        // deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        vm.startPrank(user2);
        // deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();
        console.log(
            "1. User1 balance %s vs user2 balance %s",
            ERC20(rewardTokens[0]).balanceOf(user1),
            ERC20(rewardTokens[0]).balanceOf(user2)
        );

        assertEq(
            rewardTokens[0].balanceOf(user1), 42 ether, "2. Wrong amount of reward tokens (user1)"
        );
        assertEq(
            rewardTokens[0].balanceOf(user2), 18 ether, "2. Wrong amount of reward tokens (user2)"
        );
    }

    function testRewardsFromFlowLimitAndWithout() public {
        /**
         * User3 deposits USDC to main pool
         * User3 deposits half of the amount to the mini pool
         * User2 deposits WBTC to main pool
         * User2 deposits WBTC to mini pool
         * User1 deposits WETH to main pool
         * User1 deposits WETH to mini pool
         * User2 borrows USDC
         * Set flow limit for USDC
         * User1 borrows USDC (with flow from main pool)
         * Move forward in time
         * Invariant:
         * Rewards shall be distributed equally regardless of flow limit
         * (use for log and coverage getAllUserRewardsBalance)
         */
        console.log("INITIAL BLOCK TIMESTAMP: ", block.timestamp);
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);
        deal(address(erc20Tokens[WBTC_OFFSET]), user2, 100 ether);
        deal(address(erc20Tokens[USDC_OFFSET]), user3, 1000 ether);

        TokenParamsExtended memory wethParams = TokenParamsExtended({
            token: erc20Tokens[WETH_OFFSET],
            aToken: commonContracts.aTokens[WETH_OFFSET],
            aTokenWrapper: commonContracts.aTokensWrapper[WETH_OFFSET],
            vault: new MockVaultUnit(erc20Tokens[WETH_OFFSET]),
            price: commonContracts.oracle.getAssetPrice(address(tokens[WETH_OFFSET]))
        });

        TokenParamsExtended memory wbtcParams = TokenParamsExtended({
            token: erc20Tokens[WBTC_OFFSET],
            aToken: commonContracts.aTokens[WBTC_OFFSET],
            aTokenWrapper: commonContracts.aTokensWrapper[WBTC_OFFSET],
            vault: new MockVaultUnit(erc20Tokens[WBTC_OFFSET]),
            price: commonContracts.oracle.getAssetPrice(address(tokens[WBTC_OFFSET]))
        });

        TokenParamsExtended memory usdcParams = TokenParamsExtended({
            token: erc20Tokens[USDC_OFFSET],
            aToken: commonContracts.aTokens[USDC_OFFSET],
            aTokenWrapper: commonContracts.aTokensWrapper[USDC_OFFSET],
            vault: new MockVaultUnit(erc20Tokens[USDC_OFFSET]),
            price: commonContracts.oracle.getAssetPrice(address(tokens[USDC_OFFSET]))
        });

        uint256 wethAmount = (1000 ether / wethParams.price) * 10 ** PRICE_FEED_DECIMALS
            / (10 ** (18 - wethParams.token.decimals()));
        console.log("wethAmount: %s for price: %s", wethAmount, wethParams.price);

        uint256 wbtcAmount = (1000 ether / wbtcParams.price) * 10 ** PRICE_FEED_DECIMALS
            / (10 ** (18 - wbtcParams.token.decimals()));

        console.log("wbtcAmount: %s for price: %s", wbtcAmount, wbtcParams.price);

        uint256 usdcAmount = (1000 ether / usdcParams.price) * 10 ** PRICE_FEED_DECIMALS
            / (10 ** (18 - usdcParams.token.decimals()));

        console.log("usdcAmount: %s for price: %s", usdcAmount, usdcParams.price);

        address[] memory aTokenAddresses = new address[](4);
        aTokenAddresses[0] = address(wethParams.aToken);
        aTokenAddresses[1] = address(wbtcParams.aToken);
        aTokenAddresses[2] = address(usdcParams.aToken);
        aTokenAddresses[3] = address(commonContracts.variableDebtTokens[USDC_OFFSET]);

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](4);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1000 + WETH_OFFSET); //Wrapper WETH
        assets[1] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1000 + WBTC_OFFSET);
        assets[2] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1000 + USDC_OFFSET);
        assets[3] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2000 + USDC_OFFSET);

        vm.startPrank(user3);
        console.log("User3 deposits USDC to main pool");
        erc20Tokens[USDC_OFFSET].approve(address(deployedContracts.lendingPool), usdcAmount);
        deployedContracts.lendingPool.deposit(address(usdcParams.token), true, usdcAmount, user3);
        console.log("User3 deposits half of USDC to mini pool");
        usdcParams.aTokenWrapper.approve(miniPool, usdcAmount);
        IMiniPool(miniPool).deposit(address(usdcParams.aTokenWrapper), false, usdcAmount / 2, user3);
        vm.stopPrank();

        vm.startPrank(user2);
        console.log("User2 deposits WBTC to main pool");
        erc20Tokens[WBTC_OFFSET].approve(address(deployedContracts.lendingPool), wbtcAmount);
        deployedContracts.lendingPool.deposit(address(wbtcParams.token), true, wbtcAmount, user2);
        console.log("User2 deposits WBTC to mini pool");
        wbtcParams.aTokenWrapper.approve(address(miniPool), wbtcAmount);
        IMiniPool(miniPool).deposit(address(wbtcParams.aTokenWrapper), false, wbtcAmount, user2);
        vm.stopPrank();

        vm.startPrank(user1);
        console.log("User1 deposits WETH to main pool");
        wethParams.token.approve(address(deployedContracts.lendingPool), wethAmount);
        deployedContracts.lendingPool.deposit(address(wethParams.token), true, wethAmount, user1);
        console.log("User1 deposits WETH to mini pool");
        wethParams.aTokenWrapper.approve(address(miniPool), wethAmount);
        IMiniPool(miniPool).deposit(address(wethParams.aTokenWrapper), false, wethAmount, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        console.log("User2 borrows USDC from mini pool");
        IMiniPool(miniPool).borrow(address(usdcParams.aTokenWrapper), false, usdcAmount / 3, user2);
        vm.stopPrank();

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setFlowLimit(
            tokens[USDC_OFFSET], miniPool, usdcAmount / 2
        );

        vm.startPrank(user1);
        console.log("User1 borrows USDC from mini pool");
        IMiniPool(miniPool).borrow(address(usdcParams.aTokenWrapper), false, usdcAmount / 3, user1);
        vm.stopPrank();

        console.log("Time travel 1");
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        // console.log("Time travel 2");
        // vm.warp(block.timestamp + 40);
        // vm.roll(block.number + 1);

        DistributionTypes.Asset6909[] memory assets1 = new DistributionTypes.Asset6909[](1);
        assets1[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2000 + USDC_OFFSET);

        vm.startPrank(user1);
        console.log(
            "_1.User1 Debt: ",
            ATokenERC6909(aTokensErc6909Addr).balanceOf(user1, 2000 + USDC_OFFSET)
        );
        console.log("_1.User1 balance: ", rewardTokens[0].balanceOf(user1));
        miniPoolRewarder.claimAllRewardsToSelf(assets1);
        console.log("_2.User1 balance: ", rewardTokens[0].balanceOf(user1));
        vm.stopPrank();

        vm.startPrank(user2);
        console.log(
            "_1.User1 Debt: ",
            ATokenERC6909(aTokensErc6909Addr).balanceOf(user2, 2000 + USDC_OFFSET)
        );
        console.log("_1.User2 balance: ", rewardTokens[0].balanceOf(user2));
        miniPoolRewarder.claimAllRewardsToSelf(assets1);
        console.log("_2.User2 balance: ", rewardTokens[0].balanceOf(user2));
        vm.stopPrank();

        vm.startPrank(user1);
        deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        console.log("1.User1 balance: ", rewardTokens[0].balanceOf(user1));
        miniPoolRewarder.claimAllRewardsToSelf(assets);
        console.log("2.User1 balance: ", rewardTokens[0].balanceOf(user1));
        vm.stopPrank();

        vm.startPrank(user2);
        deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        console.log("1.User2 balance: ", rewardTokens[0].balanceOf(user2));
        miniPoolRewarder.claimAllRewardsToSelf(assets);
        console.log("2.User2 balance: ", rewardTokens[0].balanceOf(user2));
        vm.stopPrank();

        vm.startPrank(user3);
        deployedContracts.rewarder.claimAllRewardsToSelf(aTokenAddresses);
        console.log("1.User3 balance: ", rewardTokens[0].balanceOf(user3));
        miniPoolRewarder.claimAllRewardsToSelf(assets);
        console.log("2.User3 balance: ", rewardTokens[0].balanceOf(user3));
        vm.stopPrank();

        // assertLt(rewardTokens[0].balanceOf(user1), 100 ether);
        // assertLt(rewardTokens[0].balanceOf(user2), 100 ether);
        // assertLt(rewardTokens[0].balanceOf(user3), 100 ether);

        assertEq(
            rewardTokens[0].balanceOf(user1),
            rewardTokens[0].balanceOf(user2),
            "1. Users have different amounts of rewards"
        );
    }

    function testClaimingRewardsWhenRewarderIsNotSet() public {
        address user1 = makeAddr("user1");

        TokenParamsExtended memory wethParams = TokenParamsExtended({
            token: erc20Tokens[WETH_OFFSET],
            aToken: commonContracts.aTokens[WETH_OFFSET],
            aTokenWrapper: commonContracts.aTokensWrapper[WETH_OFFSET],
            vault: new MockVaultUnit(erc20Tokens[WETH_OFFSET]),
            price: commonContracts.oracle.getAssetPrice(address(tokens[WETH_OFFSET]))
        });
        uint256 wethAmount = (1000 ether / wethParams.price) * 10 ** PRICE_FEED_DECIMALS
            / (10 ** (18 - wethParams.token.decimals()));
        console.log("wethAmount: %s for price: %s", wethAmount, wethParams.price);

        uint256 balanceBefore = rewardTokens[0].balanceOf(user1);

        deal(address(erc20Tokens[WETH_OFFSET]), user1, 100 ether);

        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setRewarderForReserve(
            address(wethParams.token), address(0), IMiniPool(miniPool)
        );
        vm.stopPrank();

        vm.startPrank(user1);
        console.log("User1 deposits WETH to main pool");
        wethParams.token.approve(address(deployedContracts.lendingPool), wethAmount);
        deployedContracts.lendingPool.deposit(address(wethParams.token), true, wethAmount, user1);
        console.log("User1 deposits WETH to mini pool");
        wethParams.aTokenWrapper.approve(address(miniPool), wethAmount);
        IMiniPool(miniPool).deposit(address(wethParams.aTokenWrapper), false, wethAmount, user1);
        vm.stopPrank();

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](1);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1000 + WETH_OFFSET);

        console.log("Time travel 1");
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        vm.startPrank(user1);
        miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        assertEq(rewardTokens[0].balanceOf(user1), balanceBefore);
    }
}
