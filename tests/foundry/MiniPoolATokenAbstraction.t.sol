// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolFixtures.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import "contracts/misc/Cod3xLendDataProvider.sol";

import "forge-std/StdUtils.sol";
import "forge-std/console.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract MiniPoolATokenAbstractionTest is MiniPoolFixtures {
    ERC20[] erc20Tokens;

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
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            address(0)
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
        configLpAddresses.cod3xLendDataProvider =
            address(miniPoolContracts.miniPoolAddressesProvider);
        configLpAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configLpAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 0);
        vm.label(miniPool, "MiniPool");
    }

    function testMiniPoolDepositsWrapUnwrap(uint256 amount) public {
        uint256 offset = 2; // weth
        amount = bound(amount, 10 ether, 100_000 ether);

        /* Fuzz vector creation */
        address user = makeAddr("user");

        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokensWrapper[offset], 0);
        TokenParams memory tokenParamsUSDC = TokenParams(erc20Tokens[0], aTokensWrapper[0], 0); // USDC

        /* Deposit tests */
        uint256 tokenId = 1128 + offset;
        uint256 aTokenId = 1000 + offset;

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");

        deal(address(tokenParams.token), user, amount * 2);
        deal(address(tokenParamsUSDC.token), user, 100_000e6);
        vm.startPrank(user);
        {
            tokenParams.token.approve(address(deployedContracts.lendingPool), type(uint256).max);
            deployedContracts.lendingPool.deposit(address(tokenParams.token), true, amount, user);

            tokenParamsUSDC.token.approve(address(deployedContracts.lendingPool), type(uint256).max);
            deployedContracts.lendingPool.deposit(
                address(tokenParamsUSDC.token), true, 50_000e6, user
            );

            // Borrow 1000 USDC
            deployedContracts.lendingPool.borrow(address(tokenParams.token), true, 1e18, user);

            skip(10 days);

            deployedContracts.lendingPool.borrow(address(tokenParams.token), true, 1_000, user);
        }

        vm.stopPrank();

        console.log("wrapped aToken balance :::: ", tokenParams.aToken.balanceOf(user));
        console.log("asset balance :::: ", tokenParams.token.balanceOf(user));
        console.log("a6909 :::: ", aErc6909Token.balanceOf(user, aTokenId));
        console.log("========");

        // deposit Unwrap == true
        {
            vm.startPrank(user);
            uint256 tokenUserBalance = aErc6909Token.balanceOf(user, aTokenId);
            uint256 tokenBalance = tokenParams.token.balanceOf(user);
            tokenParams.token.approve(address(miniPool), type(uint256).max);
            IMiniPool(miniPool).deposit(address(tokenParams.aToken), true, amount, user);
            assertEq(
                tokenBalance - tokenParams.aToken.convertToAssets(amount),
                tokenParams.token.balanceOf(user)
            );
            assertEq(
                tokenUserBalance + tokenParams.aToken.convertToAssets(amount),
                tokenParams.aToken.convertToAssets(aErc6909Token.balanceOf(user, aTokenId))
            );
            vm.stopPrank();
        }

        uint256 midATokenBalance = tokenParams.aToken.balanceOf(address(aErc6909Token));

        console.log("wrapped aToken balance :::: ", tokenParams.aToken.balanceOf(user));
        console.log("asset balance :::: ", tokenParams.token.balanceOf(user));
        console.log("a6909 :::: ", aErc6909Token.balanceOf(user, aTokenId));
        console.log("========");

        // deposit Unwrap == false
        {
            vm.startPrank(user);
            uint256 tokenUserBalance = aErc6909Token.balanceOf(user, aTokenId);
            uint256 tokenBalance = tokenParams.aToken.balanceOf(user);
            tokenParams.aToken.approve(address(miniPool), type(uint256).max);
            console.log("User balance before: ", tokenBalance);
            IMiniPool(miniPool).deposit(address(tokenParams.aToken), false, amount, user);
            assertEq(tokenBalance - amount, tokenParams.aToken.balanceOf(user));
            assertEq(tokenUserBalance + amount, aErc6909Token.balanceOf(user, aTokenId));
            vm.stopPrank();
        }

        uint256 finalATokenBalance = tokenParams.aToken.balanceOf(address(aErc6909Token));

        // log balance
        assertEq(midATokenBalance * 2, finalATokenBalance);
    }

    function testMiniPoolWithdrawWrapUnwrap(uint256 amount) public {
        testMiniPoolDepositsWrapUnwrap(amount);

        uint256 offset = 2; // weth
        amount = bound(amount, 10 ether, 100_000 ether);

        /* Fuzz vector creation */
        address user = makeAddr("user");

        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokensWrapper[offset], 0);
        TokenParams memory tokenParamsUSDC = TokenParams(erc20Tokens[0], aTokensWrapper[0], 0); // USDC

        /* Deposit tests */
        uint256 tokenId = 1128 + offset;
        uint256 aTokenId = 1000 + offset;

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");

        // Withdraw Unwrap == true
        {
            vm.startPrank(user);
            uint256 tokenUserBalance = aErc6909Token.balanceOf(user, aTokenId);
            uint256 tokenBalance = tokenParams.token.balanceOf(user);
            uint256 withdrawAmount = tokenUserBalance / 2;

            IMiniPool(miniPool).withdraw(address(tokenParams.aToken), true, withdrawAmount, user);

            assertEq(
                tokenBalance + tokenParams.aToken.convertToAssets(withdrawAmount),
                tokenParams.token.balanceOf(user)
            );
            assertEq(tokenUserBalance - withdrawAmount, aErc6909Token.balanceOf(user, aTokenId));
            vm.stopPrank();
        }

        uint256 midATokenBalance = tokenParams.aToken.balanceOf(address(aErc6909Token));

        console.log("wrapped aToken balance :::: ", tokenParams.aToken.balanceOf(user));
        console.log("asset balance :::: ", tokenParams.token.balanceOf(user));
        console.log("a6909 :::: ", aErc6909Token.balanceOf(user, aTokenId));
        console.log("========");

        // Withdraw Unwrap == false
        {
            vm.startPrank(user);
            uint256 tokenUserBalance = aErc6909Token.balanceOf(user, aTokenId);
            uint256 tokenBalance = tokenParams.aToken.balanceOf(user);
            uint256 withdrawAmount = tokenUserBalance / 2;

            IMiniPool(miniPool).withdraw(address(tokenParams.aToken), false, withdrawAmount, user);

            assertEq(tokenBalance + withdrawAmount, tokenParams.aToken.balanceOf(user));
            assertEq(tokenUserBalance - withdrawAmount, aErc6909Token.balanceOf(user, aTokenId));
            vm.stopPrank();
        }

        uint256 finalATokenBalance = tokenParams.aToken.balanceOf(address(aErc6909Token));
        assertApproxEqAbs(midATokenBalance / 2, finalATokenBalance, 1);
        assertLe(midATokenBalance / 2, finalATokenBalance);
    }

    function testMiniPoolBorrowWrapUnwrap(uint256 amount) public {
        testMiniPoolDepositsWrapUnwrap(amount);

        uint256 offset = 2; // weth

        /* Fuzz vector creation */
        address user = makeAddr("user");

        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokensWrapper[offset], 0);
        TokenParams memory tokenParamsUSDC = TokenParams(erc20Tokens[0], aTokensWrapper[0], 0); // USDC

        /* Deposit tests */
        uint256 tokenId = 1128 + offset;
        uint256 aTokenId = 1000 + offset;

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");

        // deposit usdc to borrow
        {
            tokenParamsUSDC.token.approve(address(miniPool), type(uint256).max);
            IMiniPool(miniPool).deposit(address(tokenParamsUSDC.aToken), true, 20_000e6, user);
        }

        // Borrow Unwrap == true
        {
            vm.startPrank(user);
            uint256 tokenBalance = tokenParamsUSDC.token.balanceOf(user);
            uint256 borrowAmount = 10_000e6;

            IMiniPool(miniPool).borrow(address(tokenParamsUSDC.aToken), true, borrowAmount, user);

            assertEq(
                tokenBalance + tokenParamsUSDC.aToken.convertToAssets(borrowAmount),
                tokenParamsUSDC.token.balanceOf(user)
            );
            vm.stopPrank();
        }

        // Borrow Unwrap == false
        {
            vm.startPrank(user);
            uint256 tokenBalance = tokenParamsUSDC.aToken.balanceOf(user);
            uint256 borrowAmount = 10_000e6;

            IMiniPool(miniPool).borrow(address(tokenParamsUSDC.aToken), false, borrowAmount, user);
            console.log("user  :::: ", user);
            console.logAddress(address(tokenParamsUSDC.aToken));
            assertEq(tokenBalance + borrowAmount, tokenParamsUSDC.aToken.balanceOf(user));
            vm.stopPrank();
        }
    }

    function testMiniPoolRepayWrapUnwrap(uint256 amount) public {
        testMiniPoolBorrowWrapUnwrap(amount);

        uint256 offset = 2; // weth

        /* Fuzz vector creation */
        address user = makeAddr("user");

        TokenParams memory tokenParams = TokenParams(erc20Tokens[offset], aTokensWrapper[offset], 0);
        TokenParams memory tokenParamsUSDC = TokenParams(erc20Tokens[0], aTokensWrapper[0], 0); // USDC

        /* Deposit tests */
        uint256 tokenId = 1128 + offset;
        uint256 aTokenId = 1000 + offset;

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");

        // Repay with wrap == true
        {
            vm.startPrank(user);
            uint256 tokenBalance = tokenParamsUSDC.token.balanceOf(user);
            uint256 repayAmount = 10_000e6;

            tokenParamsUSDC.token.approve(address(miniPool), type(uint256).max);
            IMiniPool(miniPool).repay(address(tokenParamsUSDC.aToken), true, repayAmount, user);

            assertEq(
                tokenBalance - tokenParamsUSDC.aToken.convertToAssets(repayAmount),
                tokenParamsUSDC.token.balanceOf(user)
            );
            vm.stopPrank();
        }

        // Repay with wrap == false
        {
            vm.startPrank(user);
            uint256 tokenBalance = tokenParamsUSDC.aToken.balanceOf(user);
            uint256 repayAmount = 10_000e6;

            tokenParamsUSDC.aToken.approve(address(miniPool), type(uint256).max);
            IMiniPool(miniPool).repay(address(tokenParamsUSDC.aToken), false, repayAmount, user);

            assertEq(tokenBalance - repayAmount, tokenParamsUSDC.aToken.balanceOf(user));
            vm.stopPrank();
        }
    }
}
