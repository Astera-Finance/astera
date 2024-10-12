// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {AddAssets} from "./3_AddAssets.s.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

contract TestBasicActions is Script, DeploymentUtils, Test {
    using stdJson for string;
    using WadRayMath for uint256;

    address WETH_ARB = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

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
        (, uint256 collateralLtv,,,,,,,) =
            contracts.protocolDataProvider.getReserveConfigurationData(address(collateral), true);
        uint256 maxBorrowTokenToBorrowInCollateralUnit;
        {
            uint256 collateralMaxBorrowValue = collateralLtv * collateralDepositValue / 10_000;

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

        (,,,, uint256 reserveFactors,,,,) = contracts
            .protocolDataProvider
            .getReserveConfigurationData(address(borrowToken.token), true);
        (, uint256 expectedBorrowRate) = contracts.volatileStrategy.calculateInterestRates(
            address(borrowToken.token),
            address(borrowToken.aToken),
            0,
            maxBorrowTokenToBorrowInCollateralUnit,
            maxBorrowTokenToBorrowInCollateralUnit,
            reserveFactors
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
        TokenTypes memory usdcTypes,
        TokenTypes memory wbtcTypes,
        uint256 usdcDepositAmount
    ) public {
        address user = makeAddr("user");

        (uint256 maxBorrowTokenToBorrowInCollateralUnit) =
            fixture_depositAndBorrow(usdcTypes, wbtcTypes, user, address(this), usdcDepositAmount);

        /* Main user repays his debt */
        uint256 wbtcBalanceBeforeRepay = wbtcTypes.token.balanceOf(address(this));
        uint256 wbtcDebtBeforeRepay = wbtcTypes.debtToken.balanceOf(address(this));
        wbtcTypes.token.approve(
            address(contracts.lendingPool), maxBorrowTokenToBorrowInCollateralUnit
        );
        contracts.lendingPool.repay(
            address(wbtcTypes.token), true, maxBorrowTokenToBorrowInCollateralUnit, address(this)
        );
        /* Main user's balance should be the same as before borrowing */
        assertEq(
            wbtcBalanceBeforeRepay,
            wbtcTypes.token.balanceOf(address(this)) + maxBorrowTokenToBorrowInCollateralUnit,
            "User after repayment has less borrowed tokens"
        );
        assertEq(
            wbtcDebtBeforeRepay,
            wbtcTypes.debtToken.balanceOf(address(this)) + maxBorrowTokenToBorrowInCollateralUnit,
            "User after repayment has less debt"
        );
    }

    function fixture_getATokenWrapper(address _token, ProtocolDataProvider protocolDataProvider)
        public
        view
        returns (AToken _aTokenW)
    {
        (address _aTokenAddress,) = protocolDataProvider.getReserveTokensAddresses(_token, true);
        // console.log("AToken%s: %s", idx, _aTokenAddress);
        _aTokenW = AToken(address(AToken(_aTokenAddress).WRAPPER_ADDRESS()));
    }

    function fixture_getAToken(address _token, ProtocolDataProvider protocolDataProvider)
        public
        view
        returns (AToken _aToken)
    {
        (address _aTokenAddress,) = protocolDataProvider.getReserveTokensAddresses(_token, true);
        // console.log("AToken%s: %s", idx, _aTokenAddress);
        _aToken = AToken(_aTokenAddress);
    }

    function fixture_getVarDebtToken(address _token, ProtocolDataProvider protocolDataProvider)
        public
        returns (VariableDebtToken _varDebtToken)
    {
        (, address _variableDebtToken) =
            protocolDataProvider.getReserveTokensAddresses(_token, true);
        _varDebtToken = VariableDebtToken(_variableDebtToken);
    }

    function fixture_depositTokensToMiniPool(
        uint256 amount,
        uint256 tokenId,
        address user,
        TokenParams memory tokenParams,
        IAERC6909 aErc6909Token,
        address miniPool
    ) public {
        deal(address(tokenParams.token), user, amount);
        console.log("Address: %s vs tokenId: %s", address(tokenParams.token), tokenId);
        vm.startPrank(user);
        uint256 tokenUserBalance = aErc6909Token.balanceOf(user, tokenId);
        uint256 tokenBalance = tokenParams.token.balanceOf(user);
        tokenParams.token.approve(miniPool, amount);
        IMiniPool(miniPool).deposit(address(tokenParams.token), amount, user);
        assertEq(tokenBalance - amount, tokenParams.token.balanceOf(user));
        assertEq(tokenUserBalance + amount, aErc6909Token.balanceOf(user, tokenId));
        vm.stopPrank();
    }

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

    function testMultipleUsersBorrowRepayAndWithdraw(
        TokenParams memory usdcParams,
        TokenParams memory wbtcParams,
        address miniPool
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
         *
         */
        uint8 WBTC_OFFSET = 2;
        uint8 USDC_OFFSET = 1;

        /* Fuzz vectors */
        uint256 skipDuration = 100 days;

        IAERC6909 aErc6909Token =
            IAERC6909(contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        Users memory users;
        users.user1 = makeAddr("user1");
        users.user2 = makeAddr("user2");
        users.user3 = makeAddr("distributor");

        uint256 amount1 = 15000 * 10 ** usdcParams.token.decimals(); // 15 000 usdc
        uint256 amount2 = 2 * 10 ** (wbtcParams.token.decimals() - 1); // 0.2 wbtc

        console.log("----------------USER1 DEPOSIT---------------");
        fixture_depositTokensToMiniPool(
            amount1, 1128 + USDC_OFFSET, users.user1, usdcParams, aErc6909Token, miniPool
        );
        console.log("----------------USER2 DEPOSIT---------------");
        fixture_depositTokensToMiniPool(
            amount2, 1128 + WBTC_OFFSET, users.user2, wbtcParams, aErc6909Token, miniPool
        );

        console.log("----------------USER1 BORROW---------------");
        vm.startPrank(users.user1);
        IMiniPool(miniPool).borrow(address(wbtcParams.token), amount2 / 4, users.user1);
        assertEq(wbtcParams.token.balanceOf(users.user1), amount2 / 4);
        vm.stopPrank();

        console.log("----------------USER2 BORROW---------------");
        vm.startPrank(users.user2);
        IMiniPool(miniPool).borrow(address(usdcParams.token), amount1 / 4, users.user2);
        assertEq(usdcParams.token.balanceOf(users.user2), amount1 / 4);
        vm.stopPrank();

        skip(skipDuration);

        uint256 diff = aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET) - amount2 / 4;
        console.log("Accrued wbtc debt: ", diff);
        deal(address(wbtcParams.token), users.user1, wbtcParams.token.balanceOf(users.user1) + diff);
        diff = aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET) - amount1 / 4;
        console.log("Accrued usdc debt: ", diff);
        deal(address(usdcParams.token), users.user2, usdcParams.token.balanceOf(users.user2) + diff);

        vm.startPrank(users.user1);
        console.log("----------------USER1 REPAYS---------------");
        console.log(
            "Amount %s vs debt balance %s",
            amount1,
            aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET)
        );
        wbtcParams.token.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET)
        );
        console.log("User1 Repaying...");
        /* Give lacking amount to user 1 */
        IMiniPool(miniPool).repay(
            address(wbtcParams.token),
            aErc6909Token.balanceOf(users.user1, 2128 + WBTC_OFFSET),
            users.user1
        );
        vm.stopPrank();

        console.log("----------------USER2 REPAYS---------------");
        vm.startPrank(users.user2);
        console.log(
            "Amount %s vs debt balance %s",
            amount1,
            aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET)
        );
        usdcParams.token.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET)
        );
        console.log("User2 Repaying...");
        IMiniPool(miniPool).repay(
            address(usdcParams.token),
            aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET),
            users.user2
        );
        vm.stopPrank();

        vm.startPrank(users.user1);
        console.log("Balance: ", aErc6909Token.balanceOf(users.user1, 1000 + USDC_OFFSET));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        uint256 availableLiquidity = IERC20(usdcParams.aToken).balanceOf(address(aErc6909Token));
        console.log("AvailableLiquidity: ", availableLiquidity);
        console.log("Withdrawing... %s", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        IMiniPool(miniPool).withdraw(
            address(usdcParams.token),
            aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET),
            users.user1
        );
        console.log("After Balance: ", aErc6909Token.balanceOf(users.user1, 1128 + USDC_OFFSET));
        availableLiquidity = IERC20(usdcParams.aToken).balanceOf(address(aErc6909Token));
        console.log("After availableLiquidity: ", availableLiquidity);
        vm.stopPrank();

        vm.startPrank(users.user2);
        console.log("----------------USER2 TRANSFER---------------");

        availableLiquidity = IERC20(wbtcParams.aToken).balanceOf(address(aErc6909Token));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user2, 1000 + WBTC_OFFSET));
        console.log("Balance: ", aErc6909Token.balanceOf(users.user2, 1128 + WBTC_OFFSET));
        console.log("AvailableLiquidity: ", availableLiquidity);
        console.log("Withdrawing...");
        IMiniPool(miniPool).withdraw(
            address(wbtcParams.token),
            aErc6909Token.balanceOf(users.user2, 1128 + WBTC_OFFSET),
            users.user2
        );
        vm.stopPrank();

        assertGt(
            usdcParams.token.balanceOf(users.user1), amount1, "Balance is not greater for user1"
        );
        assertGt(
            wbtcParams.token.balanceOf(users.user2), amount2, "Balance is not greater for user2"
        );
    }

    function run() external returns (DeployedContracts memory) {
        //vm.startBroadcast(vm.envUint("DEPLOYER"));

        if (vm.envBool("LOCAL_FORK")) {
            /* Fork Identifier [ARBITRUM] */
            string memory RPC = vm.envString("ARBITRUM_RPC_URL");
            uint256 FORK_BLOCK = 257827379;
            uint256 arbFork;
            arbFork = vm.createSelectFork(RPC, FORK_BLOCK);

            /* Config fetching */
            AddAssets addAssets = new AddAssets();
            contracts = addAssets.run();

            // Config fetching
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/scripts/inputs/5_TestConfig.json");
            console.log("PATH: ", path);
            string memory deploymentConfig = vm.readFile(path);

            address collateral = deploymentConfig.readAddress(".collateralAddress");
            address borrowAsset = deploymentConfig.readAddress(".borrowAssetAddress");
            uint256 depositAmount = deploymentConfig.readUint(".depositAmount");
            PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
                deploymentConfig.parseRaw(".poolAddressesProviderConfig"),
                (PoolAddressesProviderConfig)
            );

            AToken aToken = fixture_getAToken(collateral, contracts.protocolDataProvider);

            VariableDebtToken variableDebtToken =
                fixture_getVarDebtToken(collateral, contracts.protocolDataProvider);

            TokenTypes memory usdcTypes =
                TokenTypes({token: ERC20(collateral), aToken: aToken, debtToken: variableDebtToken});

            aToken = fixture_getAToken(borrowAsset, contracts.protocolDataProvider);

            variableDebtToken = fixture_getVarDebtToken(borrowAsset, contracts.protocolDataProvider);

            TokenTypes memory wbtcTypes = TokenTypes({
                token: ERC20(borrowAsset),
                aToken: aToken,
                debtToken: variableDebtToken
            });

            // vm.startPrank(FOUNDRY_DEFAULT);
            /* Test borrow repay */
            deal(address(usdcTypes.token), address(this), 2 * depositAmount);
            // testBorrowRepay(usdcTypes, wbtcTypes, depositAmount);
            address mp =
                contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);

            aToken = fixture_getATokenWrapper(collateral, contracts.protocolDataProvider);
            TokenParams memory usdcParams = TokenParams({token: ERC20(collateral), aToken: aToken});

            aToken = fixture_getATokenWrapper(borrowAsset, contracts.protocolDataProvider);
            TokenParams memory wbtcParams = TokenParams({token: ERC20(borrowAsset), aToken: aToken});
            testMultipleUsersBorrowRepayAndWithdraw(usdcParams, wbtcParams, mp);
            // vm.stopPrank();
        }
    }
}
