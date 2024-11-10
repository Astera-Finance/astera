// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";

abstract contract MiniPoolFixtures is Common {
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    DeployedContracts deployedLpContracts;
    DeployedMiniPoolContracts miniPoolContracts;

    ConfigAddresses configLpAddresses;
    address aTokensErc6909Addr;
    address miniPool;

    uint256[] grainTokenIds = [1000, 1001, 1002, 1003];
    uint256[] tokenIds = [1128, 1129, 1130, 1131];

    function fixture_depositTokensToMainPool(
        uint256 amount,
        address user,
        TokenParams memory tokenParams
    ) public {
        deal(address(tokenParams.token), user, amount);

        vm.startPrank(user);
        {
            uint256 initialTokenBalance = tokenParams.token.balanceOf(user);
            uint256 initialATokenBalance = tokenParams.aToken.balanceOf(user);
            tokenParams.token.approve(address(deployedLpContracts.lendingPool), amount);
            deployedLpContracts.lendingPool.deposit(address(tokenParams.token), true, amount, user);
            console.log("User token balance shall be {initialTokenBalance - amount}");
            assertEq(tokenParams.token.balanceOf(user), initialTokenBalance - amount, "01");
            console.log("User atoken balance shall be {initialATokenBalance + amount}");
            assertEq(tokenParams.aToken.balanceOf(user), initialATokenBalance + amount, "02");
        }
        vm.stopPrank();
    }

    function fixture_depositATokensToMiniPool(
        uint256 amount,
        uint256 aTokenId,
        address user,
        TokenParams memory tokenParams,
        IAERC6909 aErc6909Token
    ) public {
        vm.startPrank(user);
        uint256 aTokenUserBalance = aErc6909Token.balanceOf(user, aTokenId);

        uint256 aToken6909Balance = aErc6909Token.scaledTotalSupply(aTokenId);
        uint256 aTokenDepositAmount = tokenParams.aToken.balanceOf(user);
        console.log("Amount: ", amount);
        console.log("Balance of aToken: ", aTokenDepositAmount);
        tokenParams.aToken.approve(address(miniPool), amount);
        IMiniPool(miniPool).deposit(address(tokenParams.aToken), amount, user);
        console.log("User AToken balance shall be less by {amount}");
        assertEq(aTokenDepositAmount - amount, tokenParams.aToken.balanceOf(user), "11");
        console.log("User grain token 6909 balance shall be initial balance + amount");
        assertEq(aToken6909Balance + amount, aErc6909Token.scaledTotalSupply(aTokenId), "12");
        assertEq(aTokenUserBalance + amount, aErc6909Token.balanceOf(user, aTokenId), "13");
        vm.stopPrank();
    }

    function fixture_depositTokensToMiniPool(
        uint256 amount,
        uint256 tokenId,
        address user,
        TokenParams memory tokenParams,
        IAERC6909 aErc6909Token
    ) public {
        deal(address(tokenParams.token), user, amount);

        vm.startPrank(user);
        uint256 tokenUserBalance = aErc6909Token.balanceOf(user, tokenId);
        uint256 tokenBalance = tokenParams.token.balanceOf(user);
        tokenParams.token.approve(address(miniPool), amount);
        console.log("User balance before: ", tokenBalance);
        IMiniPool(miniPool).deposit(address(tokenParams.token), amount, user);
        assertEq(tokenBalance - amount, tokenParams.token.balanceOf(user));
        assertEq(tokenUserBalance + amount, aErc6909Token.balanceOf(user, tokenId));
        vm.stopPrank();
    }

    function fixture_MiniPoolDeposit(
        uint256 amount,
        uint256 offset,
        address user,
        TokenParams memory tokenParams
    ) public {
        /* Fuzz vector creation */
        console.log("[deposit]Offset: ", offset);
        uint256 tokenId = 1128 + offset;
        uint256 aTokenId = 1000 + offset;

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");

        // tokenParams.token.transfer(user, 2 * amount);
        uint256 initialSupply = aErc6909Token.scaledTotalSupply(tokenId);
        /* User deposits tokens to the main lending pool and gets lending pool's aTokens*/
        fixture_depositTokensToMainPool(amount, user, tokenParams);

        /* User deposits lending pool's aTokens to the mini pool and 
        gets mini pool's aTokens */
        fixture_depositATokensToMiniPool(amount, aTokenId, user, tokenParams, aErc6909Token);
        /* User deposits tokens to the mini pool and 
            gets mini pool's aTokens */
        fixture_depositTokensToMiniPool(amount, tokenId, user, tokenParams, aErc6909Token);
        {
            (uint256 totalCollateralETH,,,,,) = IMiniPool(miniPool).getUserAccountData(user);
            assertGt(totalCollateralETH, 0);
        }
        vm.stopPrank();

        console.log("Scaled totalSupply...");
        console.log("Address: ", address(aErc6909Token));

        uint256 aErc6909TokenBalance = aErc6909Token.scaledTotalSupply(tokenId);
        assertEq(aErc6909TokenBalance, initialSupply + amount);
    }

    struct Balances {
        uint256 debtToken;
        uint256 token;
        uint256 totalSupply;
    }

    function fixture_miniPoolBorrow(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset,
        TokenParams memory collateralTokenParams,
        TokenParams memory borrowTokenParams,
        address user
    ) public {
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");
        vm.label(address(collateralTokenParams.aToken), "aToken");
        vm.label(address(collateralTokenParams.token), "token");

        /* Test depositing */
        uint256 minNrOfTokens;
        {
            StaticData memory staticData = deployedLpContracts
                .cod3xLendDataProvider
                .getLpReserveStaticData(address(collateralTokenParams.token), true);
            uint256 borrowTokenInUsd = (amount * borrowTokenParams.price * 10_000)
                / ((10 ** PRICE_FEED_DECIMALS) * staticData.ltv);
            uint256 borrowTokenRay = borrowTokenInUsd.rayDiv(collateralTokenParams.price);
            uint256 borrowTokenInCollateralToken = fixture_preciseConvertWithDecimals(
                borrowTokenRay,
                borrowTokenParams.token.decimals(),
                collateralTokenParams.token.decimals()
            );
            minNrOfTokens = (
                borrowTokenInCollateralToken
                    > collateralTokenParams.token.balanceOf(address(this)) / 4
            )
                ? (collateralTokenParams.token.balanceOf(address(this)) / 4)
                : borrowTokenInCollateralToken;
            console.log(
                "Min nr of collateral in usd: ",
                (borrowTokenInCollateralToken * collateralTokenParams.price)
                    / (10 ** PRICE_FEED_DECIMALS)
            );
        }
        {
            /* Sb deposits tokens which will be borrowed */
            address liquidityProvider = makeAddr("liquidityProvider");
            console.log(
                "Deposit borrowTokens: %s with balance: %s",
                2 * amount,
                borrowTokenParams.token.balanceOf(address(this))
            );
            fixture_MiniPoolDeposit(amount, borrowOffset, liquidityProvider, borrowTokenParams);

            /* User deposits collateral */
            uint256 tokenId = 1128 + collateralOffset;
            uint256 aTokenId = 1000 + collateralOffset;
            console.log(
                "Deposit collateral: %s with balance: %s",
                minNrOfTokens,
                collateralTokenParams.token.balanceOf(address(this))
            );
            fixture_MiniPoolDeposit(minNrOfTokens, collateralOffset, user, collateralTokenParams);
            require(aErc6909Token.balanceOf(user, tokenId) > 0, "No token balance");
            require(aErc6909Token.balanceOf(user, aTokenId) > 0, "No aToken balance");
            console.log("Token balance:", aErc6909Token.balanceOf(user, tokenId));
            console.log("aToken Balance: ", aErc6909Token.balanceOf(user, aTokenId));
            console.log(
                "Underlying token balance:",
                collateralTokenParams.token.balanceOf(address(collateralTokenParams.aToken))
            );
        }

        /* Test borrowing */
        vm.startPrank(user);
        (,,,,, uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);

        Balances memory balances;
        {
            balances.totalSupply = aErc6909Token.scaledTotalSupply(2000 + borrowOffset);
            balances.debtToken = aErc6909Token.balanceOf(user, 2000 + borrowOffset);
            balances.token = borrowTokenParams.aToken.balanceOf(user);
            IMiniPool(miniPool).borrow(address(borrowTokenParams.aToken), amount, user);
            console.log("Total supply of debtAToken must be greater than before borrow");
            assertEq(
                aErc6909Token.scaledTotalSupply(2000 + borrowOffset), balances.totalSupply + amount
            );
            console.log("Balance of debtAToken must be greater than before borrow");
            assertEq(
                aErc6909Token.balanceOf(user, 2000 + borrowOffset), balances.debtToken + amount
            );
            console.log("Balance of AToken must be greater than before borrow");
            assertEq(borrowTokenParams.aToken.balanceOf(user), balances.token + amount);
        }

        {
            balances.totalSupply = aErc6909Token.scaledTotalSupply(2128 + borrowOffset);
            balances.debtToken = aErc6909Token.balanceOf(user, 2128 + borrowOffset);
            balances.token = borrowTokenParams.token.balanceOf(user);
            IMiniPool(miniPool).borrow(address(borrowTokenParams.token), amount, user);
            console.log("Balance of debtToken must be greater than before borrow");
            assertEq(
                aErc6909Token.scaledTotalSupply(2128 + borrowOffset), balances.totalSupply + amount
            );
            console.log("Balance of debtToken must be greater than before borrow");
            assertEq(
                aErc6909Token.balanceOf(user, 2128 + borrowOffset), balances.debtToken + amount
            );
            console.log("Balance of token must be greater than before borrow");
            assertEq(borrowTokenParams.token.balanceOf(user), balances.token + amount);
        }

        (,,,,, uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        console.log(
            "HealthFactor must be less than before borrows %s vs %s",
            healthFactorBefore,
            healthFactorAfter
        );
        console.log("Health factor at the end: ", healthFactorAfter);
        assertGt(healthFactorBefore, healthFactorAfter);
        vm.stopPrank();
    }

    function fixture_miniPoolBorrowWithFlowFromLendingPool(
        uint256 amount,
        uint256 borrowOffset,
        TokenParams memory collateralTokenParams,
        TokenParams memory borrowTokenParams,
        address user
    ) public {
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");
        vm.label(address(collateralTokenParams.aToken), "aToken");
        vm.label(address(collateralTokenParams.token), "token");

        /* Test depositing */
        uint256 minNrOfTokens;
        {
            StaticData memory staticData = deployedLpContracts
                .cod3xLendDataProvider
                .getLpReserveStaticData(address(collateralTokenParams.token), true);
            uint256 borrowTokenInUsd = (amount * borrowTokenParams.price * 10000)
                / ((10 ** PRICE_FEED_DECIMALS) * staticData.ltv);
            uint256 borrowTokenRay = borrowTokenInUsd.rayDiv(collateralTokenParams.price);
            uint256 borrowTokenInCollateralToken = fixture_preciseConvertWithDecimals(
                borrowTokenRay,
                borrowTokenParams.token.decimals(),
                collateralTokenParams.token.decimals()
            );
            minNrOfTokens = (
                borrowTokenInCollateralToken
                    > collateralTokenParams.token.balanceOf(address(this)) / 4
            )
                ? (collateralTokenParams.token.balanceOf(address(this)) / 4)
                : borrowTokenInCollateralToken;
        }
        {
            /* Sb deposits tokens which will be borrowed */
            address liquidityProvider = makeAddr("liquidityProvider");
            borrowTokenParams.token.approve(address(deployedLpContracts.lendingPool), amount);

            deployedLpContracts.lendingPool.deposit(
                address(borrowTokenParams.token), true, amount, liquidityProvider
            );
        }

        console.log("Choosen amount: ", amount);

        {
            vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider));
            console.log("address of asset:", address(borrowTokenParams.aToken));
            uint256 currentFlow = miniPoolContracts.flowLimiter.currentFlow(
                address(borrowTokenParams.token), miniPool
            );
            miniPoolContracts.flowLimiter.setFlowLimit(
                address(borrowTokenParams.token), miniPool, currentFlow + amount
            );
            console.log(
                "flowLimiter results",
                miniPoolContracts.flowLimiter.getFlowLimit(
                    address(borrowTokenParams.token), miniPool
                )
            );
            vm.stopPrank();
        }

        /* User deposits tokens to mini pool and gets aTokens*/
        collateralTokenParams.token.transfer(user, minNrOfTokens);

        vm.startPrank(user);
        console.log("Address1: %s Address2: %s", address(miniPoolContracts.miniPoolImpl), miniPool);
        collateralTokenParams.token.approve(miniPool, minNrOfTokens);
        console.log(
            "minNrOfTokens %s vs balance of tokens %s",
            minNrOfTokens,
            collateralTokenParams.token.balanceOf(address(this))
        );
        IMiniPool(miniPool).deposit(address(collateralTokenParams.token), minNrOfTokens, user);

        (,,,,, uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);
        Balances memory balances;

        balances.totalSupply = aErc6909Token.scaledTotalSupply(2000 + borrowOffset);
        balances.debtToken = aErc6909Token.balanceOf(user, 2000 + borrowOffset);
        balances.token = borrowTokenParams.aToken.balanceOf(user);
        IMiniPool(miniPool).borrow(address(borrowTokenParams.aToken), amount, user);
        console.log("Total supply of debtAToken must be greater than before borrow");
        assertEq(
            aErc6909Token.scaledTotalSupply(2000 + borrowOffset), balances.totalSupply + amount
        );
        console.log("Balance of debtAToken must be greater than before borrow");
        assertEq(aErc6909Token.balanceOf(user, 2000 + borrowOffset), balances.debtToken + amount);
        console.log("Balance of AToken must be greater than before borrow");
        assertEq(borrowTokenParams.aToken.balanceOf(user), balances.token + amount);

        (,,,,, uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        console.log("HealthFactor before borrow must be greater than after");
        assertGt(healthFactorBefore, healthFactorAfter);

        vm.stopPrank();
    }

    function setUp() public virtual {}
}
