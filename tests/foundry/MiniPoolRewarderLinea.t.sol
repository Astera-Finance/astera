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
import {MiniPoolUserReserveData} from "../../contracts/interfaces/IAsteraDataProvider.sol";
import {IAsteraDataProvider2} from "../../contracts/interfaces/IAsteraDataProvider2.sol";
import {AToken} from "../../contracts/protocol/tokenization/ERC20/AToken.sol";
import {AsteraDataProvider2} from "contracts/misc/AsteraDataProvider2.sol";
import {
    IAsteraDataProvider2,
    AggregatedMiniPoolReservesData
} from "contracts/interfaces/IAsteraDataProvider2.sol";
import "forge-std/StdUtils.sol";

import {
    IncentiveDataProvider,
    AggregatedReserveIncentiveData,
    RewardInfo,
    UserReserveIncentiveData,
    UserRewardInfo
} from "contracts/misc/IncentiveDataProvider.sol";
import {IncentiveDataProvider, RewardInfo} from "contracts/misc/IncentiveDataProvider.sol";

contract MiniPoolRewarderTest is Common {
    using WadRayMath for uint256;

    Rewarder6909 miniPoolRewarder;
    RewardsVault[] miniPoolRewardsVaults;
    MintableERC20[] rewardTokens;

    address aTokensErc6909Addr;
    uint256 REWARDING_TOKENS_AMOUNT = 3;

    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
    ILendingPoolAddressesProvider constant lendingPoolAddressesProvider =
        ILendingPoolAddressesProvider(0x9a460e7BD6D5aFCEafbE795e05C48455738fB119);
    IMiniPoolAddressesProvider constant miniPoolAddressesProvider =
        IMiniPoolAddressesProvider(0x9399aF805e673295610B17615C65b9d0cE1Ed306);
    IMiniPoolConfigurator constant miniPoolConfigurator =
        IMiniPoolConfigurator(0x41296B58279a81E20aF1c05D32b4f132b72b1B01);
    IAsteraDataProvider2 constant dataProvider =
        IAsteraDataProvider2(0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e);

    IncentiveDataProvider incentiveDataProvider;

    ILendingPool lendingPool;
    IMiniPool miniPool;

    function fixture_deployRewardTokens() public {
        for (uint256 idx = 0; idx < REWARDING_TOKENS_AMOUNT; idx++) {
            console2.log("Deploying reward token ", idx);
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
                ILendingPoolAddressesProvider(lendingPoolAddressesProvider),
                address(rewardTokens[idx])
            );
            vm.label(
                address(rewardsVault), string.concat("MiniPoolRewardsVault ", uintToString(idx))
            );
            vm.prank(address(lendingPoolAddressesProvider.getPoolAdmin()));
            rewardsVault.approveIncentivesController(type(uint256).max);
            miniPoolRewardsVaults.push(rewardsVault);
            rewardTokens[idx].mint(600 ether);
            rewardTokens[idx].transfer(address(rewardsVault), 600 ether);
            miniPoolRewarder.setRewardsVault(address(rewardsVault), address(rewardTokens[idx]));
        }
    }

    function fixture_configureMiniPoolRewarder(
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
        console2.log("rewardTokenAmount: ", rewardTokenAmount);
        configs[0] = DistributionTypes.MiniPoolRewardsConfigInput(
            emissionsPerSecond, distributionEnd, asset, address(rewardTokens[rewardTokenIndex])
        );
        console2.log("Configuring assetID: ", assetID);
        miniPoolRewarder.configureAssets(configs);

        IMiniPool _miniPool = IMiniPool(ATokenERC6909(aTokensErc6909Addr).getMinipoolAddress());
        vm.startPrank(miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolConfigurator.setRewarderForReserve(
            ATokenERC6909(aTokensErc6909Addr).getUnderlyingAsset(assetID),
            address(miniPoolRewarder),
            _miniPool
        );
        // miniPoolConfigurator.setMinDebtThreshold(0, IMiniPool(miniPool));
        vm.stopPrank();
    }

    function setUp() public {
        // LINEA setup
        uint256 opFork = vm.createSelectFork(
            "https://linea-mainnet.infura.io/v3/f47a8617e11b481fbf52c08d4e9ecf0d", 24242959
        );
        assertEq(vm.activeFork(), opFork);

        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());
        miniPool = IMiniPool(miniPoolAddressesProvider.getMiniPool(2));
        aTokensErc6909Addr = miniPoolAddressesProvider.getMiniPoolToAERC6909(2);

        incentiveDataProvider = new IncentiveDataProvider(address(miniPoolAddressesProvider));

        fixture_deployMiniPoolRewarder();

        fixture_configureMiniPoolRewarder(
            1002, //assetID USDC
            0, //rewardTokenIndex
            3 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );
        fixture_configureMiniPoolRewarder(
            1001, //assetID WETH
            0, //rewardTokenIndex
            3 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );
        fixture_configureMiniPoolRewarder(
            1001, //assetID WETH
            1, //rewardTokenIndex
            3 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );

        fixture_configureMiniPoolRewarder(
            2002, //assetID USDC
            1, //rewardTokenIndex
            3 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );

        fixture_configureMiniPoolRewarder(
            2001, //assetID WETH
            1, //rewardTokenIndex
            3 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );

        fixture_configureMiniPoolRewarder(
            2128, //assetID debt asUSD
            0, //rewardTokenIndex
            3 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );
    }

    function test_reconfigurationOnExistingMiniPool() public {
        Rewarder6909 existingMiniPoolRewarder =
            Rewarder6909(0xbE11D710E0f74aE301e73cBd16e7C4150bc81656);
        AsteraDataProvider2 existingDataProvider =
            AsteraDataProvider2(0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e);
        DistributionTypes.Asset6909[] memory allAssets = new DistributionTypes.Asset6909[](4);
        allAssets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1001);
        allAssets[1] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1002);
        allAssets[2] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2001);
        allAssets[3] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2002);
        uint256 rewards = existingMiniPoolRewarder.getUserRewardsBalance(
            allAssets,
            0xF1D6ab29d12cF2bee25A195579F544BFcC3dD78f,
            0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4
        );
        console.log("Rewards: ", rewards);
        // (
        //     uint256 index,
        //     uint256 emissionPerSecond,
        //     uint256 lastUpdateTimestamp,
        //     uint256 distributionEnd
        // ) = existingMiniPoolRewarder.getRewardsData(
        //     aTokensErc6909Addr, 1001, 0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4
        // );
        // console2.log("index: %s, emissionPerSecond: %s,", index, emissionPerSecond);
        // console2.log(
        //     " lastUpdateTimestamp: %s, distributionEnd %s", lastUpdateTimestamp, distributionEnd
        // );

        address user1;
        user1 = makeAddr("user1");
        // address aTokensErc6909Addr = miniPoolAddressesProvider.getMiniPoolToAERC6909(2);
        // ILendingPool lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());
        IMiniPool rex33MiniPool = IMiniPool(miniPoolAddressesProvider.getMiniPool(2));

        ERC20 weth = ERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f);
        // ERC20 wasWeth = ERC20(0x9A4cA144F38963007cFAC645d77049a1Dd4b209A);
        console2.log("Dealing tokens");
        AggregatedMiniPoolReservesData memory wethAggregatedMiniPoolReservesData =
        existingDataProvider.getReserveDataForAssetAtMiniPool(
            0x9A4cA144F38963007cFAC645d77049a1Dd4b209A, address(rex33MiniPool)
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

        console2.log("Getting rewards vault");
        RewardsVault vault = RewardsVault(
            existingMiniPoolRewarder.getRewardsVault(
                address(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4)
            )
        );
        // console2.log("vault", address(vault));

        // vm.startPrank(user1);
        // weth.approve(address(lendingPool), 100 ether);
        // lendingPool.deposit(address(weth), true, 100 ether, user1);
        // assertGt(wasWeth.balanceOf(user1), 90 ether);
        // vm.stopPrank();

        console2.log("User1 depositing");
        vm.startPrank(user1);
        weth.approve(address(rex33MiniPool), weth.balanceOf(user1));
        IMiniPool(rex33MiniPool).deposit(
            0x9A4cA144F38963007cFAC645d77049a1Dd4b209A, true, weth.balanceOf(user1) / 2, user1
        );
        IMiniPool(rex33MiniPool).borrow(
            0x9A4cA144F38963007cFAC645d77049a1Dd4b209A,
            true,
            wethAggregatedMiniPoolReservesData.totalScaledVariableDebt,
            user1
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
        vm.roll(block.number + 1);

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](1);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1001);

        console2.log("1. User claims");
        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) = existingMiniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("1. user1Rewards[0]", user1Rewards[0]);

        assertApproxEqRel(user1Rewards[0], 864000, 15e16, "wrong user1 rewards0 for weth");
        assertEq(
            user1Rewards[0],
            ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4).balanceOf(user1),
            "wrong user1 rewards0 for weth"
        );
        uint256 previousUserRewards = user1Rewards[0];

        DistributionTypes.MiniPoolRewardsConfigInput[] memory configs =
            new DistributionTypes.MiniPoolRewardsConfigInput[](1);
        configs[0] = DistributionTypes.MiniPoolRewardsConfigInput(
            uint88(1e17),
            uint32(block.timestamp + 2 days),
            assets[0],
            address(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4)
        );
        vm.startPrank(miniPoolAddressesProvider.getMainPoolAdmin());
        vault.approveIncentivesController(2 days * 1e17);
        ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4).transfer(address(vault), 2 days * 1e17);
        existingMiniPoolRewarder.configureAssets(configs);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
        vm.roll(block.number + 1);

        console2.log("2. User claims");
        vm.startPrank(user1);
        (, user1Rewards) = existingMiniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("1. user1Rewards[0]", user1Rewards[0]);

        assertApproxEqRel(user1Rewards[0], 1 days * 1e17, 5e16, "wrong user1 rewards0 for weth");
        assertEq(
            user1Rewards[0] + previousUserRewards,
            ERC20(0xe4eEB461Ad1e4ef8b8EF71a33694CCD84Af051C4).balanceOf(user1),
            "wrong user1 rewards0 for weth"
        );
    }

    function test_basicRewarder6909() public {
        address user1;
        address user2;
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        ERC20 weth = ERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f);
        ERC20 wasWeth = ERC20(0x9A4cA144F38963007cFAC645d77049a1Dd4b209A);
        console2.log("Dealing tokens");
        deal(address(weth), user1, 100 ether);
        deal(address(weth), user2, 100 ether);

        vm.startPrank(user1);
        weth.approve(address(lendingPool), 100 ether);
        lendingPool.deposit(address(weth), true, 100 ether, user1);
        assertGt(wasWeth.balanceOf(user1), 90 ether);
        vm.stopPrank();

        console2.log("User2 depositing");
        vm.startPrank(user2);
        weth.approve(address(lendingPool), 100 ether);
        lendingPool.deposit(address(weth), true, 100 ether, user2);
        vm.stopPrank();

        console2.log("User1 depositing");
        vm.startPrank(user1);
        wasWeth.approve(address(miniPool), 90 ether);
        IMiniPool(miniPool).deposit(address(wasWeth), false, 90 ether, user1);
        IMiniPool(miniPool).borrow(address(wasWeth), false, 50 ether, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        console2.log("Getting rewards vault");
        address vault = miniPoolRewarder.getRewardsVault(address(rewardTokens[0]));
        console2.log("vault", address(vault));

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](4);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1001);
        assets[1] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1002);
        assets[2] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2001);
        assets[3] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2002);

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) = miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("user1Rewards[0]", user1Rewards[0]);

        vm.startPrank(user2);
        (, uint256[] memory user2Rewards) = miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        assertGt(user1Rewards[0], 0, "wrong user1 rewards0");
        assertGt(user1Rewards[1], 0, "wrong user1 rewards1");
        assertEq(user2Rewards[0], 0 ether, "wrong user2 rewards");
    }

    function test_basicRewarder6909_1() public {
        address user1 = makeAddr("user1");

        ERC20 asUsd = ERC20(0xa500000000e482752f032eA387390b6025a2377b);
        console2.log("Dealing tokens");
        {
            AsteraDataProvider2 existingDataProvider =
                AsteraDataProvider2(0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e);
            AggregatedMiniPoolReservesData memory asUsdAggregatedMiniPoolReservesData =
            existingDataProvider.getReserveDataForAssetAtMiniPool(address(asUsd), address(miniPool));

            uint256 amountToDeposit = asUsdAggregatedMiniPoolReservesData.availableLiquidity
                + asUsdAggregatedMiniPoolReservesData.totalScaledVariableDebt;
            deal(address(asUsd), user1, 2 * amountToDeposit);

            console2.log("User1 depositing", amountToDeposit);
            vm.startPrank(user1);
            asUsd.approve(address(miniPool), amountToDeposit);
            IMiniPool(miniPool).deposit(address(asUsd), false, amountToDeposit, user1);
            console2.log(
                "User1 borrowing", asUsdAggregatedMiniPoolReservesData.totalScaledVariableDebt
            );
            IMiniPool(miniPool).borrow(
                address(asUsd),
                false,
                asUsdAggregatedMiniPoolReservesData.totalScaledVariableDebt,
                user1
            );
            vm.stopPrank();
        }
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 1);

        DistributionTypes.Asset6909[] memory assets = new DistributionTypes.Asset6909[](1);
        // assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1001);
        // assets[1] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1002);
        // assets[2] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2001);
        // assets[3] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2002);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2128);

        console2.log(
            "1. Get user unclaimed rewards: ",
            miniPoolRewarder.getUserUnclaimedRewardsFromStorage(user1, address(rewardTokens[0]))
        );
        console2.log(
            "1. Get user rewards rewards: ",
            miniPoolRewarder.getUserRewardsBalance(assets, user1, address(rewardTokens[0]))
        );

        vm.startPrank(user1);
        IMiniPool(miniPool).borrow(address(asUsd), false, 10, user1);
        vm.stopPrank();

        console2.log(
            "2. Get user unclaimed rewards: ",
            miniPoolRewarder.getUserUnclaimedRewardsFromStorage(user1, address(rewardTokens[0]))
        );
        console2.log(
            "2. Get user rewards rewards: ",
            miniPoolRewarder.getUserRewardsBalance(assets, user1, address(rewardTokens[0]))
        );

        // AggregatedReserveIncentiveData[] memory reserveIncentiveData =
        //     incentiveDataProvider.getReservesIncentivesData();

        // UserReserveIncentiveData[] memory userReserveIncentiveData =
        //     incentiveDataProvider.getUserReservesIncentivesData(user1);

        // logAggregatedReserveIncentiveData(reserveIncentiveData);

        // logUserReserveIncentiveData(userReserveIncentiveData);

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) = miniPoolRewarder.claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("user1Rewards[0]", user1Rewards[0]);

        assertApproxEqRel(user1Rewards[0], 50 ether, 1e16, "wrong user1 rewards0");
        assertEq(user1Rewards[1], 0, "wrong user1 rewards1");
    }

    function logAggregatedReserveIncentiveData(AggregatedReserveIncentiveData[] memory arr)
        internal
        pure
    {
        for (uint256 i = 0; i < arr.length; ++i) {
            AggregatedReserveIncentiveData memory d = arr[i];
            console2.log("  UserReserveIncentiveData i: ", i);
            console2.log("    underlyingAsset:", d.underlyingAsset);
            console2.log("    miniPool:", d.miniPool);
            logIncentiveData("    asIncentiveData", d.asIncentiveData);
            logIncentiveData("    asDebtIncentiveData", d.asDebtIncentiveData);
            console2.log("    erc6909:", d.erc6909);
            console2.log("    asTokenId:", d.asTokenId);
            console2.log("    asDebtTokenId:", d.asDebtTokenId);
            console2.log("    incentiveControllerAddress:", d.incentiveControllerAddress);
        }
    }

    function logIncentiveData(string memory prefix, RewardInfo[] memory rewardsTokenInformation)
        internal
        pure
    {
        for (uint256 j = 0; j < rewardsTokenInformation.length; ++j) {
            logRewardInfo(prefix, rewardsTokenInformation[j], j);
        }
    }

    function logRewardInfo(string memory prefix, RewardInfo memory info, uint256 idx)
        internal
        pure
    {
        console2.log(prefix, "  --RewardInfo idx:", idx);
        console2.log(prefix, "    rewardTokenSymbol:", info.rewardTokenSymbol);
        console2.log(prefix, "    rewardTokenAddress:", info.rewardTokenAddress);
        console2.log(prefix, "    rewardOracleAddress:", info.rewardOracleAddress);
        console2.log(prefix, "    emissionPerSecond:", info.emissionPerSecond);
        console2.log(
            prefix, "    incentivesLastUpdateTimestamp:", info.incentivesLastUpdateTimestamp
        );
        console2.log(prefix, "    tokenIncentivesIndex:", info.tokenIncentivesIndex);
        console2.log(prefix, "    emissionEndTimestamp:", info.emissionEndTimestamp);
        console2.log(prefix, "    rewardPriceFeed:", uint256(info.rewardPriceFeed));
        console2.log(prefix, "    rewardTokenDecimals:", info.rewardTokenDecimals);
        console2.log(prefix, "    precision:", info.precision);
        console2.log(prefix, "    priceFeedDecimals:", info.priceFeedDecimals);
    }

    function logUserReserveIncentiveData(UserReserveIncentiveData[] memory arr) internal pure {
        for (uint256 i = 0; i < arr.length; ++i) {
            UserReserveIncentiveData memory d = arr[i];
            console2.log("  UserReserveIncentiveData i:", i);
            console2.log("    underlyingAsset:", d.underlyingAsset);
            console2.log("    miniPool:", d.miniPool);
            console2.log("    erc6909:", d.erc6909);
            console2.log("    tokenId:", d.asTokenId);
            console2.log("    tokenId:", d.asDebtTokenId);
            console2.log("    incentiveControllerAddress:", d.incentiveControllerAddress);
            logUserIncentiveData("    asTokenIncentivesUserData", d.asTokenIncentivesUserData);
            logUserIncentiveData(
                "    asDebtTokenIncentivesUserData", d.asDebtTokenIncentivesUserData
            );
        }
    }

    function logUserIncentiveData(
        string memory prefix,
        UserRewardInfo[] memory userRewardsInformation
    ) internal pure {
        for (uint256 j = 0; j < userRewardsInformation.length; ++j) {
            logUserRewardInfo(prefix, userRewardsInformation[j], j);
        }
    }

    function logUserRewardInfo(string memory prefix, UserRewardInfo memory info, uint256 idx)
        internal
        pure
    {
        console2.log(prefix, "  --UserRewardInfo idx:", idx);
        console2.log(prefix, "    rewardTokenSymbol:", info.rewardTokenSymbol);
        console2.log(prefix, "    rewardOracleAddress:", info.rewardOracleAddress);
        console2.log(prefix, "    rewardTokenAddress:", info.rewardTokenAddress);
        console2.log(prefix, "    userUnclaimedRewards:", info.userUnclaimedRewards);
        console2.log(prefix, "    tokenIncentivesUserIndex:", info.tokenIncentivesUserIndex);
        console2.log(prefix, "    rewardPriceFeed:", uint256(info.rewardPriceFeed));
        console2.log(prefix, "    priceFeedDecimals:", info.priceFeedDecimals);
        console2.log(prefix, "    rewardTokenDecimals:", info.rewardTokenDecimals);
    }

    function testIncentiveProvider() external view {
        console2.log("incentiveDataProvider deployed at:", address(incentiveDataProvider));

        RewardInfo[] memory rewardInfo =
            incentiveDataProvider.getReservesIncentivesData()[0].asIncentiveData;

        console2.log("Reward symbol:", rewardInfo[0].rewardTokenSymbol);
        console2.log("Reward address:", rewardInfo[0].rewardTokenAddress);
        console2.log("Reward oracle:", rewardInfo[0].rewardOracleAddress);
        console2.log("Reward emissionPerSecond:", rewardInfo[0].emissionPerSecond);
        console2.log(
            "Reward incentivesLastUpdateTimestamp:", rewardInfo[0].incentivesLastUpdateTimestamp
        );
        console2.log("Reward tokenIncentivesIndex:", rewardInfo[0].tokenIncentivesIndex);
        console2.log("Reward emissionEndTimestamp:", rewardInfo[0].emissionEndTimestamp);
        console2.log("Reward rewardPriceFeed:", rewardInfo[0].rewardPriceFeed);
        console2.log("Reward priceFeedDecimals:", rewardInfo[0].priceFeedDecimals);
    }
}
