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

    // function testBorrowRepay() public {
    //     testDeposits();
    // }

    // function testBorrowRepay() public {
    //     address user = makeAddr("user");

    //     IERC20 usdc = erc20Tokens[0];
    //     IERC20 wbtc = erc20Tokens[1];
    //     uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

    //     uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc)); // 6e12 / 1e6; /* $60k / $1 */ // TODO - price feeds
    //     uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
    //     uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
    //     (, uint256 usdcLtv,,,,,,,) =
    //         deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), false);
    //     // (, uint256 wbtcLtv,,,,,,,) =
    //     //     deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), false);
    //     console.log("LTV: ", usdcLtv);
    //     uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;

    //     console.log("Price: ", wbtcPrice);
    //     uint256 wbtcMaxBorrowAmountWithUsdcCollateral = (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
    //     require(wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc");
    //     console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
    //     uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral * 15 / 10;

    //     /* Main user deposits usdc and wants to borrow */
    //     usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
    //     deployedContracts.lendingPool.deposit(address(usdc), false, usdcDepositAmount, address(this));

    //     /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
    //     wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
    //     deployedContracts.lendingPool.deposit(address(wbtc), false, wbtcDepositAmount, user);

    //     uint256 wbtcBalanceBeforeBorrow = wbtc.balanceOf(address(this));
    //     console.log("Wbtc balance before: ", wbtcBalanceBeforeBorrow);

    //     /* Main user borrows maxPossible amount of wbtc */
    //     // vm.expectEmit(true, true, true, true);
    //     // emit Borrow(
    //     //     address(wbtc),
    //     //     address(this),
    //     //     address(this),
    //     //     wbtcMaxBorrowAmountWithUsdcCollateral,
    //     //     1251838485129347319607618207 // TODO
    //     // );
    //     deployedContracts.lendingPool.borrow(address(wbtc), false, wbtcMaxBorrowAmountWithUsdcCollateral, address(this));
    //     /* Main user's balance should be: initial amount + borrowed amount */
    //     assertEq(wbtcBalanceBeforeBorrow + wbtcMaxBorrowAmountWithUsdcCollateral, wbtc.balanceOf(address(this)));
    //     console.log("Wbtc balance after: ", wbtc.balanceOf(address(this)));
    //     /* Main user repays his debt */

    //     wbtc.approve(address(deployedContracts.lendingPool), wbtcMaxBorrowAmountWithUsdcCollateral);
    //     vm.expectEmit(true, true, true, true);
    //     emit Repay(address(wbtc), address(this), address(this), wbtcMaxBorrowAmountWithUsdcCollateral);
    //     deployedContracts.lendingPool.repay(address(wbtc), false, wbtcMaxBorrowAmountWithUsdcCollateral, address(this));
    //     /* Main user's balance should be the same as before borrowing */
    //     assertEq(wbtcBalanceBeforeBorrow, wbtc.balanceOf(address(this)));
    //     console.log("Wbtc balance end: ", wbtc.balanceOf(address(this)));
    // }

    // function testBorrowTooBigForUsersCollateral() public {
    //     address user = makeAddr("user");

    //     ERC20 usdc = erc20Tokens[0];
    //     ERC20 wbtc = erc20Tokens[1];
    //     uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

    //     uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc)); // 6e12 / 1e6; /* $60k / $1 */ // TODO - price feeds
    //     uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
    //     uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
    //     console.log("usdc value: ", usdcDepositValue);
    //     (, uint256 usdcLtv,,,,,,,) =
    //         deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), false);
    //     // (, uint256 wbtcLtv,,,,,,,) =
    //     //     deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), false);
    //     console.log("LTV: ", usdcLtv);
    //     uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;
    //     uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
    //     console.log("Price: ", wbtcPrice);
    //     {
    //         uint256 wbtcMaxBorrowAmountRaw = (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
    //         wbtcMaxBorrowAmountWithUsdcCollateral = (wbtc.decimals() > usdc.decimals())
    //             ? wbtcMaxBorrowAmountRaw * (10 ** (wbtc.decimals() - usdc.decimals()))
    //             : wbtcMaxBorrowAmountRaw / (10 ** (usdc.decimals() - wbtc.decimals()));
    //         require(wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc");
    //         console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
    //     }
    //     {
    //         uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral * 15 / 10;
    //         /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
    //         wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
    //         deployedContracts.lendingPool.deposit(address(wbtc), false, wbtcDepositAmount, user);
    //     }

    //     /* Main user deposits usdc and wants to borrow */
    //     usdc.approve(address(deployedContracts.lendingPool), usdcDepositValue);
    //     deployedContracts.lendingPool.deposit(address(usdc), false, usdcDepositValue, address(this));

    //     /* Main user borrows maxPossible amount of wbtc */
    //     vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    //     deployedContracts.lendingPool.borrow(
    //         address(wbtc), false, wbtcMaxBorrowAmountWithUsdcCollateral + 100, address(this)
    //     );
    //     // Issue: Why we not having error for +1 ?
    // }

    // function testBorrowTooBigForProtocolsCollateral() public {
    //     address user = makeAddr("user");

    //     ERC20 usdc = erc20Tokens[0];
    //     ERC20 wbtc = erc20Tokens[1];
    //     uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here

    //     uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc)); // 6e12 / 1e6; /* $60k / $1 */ // TODO - price feeds
    //     uint256 usdcPrice = oracle.getAssetPrice(address(usdc));
    //     uint256 usdcDepositValue = usdcDepositAmount * usdcPrice / (10 ** PRICE_FEED_DECIMALS);
    //     console.log("usdc value: ", usdcDepositValue);
    //     (, uint256 usdcLtv,,,,,,,) =
    //         deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), false);
    //     // (, uint256 wbtcLtv,,,,,,,) =
    //     //     deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), false);
    //     console.log("LTV: ", usdcLtv);
    //     uint256 usdcMaxBorrowValue = usdcLtv * usdcDepositValue / 10_000;
    //     uint256 wbtcMaxBorrowAmountWithUsdcCollateral;
    //     console.log("Price: ", wbtcPrice);
    //     {
    //         wbtcMaxBorrowAmountWithUsdcCollateral = fixture_calcMaxAmountToBorrowBasedOnCollateral(
    //             usdcMaxBorrowValue, wbtcPrice, usdc.decimals(), wbtc.decimals()
    //         );
    //         require(wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc");
    //         console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
    //     }
    //     uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithUsdcCollateral - 1;

    //     /* Main user deposits usdc and wants to borrow */
    //     usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
    //     deployedContracts.lendingPool.deposit(address(usdc), false, usdcDepositAmount, address(this));

    //     /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
    //     wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
    //     deployedContracts.lendingPool.deposit(address(wbtc), false, wbtcDepositAmount, user);

    //     /* Main user borrows maxPossible amount of wbtc */
    //     vm.expectRevert();
    //     //vm.expectRevert(bytes(Errors.LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW)); // Issue: over/underflow instead of LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW
    //     deployedContracts.lendingPool.borrow(address(wbtc), false, wbtcMaxBorrowAmountWithUsdcCollateral, address(this));
    // }

    // function testUseReserveAsCollateral() public {
    //     address user = makeAddr("user");

    //     // add for loop for all tokens
    //     IERC20 usdc = erc20Tokens[0];
    //     IERC20 wbtc = erc20Tokens[1];
    //     uint256 usdcDepositAmount = 5e9; /* $5k */ // consider fuzzing here
    //     uint256 wbtcPriceInUsdc = oracle.getAssetPrice(address(wbtc)); // 6e12 / 1e6; /* $60k / $1 */ // TODO - price feeds
    //     (, uint256 usdcLtv,,,,,,,) =
    //         deployedContracts.protocolDataProvider.getReserveConfigurationData(address(usdc), false);
    //     // (, uint256 wbtcLtv,,,,,,,) =
    //     //     deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), false);
    //     console.log("LTV: ", usdcLtv);
    //     uint256 usdcMaxBorrowAmount = usdcLtv * usdcDepositAmount / 10_000;

    //     console.log("Price: ", wbtcPriceInUsdc);
    //     uint256 wbtcMaxBorrowAmountWithUsdcCollateral = usdcMaxBorrowAmount * 1e10 / wbtcPriceInUsdc;
    //     require(wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithUsdcCollateral, "Too less wbtc");
    //     console.log("Max to borrow: ", wbtcMaxBorrowAmountWithUsdcCollateral);
    //     uint256 wbtcDepositAmount = wbtc.balanceOf(address(this));

    //     /* Main user deposits usdc and wants to borrow */
    //     usdc.approve(address(deployedContracts.lendingPool), usdcDepositAmount);
    //     deployedContracts.lendingPool.deposit(address(usdc), false, usdcDepositAmount, address(this));

    //     /* Other user deposits wbtc thanks to that there is enaugh funds to borrow */
    //     wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
    //     deployedContracts.lendingPool.deposit(address(wbtc), false, wbtcDepositAmount, user);

    //     uint256 usdcBalanceBeforeBorrow = usdc.balanceOf(address(this));
    //     console.log("Usdc balance before: ", usdcBalanceBeforeBorrow);

    //     deployedContracts.lendingPool.setUserUseReserveAsCollateral(address(usdc), false, false);
    //     vm.expectRevert(bytes(Errors.VL_COLLATERAL_BALANCE_IS_0));
    //     deployedContracts.lendingPool.borrow(address(usdc), false, usdcMaxBorrowAmount, address(this));

    //     deployedContracts.lendingPool.setUserUseReserveAsCollateral(address(usdc), false, true);
    //     /* Main user borrows maxPossible amount of wbtc */
    //     vm.expectEmit(true, true, true, true);
    //     emit Borrow(
    //         address(usdc),
    //         address(this),
    //         address(this),
    //         usdcMaxBorrowAmount,
    //         40000000000000000000000000 // TODO
    //     );
    //     deployedContracts.lendingPool.borrow(address(usdc), false, usdcMaxBorrowAmount, address(this));
    //     /* Main user's balance should be: initial amount + borrowed amount */
    //     assertEq(usdcBalanceBeforeBorrow + usdcMaxBorrowAmount, usdc.balanceOf(address(this)));
    //     console.log("Usdc balance after: ", usdc.balanceOf(address(this)));
    // }
}
