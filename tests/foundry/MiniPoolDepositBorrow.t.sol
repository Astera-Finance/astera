// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolFixtures.t.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {ReserveConfiguration} from
    "contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {PercentageMath} from "contracts/protocol/libraries/math/PercentageMath.sol";
import {MintableERC20} from "contracts/mocks/tokens/MintableERC20.sol";
import "contracts/misc/AsteraDataProvider.sol";

import "forge-std/StdUtils.sol";
import "forge-std/console2.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract MiniPoolDepositBorrowTest is MiniPoolFixtures {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();

        configLpAddresses = ConfigAddresses(
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
            configLpAddresses,
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
        configLpAddresses.asteraDataProvider = address(miniPoolContracts.miniPoolAddressesProvider);
        configLpAddresses.stableStrategy = address(miniPoolContracts.stableStrategy);
        configLpAddresses.volatileStrategy = address(miniPoolContracts.volatileStrategy);
        miniPool =
            fixture_configureMiniPoolReserves(reserves, configLpAddresses, miniPoolContracts, 0);
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setMinDebtThreshold(0, IMiniPool(miniPool));
        vm.label(miniPool, "MiniPool");
    }

    function testInitalizeReserveWithReserveTypeFalse() public {
        address user = address(0x1223);
        MintableERC20 mockToken = new MintableERC20("a", "a", 18);

        vm.prank(user);
        mockToken.mint(100 ether);

        {
            ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
                new ILendingPoolConfigurator.InitReserveInput[](1);
            ATokensAndRatesHelper.ConfigureReserveInput[] memory inputConfigParams =
                new ATokensAndRatesHelper.ConfigureReserveInput[](1);

            string memory tmpSymbol = ERC20(mockToken).symbol();
            address interestStrategy = address(
                new DefaultReserveInterestRateStrategy(
                    deployedContracts.lendingPoolAddressesProvider,
                    sStrat[0],
                    sStrat[1],
                    sStrat[2],
                    sStrat[3]
                )
            );

            initInputParams[0] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: address(commonContracts.aToken),
                variableDebtTokenImpl: address(commonContracts.variableDebtToken),
                underlyingAssetDecimals: ERC20(mockToken).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: address(mockToken),
                reserveType: false,
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat("Astera ", tmpSymbol),
                aTokenSymbol: string.concat("cl", tmpSymbol),
                variableDebtTokenName: string.concat("Astera variable debt bearing ", tmpSymbol),
                variableDebtTokenSymbol: string.concat("variableDebt", tmpSymbol),
                params: "0x10"
            });

            console2.log("interestStrategy :::: ", interestStrategy);

            vm.prank(admin);
            deployedContracts.lendingPoolConfigurator.batchInitReserve(initInputParams);

            inputConfigParams[0] = ATokensAndRatesHelper.ConfigureReserveInput({
                asset: address(mockToken),
                reserveType: false,
                baseLTV: 8000,
                liquidationThreshold: 8500,
                liquidationBonus: 10500,
                reserveFactor: 1500,
                borrowingEnabled: true
            });

            deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(
                address(deployedContracts.aTokensAndRatesHelper)
            );
            ATokensAndRatesHelper(deployedContracts.aTokensAndRatesHelper).configureReserves(
                inputConfigParams
            );
            deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(admin);
        }

        address[] memory aTokensW = new address[](1);

        (address _aTokenAddress,) = AsteraDataProvider(deployedContracts.asteraDataProvider)
            .getLpTokens(address(mockToken), false);
        console2.log("AToken ::::  ", _aTokenAddress);
        aTokensW[0] = address(AToken(_aTokenAddress).WRAPPER_ADDRESS());

        {
            IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
                new IMiniPoolConfigurator.InitReserveInput[](aTokensW.length);
            console2.log("Getting Mini pool: ");
            address miniPool = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);

            string memory tmpSymbol = ERC20(aTokensW[0]).symbol();
            string memory tmpName = ERC20(aTokensW[0]).name();

            address interestStrategy = configAddresses.volatileStrategy;
            // console2.log("[common]interestStartegy: ", interestStrategy);
            initInputParams[0] = IMiniPoolConfigurator.InitReserveInput({
                underlyingAssetDecimals: ERC20(aTokensW[0]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: aTokensW[0],
                underlyingAssetName: tmpName,
                underlyingAssetSymbol: tmpSymbol
            });

            vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin()));
            vm.expectRevert(bytes(Errors.RL_RESERVE_NOT_INITIALIZED));
            miniPoolContracts.miniPoolConfigurator.batchInitReserve(
                initInputParams, IMiniPool(miniPool)
            );

            vm.stopPrank();
        }
    }

    function testMiniPoolDeposits(uint256 amount, uint256 offset) public {
        /* Fuzz vector creation */
        address user = makeAddr("user");
        offset = bound(offset, 0, tokens.length - 1);
        TokenParams memory tokenParams =
            TokenParams(erc20Tokens[offset], commonContracts.aTokensWrapper[offset], 0);

        /* Assumptions */
        vm.assume(amount <= tokenParams.token.balanceOf(address(this)) / 2);
        vm.assume(amount > 10 ** tokenParams.token.decimals() / 100);

        /* Deposit tests */
        fixture_MiniPoolDeposit(amount, offset, user, tokenParams);
    }

    function testMiniPoolNormalBorrow(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows token
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard increased
         * 2. Total supply of debtToken shall increase
         * 3. Health of user's position shall decrease
         * 4. User shall have borrowed assets
         */

        /* Fuzz vectors */
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        console2.log("[collateral]Offset: ", collateralOffset);
        console2.log("[borrow]Offset: ", borrowOffset);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[collateralOffset],
            commonContracts.aTokensWrapper[collateralOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[borrowOffset],
            commonContracts.aTokensWrapper[borrowOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
        );
        /* Assumptions */
        amount = bound(
            amount,
            10 ** (borrowTokenParams.token.decimals() - 2),
            borrowTokenParams.token.balanceOf(address(this)) / 10
        );
        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );
        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralTokenParams, borrowTokenParams, user
        );
    }

    function testMiniPoolReserveFactors(
        uint256 amount,
        uint256 collateralOffset,
        uint256 borrowOffset,
        uint256 validReserveFactor
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows token
         * 3. Astera and pool owner treasuries are set
         * 4. Reserve factors are established to non-zero values
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard increased
         * 2. Total supply of debtToken shall increase
         * 3. Health of user's position shall decrease
         * 4. User shall have borrowed assets
         * 5. Astera treasury shall have some funds taken according to astera reserve factor
         * 6. Owner treasury shall have some funds taken according to owner reserve factor
         */

        /* Fuzz vectors */
        validReserveFactor = bound(validReserveFactor, 100, 1_500);
        collateralOffset = bound(collateralOffset, 0, tokens.length - 1);
        borrowOffset = bound(borrowOffset, 0, tokens.length - 1);
        console2.log("[collateral]Offset: ", collateralOffset);
        console2.log("[borrow]Offset: ", borrowOffset);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[collateralOffset],
            commonContracts.aTokensWrapper[collateralOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[borrowOffset],
            commonContracts.aTokensWrapper[borrowOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[borrowOffset]))
        );
        /* Assumptions */
        amount = bound(
            amount,
            10 ** (borrowTokenParams.token.decimals() - 2),
            borrowTokenParams.token.balanceOf(address(this)) / 10
        );
        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );

        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(
            makeAddr("ownerTreasury"), IMiniPool(miniPool)
        );
        vm.stopPrank();

        address treasury = address(deployedContracts.treasury);
        console2.log("Treasury 1: ", treasury);
        console2.log(
            "Treasury 2: ", miniPoolContracts.miniPoolAddressesProvider.getMiniPoolAsteraTreasury()
        );
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setAsteraTreasury(treasury);
        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        console2.log("\n>> First borrowing <<\n");
        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralTokenParams, borrowTokenParams, user
        );
        DynamicData memory dynamicData = deployedContracts
            .asteraDataProvider
            .getMpReserveDynamicData(address(borrowTokenParams.token), 0);
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setAsteraReserveFactor(
            address(borrowTokenParams.token), validReserveFactor, IMiniPool(miniPool)
        );
        uint256 previousVariableBorrowIndex = dynamicData.variableBorrowIndex;
        vm.stopPrank();

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
            address(borrowTokenParams.token), validReserveFactor - 100, IMiniPool(miniPool)
        );

        skip(1 days);

        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );

        console2.log("1.Treasury balance: ", aErc6909Token.balanceOf(treasury, 1128 + borrowOffset));
        uint256 scaledVariableDebt = aErc6909Token.scaledTotalSupply(2128 + borrowOffset);

        console2.log("\n>> Second borrowing MiniPoolBorrow with reserve factor <<\n");
        fixture_miniPoolBorrow(
            amount, collateralOffset, borrowOffset, collateralTokenParams, borrowTokenParams, user
        );
        dynamicData = deployedContracts.asteraDataProvider.getMpReserveDynamicData(
            address(borrowTokenParams.token), 0
        );
        console2.log("2.Treasury balance: ", aErc6909Token.balanceOf(treasury, 1128 + borrowOffset));
        console2.log("Balance of token must be greater than before borrow");
        console2.log("variableBorrowIndex: ", dynamicData.variableBorrowIndex);
        console2.log("previousVariableBorrowIndex: ", previousVariableBorrowIndex);
        console2.log("scaledVariableDebt: ", scaledVariableDebt);

        assertApproxEqAbs(
            aErc6909Token.balanceOf(treasury, 1128 + borrowOffset),
            (
                scaledVariableDebt.rayMul(dynamicData.variableBorrowIndex)
                    - scaledVariableDebt.rayMul(previousVariableBorrowIndex)
            ).percentMul(validReserveFactor),
            1
        );

        assertApproxEqAbs(
            aErc6909Token.balanceOf(makeAddr("ownerTreasury"), 1128 + borrowOffset),
            (
                scaledVariableDebt.rayMul(dynamicData.variableBorrowIndex)
                    - scaledVariableDebt.rayMul(previousVariableBorrowIndex)
            ).percentMul(validReserveFactor - 100),
            1
        );
    }

    struct TestParams {
        uint256 depositAmount;
        uint256 borrowAmount;
        uint256 collateralOffset;
        uint256 borrowOffset;
        uint256 asteraReserveFactor;
        uint256 ownerReserveFactor;
        address asteraTreasury;
        address ownerTreasury;
    }

    struct DynamicParams {
        uint256 scaledVariableDebt;
        uint256 scaledTotalSupply;
        uint256 asteraTreasuryAmountToMint;
        uint256 ownerTreasuryAmountToMint;
    }

    function testMiniPoolReserveFactorsFixedNumber() public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows token
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard increased
         * 2. Total supply of debtToken shall increase
         * 3. Health of user's position shall decrease
         * 4. User shall have borrowed assets
         * 5. Treasury shall have some funds taken according to reserve factor
         */

        /* Fixed values */
        TestParams memory testParams;
        DynamicParams memory dynamicParams;
        testParams.depositAmount = 100_000e6; // 100 000 USDC
        testParams.borrowAmount = 1e8; // 1 BTC
        testParams.collateralOffset = 0; // USDC
        testParams.borrowOffset = 1; // BTC
        testParams.asteraReserveFactor = 500; // 5%
        testParams.ownerReserveFactor = 200; //2%
        testParams.asteraTreasury = address(deployedContracts.treasury);
        testParams.ownerTreasury = makeAddr("ownerTreasury");

        console2.log("[collateral]Offset: ", testParams.collateralOffset);
        console2.log("[borrow]Offset: ", testParams.borrowOffset);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[testParams.collateralOffset],
            commonContracts.aTokensWrapper[testParams.collateralOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[testParams.collateralOffset]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[testParams.borrowOffset],
            commonContracts.aTokensWrapper[testParams.borrowOffset],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[testParams.borrowOffset]))
        );

        deal(address(collateralTokenParams.token), user, 2 * testParams.depositAmount);

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setAsteraTreasury(testParams.asteraTreasury);
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerTreasuryToMiniPool(
            testParams.ownerTreasury, IMiniPool(miniPool)
        );
        vm.stopPrank();

        IAERC6909 aErc6909Token =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        console2.log("\n>> First borrowing <<\n");
        fixture_depositTokensToMiniPool(
            2 * testParams.borrowAmount,
            1128 + testParams.borrowOffset,
            makeAddr("LP"),
            borrowTokenParams,
            aErc6909Token
        );
        fixture_depositTokensToMiniPool(
            testParams.depositAmount,
            1128 + testParams.collateralOffset,
            user,
            collateralTokenParams,
            aErc6909Token
        );
        vm.startPrank(user);
        IMiniPool(miniPool).borrow(
            address(borrowTokenParams.token), false, testParams.borrowAmount, user
        );
        vm.stopPrank();

        DynamicData memory dynamicData = deployedContracts
            .asteraDataProvider
            .getMpReserveDynamicData(address(borrowTokenParams.token), 0);
        uint256 previousVariableBorrowIndex = dynamicData.variableBorrowIndex;
        vm.startPrank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setAsteraReserveFactor(
            address(borrowTokenParams.token), testParams.asteraReserveFactor, IMiniPool(miniPool)
        );
        vm.stopPrank();

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin(0));
        miniPoolContracts.miniPoolConfigurator.setMinipoolOwnerReserveFactor(
            address(borrowTokenParams.token), testParams.ownerReserveFactor, IMiniPool(miniPool)
        );

        skip(10 days);

        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );

        console2.log(
            "1.Treasury balance: ",
            aErc6909Token.balanceOf(testParams.asteraTreasury, 1128 + testParams.borrowOffset)
        );
        dynamicParams.scaledVariableDebt =
            aErc6909Token.scaledTotalSupply(2128 + testParams.borrowOffset);
        dynamicParams.scaledTotalSupply =
            aErc6909Token.scaledTotalSupply(1128 + testParams.borrowOffset);

        console2.log("\n>> Second borrowing MiniPoolBorrow with reserve factor <<\n");
        console2.log(
            "1. Total balance: ", aErc6909Token.scaledTotalSupply(1128 + testParams.borrowOffset)
        );
        fixture_depositTokensToMiniPool(
            2 * testParams.borrowAmount,
            1128 + testParams.borrowOffset,
            makeAddr("LP"),
            borrowTokenParams,
            aErc6909Token
        );
        console2.log(
            "2. Total balance: ", aErc6909Token.scaledTotalSupply(1128 + testParams.borrowOffset)
        );
        fixture_depositTokensToMiniPool(
            testParams.depositAmount,
            1128 + testParams.collateralOffset,
            user,
            collateralTokenParams,
            aErc6909Token
        );
        vm.startPrank(user);
        IMiniPool(miniPool).borrow(
            address(borrowTokenParams.token), false, testParams.borrowAmount, user
        );
        vm.stopPrank();

        dynamicData = deployedContracts.asteraDataProvider.getMpReserveDynamicData(
            address(borrowTokenParams.token), 0
        );
        console2.log(
            "2.Treasury balance: ",
            aErc6909Token.balanceOf(testParams.asteraTreasury, 1128 + testParams.borrowOffset)
        );
        console2.log("Balance of token must be greater than before borrow");
        console2.log(
            "Astera treasury balance: ",
            aErc6909Token.balanceOf(testParams.asteraTreasury, 1128 + testParams.borrowOffset)
        );
        console2.log(
            "OwnerTreasury balance: ",
            aErc6909Token.balanceOf(testParams.ownerTreasury, 1128 + testParams.borrowOffset)
        );

        dynamicParams.asteraTreasuryAmountToMint = (
            dynamicParams.scaledVariableDebt.rayMul(dynamicData.variableBorrowIndex)
                - dynamicParams.scaledVariableDebt.rayMul(previousVariableBorrowIndex)
        ).percentMul(testParams.asteraReserveFactor);

        dynamicParams.ownerTreasuryAmountToMint = (
            dynamicParams.scaledVariableDebt.rayMul(dynamicData.variableBorrowIndex)
                - dynamicParams.scaledVariableDebt.rayMul(previousVariableBorrowIndex)
        ).percentMul(testParams.ownerReserveFactor);

        assertApproxEqAbs(
            aErc6909Token.balanceOf(testParams.asteraTreasury, 1128 + testParams.borrowOffset),
            dynamicParams.asteraTreasuryAmountToMint,
            1
        );
        assertApproxEqAbs(
            aErc6909Token.balanceOf(testParams.ownerTreasury, 1128 + testParams.borrowOffset),
            dynamicParams.ownerTreasuryAmountToMint,
            1
        );
        // @issue -> failing

        assertApproxEqAbs(
            dynamicParams.scaledTotalSupply
                + (
                    2 * testParams.borrowAmount + dynamicParams.asteraTreasuryAmountToMint
                        + dynamicParams.ownerTreasuryAmountToMint
                ).rayDiv(dynamicData.liquidityIndex),
            aErc6909Token.scaledTotalSupply(1128 + testParams.borrowOffset),
            1
        );
    }

    function testMiniPoolNormalBorrowWithDebtThreshold(
        uint256 amountInUsd,
        uint256 offset1,
        uint256 offset2
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in MiniPool must be configured
         * 2. Debt threshold is set to non zero values
         * Test Scenario:
         * 1. User adds token as collateral into the miniPool
         * 2. User borrows token
         * Invariants:
         * 1. Balance of debtToken for user in IERC6909 standard increased
         * 2. Total supply of debtToken shall increase
         * 3. Health of user's position shall decrease
         * 4. User shall have borrowed assets
         */
        amountInUsd = bound(amountInUsd, 1 ether, 200_000 ether); // $1 - $200k
        offset1 = bound(offset1, 0, tokens.length - 1);
        offset2 = bound(offset2, 0, tokens.length - 1);

        /* Test vars */
        address user = makeAddr("user");
        TokenParams memory collateralTokenParams = TokenParams(
            erc20Tokens[offset1],
            commonContracts.aTokensWrapper[offset1],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[offset1]))
        );
        TokenParams memory borrowTokenParams = TokenParams(
            erc20Tokens[offset2],
            commonContracts.aTokensWrapper[offset2],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[offset2]))
        );

        /* Fuzz vectors */
        uint256 amount = ((amountInUsd / borrowTokenParams.price) * 10 ** PRICE_FEED_DECIMALS)
            / 10 ** (18 - borrowTokenParams.token.decimals());
        console2.log("Calculated debt threshold: %s %s", amount, borrowTokenParams.token.symbol());

        uint256 debtThreshold = amount / (10 ** (borrowTokenParams.token.decimals() - 6));

        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setMinDebtThreshold(
            debtThreshold, IMiniPool(miniPool)
        );

        /* Assumptions */
        // amount = IMiniPool(miniPool).minDebtThreshold(borrowTokenParams.token.decimals());
        deal(
            address(borrowTokenParams.token), user, borrowTokenParams.token.balanceOf(address(this))
        );
        deal(
            address(collateralTokenParams.token),
            user,
            collateralTokenParams.token.balanceOf(address(this))
        );
        console2.log(">>> Bootstraping minDebt %s for %s", amount, borrowTokenParams.token.symbol());
        fixture_miniPoolBorrow(
            amount, offset1, offset2, collateralTokenParams, borrowTokenParams, user
        );

        console2.log("Time travel 1");
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        /* Assumptions */
        address otherUser = makeAddr("otherUser");
        amount = bound(
            amount,
            10 ** (borrowTokenParams.token.decimals() - 2),
            borrowTokenParams.token.balanceOf(address(this)) / 10
        );
        deal(address(collateralTokenParams.token), otherUser, 1e26);
        console2.log(">>> Real borrow", amount);
        fixture_miniPoolBorrow(
            amount, offset1, offset2, collateralTokenParams, borrowTokenParams, otherUser
        );
    }
}
