// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import "contracts/protocol/lendingpool/minipool/MiniPoolDefaultReserveInterestRate.sol";

import "forge-std/StdUtils.sol";
// import {ILendingPool} from "contracts/interfaces/ILendingPool.sol";

contract MiniPoolTest is Common {
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;
    DeployedMiniPoolContracts miniPoolContracts;

    event Deposit(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount);
    event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);
    event Borrow(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount, uint256 borrowRate);
    event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount);

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        configAddresses = ConfigAddresses(
            address(deployedContracts.stableStrategy),
            address(deployedContracts.volatileStrategy),
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );
        fixture_configureProtocol(
            address(deployedContracts.lendingPool),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider,
            deployedContracts.protocolDataProvider
        );
        (grainTokens, variableDebtTokens) =
            fixture_getGrainTokensAndDebts(tokens, deployedContracts.protocolDataProvider);
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, tokensWhales, address(this));
        miniPoolContracts = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool)
        );


        miniPoolContracts.miniPoolAddressesProvider.deployMiniPool();
        address mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        assertNotEq(mp, address(0));

        address aToken = miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp);
        assertNotEq(aToken, address(0));
        address Atoken0 = miniPoolContracts.miniPoolAddressesProvider.getAERC6909BYID(0);
        assertEq(aToken, Atoken0);

        IMiniPoolConfigurator.InitReserveInput[] memory inputs = new IMiniPoolConfigurator.InitReserveInput[](2);

        inputs[0] = IMiniPoolConfigurator.InitReserveInput({
            underlyingAssetDecimals: 18,
            interestRateStrategyAddress: configAddresses.stableStrategy,
            underlyingAsset: address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            underlyingAssetName: "DAI",
            underlyingAssetSymbol: "DAI"
        });

        inputs[1] = IMiniPoolConfigurator.InitReserveInput({
            underlyingAssetDecimals: 6,
            interestRateStrategyAddress: configAddresses.stableStrategy,
            underlyingAsset: address(grainTokens[0]),
            underlyingAssetName: grainTokens[0].name(),
            underlyingAssetSymbol: grainTokens[0].symbol()
        });
        assertEq(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator(), 
                address(miniPoolContracts.miniPoolConfigurator));


        vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin()));



        miniPoolContracts.miniPoolConfigurator.batchInitReserve(inputs, IMiniPool(mp));
        //ID 1000 -> grainUSDC
        //ID 1128 -> dai

        console.log(IAERC6909(aToken).getUnderlyingAsset(1000));
        console.log(IAERC6909(aToken).name(1000), IAERC6909(aToken).symbol(1000), IAERC6909(aToken).decimals(1000));
        console.log(IAERC6909(aToken).getUnderlyingAsset(1128));
        console.log(IAERC6909(aToken).name(1128), IAERC6909(aToken).symbol(1128), IAERC6909(aToken).decimals(1128));

        miniPoolContracts.miniPoolConfigurator.configureReserveAsCollateral(
            address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            true,
            9500,
            9700,
            10100,
            IMiniPool(mp)
        );

        miniPoolContracts.miniPoolConfigurator.configureReserveAsCollateral(
            address(grainTokens[0]),
            true,
            9500,
            9700,
            10100,
            IMiniPool(mp)
        );

        miniPoolContracts.miniPoolConfigurator.activateReserve(
            address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            true,
            IMiniPool(mp)
        );

        miniPoolContracts.miniPoolConfigurator.activateReserve(
            address(grainTokens[0]),
            true,
            IMiniPool(mp)
        );

        miniPoolContracts.miniPoolConfigurator.enableBorrowingOnReserve(
            address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            true,
            IMiniPool(mp)
        );

        miniPoolContracts.miniPoolConfigurator.enableBorrowingOnReserve(
            address(grainTokens[0]),
            true,
            IMiniPool(mp)
        );

        uint256[] memory ssStrat = new uint256[](4);
        ssStrat[0] = uint256(.75e27);
        ssStrat[1] = uint256(0e27);
        ssStrat[2] = uint256(.01e27);
        ssStrat[3] = uint256(.10e27);

        MiniPoolDefaultReserveInterestRateStrategy IRS = new MiniPoolDefaultReserveInterestRateStrategy(
            IMiniPoolAddressesProvider(address(miniPoolContracts.miniPoolAddressesProvider)),
            ssStrat[0],
            ssStrat[1],
            ssStrat[2],
            ssStrat[3]
        );

        miniPoolContracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
            address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            true,
            address(IRS),
            IMiniPool(mp)
        );

        miniPoolContracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
            address(grainTokens[0]),
            true,
            address(IRS),
            IMiniPool(mp)
        );


        vm.stopPrank();

    }

  

    function testDeposits() public {
        address whale = 0xacD03D601e5bB1B275Bb94076fF46ED9D753435A;
        vm.label(whale, "Whale");
        address daiWhale = 0xD28843E10C3795E51A6e574378f8698aFe803029;
        vm.label(daiWhale, "DaiWhale");

        address user = makeAddr("user");
        uint256 mpId = 0;
        address mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(mpId);
        vm.label(mp, "MiniPool");
        IAERC6909 ATOKEN = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp));
        vm.label(address(ATOKEN), "ATOKEN");


        IERC20 usdc = erc20Tokens[0];
        IERC20 grainUSDC = grainTokens[0];
        uint256 amount = 5E8; //bound(amount, 1E6, 1E13); /* $5k */ // consider fuzzing here
        uint256 usdcAID = 1000;
        // uint256 usdcDID = 2000;
        // uint256 daiAID = 1128;
        // uint256 daiDID = 2128;
        IERC20 dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

        vm.prank(whale);
        usdc.transfer(user, amount);

        console.log("whale balance: ", dai.balanceOf(daiWhale));
        vm.prank(daiWhale);
        dai.transfer(user, amount*1E12);

        vm.startPrank(user);

        usdc.approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(address(usdc), false, amount, user);
        assertEq(usdc.balanceOf(user), 0);

        uint256 grainUSDCDepositAmount = grainUSDC.balanceOf(user);
        console.log("GrainUSDC balance: ", grainUSDCDepositAmount);
        grainUSDC.approve(address(mp), grainUSDCDepositAmount);
        IMiniPool(mp).deposit(address(grainUSDC), true, grainUSDCDepositAmount, user);
        assertEq(grainUSDC.balanceOf(address(this)), 0);

        uint256 grainUSDC6909balance = ATOKEN.scaledTotalSupply(usdcAID);
        assertEq(grainUSDC6909balance, amount);


        dai.approve(address(mp), amount*1E12);
        IMiniPool(mp).deposit(address(dai), true, amount*1E12, user);
        assertEq(dai.balanceOf(user), 0);

        uint256 dai6909balance = ATOKEN.scaledTotalSupply(1128);
        assertEq(dai6909balance, amount*1E12);

    }

    function testWithdrawalsZeroDebt() public {
        testDeposits();
        IERC20 dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
        address user = makeAddr("user");
        uint256 mpId = 0;
        address mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(mpId);
        vm.label(mp, "MiniPool");
        IAERC6909 ATOKEN = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp));
        vm.label(address(ATOKEN), "ATOKEN");

        IMiniPool(mp).withdraw(address(dai), false, 1E12, user);
        assertEq(dai.balanceOf(user), 1E12);
        IMiniPool(mp).withdraw(address(grainTokens[0]), false, 1E6, user);
        assertEq(grainTokens[0].balanceOf(user), 1E6);

    }

    function testTransferCollateral() public {
        testDeposits();
        IERC20 dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
        address user = makeAddr("user");
        address user2 = makeAddr("user2");
        uint256 mpId = 0;
        address mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(mpId);
        vm.label(mp, "MiniPool");
        IAERC6909 ATOKEN = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp));
        vm.label(address(ATOKEN), "ATOKEN");

        ATOKEN.transfer(user2, 1000, 1E6);
        ATOKEN.transfer(user2, 1128, 1E12);

    }

    function testBorrowRepay() public {
        testDeposits();
        address user = makeAddr("user");
        address user2 = makeAddr("user2");
        uint mpId = 0;
        address mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(mpId);
        vm.label(mp, "MiniPool");
        IAERC6909 ATOKEN = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp));
        vm.label(address(ATOKEN), "ATOKEN");
        require(ATOKEN.balanceOf(user, 1000) > 0, "No balance");

        IMiniPool(mp).borrow(address(grainTokens[0]), true, 500E6, user);
        uint256 userBalance = grainTokens[0].balanceOf(user);
        require(userBalance > 0, "No balance");
        console.log("User balance: ", userBalance);
        require(ATOKEN.scaledTotalSupply(2000) > 0, "No balance");
        console.log("ATOKEN balance: ", ATOKEN.scaledTotalSupply(2000));
        vm.expectRevert(); //Test that you cannot transfer a debtTokenID
        ATOKEN.transfer(user2, 2000, 1E6);

        skip(36000);
        {
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )=IMiniPool(mp).getUserAccountData(user);
        console.log("User data: totalCollateralETH ", totalCollateralETH);
        console.log("User data: totalDebtETH ",totalDebtETH);
        console.log("User data: availableBorrowsETH ",availableBorrowsETH);
        console.log("User data: currentLiquidationThreshold ",currentLiquidationThreshold);
        console.log("User data: ltv ",ltv);
        console.log("User data: healthFactor ", healthFactor);
        }
        IERC20(grainTokens[0]).approve(address(mp), 500E6);
        IMiniPool(mp).repay(address(grainTokens[0]), true, 500E6, user);
        console.log("User balance: ", grainTokens[0].balanceOf(user));
        console.log("ATOKEN balance: ", ATOKEN.balanceOf(user, 2000));

    }

    struct flowLimiterTestLocalVars {
        IERC20 usdc;
        IERC20 grainUSDC;
        IERC20 debtUSDC;
        IERC20 dai;
        uint256 mpId;
        address mp;
        IAERC6909 ATOKEN;
        address user;
        address whaleUser;
        address usdcWhale;
        address daiWhale;
        uint256 amount;
        address flowLimiter;
    }

    function testFlowLimiter() public {
        flowLimiterTestLocalVars memory vars;
        vars.user = makeAddr("user");
        vars.mpId = 0;
        vars.mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(vars.mpId);
        vm.label(vars.mp, "MiniPool");
        vars.ATOKEN = IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(vars.mp));
        vm.label(address(vars.ATOKEN), "ATOKEN");

        vars.whaleUser = makeAddr("whaleUser");

        vars.usdcWhale = 0xacD03D601e5bB1B275Bb94076fF46ED9D753435A;
        vm.label(vars.usdcWhale, "Whale");
        vars.daiWhale = 0xD28843E10C3795E51A6e574378f8698aFe803029;
        vm.label(vars.daiWhale, "DaiWhale");


        vars.usdc = erc20Tokens[0];
        vars.grainUSDC = grainTokens[0];
        vars.debtUSDC = variableDebtTokens[0];
        vars.amount = 5E8; //bound(amount, 1E6, 1E13); /* $500 */ // consider fuzzing here
        uint256 usdcAID = 1000;
        // uint256 usdcDID = 2000;
        // uint256 daiAID = 1128;
        // uint256 daiDID = 2128;
        vars.dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
        
        vm.prank(vars.usdcWhale);
        vars.usdc.transfer(vars.whaleUser, vars.amount*1000);

        console.log("whale balance: ", vars.dai.balanceOf(vars.daiWhale)/(10**18));
        vm.prank(vars.daiWhale);
        vars.dai.transfer(vars.user, vars.amount*1E14); // 50000 DAI

        vm.startPrank(vars.whaleUser);
        vars.usdc.approve(address(deployedContracts.lendingPool), vars.amount*1000); //500000 USDC
        deployedContracts.lendingPool.deposit(address(vars.usdc), false, vars.amount*1000, vars.whaleUser);
        vm.stopPrank();
        
        vm.startPrank(vars.user);
        vars.dai.approve(address(vars.mp), vars.amount*1E14);
        console.log("User balance: ", vars.dai.balanceOf(vars.user)/(10**18));
        console.log("User depositAmount: ", vars.amount*1E14/(10**18));
        IMiniPool(vars.mp).deposit(address(vars.dai), true, vars.amount*1E14, vars.user);
        vm.stopPrank();

        vars.flowLimiter = address(miniPoolContracts.flowLimiter);

        vm.prank(address(miniPoolContracts.miniPoolAddressesProvider));
        miniPoolContracts.flowLimiter.setFlowLimit(address(vars.usdc), vars.mp, vars.amount*100);// 50000 USDC

        vm.startPrank(vars.user);
        IMiniPool(vars.mp).borrow(address(vars.grainUSDC),false, vars.amount*94, vars.user); // 47000 USDC
        assertEq(vars.debtUSDC.balanceOf(vars.mp), vars.amount*94);
        DataTypes.ReserveData memory reserveData = deployedContracts.lendingPool.getReserveData(address(vars.usdc), false);
        uint128 currentLiquidityRate = reserveData.currentLiquidityRate;
        uint128 currentVariableBorrowRate = reserveData.currentVariableBorrowRate;
        uint128 delta = currentVariableBorrowRate - currentLiquidityRate;
        console.log("CurrentLiquidityRate: ", currentLiquidityRate);
        console.log("CurrentVariableBorrowRate: ", currentVariableBorrowRate);
        console.log("Delta: ", delta);
        DataTypes.MiniPoolReserveData memory mpReserveData = IMiniPool(vars.mp).getReserveData(address(grainTokens[0]), false);
        uint128 mpCurrentLiquidityRate = mpReserveData.currentLiquidityRate;
        uint128 mpCurrentVariableBorrowRate = mpReserveData.currentVariableBorrowRate;
        assertGe(mpCurrentVariableBorrowRate, delta );


        IERC20(vars.grainUSDC).approve(address(vars.mp), vars.amount*94);
        IMiniPool(vars.mp).repay(address(vars.grainUSDC),false, vars.amount*94, vars.user); // 47000 USDC



        assertEq(vars.debtUSDC.balanceOf(vars.mp), 0);



    }
}
