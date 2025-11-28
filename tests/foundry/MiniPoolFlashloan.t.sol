// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {
    ReserveConfiguration
} from "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import "forge-std/StdUtils.sol";
import "contracts/interfaces/IMiniPool.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract MiniPoolFlashloanTest is Common {
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    DeployedMiniPoolContracts miniPoolContracts;

    ConfigAddresses configAddresses;
    address aTokensErc6909Addr;
    address miniPool;

    uint256[] grainTokenIds = [1000, 1001, 1002, 1003];
    uint256[] tokenIds = [1128, 1129, 1130, 1131];

    event Deposit(
        address indexed reserve, address user, address indexed onBehalfOf, uint256 amount
    );
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );

    function fixture_MiniPoolDeposit(
        uint256 amount,
        uint256 offset,
        address user,
        TokenParams memory tokenParams
    ) public {
        /* Fuzz vector creation */
        offset = bound(offset, 0, tokens.length - 1);
        console2.log("[deposit]Offset: ", offset);
        uint256 tokenId = 1128 + offset;
        uint256 aTokenId = 1000 + offset;

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        vm.label(address(aErc6909Token), "aErc6909Token");

        tokenParams.token.transfer(user, 2 * amount);

        /* User deposits tokens to the main lending pool and gets lending pool's aTokens*/
        vm.startPrank(user);
        uint256 initialSupply = aErc6909Token.scaledTotalSupply(tokenId);
        {
            uint256 initialTokenBalance = tokenParams.token.balanceOf(user);
            uint256 initialATokenBalance = tokenParams.aToken.balanceOf(user);
            tokenParams.token.approve(address(deployedContracts.lendingPool), amount);
            deployedContracts.lendingPool.deposit(address(tokenParams.token), true, amount, user);
            console2.log("User token balance shall be {initialTokenBalance - amount}");
            assertEq(tokenParams.token.balanceOf(user), initialTokenBalance - amount, "01");
            console2.log("User grain token balance shall be {initialATokenBalance + amount}");
            assertEq(tokenParams.aToken.balanceOf(user), initialATokenBalance + amount, "02");
        }
        /* User deposits lending pool's aTokens to the mini pool and
        gets mini pool's aTokens */
        {
            uint256 grainTokenUserBalance = aErc6909Token.balanceOf(user, aTokenId);

            uint256 grainToken6909Balance = aErc6909Token.scaledTotalSupply(aTokenId);
            uint256 grainTokenDepositAmount = tokenParams.aToken.balanceOf(user);
            console2.log("Balance amount: ", amount);
            console2.log("Balance grainAmount: ", grainTokenDepositAmount);
            tokenParams.aToken.approve(address(miniPool), amount);
            IMiniPool(miniPool).deposit(address(tokenParams.aToken), false, amount, user);
            console2.log("User AToken balance shall be less by {amount}");
            assertEq(grainTokenDepositAmount - amount, tokenParams.aToken.balanceOf(user), "11");
            console2.log("User grain token 6909 balance shall be initial balance + amount");
            assertEq(
                grainToken6909Balance + amount, aErc6909Token.scaledTotalSupply(aTokenId), "12"
            );
            assertEq(grainTokenUserBalance + amount, aErc6909Token.balanceOf(user, aTokenId), "13");
        }
        {
            /* User deposits tokens to the mini pool and
            gets mini pool's aTokens */
            uint256 tokenUserBalance = aErc6909Token.balanceOf(user, tokenId);
            uint256 tokenBalance = tokenParams.token.balanceOf(user);
            tokenParams.token.approve(address(miniPool), amount);
            console2.log("User balance after: ", tokenBalance);
            IMiniPool(miniPool).deposit(address(tokenParams.token), false, amount, user);
            assertEq(tokenBalance - amount, tokenParams.token.balanceOf(user));
            assertEq(tokenUserBalance + amount, aErc6909Token.balanceOf(user, tokenId));
        }
        {
            (uint256 totalCollateralETH,,,,,) = IMiniPool(miniPool).getUserAccountData(user);
            assertGt(totalCollateralETH, 0);
        }
        vm.stopPrank();

        console2.log("Scaled totalSupply...");
        console2.log("Address: ", address(aErc6909Token));

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
        IAERC6909 aErc6909Token = IAERC6909(
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool)
        );
        vm.label(address(aErc6909Token), "aErc6909Token");
        vm.label(address(collateralTokenParams.aToken), "aToken");
        vm.label(address(collateralTokenParams.token), "token");

        /* Test depositing */
        uint256 minNrOfTokens;
        {
            StaticData memory staticData =
                deployedContracts.asteraDataProvider
                    .getLpReserveStaticData(address(collateralTokenParams.token), true);
            uint256 borrowTokenInUsd = (amount * borrowTokenParams.price * 10_000)
                / ((10 ** PRICE_FEED_DECIMALS) * staticData.ltv);
            uint256 borrowTokenRay = borrowTokenInUsd.rayDiv(collateralTokenParams.price);
            uint256 borrowTokenInCollateralToken = fixture_preciseConvertWithDecimals(
                borrowTokenRay,
                borrowTokenParams.token.decimals(),
                collateralTokenParams.token.decimals()
            );
            minNrOfTokens = (borrowTokenInCollateralToken
                    > collateralTokenParams.token.balanceOf(address(this)) / 4)
                ? (collateralTokenParams.token.balanceOf(address(this)) / 4)
                : borrowTokenInCollateralToken;
            console2.log(
                "Min nr of collateral in usd: ",
                (borrowTokenInCollateralToken * collateralTokenParams.price)
                    / (10 ** PRICE_FEED_DECIMALS)
            );
        }
        {
            /* Sb deposits tokens which will be borrowed */
            address liquidityProvider = makeAddr("liquidityProvider");
            console2.log(
                "Deposit borrowTokens: %s with balance: %s",
                2 * amount,
                borrowTokenParams.token.balanceOf(address(this))
            );
            fixture_MiniPoolDeposit(amount, borrowOffset, liquidityProvider, borrowTokenParams);

            /* User deposits collateral */
            uint256 tokenId = 1128 + collateralOffset;
            uint256 aTokenId = 1000 + collateralOffset;
            console2.log(
                "Deposit collateral: %s with balance: %s",
                minNrOfTokens,
                collateralTokenParams.token.balanceOf(address(this))
            );
            fixture_MiniPoolDeposit(minNrOfTokens, collateralOffset, user, collateralTokenParams);
            require(aErc6909Token.balanceOf(user, tokenId) > 0, "No token balance");
            require(aErc6909Token.balanceOf(user, aTokenId) > 0, "No aToken balance");
            console2.log("Token balance:", aErc6909Token.balanceOf(user, tokenId));
            console2.log("aToken Balance: ", aErc6909Token.balanceOf(user, aTokenId));
            console2.log(
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
            IMiniPool(miniPool).borrow(address(borrowTokenParams.aToken), false, amount, user);
            console2.log("Total supply of debtAToken must be greater than before borrow");
            assertEq(
                aErc6909Token.scaledTotalSupply(2000 + borrowOffset), balances.totalSupply + amount
            );
            console2.log("Balance of debtAToken must be greater than before borrow");
            assertEq(
                aErc6909Token.balanceOf(user, 2000 + borrowOffset), balances.debtToken + amount
            );
            console2.log("Balance of AToken must be greater than before borrow");
            assertEq(borrowTokenParams.aToken.balanceOf(user), balances.token + amount);
        }

        {
            balances.totalSupply = aErc6909Token.scaledTotalSupply(2128 + borrowOffset);
            balances.debtToken = aErc6909Token.balanceOf(user, 2128 + borrowOffset);
            balances.token = borrowTokenParams.token.balanceOf(user);
            IMiniPool(miniPool).borrow(address(borrowTokenParams.token), false, amount, user);
            console2.log("Balance of debtToken must be greater than before borrow");
            assertEq(
                aErc6909Token.scaledTotalSupply(2128 + borrowOffset), balances.totalSupply + amount
            );
            console2.log("Balance of debtToken must be greater than before borrow");
            assertEq(
                aErc6909Token.balanceOf(user, 2128 + borrowOffset), balances.debtToken + amount
            );
            console2.log("Balance of token must be greater than before borrow");
            assertEq(borrowTokenParams.token.balanceOf(user), balances.token + amount);
        }

        (,,,,, uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        console2.log(
            "HealthFactor must be less than before borrows %s vs %s",
            healthFactorBefore,
            healthFactorAfter
        );
        console2.log("Health factor at the end: ", healthFactorAfter);
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
        IAERC6909 aErc6909Token = IAERC6909(
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool)
        );
        vm.label(address(aErc6909Token), "aErc6909Token");
        vm.label(address(collateralTokenParams.aToken), "aToken");
        vm.label(address(collateralTokenParams.token), "token");

        /* Test depositing */
        uint256 minNrOfTokens;
        {
            StaticData memory staticData =
                deployedContracts.asteraDataProvider
                    .getLpReserveStaticData(address(collateralTokenParams.token), true);
            uint256 borrowTokenInUsd = (amount * borrowTokenParams.price * 10000)
                / ((10 ** PRICE_FEED_DECIMALS) * staticData.ltv);
            uint256 borrowTokenRay = borrowTokenInUsd.rayDiv(collateralTokenParams.price);
            uint256 borrowTokenInCollateralToken = fixture_preciseConvertWithDecimals(
                borrowTokenRay,
                borrowTokenParams.token.decimals(),
                collateralTokenParams.token.decimals()
            );
            minNrOfTokens = (borrowTokenInCollateralToken
                    > collateralTokenParams.token.balanceOf(address(this)) / 4)
                ? (collateralTokenParams.token.balanceOf(address(this)) / 4)
                : borrowTokenInCollateralToken;
        }
        {
            /* Sb deposits tokens which will be borrowed */
            address liquidityProvider = makeAddr("liquidityProvider");
            borrowTokenParams.token.approve(address(deployedContracts.lendingPool), amount);

            deployedContracts.lendingPool
                .deposit(address(borrowTokenParams.token), true, amount, liquidityProvider);
        }

        console2.log("Choosen amount: ", amount);

        {
            vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider));
            console2.log("address of asset:", address(borrowTokenParams.aToken));
            uint256 currentFlow = miniPoolContracts.flowLimiter
            .currentFlow(address(borrowTokenParams.token), miniPool);
            miniPoolContracts.flowLimiter
                .setFlowLimit(address(borrowTokenParams.token), miniPool, currentFlow + amount);
            console2.log(
                "FlowLimiter results",
                miniPoolContracts.flowLimiter
                    .getFlowLimit(address(borrowTokenParams.token), miniPool)
            );
            vm.stopPrank();
        }

        /* User deposits tokens to mini pool and gets aTokens*/
        collateralTokenParams.token.transfer(user, minNrOfTokens);

        vm.startPrank(user);
        console2.log("Address1: %s Address2: %s", address(miniPoolContracts.miniPoolImpl), miniPool);
        collateralTokenParams.token.approve(miniPool, minNrOfTokens);
        console2.log(
            "minNrOfTokens %s vs balance of tokens %s",
            minNrOfTokens,
            collateralTokenParams.token.balanceOf(address(this))
        );
        IMiniPool(miniPool)
            .deposit(address(collateralTokenParams.token), false, minNrOfTokens, user);

        (,,,,, uint256 healthFactorBefore) = IMiniPool(miniPool).getUserAccountData(user);
        Balances memory balances;

        balances.totalSupply = aErc6909Token.scaledTotalSupply(2000 + borrowOffset);
        balances.debtToken = aErc6909Token.balanceOf(user, 2000 + borrowOffset);
        balances.token = borrowTokenParams.aToken.balanceOf(user);
        IMiniPool(miniPool).borrow(address(borrowTokenParams.aToken), false, amount, user);
        console2.log("Total supply of debtAToken must be greater than before borrow");
        assertEq(
            aErc6909Token.scaledTotalSupply(2000 + borrowOffset), balances.totalSupply + amount
        );
        console2.log("Balance of debtAToken must be greater than before borrow");
        assertEq(aErc6909Token.balanceOf(user, 2000 + borrowOffset), balances.debtToken + amount);
        console2.log("Balance of AToken must be greater than before borrow");
        assertEq(borrowTokenParams.aToken.balanceOf(user), balances.token + amount);

        (,,,,, uint256 healthFactorAfter) = IMiniPool(miniPool).getUserAccountData(user);
        console2.log("HealthFactor before borrow must be greater than after");
        assertGt(healthFactorBefore, healthFactorAfter);

        vm.stopPrank();
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        uint256[] memory totalAmountsToPay = new uint256[](assets.length);
        for (uint32 idx = 0; idx < assets.length; idx++) {
            totalAmountsToPay[idx] = amounts[idx] + premiums[idx];
            IERC20(assets[idx]).approve(address(miniPool), totalAmountsToPay[idx]);
        }
        return true;
    }

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.asteraDataProvider),
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
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));
        (miniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.asteraDataProvider),
            miniPoolContracts
        );

        address accessManager =
            miniPoolContracts.miniPoolAddressesProvider.getSecurityAccessManager();
        SecurityAccessManager(accessManager).addUserToFlashloanWhitelist(address(this));

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console2.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] =
                    address(commonContracts.aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        configAddresses.asteraDataProvider = address(miniPoolContracts.miniPoolAddressesProvider);
        configAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configAddresses, miniPoolContracts, 0);
        vm.label(miniPool, "MiniPool");
    }

    function fixture_minipoolFL() internal returns (TokenParams memory, TokenParams memory) {
        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        TokenParams memory tokenParamsUsdc =
            TokenParams(erc20Tokens[0], commonContracts.aTokensWrapper[0], 0);
        TokenParams memory tokenParamsWbtc =
            TokenParams(erc20Tokens[1], commonContracts.aTokensWrapper[1], 0);

        uint256 amountUsdc = 1000 * (10 ** tokenParamsUsdc.token.decimals());
        uint256 amountwBtc = 1 * (10 ** tokenParamsWbtc.token.decimals());

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        deal(address(tokenParamsUsdc.token), user, amountUsdc);
        deal(address(tokenParamsUsdc.token), user2, amountUsdc);
        deal(address(tokenParamsUsdc.token), address(this), amountUsdc);
        deal(address(tokenParamsWbtc.token), user, amountwBtc);
        deal(address(tokenParamsWbtc.token), user2, amountwBtc);
        deal(address(tokenParamsWbtc.token), address(this), amountwBtc);

        vm.startPrank(user);
        tokenParamsUsdc.token.approve(address(deployedContracts.lendingPool), amountUsdc);
        deployedContracts.lendingPool
            .deposit(address(tokenParamsUsdc.token), true, amountUsdc, user);

        vm.startPrank(user2);
        tokenParamsWbtc.token.approve(address(deployedContracts.lendingPool), amountwBtc);
        deployedContracts.lendingPool
            .deposit(address(tokenParamsWbtc.token), true, amountwBtc, user2);
        deployedContracts.lendingPool
            .borrow(address(tokenParamsUsdc.token), true, amountUsdc, user2);

        vm.startPrank(user);
        uint256 amtAUsdc = tokenParamsUsdc.aToken.balanceOf(address(user)) / 2;
        tokenParamsUsdc.aToken.approve(miniPool, amtAUsdc);
        IMiniPool(miniPool).deposit(address(tokenParamsUsdc.aToken), false, amtAUsdc, user);

        uint256 amt = amountUsdc * 10;
        deal(address(tokenParamsUsdc.token), user, amt);
        tokenParamsUsdc.token.approve(miniPool, amt);
        IMiniPool(miniPool).deposit(address(tokenParamsUsdc.token), false, amt, user);

        amt = amountwBtc * 10;
        deal(address(tokenParamsWbtc.token), user, amt);
        tokenParamsWbtc.token.approve(miniPool, amt);
        IMiniPool(miniPool).deposit(address(tokenParamsWbtc.token), false, amt, user);

        vm.stopPrank();

        return (tokenParamsUsdc, tokenParamsWbtc);
    }

    function testMiniPoolFL1() public {
        (TokenParams memory tokenParamsUsdc, TokenParams memory tokenParamsWbtc) =
            fixture_minipoolFL();

        /// FL
        address[] memory assets = new address[](1);
        assets[0] = address(tokenParamsUsdc.token);

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 1e8;

        uint256[] memory modes = new uint256[](assets.length);
        modes[0] = 0;

        IMiniPool.FlashLoanParams memory flashLoanParams =
            IMiniPool.FlashLoanParams(address(this), assets, address(this));

        uint256 balanceBefore = tokenParamsUsdc.token.balanceOf(address(this));

        IMiniPool(miniPool).flashLoan(flashLoanParams, amounts, modes, bytes("0"));

        assertEq(
            tokenParamsUsdc.token.balanceOf(address(this)),
            balanceBefore - amounts[0] * IMiniPool(miniPool).FLASHLOAN_PREMIUM_TOTAL() / 10000
        );
    }

    function testMiniPoolFL2() public {
        (TokenParams memory tokenParamsUsdc, TokenParams memory tokenParamsWbtc) =
            fixture_minipoolFL();

        /// FL
        address[] memory assets = new address[](1);
        assets[0] = address(tokenParamsWbtc.token);

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 100e6;

        uint256[] memory modes = new uint256[](assets.length);
        modes[0] = 0;

        IMiniPool.FlashLoanParams memory flashLoanParams =
            IMiniPool.FlashLoanParams(address(this), assets, address(this));

        IMiniPool(miniPool).flashLoan(flashLoanParams, amounts, modes, bytes("0"));
    }

    function testMiniPoolFLMultiAssets() public {
        (TokenParams memory tokenParamsUsdc, TokenParams memory tokenParamsWbtc) =
            fixture_minipoolFL();

        /// FL
        address[] memory assets = new address[](2);
        assets[0] = address(tokenParamsUsdc.token);
        assets[1] = address(tokenParamsWbtc.token);

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 100e6;
        amounts[1] = 1e8;

        uint256[] memory modes = new uint256[](assets.length);
        modes[0] = 0;
        modes[1] = 0;

        IMiniPool.FlashLoanParams memory flashLoanParams =
            IMiniPool.FlashLoanParams(address(this), assets, address(this));

        IMiniPool(miniPool).flashLoan(flashLoanParams, amounts, modes, bytes("0"));
    }

    function testMiniPoolFLRevertTranchedAsset() public {
        (TokenParams memory tokenParamsUsdc, TokenParams memory tokenParamsWbtc) =
            fixture_minipoolFL();

        /// FL
        address[] memory assets = new address[](1);
        assets[0] = address(tokenParamsUsdc.aToken);

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 100e6;

        uint256[] memory modes = new uint256[](assets.length);
        modes[0] = 0;

        IMiniPool.FlashLoanParams memory flashLoanParams =
            IMiniPool.FlashLoanParams(address(this), assets, address(this));

        vm.expectRevert(bytes(Errors.VL_TRANCHED_ASSET_CANNOT_BE_FLASHLOAN));
        IMiniPool(miniPool).flashLoan(flashLoanParams, amounts, modes, bytes("0"));
    }

    function testMiniPoolFLRevertTranchedAssets() public {
        (TokenParams memory tokenParamsUsdc, TokenParams memory tokenParamsWbtc) =
            fixture_minipoolFL();

        /// FL
        address[] memory assets = new address[](2);
        assets[0] = address(tokenParamsUsdc.token);
        assets[1] = address(tokenParamsUsdc.aToken);

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 100e6;
        amounts[1] = 100e6;

        uint256[] memory modes = new uint256[](assets.length);
        modes[0] = 0;
        modes[1] = 0;

        IMiniPool.FlashLoanParams memory flashLoanParams =
            IMiniPool.FlashLoanParams(address(this), assets, address(this));

        vm.expectRevert(bytes(Errors.VL_TRANCHED_ASSET_CANNOT_BE_FLASHLOAN));
        IMiniPool(miniPool).flashLoan(flashLoanParams, amounts, modes, bytes("0"));
    }

    function testMiniPoolFLIntoBorrow() public {
        (TokenParams memory tokenParamsUsdc, TokenParams memory tokenParamsWbtc) =
            fixture_minipoolFL();
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        uint256 USDC_OFFSET = 0;

        uint256 amt = 2e8;
        deal(address(tokenParamsWbtc.token), address(this), amt);
        tokenParamsWbtc.token.approve(miniPool, amt);
        IMiniPool(miniPool).deposit(address(tokenParamsWbtc.token), false, amt, address(this));

        /// FL
        address[] memory assets = new address[](1);
        assets[0] = address(tokenParamsUsdc.token);

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 100e6;

        uint256[] memory modes = new uint256[](assets.length);
        modes[0] = 1;

        IMiniPool.FlashLoanParams memory flashLoanParams =
            IMiniPool.FlashLoanParams(address(this), assets, address(this));

        uint256 balanceBefore = tokenParamsUsdc.token.balanceOf(address(this));

        IMiniPool(miniPool).flashLoan(flashLoanParams, amounts, modes, bytes("0"));

        // Must not take a fee but + amount
        assertEq(tokenParamsUsdc.token.balanceOf(address(this)), balanceBefore + amounts[0]);

        assertEq(aErc6909Token.balanceOf(address(this), 2000 + 128 + USDC_OFFSET), amounts[0]);
    }

    function testMiniPoolFLIntoMultipleBorrow1() public {
        (TokenParams memory tokenParamsUsdc, TokenParams memory tokenParamsWbtc) =
            fixture_minipoolFL();
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        uint256 USDC_OFFSET = 0;

        uint256 amt = 2e8;
        deal(address(tokenParamsWbtc.token), address(this), amt);
        tokenParamsWbtc.token.approve(miniPool, amt);
        IMiniPool(miniPool).deposit(address(tokenParamsWbtc.token), false, amt, address(this));

        /// FL
        address[] memory assets = new address[](2);
        assets[0] = address(tokenParamsUsdc.token);
        assets[1] = address(tokenParamsWbtc.token);

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 100e6;
        amounts[1] = 1e8;

        uint256[] memory modes = new uint256[](assets.length);
        modes[0] = 1;
        modes[1] = 1;

        bool[] memory reserveTypes = new bool[](assets.length);
        reserveTypes[0] = false;
        reserveTypes[1] = false;

        IMiniPool.FlashLoanParams memory flashLoanParams =
            IMiniPool.FlashLoanParams(address(this), assets, address(this));

        uint256 balanceBeforeUsdc = tokenParamsUsdc.token.balanceOf(address(this));
        uint256 balanceBeforeWbtc = tokenParamsWbtc.token.balanceOf(address(this));

        IMiniPool(miniPool).flashLoan(flashLoanParams, amounts, modes, bytes("0"));

        // Must not take a fee but + amount
        assertEq(tokenParamsUsdc.token.balanceOf(address(this)), balanceBeforeUsdc + amounts[0]);
        assertEq(tokenParamsWbtc.token.balanceOf(address(this)), balanceBeforeWbtc + amounts[1]);

        assertEq(aErc6909Token.balanceOf(address(this), 2000 + 128 + 0), amounts[0]);
        assertEq(aErc6909Token.balanceOf(address(this), 2000 + 128 + 1), amounts[1]);
    }

    function testMiniPoolFLIntoMultipleBorrow2() public {
        (TokenParams memory tokenParamsUsdc, TokenParams memory tokenParamsWbtc) =
            fixture_minipoolFL();
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));
        uint256 USDC_OFFSET = 0;

        uint256 amt = 2e8;
        deal(address(tokenParamsWbtc.token), address(this), amt * 2);
        tokenParamsWbtc.token.approve(miniPool, amt);
        IMiniPool(miniPool).deposit(address(tokenParamsWbtc.token), false, amt, address(this));

        /// FL
        address[] memory assets = new address[](2);
        assets[0] = address(tokenParamsUsdc.token);
        assets[1] = address(tokenParamsWbtc.token);

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 100e6;
        amounts[1] = 1e8;

        uint256[] memory modes = new uint256[](assets.length);
        modes[0] = 1;
        modes[1] = 1;

        IMiniPool.FlashLoanParams memory flashLoanParams =
            IMiniPool.FlashLoanParams(address(this), assets, address(this));

        uint256 balanceBeforeUsdc = tokenParamsUsdc.token.balanceOf(address(this));
        uint256 balanceBeforeWbtc = tokenParamsWbtc.token.balanceOf(address(this));

        IMiniPool(miniPool).flashLoan(flashLoanParams, amounts, modes, bytes("0"));

        // Must not take a fee but + amount
        assertEq(tokenParamsUsdc.token.balanceOf(address(this)), balanceBeforeUsdc + amounts[0]);
        assertEq(tokenParamsWbtc.token.balanceOf(address(this)), balanceBeforeWbtc + amounts[1]);

        assertEq(aErc6909Token.balanceOf(address(this), 2000 + 128 + 0), amounts[0]);
        assertEq(aErc6909Token.balanceOf(address(this), 2000 + 128 + 1), amounts[1]);
    }
}
