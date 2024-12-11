// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IERC20, ERC20} from "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {DeployedContracts, PoolAddressesProviderConfig} from "../DeployDataTypes.s.sol";

import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {AToken} from "contracts/protocol/tokenization/ERC20/AToken.sol";
import {ATokenERC6909} from "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import {VariableDebtToken} from "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import {IAERC6909} from "contracts/interfaces/IAERC6909.sol";
import {Oracle} from "contracts/protocol/core/Oracle.sol";
import {Cod3xLendDataProvider} from "contracts/misc/Cod3xLendDataProvider.sol";
import {StaticData, DynamicData} from "contracts/interfaces/ICod3xLendDataProvider.sol";
import {IMiniPool} from "contracts/interfaces/IMiniPool.sol";

import {DefaultReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import {PiReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";
import {MiniPoolDefaultReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import {MiniPoolPiReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolPiReserveInterestRateStrategy.sol";
import {MintableERC20} from "contracts/mocks/tokens/MintableERC20.sol";
import {LendingPool} from "contracts/protocol/core/lendingpool/LendingPool.sol";
import {LendingPoolConfigurator} from
    "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
// import "contracts/protocol/core/minipool/MiniPool.sol";
import {MiniPoolAddressesProvider} from
    "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import {MiniPoolConfigurator} from "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import {LendingPoolAddressesProvider} from
    "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import {AddAssetsLocal} from "./4_AddAssetsLocal.s.sol";

import "lib/forge-std/src/console.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";

contract TestBasicActions is Script, Test {
    using stdJson for string;
    using WadRayMath for uint256;

    address constant FOUNDRY_DEFAULT = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    DeployedContracts contracts;

    struct Users {
        address user1;
        address user2;
        address user3;
        address user4;
        address user5;
        address user6;
        address user7;
        address user8;
        address user9;
    }

    struct TokenParams {
        ERC20 token;
        AToken aToken;
    }

    struct TokenTypes {
        ERC20 token;
        AToken aToken;
        VariableDebtToken debtToken;
    }

    uint256 constant RAY_DECIMALS = 27;
    uint256 constant PRICE_FEED_DECIMALS = 8;

    function fixture_preciseConvertWithDecimals(
        uint256 amountRay,
        uint256 decimalsA,
        uint256 decimalsB
    ) public pure returns (uint256) {
        return (decimalsA > decimalsB)
            ? amountRay / 10 ** (RAY_DECIMALS - PRICE_FEED_DECIMALS + (decimalsA - decimalsB))
            : amountRay / 10 ** (RAY_DECIMALS - PRICE_FEED_DECIMALS - (decimalsB - decimalsA));
    }

    function fixture_deposit(
        ERC20 erc20Token,
        AToken aToken,
        address sender,
        address receiver,
        uint256 amount
    ) internal {
        uint256 _receiverATokenBalanceBefore = aToken.balanceOf(address(receiver));
        uint256 _senderTokenBalanceTokenBefore = erc20Token.balanceOf(sender);
        uint256 _aTokenBalanceBefore = erc20Token.balanceOf(address(aToken));
        vm.startPrank(sender);
        erc20Token.approve(address(contracts.lendingPool), amount);
        contracts.lendingPool.deposit(address(erc20Token), true, amount, receiver);
        vm.stopPrank();
        console.log("_aTokenBalanceBefore: ", _aTokenBalanceBefore);
        console.log("_aTokenBalanceAfter: ", erc20Token.balanceOf(address(aToken)));
        assertEq(
            _senderTokenBalanceTokenBefore,
            erc20Token.balanceOf(address(this)) + amount,
            "Sender's token balance is not lower by {amount} after deposit"
        );
        console.log(
            "Sender balance: %s, receiver balance: %s, This balance: %s",
            aToken.balanceOf(address(sender)),
            aToken.balanceOf(address(receiver)),
            aToken.balanceOf(address(address(this)))
        );
        assertEq(
            _receiverATokenBalanceBefore + amount,
            aToken.balanceOf(address(receiver)),
            "Receiver aToken balance is not greater by {amount} after deposit"
        );
    }

    function fixture_withdraw(ERC20 erc20Token, address sender, address receiver, uint256 amount)
        public
    {
        uint256 _receiverTokenBalanceBefore = erc20Token.balanceOf(address(receiver));

        vm.startPrank(sender);
        // vm.expectEmit(true, true, true, true);
        // emit Withdraw(address(erc20Token), sender, receiver, amount);
        contracts.lendingPool.withdraw(address(erc20Token), true, amount, receiver);
        vm.stopPrank();
        assertEq(
            _receiverTokenBalanceBefore + amount,
            erc20Token.balanceOf(receiver),
            "Receiver's token balance is not greater by {amount} after withdrawal"
        );
    }

    function fixture_getMaxValueToBorrow(ERC20 collateral, ERC20 borrowToken, uint256 amount)
        internal
        view
        returns (uint256)
    {
        Oracle oracle = Oracle(contracts.miniPoolAddressesProvider.getPriceOracle());
        uint256 borrowTokenPrice = oracle.getAssetPrice(address(borrowToken));
        uint256 collateralPrice = oracle.getAssetPrice(address(collateral));
        uint256 collateralDepositValue = amount * collateralPrice / (10 ** PRICE_FEED_DECIMALS);
        StaticData memory staticData =
            contracts.cod3xLendDataProvider.getLpReserveStaticData(address(collateral), true);
        uint256 maxBorrowTokenToBorrowInCollateralUnit;
        {
            uint256 collateralMaxBorrowValue = staticData.ltv * collateralDepositValue / 10_000;

            uint256 wbtcMaxBorrowAmountRay = collateralMaxBorrowValue.rayDiv(borrowTokenPrice);
            maxBorrowTokenToBorrowInCollateralUnit = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, collateral.decimals(), borrowToken.decimals()
            );
            // (usdcMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
        }
        return maxBorrowTokenToBorrowInCollateralUnit;
    }

    function fixture_depositAndBorrow(
        TokenTypes memory collateral,
        TokenTypes memory borrowToken,
        address provider,
        address borrower,
        uint256 amount
    ) public returns (uint256) {
        /* Borrower deposits collateral and wants to borrow */
        fixture_deposit(collateral.token, collateral.aToken, borrower, borrower, amount);

        uint256 maxBorrowTokenToBorrowInCollateralUnit =
            fixture_getMaxValueToBorrow(collateral.token, borrowToken.token, amount);
        deal(address(borrowToken.token), borrower, 2 * maxBorrowTokenToBorrowInCollateralUnit);

        require(
            borrowToken.token.balanceOf(borrower) > maxBorrowTokenToBorrowInCollateralUnit * 15 / 10,
            "Too less borrowToken"
        );
        uint256 borrowTokenDepositAmount = maxBorrowTokenToBorrowInCollateralUnit * 15 / 10;
        console.log("borrowTokenDepositAmount: ", borrowTokenDepositAmount);
        /* Provider deposits wbtc thanks to that there is enough funds to borrow */
        fixture_deposit(
            borrowToken.token, borrowToken.aToken, borrower, provider, borrowTokenDepositAmount
        );

        uint256 borrowTokenBalanceBeforeBorrow = borrowToken.token.balanceOf(borrower);
        uint256 debtBalanceBefore = borrowToken.debtToken.balanceOf(borrower);

        StaticData memory staticData =
            contracts.cod3xLendDataProvider.getLpReserveStaticData(address(borrowToken.token), true);
        DataTypes.ReserveData memory data =
            contracts.lendingPool.getReserveData(address(borrowToken.token), true);
        (, uint256 expectedBorrowRate) = DefaultReserveInterestRateStrategy(
            data.interestRateStrategyAddress
        ).calculateInterestRates(
            address(borrowToken.token),
            address(borrowToken.aToken),
            0,
            maxBorrowTokenToBorrowInCollateralUnit,
            maxBorrowTokenToBorrowInCollateralUnit,
            staticData.cod3xReserveFactor
        );
        console.log("AToken balance: ", borrowToken.token.balanceOf(address(borrowToken.aToken)));
        /* Borrower borrows maxPossible amount of borrowToken */
        contracts.lendingPool.borrow(
            address(borrowToken.token), true, maxBorrowTokenToBorrowInCollateralUnit, borrower
        );
        console.log("AToken balance: ", borrowToken.token.balanceOf(address(borrowToken.aToken)));
        /* Main user's balance should be: initial amount + borrowed amount */
        assertEq(
            borrowTokenBalanceBeforeBorrow + maxBorrowTokenToBorrowInCollateralUnit,
            borrowToken.token.balanceOf(borrower),
            "Borrower hasn't more borrowToken than before"
        );
        assertEq(
            debtBalanceBefore + maxBorrowTokenToBorrowInCollateralUnit,
            borrowToken.debtToken.balanceOf(borrower),
            "Borrower hasn't more borrowToken than before"
        );
        return (maxBorrowTokenToBorrowInCollateralUnit);
    }

    function testBorrowRepay(
        TokenTypes memory collateralTypes,
        TokenTypes memory borrowTypes,
        uint256 usdcDepositAmount
    ) public {
        address user = makeAddr("user");

        (uint256 maxBorrowTokenToBorrowInCollateralUnit) = fixture_depositAndBorrow(
            collateralTypes, borrowTypes, user, address(this), usdcDepositAmount
        );

        /* Main user repays his debt */
        uint256 wbtcBalanceBeforeRepay = borrowTypes.token.balanceOf(address(this));
        uint256 wbtcDebtBeforeRepay = borrowTypes.debtToken.balanceOf(address(this));
        borrowTypes.token.approve(
            address(contracts.lendingPool), maxBorrowTokenToBorrowInCollateralUnit
        );
        contracts.lendingPool.repay(
            address(borrowTypes.token), true, maxBorrowTokenToBorrowInCollateralUnit, address(this)
        );
        /* Main user's balance should be the same as before borrowing */
        assertEq(
            wbtcBalanceBeforeRepay,
            borrowTypes.token.balanceOf(address(this)) + maxBorrowTokenToBorrowInCollateralUnit,
            "User after repayment has less borrowed tokens"
        );
        assertEq(
            wbtcDebtBeforeRepay,
            borrowTypes.debtToken.balanceOf(address(this)) + maxBorrowTokenToBorrowInCollateralUnit,
            "User after repayment has less debt"
        );
    }

    function fixture_getATokenWrapper(address _token, Cod3xLendDataProvider cod3xLendDataProvider)
        public
        view
        returns (AToken _aTokenW)
    {
        (address _aTokenAddress,) = cod3xLendDataProvider.getLpTokens(_token, true);
        // console.log("AToken%s: %s", idx, _aTokenAddress);
        _aTokenW = AToken(address(AToken(_aTokenAddress).WRAPPER_ADDRESS()));
    }

    function fixture_getAToken(address _token, Cod3xLendDataProvider cod3xLendDataProvider)
        public
        view
        returns (AToken _aToken)
    {
        (address _aTokenAddress,) = cod3xLendDataProvider.getLpTokens(_token, true);
        // console.log("AToken%s: %s", idx, _aTokenAddress);
        _aToken = AToken(_aTokenAddress);
    }

    function fixture_getVarDebtToken(address _token, Cod3xLendDataProvider cod3xLendDataProvider)
        public
        returns (VariableDebtToken _varDebtToken)
    {
        (, address _variableDebtToken) = cod3xLendDataProvider.getLpTokens(_token, true);
        _varDebtToken = VariableDebtToken(_variableDebtToken);
    }

    function fixture_depositTokensToMiniPool(
        uint256 amount,
        uint256 tokenId,
        address user,
        ERC20 collateral,
        IAERC6909 aErc6909Token,
        address miniPool
    ) public {
        deal(address(collateral), user, amount);
        console.log("Address: %s vs tokenId: %s", address(collateral), tokenId);
        vm.startPrank(user);
        uint256 tokenUserBalance = aErc6909Token.balanceOf(user, tokenId);
        uint256 tokenBalance = collateral.balanceOf(user);
        collateral.approve(miniPool, amount);
        IMiniPool(miniPool).deposit(address(collateral), false, amount, user);
        assertEq(tokenBalance - amount, collateral.balanceOf(user), "Token balance is wrong");
        assertEq(
            tokenUserBalance + amount,
            aErc6909Token.balanceOf(user, tokenId),
            "AToken balance is wrong"
        );
        vm.stopPrank();
    }

    function testMultipleUsersBorrowRepayAndWithdraw(
        TokenParams memory collateralParams,
        TokenParams memory borrowParams,
        address miniPool,
        Users memory users,
        uint256 depositAmount,
        uint256 borrowAmount
    ) public {
        /**
         * Preconditions:
         * 1. Reserves in LendingPool and MiniPool must be configured
         * 2. Mini Pool must be properly funded
         * 3. There is some liquidity deposited by provider to borrow certain asset from lending pool (WBTC)
         * Test Scenario:
         * 1. User adds token (USDC) as a collateral into the mini pool
         * 3. User borrows token (WBTC) in miniPool
         * 4. Provider borrows some USDC - User starts getting interest rates
         * 5. Some time elapse - aTokens and debtTokens appreciate in value
         * 6. User repays all debts (WBTC) - distribute some WBTC to pay accrued interests
         * 7. Provider repays all debts (USDC) - distribute some USDC to pay accrued interests
         * 8. User withdraws all the funds with accrued interests
         * 9. Provider withdraws all the funds with accrued interests
         * Invariants:
         * 1. All users shall be able to withdraw the greater or equal amount of funds that they deposited
         * 2.
         */
        uint8 WBTC_OFFSET = 2;
        uint8 USDC_OFFSET = 1;

        /* Fuzz vectors */
        uint256 skipDuration = 100 days;

        IAERC6909 aErc6909Token =
            IAERC6909(contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        // uint256 depositAmount = 15000 * 10 ** collateralParams.token.decimals(); // 15 000 usdc
        // uint256 borrowAmount = 2 * 10 ** (borrowParams.token.decimals() - 1); // 0.2 wbtc

        console.log("----------------USER1 DEPOSIT---------------");
        fixture_depositTokensToMiniPool(
            depositAmount,
            1128 + USDC_OFFSET,
            users.user1,
            collateralParams.token,
            aErc6909Token,
            miniPool
        );
        console.log("----------------USER2 DEPOSIT---------------");
        fixture_depositTokensToMiniPool(
            borrowAmount,
            1128 + WBTC_OFFSET,
            users.user2,
            borrowParams.token,
            aErc6909Token,
            miniPool
        );

        console.log("----------------USER1 BORROW---------------");
        vm.startPrank(users.user1);
        IMiniPool(miniPool).borrow(
            address(borrowParams.token), false, borrowAmount / 4, users.user1
        );
        assertEq(borrowParams.token.balanceOf(users.user1), borrowAmount / 4);
        vm.stopPrank();

        console.log("----------------USER2 BORROW---------------");
        vm.startPrank(users.user2);
        IMiniPool(miniPool).borrow(
            address(collateralParams.token), false, depositAmount / 4, users.user2
        );
        assertEq(collateralParams.token.balanceOf(users.user2), depositAmount / 4);
        vm.stopPrank();

        skip(skipDuration);

        uint256 diff = aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET) - borrowAmount / 4;
        console.log("Accrued wbtc debt: ", diff);
        deal(
            address(borrowParams.token),
            users.user1,
            borrowParams.token.balanceOf(users.user1) + diff
        );
        diff = aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET) - depositAmount / 4;
        console.log("Accrued usdc debt: ", diff);
        deal(
            address(collateralParams.token),
            users.user2,
            collateralParams.token.balanceOf(users.user2) + diff
        );

        vm.startPrank(users.user1);
        console.log("----------------USER1 REPAYS---------------");
        console.log(
            "Amount %s vs debt balance %s",
            depositAmount,
            aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET)
        );
        borrowParams.token.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET)
        );
        console.log("User1 Repaying...");
        /* Give lacking amount to user 1 */
        IMiniPool(miniPool).repay(
            address(borrowParams.token),
            false,
            aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET),
            users.user1
        );
        vm.stopPrank();

        console.log("----------------USER2 REPAYS---------------");
        vm.startPrank(users.user2);
        console.log(
            "Amount %s vs debt balance %s",
            depositAmount,
            aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET)
        );
        collateralParams.token.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET)
        );
        console.log("User2 Repaying...");
        IMiniPool(miniPool).repay(
            address(collateralParams.token),
            false,
            aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET),
            users.user2
        );
        vm.stopPrank();

        vm.startPrank(users.user1);
        console.log("Balance: ", aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        uint256 availableLiquidity =
            IERC20(collateralParams.aToken).balanceOf(address(aErc6909Token));
        console.log("AvailableLiquidity: ", availableLiquidity);
        console.log("Withdrawing... %s", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        IMiniPool(miniPool).withdraw(
            address(collateralParams.token),
            false,
            aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET),
            users.user1
        );
        console.log("After Balance: ", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        availableLiquidity = IERC20(collateralParams.aToken).balanceOf(address(aErc6909Token));
        console.log("After availableLiquidity: ", availableLiquidity);
        vm.stopPrank();

        vm.startPrank(users.user2);
        console.log("----------------USER2 TRANSFER---------------");

        availableLiquidity = IERC20(borrowParams.aToken).balanceOf(address(aErc6909Token));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user2, 1000 + WBTC_OFFSET));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user2, 1128 + WBTC_OFFSET));
        console.log("AvailableLiquidity: ", availableLiquidity);
        console.log("Withdrawing...");
        IMiniPool(miniPool).withdraw(
            address(borrowParams.token),
            false,
            aErc6909Token.balanceOf(users.user2, 1128 + WBTC_OFFSET),
            users.user2
        );
        vm.stopPrank();

        assertGt(
            collateralParams.token.balanceOf(users.user1),
            depositAmount,
            "Balance is not greater for user1"
        );
        assertGt(
            borrowParams.token.balanceOf(users.user2),
            borrowAmount,
            "Balance is not greater for user2"
        );
    }

    function depositToMainPool() public {
        (address[] memory assets, bool[] memory reserveTypes) =
            contracts.lendingPool.getReservesList();
        for (uint256 idx = 0; idx < assets.length; idx++) {
            DataTypes.ReserveData memory data =
                contracts.lendingPool.getReserveData(assets[idx], reserveTypes[idx]);
            uint256 depositAmount = 10 ** ERC20(assets[idx]).decimals();
            AToken aToken = fixture_getATokenWrapper(assets[idx], contracts.cod3xLendDataProvider);
            TokenParams memory collateralParams =
                TokenParams({token: ERC20(assets[idx]), aToken: aToken});
            deal(assets[idx], address(this), depositAmount);
            fixture_deposit(ERC20(assets[idx]), aToken, address(this), address(this), depositAmount);
        }
    }

    function bootstrapMiniPools() public {
        uint256 index = 0;
        address miniPool = contracts.miniPoolAddressesProvider.getMiniPool(index);
        while (miniPool != address(0)) {
            console.log("ITERATION: %s", index);
            IAERC6909 aErc6909Token =
                IAERC6909(contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

            (address[] memory assets,) = IMiniPool(miniPool).getReservesList();
            for (uint256 idx = 0; idx < assets.length; idx++) {
                DataTypes.MiniPoolReserveData memory data =
                    IMiniPool(miniPool).getReserveData(assets[idx]);
                uint256 depositAmount = 10 ** ERC20(assets[idx]).decimals();
                fixture_depositTokensToMiniPool(
                    depositAmount,
                    data.aTokenID,
                    address(this),
                    ERC20(assets[idx]),
                    aErc6909Token,
                    miniPool
                );
            }
            index++;
            miniPool = contracts.miniPoolAddressesProvider.getMiniPool(index);
        }
    }

    function run() external returns (DeployedContracts memory) {
        //vm.startBroadcast(vm.envUint("DEPLOYER"));

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier */
            {
                string memory RPC = vm.envString("BASE_RPC_URL");
                uint256 FORK_BLOCK = 21838058;
                uint256 fork;
                fork = vm.createSelectFork(RPC, FORK_BLOCK);
            }
            string memory deploymentConfig;
            {
                /* Config fetching */
                AddAssetsLocal addAssets = new AddAssetsLocal();
                contracts = addAssets.run();

                // Config fetching
                string memory root = vm.projectRoot();
                string memory path = string.concat(root, "/scripts/inputs/8_TestConfig.json");
                console.log("PATH: ", path);
                deploymentConfig = vm.readFile(path);
            }

            uint256 depositAmount = deploymentConfig.readUint(".depositAmount");
            uint256 borrowAmount = deploymentConfig.readUint(".borrowAmount");
            bool bootstrapMainPool = deploymentConfig.readBool(".bootstrapMainPool");
            bool bootstrapMiniPool = deploymentConfig.readBool(".bootstrapMiniPool");

            TokenTypes memory borrowTypes;
            TokenTypes memory collateralTypes;
            address mp;
            AToken aToken;

            {
                address collateral = deploymentConfig.readAddress(".collateralAddress");
                address borrowAsset = deploymentConfig.readAddress(".borrowAssetAddress");
                PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
                    deploymentConfig.parseRaw(".poolAddressesProviderConfig"),
                    (PoolAddressesProviderConfig)
                );

                aToken = fixture_getAToken(collateral, contracts.cod3xLendDataProvider);

                VariableDebtToken variableDebtToken =
                    fixture_getVarDebtToken(collateral, contracts.cod3xLendDataProvider);

                collateralTypes = TokenTypes({
                    token: ERC20(collateral),
                    aToken: aToken,
                    debtToken: variableDebtToken
                });

                aToken = fixture_getAToken(borrowAsset, contracts.cod3xLendDataProvider);

                variableDebtToken =
                    fixture_getVarDebtToken(borrowAsset, contracts.cod3xLendDataProvider);

                borrowTypes = TokenTypes({
                    token: ERC20(borrowAsset),
                    aToken: aToken,
                    debtToken: variableDebtToken
                });

                // vm.startPrank(FOUNDRY_DEFAULT);
                /* Test borrow repay */
                deal(address(collateralTypes.token), address(this), 2 * depositAmount);
                // testBorrowRepay(collateralTypes, borrowTypes, depositAmount);
                mp = contracts.miniPoolAddressesProvider.getMiniPool(
                    poolAddressesProviderConfig.poolId
                );
            }

            vm.startPrank(FOUNDRY_DEFAULT);
            contracts.lendingPoolConfigurator.setPoolPause(false);
            contracts.miniPoolConfigurator.setPoolPause(false, IMiniPool(mp));
            vm.stopPrank();

            TokenParams memory collateralParams;
            TokenParams memory borrowParams;
            {
                aToken = fixture_getATokenWrapper(
                    address(collateralTypes.token), contracts.cod3xLendDataProvider
                );
                collateralParams =
                    TokenParams({token: ERC20(address(collateralTypes.token)), aToken: aToken});

                aToken = fixture_getATokenWrapper(
                    address(borrowTypes.token), contracts.cod3xLendDataProvider
                );
                borrowParams =
                    TokenParams({token: ERC20(address(borrowTypes.token)), aToken: aToken});
            }

            if (bootstrapMainPool == true && bootstrapMiniPool == true) {
                depositToMainPool();
                bootstrapMiniPools();
            } else if (bootstrapMiniPool == true) {
                bootstrapMiniPools();
            } else {
                Users memory users;
                users.user1 = vm.addr(vm.envUint("USER1_PRIVATE_KEY"));
                users.user2 = vm.addr(vm.envUint("USER2_PRIVATE_KEY"));
                users.user3 = vm.addr(vm.envUint("DIST_PRIVATE_KEY"));
                testMultipleUsersBorrowRepayAndWithdraw(
                    collateralParams, borrowParams, mp, users, depositAmount, borrowAmount
                );
            }

            // vm.stopPrank();
        } else {
            console.log("Test only available for mainnet fork");
        }
    }
}
