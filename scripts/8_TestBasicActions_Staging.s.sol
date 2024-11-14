// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

// import "./DeployArbTestNet.s.sol";
// import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import "./DeploymentUtils.s.sol";
import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {AddAssets} from "./4_AddAssets.s.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {DataTypes} from "../contracts/protocol/libraries/types/DataTypes.sol";

contract TestBasicActionsStaging is Script, DeploymentUtils, Test {
    using stdJson for string;
    using WadRayMath for uint256;

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
        vm.startBroadcast(sender);
        erc20Token.approve(address(contracts.lendingPool), amount);
        contracts.lendingPool.deposit(address(erc20Token), true, amount, receiver);
        vm.stopBroadcast();
        console.log("_aTokenBalanceBefore: ", _aTokenBalanceBefore);
        console.log("_aTokenBalanceAfter: ", erc20Token.balanceOf(address(aToken)));
        assertEq(
            _senderTokenBalanceTokenBefore,
            erc20Token.balanceOf(sender) + amount,
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

        vm.startBroadcast(sender);
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
        console.log("Address: %s vs tokenId: %s", address(collateral), tokenId);
        vm.startBroadcast(user);
        uint256 tokenUserBalance = aErc6909Token.balanceOf(user, tokenId);
        uint256 tokenBalance = collateral.balanceOf(user);
        collateral.approve(miniPool, amount);
        IMiniPool(miniPool).deposit(address(collateral), amount, user);
        assertEq(tokenBalance - amount, collateral.balanceOf(user));
        assertEq(tokenUserBalance + amount, aErc6909Token.balanceOf(user, tokenId));
        vm.stopBroadcast();
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
         *
         */
        uint8 WBTC_OFFSET = 2;
        uint8 USDC_OFFSET = 1;

        /* Fuzz vectors */
        uint256 skipDuration = 100 days;

        IAERC6909 aErc6909Token =
            IAERC6909(contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        console.log("----------------USER1 DEPOSIT---------------");
        fixture_depositTokensToMiniPool(
            depositAmount,
            1128 + USDC_OFFSET,
            users.user1,
            usdcParams.token,
            aErc6909Token,
            miniPool
        );
        console.log("----------------USER2 DEPOSIT---------------");
        fixture_depositTokensToMiniPool(
            borrowAmount, 1128 + WBTC_OFFSET, users.user2, wbtcParams.token, aErc6909Token, miniPool
        );

        // console.log("----------------USER1 BORROW---------------");
        vm.startBroadcast(users.user1);
        uint256 balanceBefore = wbtcParams.token.balanceOf(users.user1);
        IMiniPool(miniPool).borrow(address(wbtcParams.token), borrowAmount / 4, users.user1);
        assertEq(wbtcParams.token.balanceOf(users.user1), balanceBefore + (borrowAmount / 4));
        vm.stopBroadcast();

        console.log("----------------USER2 BORROW---------------");
        vm.startBroadcast(users.user2);
        balanceBefore = usdcParams.token.balanceOf(users.user2);
        IMiniPool(miniPool).borrow(address(usdcParams.token), borrowAmount / 4, users.user2);
        assertEq(usdcParams.token.balanceOf(users.user2), balanceBefore + borrowAmount / 4);
        vm.stopBroadcast();

        vm.startBroadcast(users.user1);
        console.log("----------------USER1 REPAYS---------------");
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
        vm.stopBroadcast();

        console.log("----------------USER2 REPAYS---------------");
        vm.startBroadcast(users.user2);
        usdcParams.token.approve(
            address(miniPool), aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET)
        );
        console.log("User2 Repaying...");
        IMiniPool(miniPool).repay(
            address(usdcParams.token),
            aErc6909Token.balanceOf(users.user2, 2128 + USDC_OFFSET),
            users.user2
        );
        vm.stopBroadcast();

        vm.startBroadcast(users.user1);
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
        vm.stopBroadcast();

        vm.startBroadcast(users.user2);
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
        vm.stopBroadcast();

        assertGt(
            usdcParams.token.balanceOf(users.user1),
            depositAmount,
            "Balance is not greater for user1"
        );
        assertGt(
            wbtcParams.token.balanceOf(users.user2),
            borrowAmount,
            "Balance is not greater for user2"
        );
    }

    function readContracts(string memory root) public {
        string memory path = string.concat(root, "/scripts/outputs/1_LendingPoolContracts.json");
        string memory deployedContracts = vm.readFile(path);

        contracts.lendingPool = LendingPool(deployedContracts.readAddress(".lendingPool"));
        contracts.cod3xLendDataProvider =
            Cod3xLendDataProvider(deployedContracts.readAddress(".cod3xLendDataProvider"));
        contracts.lendingPoolAddressesProvider = LendingPoolAddressesProvider(
            deployedContracts.readAddress(".lendingPoolAddressesProvider")
        );
        contracts.lendingPoolConfigurator =
            LendingPoolConfigurator(deployedContracts.readAddress(".lendingPoolConfigurator"));

        path = string.concat(root, "/scripts/outputs/2_MiniPoolContracts.json");
        deployedContracts = vm.readFile(path);
        contracts.miniPoolAddressesProvider =
            MiniPoolAddressesProvider(deployedContracts.readAddress(".miniPoolAddressesProvider"));
        contracts.miniPoolConfigurator =
            MiniPoolConfigurator(deployedContracts.readAddress(".miniPoolConfigurator"));
    }

    function readStrategiesToContracts(string memory root) public {
        string memory path = string.concat(root, "/scripts/outputs/3_DeployedStrategies.json");
        string memory deployedStrategies = vm.readFile(path);
        /* Pi miniPool strats */
        address[] memory tmpStrats = deployedStrategies.readAddressArray(".miniPoolPiStrategies");
        delete contracts.miniPoolPiStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolPiStrategies.push(
                MiniPoolPiReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Stable miniPool strats */
        tmpStrats = deployedStrategies.readAddressArray(".miniPoolStableStrategies");
        delete contracts.miniPoolStableStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolStableStrategies.push(
                MiniPoolDefaultReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Volatile miniPool strats */
        tmpStrats = deployedStrategies.readAddressArray(".miniPoolVolatileStrategies");
        delete contracts.miniPoolVolatileStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.miniPoolVolatileStrategies.push(
                MiniPoolDefaultReserveInterestRateStrategy(tmpStrats[idx])
            );
        }
        /* Pi strats */
        tmpStrats = deployedStrategies.readAddressArray(".piStrategies");
        delete contracts.piStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.piStrategies.push(PiReserveInterestRateStrategy(tmpStrats[idx]));
        }
        /* Stable strats */
        tmpStrats = deployedStrategies.readAddressArray(".stableStrategies");
        delete contracts.stableStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.stableStrategies.push(DefaultReserveInterestRateStrategy(tmpStrats[idx]));
        }
        /* Volatile strats */
        tmpStrats = deployedStrategies.readAddressArray(".volatileStrategies");
        delete contracts.volatileStrategies;
        for (uint8 idx = 0; idx < tmpStrats.length; idx++) {
            contracts.volatileStrategies.push(DefaultReserveInterestRateStrategy(tmpStrats[idx]));
        }
    }

    function mintAllMockedTokens(string memory root, uint256 amount, Users memory users)
        public
        returns (address collateral, address borrowAsset)
    {
        string memory path = string.concat(root, "/scripts/outputs/0_MockedTokens.json");
        string memory deployedMocks = vm.readFile(path);

        address[] memory mocks = deployedMocks.readAddressArray(".mockedTokens");
        contracts.oracle = Oracle(deployedMocks.readAddress(".mockedOracle"));
        for (uint8 idx = 0; idx < mocks.length; idx++) {
            console.log("Minting user1... ");
            vm.broadcast(users.user1);
            MintableERC20(mocks[idx]).mint(amount);

            console.log("Minting user2... ");
            vm.broadcast(users.user2);
            MintableERC20(mocks[idx]).mint(amount);

            console.log("Minting user3... ");
            vm.broadcast(users.user3);
            MintableERC20(mocks[idx]).mint(amount);
            collateral = mocks[idx];
        }
    }

    function mintMockedTokens(
        string memory root,
        uint256 depositAmount,
        uint256 borrowAmount,
        string memory collateralSymbol,
        string memory borrowAsetSymbol,
        Users memory users
    ) public returns (address collateral, address borrowAsset) {
        string memory path = string.concat(root, "/scripts/outputs/0_MockedTokens.json");
        string memory deployedMocks = vm.readFile(path);

        address[] memory mocks = deployedMocks.readAddressArray(".mockedTokens");
        for (uint8 idx = 0; idx < mocks.length; idx++) {
            if (
                keccak256(abi.encodePacked(collateralSymbol))
                    == keccak256(abi.encodePacked(ERC20(mocks[idx]).symbol()))
            ) {
                console.log("Minting user1... ");
                vm.broadcast(users.user1);
                MintableERC20(mocks[idx]).mint(depositAmount);

                console.log("Minting user2... ");
                vm.broadcast(users.user2);
                MintableERC20(mocks[idx]).mint(depositAmount);

                console.log("Minting user3... ");
                vm.broadcast(users.user3);
                MintableERC20(mocks[idx]).mint(depositAmount);
                collateral = mocks[idx];
            }

            if (
                keccak256(abi.encodePacked(borrowAsetSymbol))
                    == keccak256(abi.encodePacked(ERC20(mocks[idx]).symbol()))
            ) {
                vm.broadcast(users.user1);
                MintableERC20(mocks[idx]).mint(borrowAmount);

                vm.broadcast(users.user2);
                MintableERC20(mocks[idx]).mint(borrowAmount);

                vm.broadcast(users.user3);
                MintableERC20(mocks[idx]).mint(borrowAmount);

                borrowAsset = mocks[idx];
            }
        }
    }

    /**
     * @dev amount in 18 decimalse -> will be converted to proper decimals inside
     */
    function depositToMainPool(uint256 amount, address user) public {
        (address[] memory assets, bool[] memory reserveTypes) =
            contracts.lendingPool.getReservesList();
        for (uint256 idx = 0; idx < assets.length; idx++) {
            DataTypes.ReserveData memory data =
                contracts.lendingPool.getReserveData(assets[idx], reserveTypes[idx]);
            console.log("Price: ", contracts.oracle.getAssetPrice(assets[idx]));
            uint256 collateralAmount = (amount * 1e8) / contracts.oracle.getAssetPrice(assets[idx]);
            console.log("Collateral amount: ", collateralAmount);
            uint256 depositAmount = collateralAmount / (10 ** (18 - ERC20(assets[idx]).decimals()));
            console.log("depositAmount: ", depositAmount);
            AToken aToken = fixture_getATokenWrapper(assets[idx], contracts.cod3xLendDataProvider);
            TokenParams memory collateralParams =
                TokenParams({token: ERC20(assets[idx]), aToken: aToken});
            console.log("Depositing: ", depositAmount);
            fixture_deposit(ERC20(assets[idx]), aToken, user, user, depositAmount);
        }
    }

    /**
     * @dev amount in 18 decimalse -> will be converted to proper decimals inside
     */
    function bootstrapAllsMiniPools(uint256 amount, address user, address admin) public {
        uint256 index = 0;
        address miniPool = contracts.miniPoolAddressesProvider.getMiniPool(index);
        while (miniPool != address(0)) {
            vm.startBroadcast(admin);
            contracts.miniPoolConfigurator.setPoolPause(false, IMiniPool(miniPool));
            vm.stopBroadcast();
            console.log("ITERATION: %s", index);
            IAERC6909 aErc6909Token =
                IAERC6909(contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

            (address[] memory assets,) = IMiniPool(miniPool).getReservesList();
            for (uint256 idx = 0; idx < assets.length; idx++) {
                DataTypes.MiniPoolReserveData memory data =
                    IMiniPool(miniPool).getReserveData(assets[idx]);
                uint256 depositAmount = amount / (10 ** (18 - ERC20(assets[idx]).decimals()));
                fixture_depositTokensToMiniPool(
                    depositAmount, data.aTokenID, user, ERC20(assets[idx]), aErc6909Token, miniPool
                );
            }
            vm.startBroadcast(admin);
            contracts.miniPoolConfigurator.setPoolPause(true, IMiniPool(miniPool));
            vm.stopBroadcast();
            index++;
            miniPool = contracts.miniPoolAddressesProvider.getMiniPool(index);
        }
    }

    function depositToMiniPool(uint256 amount, address user, address admin, address miniPool)
        public
    {
        vm.startBroadcast(admin);
        contracts.miniPoolConfigurator.setPoolPause(false, IMiniPool(miniPool));
        vm.stopBroadcast();
        IAERC6909 aErc6909Token =
            IAERC6909(contracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        (address[] memory assets,) = IMiniPool(miniPool).getReservesList();
        for (uint256 idx = 0; idx < assets.length; idx++) {
            DataTypes.MiniPoolReserveData memory data =
                IMiniPool(miniPool).getReserveData(assets[idx]);
            uint256 depositAmount = amount / (10 ** (18 - ERC20(assets[idx]).decimals()));
            fixture_depositTokensToMiniPool(
                depositAmount, data.aTokenID, user, ERC20(assets[idx]), aErc6909Token, miniPool
            );
        }
        vm.startBroadcast(admin);
        contracts.miniPoolConfigurator.setPoolPause(true, IMiniPool(miniPool));
        vm.stopBroadcast();
    }

    function run() external returns (DeployedContracts memory) {
        console.log("8_TestBasicActions_Staging");
        // Config fetching
        string memory root = vm.projectRoot();

        readContracts(root);
        readStrategiesToContracts(root);
        string memory testConfigs;
        {
            // Config fetching
            string memory testConfigPath = string.concat(root, "/scripts/inputs/8_TestConfig.json");
            console.log("TEST PATH: ", testConfigPath);
            testConfigs = vm.readFile(testConfigPath);
        }

        PoolAddressesProviderConfig memory poolAddressesProviderConfig = abi.decode(
            testConfigs.parseRaw(".poolAddressesProviderConfig"), (PoolAddressesProviderConfig)
        );

        bool bootstrapMainPool = testConfigs.readBool(".bootstrapMainPool");
        bool bootstrapMiniPool = testConfigs.readBool(".bootstrapMiniPool");
        uint256 usdDepositAmount = testConfigs.readUint(".usdAmountToDeposit");

        address collateral;
        address borrowAsset;
        Users memory users;
        users.user1 = vm.addr(vm.envUint("USER1_PRIVATE_KEY"));
        users.user2 = vm.addr(vm.envUint("USER2_PRIVATE_KEY"));
        users.user3 = vm.addr(vm.envUint("DIST_PRIVATE_KEY"));

        if (vm.envBool("MAINNET")) {
            collateral = testConfigs.readAddress(".collateralAddress");
            borrowAsset = testConfigs.readAddress(".borrowAssetAddress");
        } else {
            // TESTNET
            uint256 depositAmount = testConfigs.readUint(".depositAmount");
            uint256 borrowAmount = testConfigs.readUint(".borrowAmount");
            (collateral, borrowAsset) =
                mintMockedTokens(root, 2 * depositAmount, 2 * borrowAmount, "USDC", "WBTC", users);
        }

        address mp =
            contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);

        vm.startBroadcast(users.user1);
        contracts.lendingPoolConfigurator.setPoolPause(false);
        contracts.miniPoolConfigurator.setPoolPause(false, IMiniPool(mp));
        vm.stopBroadcast();

        console.log("Getting wrapper");
        TokenParams memory usdcParams;
        TokenParams memory wbtcParams;
        {
            AToken aToken = fixture_getATokenWrapper(collateral, contracts.cod3xLendDataProvider);
            usdcParams = TokenParams({token: ERC20(collateral), aToken: aToken});

            aToken = fixture_getATokenWrapper(borrowAsset, contracts.cod3xLendDataProvider);
            wbtcParams = TokenParams({token: ERC20(borrowAsset), aToken: aToken});
        }

        if (bootstrapMainPool == true && bootstrapMiniPool == true) {
            mintAllMockedTokens(root, 5 ether, users);
            console.log("Bootstrapping...");
            depositToMainPool(1 ether, users.user1);
            depositToMiniPool(1 ether, users.user1, users.user1, mp);
        } else if (bootstrapMiniPool == true) {
            mintAllMockedTokens(root, 5 ether, users);
            depositToMiniPool(1 ether, users.user1, users.user1, mp);
        } else {
            uint256 depositAmount = testConfigs.readUint(".depositAmount");
            uint256 borrowAmount = testConfigs.readUint(".borrowAmount");
            mp = contracts.miniPoolAddressesProvider.getMiniPool(poolAddressesProviderConfig.poolId);
            testMultipleUsersBorrowRepayAndWithdraw(
                usdcParams, wbtcParams, mp, users, depositAmount, borrowAmount
            );
        }
    }
}
