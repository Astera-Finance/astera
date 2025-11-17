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
import "forge-std/StdUtils.sol";

contract MiniPoolRewarderTest is Common {
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    Rewarder6909 miniPoolRewarder;
    RewardsVault[] miniPoolRewardsVaults;
    MintableERC20[] rewardTokens;

    ConfigAddresses configAddresses;
    address aTokensErc6909Addr;
    uint256 REWARDING_TOKENS_AMOUNT = 3;

    address constant ORACLE = 0xd971e9EC7357e9306c2a138E5c4eAfC04d241C87;
    ILendingPoolAddressesProvider lendingPoolAddressesProvider =
        ILendingPoolAddressesProvider(
            0x9a460e7BD6D5aFCEafbE795e05C48455738fB119
        );
    IMiniPoolAddressesProvider miniPoolAddressesProvider =
        IMiniPoolAddressesProvider(0x9399aF805e673295610B17615C65b9d0cE1Ed306);
    IMiniPoolConfigurator miniPoolConfigurator =
        IMiniPoolConfigurator(0x41296B58279a81E20aF1c05D32b4f132b72b1B01);
    IAsteraDataProvider2 dataProvider =
        IAsteraDataProvider2(0xE4FeC590F1Cf71B36c0A782Aac2E4589aFdaD88e);

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
            vm.label(
                address(rewardTokens[idx]),
                string.concat("RewardToken ", uintToString(idx))
            );
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
                address(rewardsVault),
                string.concat("MiniPoolRewardsVault ", uintToString(idx))
            );
            vm.prank(address(lendingPoolAddressesProvider.getPoolAdmin()));
            rewardsVault.approveIncentivesController(type(uint256).max);
            miniPoolRewardsVaults.push(rewardsVault);
            rewardTokens[idx].mint(600 ether);
            rewardTokens[idx].transfer(address(rewardsVault), 600 ether);
            miniPoolRewarder.setRewardsVault(
                address(rewardsVault),
                address(rewardTokens[idx])
            );
        }
    }

    function fixture_configureMiniPoolRewarder(
        uint256 assetID,
        uint256 rewardTokenIndex,
        uint256 rewardTokenAmount,
        uint88 emissionsPerSecond,
        uint32 distributionEnd
    ) public {
        DistributionTypes.MiniPoolRewardsConfigInput[]
            memory configs = new DistributionTypes.MiniPoolRewardsConfigInput[](
                1
            );
        DistributionTypes.Asset6909 memory asset = DistributionTypes.Asset6909(
            aTokensErc6909Addr,
            assetID
        );
        console2.log("rewardTokenAmount: ", rewardTokenAmount);
        configs[0] = DistributionTypes.MiniPoolRewardsConfigInput(
            emissionsPerSecond,
            distributionEnd,
            asset,
            address(rewardTokens[rewardTokenIndex])
        );
        console2.log("Configuring assetID: ", assetID);
        miniPoolRewarder.configureAssets(configs);

        IMiniPool _miniPool = IMiniPool(
            ATokenERC6909(aTokensErc6909Addr).getMinipoolAddress()
        );
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
            vm.envString("LINEA_RPC_URL"),
            24096464
        );
        assertEq(vm.activeFork(), opFork);

        lendingPool = ILendingPool(
            lendingPoolAddressesProvider.getLendingPool()
        );
        miniPool = IMiniPool(miniPoolAddressesProvider.getMiniPool(2));
        aTokensErc6909Addr = miniPoolAddressesProvider.getMiniPoolToAERC6909(2);

        fixture_deployMiniPoolRewarder();

        console2.log("First config");
        fixture_configureMiniPoolRewarder(
            1002, //assetID USDC
            0, //rewardTokenIndex
            3 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );
        console2.log("Second config");
        fixture_configureMiniPoolRewarder(
            1001, //assetID WETH
            0, //rewardTokenIndex
            3 ether, //rewardTokenAMT
            1 ether, //emissionsPerSecond
            uint32(block.timestamp + 100) //distributionEnd
        );
        console2.log("Third config");
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
        address vault = miniPoolRewarder.getRewardsVault(
            address(rewardTokens[0])
        );
        console2.log("vault", address(vault));

        DistributionTypes.Asset6909[]
            memory assets = new DistributionTypes.Asset6909[](4);
        assets[0] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1001);
        assets[1] = DistributionTypes.Asset6909(aTokensErc6909Addr, 1002);
        assets[2] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2001);
        assets[3] = DistributionTypes.Asset6909(aTokensErc6909Addr, 2002);

        vm.startPrank(user1);
        (, uint256[] memory user1Rewards) = miniPoolRewarder
            .claimAllRewardsToSelf(assets);
        vm.stopPrank();

        console2.log("user1Rewards[0]", user1Rewards[0]);

        vm.startPrank(user2);
        (, uint256[] memory user2Rewards) = miniPoolRewarder
            .claimAllRewardsToSelf(assets);
        vm.stopPrank();

        assertGt(user1Rewards[0], 0, "wrong user1 rewards0");
        assertGt(user1Rewards[1], 0, "wrong user1 rewards1");
        assertEq(user2Rewards[0], 0 ether, "wrong user2 rewards");
    }

    function test_setStratLinea() public {
        address addr = 0x7D66a2e916d79c0988D41F1E50a1429074ec53a4;

        // console2.log("Converted balance", convertedBalance);
        vm.startPrank(addr);
        // console2.log("First deposit");
        miniPoolConfigurator.setReserveInterestRateStrategyAddress(
            0xa500000000e482752f032eA387390b6025a2377b,
            0x9F5B9761Ac612aa2d0775807bEcB8AB6DC99a0fd,
            IMiniPool(0x65559abECD1227Cc1779F500453Da1f9fcADd928)
        );

        vm.stopPrank();
    }
}
