// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolFixtures.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";

import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

contract MultiplePools is MiniPoolFixtures {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    address[] miniPools;
    uint256 id;

    function logState(
        TokenParamsExtended memory collateral,
        TokenParamsExtended memory borrowToken,
        uint256 idx
    ) internal view {
        console.log(
            "%s. Balance of USDC in ATOKEN: %s",
            idx,
            collateral.token.balanceOf(address(collateral.aToken))
        );
        console.log(
            "%s. Balance of WBTC in ATOKEN: %s",
            idx,
            borrowToken.token.balanceOf(address(borrowToken.aToken))
        );
        console.log(
            "%s. Balance of USDC in VAULT: %s",
            idx,
            collateral.token.balanceOf(address(collateral.vault))
        );
        console.log(
            "%s. Balance of WBTC in VAULT: %s",
            idx,
            borrowToken.token.balanceOf(address(borrowToken.vault))
        );
        // console.log(
        //     "%s. Balance of aUSDC in AERC6909: %s",
        //     idx,
        //     collateral.aToken.balanceOf(address(collateral.))
        // );
        // console.log(
        //     "%s. Balance of aWBTC in AERC6909: %s",
        //     idx,
        //     borrowToken.aToken.balanceOf(address(borrowToken.aTokenWrapper))
        // );
    }

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();

        configLpAddresses = ConfigAddresses(
            address(deployedContracts.cod3xLendDataProvider),
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            address(aToken),
            configLpAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );
        mockedVaults = fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));

        /* Deploy first mini pool */
        console.log("Deploy first mini pool");
        (miniPoolContracts, id) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            miniPoolContracts
        );
        console.log("1.Id: ", id);
        console.log("1. MiniPoolImpl: ", address(miniPoolContracts.miniPoolImpl));
        /* Deploy second mini pool */
        console.log("Deploy second mini pool");
        (miniPoolContracts, id) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            miniPoolContracts
        );
        console.log("2.Id: ", id);
        /* Deploy third mini pool */
        console.log("Deploy third mini pool");
        (miniPoolContracts, id) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            miniPoolContracts
        );
        console.log("3.Id: ", id);
        console.log("2. MiniPoolImpl: ", address(miniPoolContracts.miniPoolImpl));

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] = address(aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        configLpAddresses.cod3xLendDataProvider =
            address(miniPoolContracts.miniPoolAddressesProvider);
        configLpAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configLpAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        console.log("Configure first mini pool");
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 0);
        miniPools.push(miniPool);
        vm.label(miniPool, "MiniPool1");
        console.log("Configure second mini pool");
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 1);
        miniPools.push(miniPool);
        vm.label(miniPool, "MiniPool2");
        console.log("Configure third mini pool");
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 2);
        miniPools.push(miniPool);
        vm.label(miniPool, "MiniPool3");
    }

    function testBorrowsFromLendingPool() public {
        /**
         * Preconditions:
         * 1. Reserves in all MiniPools must be configured
         * 2. Specified amount of funds must be deposited to the main pool
         * Test Scenario:
         * 1. Admin configures flow limiters for all the pools
         * 2. First mini pool uses max of flow limit to borrow asset
         * 3. Second mini pool uses max of flow limit to borrow asset
         * 4. Third mini pool uses max of flow limit to borrow asset but it exceeds available funds in main pool
         * Invariants:
         * 1. First mini pool borrowing should succeed
         * 2. Second mini pool borrowing should succeed
         * 3. Third mini pool borrowing should revert
         *
         */
    }

    function testConfigurationForMultipleMiniPool() public {
        /**
         * Check if configurations applies only for specified mini pool and other works the same
         */
    }

    struct TestBalances {
        uint256 collateralInAToken;
        uint256 collateralInVault;
        uint256 borrowTokenInAToken;
        uint256 borrowTokenInVault;
    }

    function testFlowBorrowWithRehypo(uint256 amount1, uint256 amount2, uint256 skipDuration)
        public
    {
        /**
         * Use flow borrow on 2 miniPools with rehypo turned on main pool - check if all funds on rehypo will be withdrawn/redeposited
         */
        /* Constants */
        uint8 WBTC_OFFSET = 1;
        uint8 USDC_OFFSET = 0;

        /* Fuzz vectors */
        skipDuration = 300 days; //bound(skipDuration, 0, 300 days);

        TokenParamsExtended memory usdcParams = TokenParamsExtended(
            erc20Tokens[USDC_OFFSET],
            aTokens[USDC_OFFSET],
            aTokensWrapper[USDC_OFFSET],
            mockVaultUnits[USDC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[USDC_OFFSET]))
        );
        TokenParamsExtended memory wbtcParams = TokenParamsExtended(
            erc20Tokens[WBTC_OFFSET],
            aTokens[WBTC_OFFSET],
            aTokensWrapper[WBTC_OFFSET],
            mockVaultUnits[WBTC_OFFSET],
            oracle.getAssetPrice(address(erc20Tokens[WBTC_OFFSET]))
        );
        console.log("\n---------------->>>>>>>>>>> FIRST MINI POOL <<<<<<<<--------------");
        miniPool = miniPools[0];
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        Users memory users;
        users.user1 = makeAddr("user1");
        users.user2 = makeAddr("provider");
        users.user3 = makeAddr("distributor");

        TestBalances memory testBalances;

        amount1 = 2000 * 10 ** usdcParams.token.decimals(); // 2 000 usdc
        amount2 = 2 * 10 ** (wbtcParams.token.decimals() - 2); // 0.02 wbtc (1300)
        // Set flow limiter
        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
        miniPoolContracts.flowLimiter.setFlowLimit(address(wbtcParams.token), miniPool, amount2 / 4);
        console.log(
            "1. Remaining flow limit: ",
            miniPoolContracts.flowLimiter.getFlowLimit(address(wbtcParams.token), miniPool)
                - miniPoolContracts.flowLimiter.currentFlow(address(wbtcParams.token), miniPool)
        );

        console.log("----------------REHYPOTHECATION ON WBTC --------------");
        turnOnRehypothecation(
            deployedContracts.lendingPoolConfigurator,
            address(wbtcParams.aToken),
            address(wbtcParams.vault),
            admin,
            8000, // 80%
            0, // temporarily any amount can be claimed
            200
        );

        console.log("----------------REHYPOTHECATION ON USDC ---------------");
        turnOnRehypothecation(
            deployedContracts.lendingPoolConfigurator,
            address(usdcParams.aToken),
            address(usdcParams.vault),
            admin,
            8000, // 80%
            0, // temporarily any amount can be claimed
            200
        );
        logState(usdcParams, wbtcParams, 1);
        {
            TokenParams memory usdcTokenParams = TokenParams(
                erc20Tokens[USDC_OFFSET],
                aTokensWrapper[USDC_OFFSET],
                oracle.getAssetPrice(address(erc20Tokens[USDC_OFFSET]))
            );
            TokenParams memory wbtcTokenParams = TokenParams(
                erc20Tokens[WBTC_OFFSET],
                aTokensWrapper[WBTC_OFFSET],
                oracle.getAssetPrice(address(erc20Tokens[USDC_OFFSET]))
            );
            console.log("----------------PROVIDER DEPOSITs LIQUIDITY (WBTC)---------------");
            fixture_depositTokensToMainPool(amount2, users.user2, wbtcTokenParams);
            logState(usdcParams, wbtcParams, 2);

            console.log(
                "----------------USER DEPOSITs LIQUIDITY (USDC) TO LENDING POOL---------------"
            );
            /* User deposits tokens to the main lending pool and gets lending pool's aTokens*/
            fixture_depositTokensToMainPool(amount1, users.user1, usdcTokenParams);
            logState(usdcParams, wbtcParams, 3);

            testBalances.collateralInAToken = usdcParams.token.balanceOf(address(usdcParams.aToken));
            testBalances.borrowTokenInAToken =
                wbtcParams.token.balanceOf(address(wbtcParams.aToken));
            testBalances.collateralInVault = usdcParams.token.balanceOf(address(usdcParams.vault));
            testBalances.borrowTokenInVault = wbtcParams.token.balanceOf(address(wbtcParams.vault));

            console.log(
                "----------------USER DEPOSITs LIQUIDITY (aUSDC) TO MINI POOL---------------"
            );
            /* User deposits lending pool's aTokens to the mini pool and
        gets mini pool's aTokens */
            fixture_depositATokensToMiniPool(
                amount1, 1000 + USDC_OFFSET, users.user1, usdcTokenParams, aErc6909Token
            );
            logState(usdcParams, wbtcParams, 4);
        }

        console.log("----------------USER1 BORROWs---------------");
        vm.startPrank(users.user1);
        IMiniPool(miniPool).borrow(
            address(wbtcParams.aTokenWrapper), false, amount2 / 4, users.user1
        );
        vm.stopPrank();
        logState(usdcParams, wbtcParams, 5);
        console.log(
            "%s. Balance of WBTC in MINI POOL: %s", 5, wbtcParams.token.balanceOf(address(miniPool))
        );
        uint256 flowLimit =
            miniPoolContracts.flowLimiter.getFlowLimit(address(wbtcParams.token), miniPool);
        console.log(
            "5. Remaining flow limit: ",
            miniPoolContracts.flowLimiter.getFlowLimit(address(wbtcParams.token), miniPool)
                - miniPoolContracts.flowLimiter.currentFlow(address(wbtcParams.token), miniPool)
        );
        console.log("5. Balance aToken: ", aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET));
        console.log(
            "5. AvailableLiquidity: ",
            IERC20(aTokens[USDC_OFFSET]).balanceOf(address(aErc6909Token))
        );

        assertEq(
            miniPoolContracts.flowLimiter.getFlowLimit(address(wbtcParams.token), miniPool)
                - miniPoolContracts.flowLimiter.currentFlow(address(wbtcParams.token), miniPool),
            0,
            "FlowLimit is not 0"
        );
        assertEq(
            testBalances.collateralInAToken, usdcParams.token.balanceOf(address(usdcParams.aToken))
        );
        assertEq(
            testBalances.borrowTokenInAToken, wbtcParams.token.balanceOf(address(wbtcParams.aToken))
        );
        assertEq(
            testBalances.collateralInVault, usdcParams.token.balanceOf(address(usdcParams.vault))
        );
        assertEq(
            testBalances.borrowTokenInVault, wbtcParams.token.balanceOf(address(wbtcParams.vault))
        );

        console.log("----------------TIME TRAVEL---------------");
        skip(skipDuration);

        console.log("\n---------------->>>>>>>>>>> SECOND MINI POOL <<<<<<<<--------------");
        miniPool = miniPools[1];
        aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        {
            uint8 WETH_OFFSET = 2;
            TokenParams memory wethTokenParams = TokenParams(
                erc20Tokens[WETH_OFFSET],
                aTokensWrapper[WETH_OFFSET],
                oracle.getAssetPrice(address(erc20Tokens[WETH_OFFSET]))
            );
            amount1 = 2e18; //1 ETH

            console.log(
                "----------------USER DEPOSITs LIQUIDITY (USDC) TO LENDING POOL---------------"
            );
            /* User deposits tokens to the main lending pool and gets lending pool's aTokens*/
            fixture_depositTokensToMainPool(amount1, users.user1, wethTokenParams);
            testBalances.collateralInAToken = usdcParams.token.balanceOf(address(usdcParams.aToken));
            testBalances.borrowTokenInAToken =
                wbtcParams.token.balanceOf(address(wbtcParams.aToken));
            testBalances.collateralInVault = usdcParams.token.balanceOf(address(usdcParams.vault));
            testBalances.borrowTokenInVault = wbtcParams.token.balanceOf(address(wbtcParams.vault));

            console.log(
                "----------------USER DEPOSITs LIQUIDITY (aWETH) TO MINI POOL---------------"
            );
            /* User deposits lending pool's aTokens to the mini pool and
        gets mini pool's aTokens */
            fixture_depositATokensToMiniPool(
                amount1, 1000 + WETH_OFFSET, users.user1, wethTokenParams, aErc6909Token
            );
            // logState(usdcParams, wbtcParams, 8);
        }
        uint256 scaledAmountToBorrow = amount2.rayDiv(
            deployedContracts.lendingPool.getReserveNormalizedIncome(
                address(wbtcParams.token), true
            )
        );
        {
            vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
            miniPoolContracts.flowLimiter.setFlowLimit(address(wbtcParams.token), miniPool, amount2);
        }
        console.log("----------------USER1 BORROWs---------------");
        console.log("scaledAmountToBorrow: ", scaledAmountToBorrow);
        vm.startPrank(users.user1);
        IMiniPool(miniPool).borrow(
            address(wbtcParams.aTokenWrapper), false, scaledAmountToBorrow, users.user1
        );
        vm.stopPrank();
        logState(usdcParams, wbtcParams, 9);
        console.log(
            "%s. Balance of WBTC in MINI POOL: %s", 9, wbtcParams.token.balanceOf(address(miniPool))
        );

        assertEq(
            miniPoolContracts.flowLimiter.getFlowLimit(address(wbtcParams.token), miniPool)
                - miniPoolContracts.flowLimiter.currentFlow(address(wbtcParams.token), miniPool),
            0,
            "FlowLimit is not 0"
        );
        assertEq(
            testBalances.collateralInAToken, usdcParams.token.balanceOf(address(usdcParams.aToken))
        );
        assertEq(
            testBalances.borrowTokenInAToken, wbtcParams.token.balanceOf(address(wbtcParams.aToken))
        );
        assertEq(
            testBalances.collateralInVault, usdcParams.token.balanceOf(address(usdcParams.vault))
        );
        assertEq(
            testBalances.borrowTokenInVault, wbtcParams.token.balanceOf(address(wbtcParams.vault))
        );

        console.log("1. User1 aWbtc balance: ", wbtcParams.aToken.balanceOf(users.user1));
        console.log(
            "1. User1 scaled aWbtc balance: ", wbtcParams.aToken.scaledBalanceOf(users.user1)
        );
        console.log("1. User1 wbtc balance: ", wbtcParams.token.balanceOf(users.user1));

        vm.startPrank(users.user1);
        deployedContracts.lendingPool.withdraw(
            address(wbtcParams.token),
            true,
            testBalances.borrowTokenInAToken + testBalances.borrowTokenInVault,
            users.user1
        );
        vm.stopPrank();

        console.log("2. User1 aWbtc balance: ", wbtcParams.aToken.balanceOf(users.user1));
        console.log("2. User1 wbtc balance: ", wbtcParams.token.balanceOf(users.user1));
    }
}
