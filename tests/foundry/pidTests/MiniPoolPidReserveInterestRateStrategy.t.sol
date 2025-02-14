// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolPiReserveInterestRateStrategy.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract MiniPoolPidReserveInterestRateStrategyTest is Common {
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    address[] users;
    DeployedContracts deployedContracts;
    address miniPool;
    DeployedMiniPoolContracts deployedMiniPoolContracts;
    ConfigAddresses configAddresses;
    MiniPoolPiReserveInterestRateStrategy miniPoolPidStrat;
    PiReserveInterestRateStrategy pidStrat;

    string path = "./tests/foundry/pidTests/data/LendingPoolOut.csv";
    string pathMiniPool = "./tests/foundry/pidTests/data/MiniPoolOut.csv";
    uint256 nbUsers = 4;
    uint256 initialAmt = 1e12 ether;
    uint256 DEFAULT_TIME_BEFORE_OP = 6 hours;

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();
        (deployedMiniPoolContracts,) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.cod3xLendDataProvider),
            deployedMiniPoolContracts
        );
        console.log("PiReserveInterestRateStrategy deployment: ");
        pidStrat = new PiReserveInterestRateStrategy(
            address(deployedContracts.lendingPoolAddressesProvider),
            DAI,
            true,
            -400e24, //-192e24, // min rate == 0.5%
            20 days, // min I amp
            45e25, // Optimal Utilization Rate (80%)
            1e27, // Kp
            13e19
        );
        miniPool = deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        console.log("1.Minipool: ", miniPool);
        console.log("MiniPoolPiReserveInterestRateStrategy deployment: ");
        miniPoolPidStrat = new MiniPoolPiReserveInterestRateStrategy(
            address(deployedMiniPoolContracts.miniPoolAddressesProvider),
            0, // minipool ID
            DAI,
            true,
            -400e24, //-192e24, // min rate == 0.5%
            20 days, // min I amp
            45e25, // Optimal Utilization Rate (80%)
            1e27, // Kp
            13e19
        );

        // we replace stableStrategy and volatileStrategy by pidStrat
        configAddresses = ConfigAddresses(
            address(deployedContracts.cod3xLendDataProvider),
            address(pidStrat), // address(deployedContracts.stableStrategy), usdc, dai
            address(pidStrat), // address(deployedContracts.volatileStrategy), wbtc, weth
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

        miniPool = deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        console.log("2.Minipool: ", miniPool);

        commonContracts.aTokens =
            fixture_getATokens(tokens, deployedContracts.cod3xLendDataProvider);
        // variableDebtTokens = fixture_getVarDebtTokens(tokens, deployedContracts.cod3xLendDataProvider);
        commonContracts.mockedVaults =
            fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000_000 ether, address(this));
        console.log("strat address: ", address(miniPoolPidStrat));
        configAddresses = ConfigAddresses(
            address(deployedContracts.cod3xLendDataProvider),
            address(miniPoolPidStrat), // address(deployedContracts.stableStrategy), usdc, dai
            address(miniPoolPidStrat), // address(deployedContracts.volatileStrategy), wbtc, weth
            address(deployedContracts.treasury),
            address(deployedContracts.rewarder),
            address(deployedContracts.aTokensAndRatesHelper)
        );

        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
            console.log(idx);
            if (idx < tokens.length) {
                reserves[idx] = tokens[idx];
            } else {
                reserves[idx] =
                    address(commonContracts.aTokens[idx - tokens.length].WRAPPER_ADDRESS());
            }
        }
        console.log("Mini pool reserve configuration..... ");
        fixture_configureMiniPoolReserves(reserves, configAddresses, deployedMiniPoolContracts, 0);

        miniPool = deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        console.log("3.Minipool: ", miniPool);

        /// users
        for (uint256 i = 0; i < 4; i++) {
            users.push(vm.addr(i + 1));
            for (uint256 j = 1; j < erc20Tokens.length; j++) {
                // Start at j=1 because usdc can't be "deal()".
                deal(address(erc20Tokens[j]), users[i], initialAmt);
            }
        }

        /// File setup
        if (vm.exists(path)) vm.removeFile(path);
        vm.writeLine(
            path,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate,errI"
        );
        /// File setup for MiniPool
        if (vm.exists(pathMiniPool)) vm.removeFile(pathMiniPool);
        vm.writeLine(
            pathMiniPool,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate,errI"
        );
    }

    // function testTF() public view {
    //     console.log("transferFunction == ", miniPoolPidStrat.transferFunction(-400e24) / (1e27 / 10000)); // bps
    // }

    // 4 users  (users[0], users[1], users[2], users[3])
    // 3 tokens (wbtc, eth, dai)
    function testPid() public {
        IERC20 wbtc = erc20Tokens[1]; // wbtcPrice =  670000,0000000$
        IERC20 eth = erc20Tokens[2]; // ethPrice =  3700,00000000$
        IERC20 dai = erc20Tokens[3]; // daiPrice =  1,00000000$

        deposit(users[0], wbtc, 2e8);
        deposit(users[1], wbtc, 20e8);
        deposit(users[1], dai, 100_000e18);

        // borrow(users[0], dai, 10_000e18);
        // skip(5 * DEFAULT_TIME_BEFORE_OP);

        // borrow(users[0], dai, 1_000e18);
        // repay(users[0], dai, 1_000e18);
        // borrow(users[0], dai, 1_000e18);
        // repay(users[0], dai, 1_000e18);

        // borrow(users[0], dai, 10_000e18);
        // skip(5 * DEFAULT_TIME_BEFORE_OP);
        // repay(users[0], dai, 5_000e18);
        // // plateau(100);
        // repay(users[0], dai, 10_000e18);

        borrow(users[0], dai, 50000e18);
        plateau(200);
        repay(users[0], dai, 30000e18);
        plateau(200);

        // use to check n factor
        // ensure ki and kd set to 0
        // borrow(users[0], dai, 50000e18); // borrow amount should result in optimal utilization
        // plateau(100);

        // use to check ki
        // ensure kd set to 0
        // borrow(users[0], dai, 50000e18);
        // plateau(100);

        // use to check ki limit for long term underutilization followed by sudden max U
        // borrow(users[0], dai, 1e18);
        // plateau(1000);
        // borrow(users[0], dai, 81000e18);
        // plateau(200);

        // borrow(users[0], dai, 80000e18);
        // for (int256 i = 0; i < 100; i++) {
        //     borrow(users[0], dai, 150e18);
        // }
        // plateau(50);
        // repay(users[0], dai, 15000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // repay(users[0], dai, 40000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // borrow(users[0], dai, 40000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // borrow(users[0], dai, 4000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // repay(users[0], dai, 4000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // borrow(users[0], dai, 20000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // repay(users[0], dai, 20000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // repay(users[0], dai, 10000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // borrow(users[0], dai, 4000e18);
        // plateau(30);
        // for (int256 i = 0; i < 70; i++) {
        //     // borrowWithoutSkip(users[0], dai, 1);
        //     borrow(users[0], dai, 300e18);
        // }
        // plateau(150);
        // borrow(users[0], dai, 1);
    }

    function testPidMiniPool() public {
        IERC20 wbtc = erc20Tokens[1]; // wbtcPrice =  670000,0000000$
        IERC20 eth = erc20Tokens[2]; // ethPrice =  3700,00000000$
        IERC20 dai = erc20Tokens[3]; // daiPrice =  1,00000000$

        depositMiniPool(users[0], wbtc, 2e8);
        depositMiniPool(users[1], wbtc, 20e8);
        depositMiniPool(users[1], dai, 100_000e18);
        // depositMiniPool(users[0], dai, 20_000e18);

        // borrowMiniPool(users[0], dai, 10_000e18);
        // skip(5 * DEFAULT_TIME_BEFORE_OP);

        // borrowMiniPool(users[0], dai, 1_000e18);
        // repayMiniPool(users[0], dai, 1_000e18);
        // borrowMiniPool(users[0], dai, 1_000e18);
        // repayMiniPool(users[0], dai, 1_000e18);

        // borrowMiniPool(users[0], dai, 10_000e18);
        // skip(5 * DEFAULT_TIME_BEFORE_OP);
        // repayMiniPool(users[0], dai, 5_000e18);
        // // plateauMiniPool(100);
        // repayMiniPool(users[0], dai, 10_000e18);

        borrowMiniPool(users[0], dai, 50_000e18);
        plateauMiniPool(200);
        repayMiniPool(users[0], dai, 30_000e18);
        plateauMiniPool(200);

        // use to check n factor
        // ensure ki and kd set to 0
        // borrow(users[0], dai, 50000e18); // borrow amount should result in optimal utilization
        // plateau(100);

        // use to check ki
        // ensure kd set to 0
        // borrow(users[0], dai, 50000e18);
        // plateau(100);

        // use to check ki limit for long term underutilization followed by sudden max U
        // borrow(users[0], dai, 1e18);
        // plateau(1000);
        // borrow(users[0], dai, 81000e18);
        // plateau(200);

        // borrow(users[0], dai, 80000e18);
        // for (int256 i = 0; i < 100; i++) {
        //     borrow(users[0], dai, 150e18);
        // }
        // plateau(50);
        // repay(users[0], dai, 15000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // repay(users[0], dai, 40000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // borrow(users[0], dai, 40000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // borrow(users[0], dai, 4000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // repay(users[0], dai, 4000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // borrow(users[0], dai, 20000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // repay(users[0], dai, 20000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // repay(users[0], dai, 10000e18);
        // plateau(30);
        // // borrowWithoutSkip(users[0], dai, 1);
        // borrow(users[0], dai, 4000e18);
        // plateau(30);
        // for (int256 i = 0; i < 70; i++) {
        //     // borrowWithoutSkip(users[0], dai, 1);
        //     borrow(users[0], dai, 300e18);
        // }
        // plateau(150);
        // borrow(users[0], dai, 1);
    }
    // ------------------------------
    // ---------- Helpers -----------
    // ------------------------------

    function depositMiniPool(address user, IERC20 asset, uint256 amount) public {
        vm.startPrank(user);
        asset.approve(address(miniPool), amount);
        console.log("Depositing to miniPool: %s", miniPool);
        IMiniPool(miniPool).deposit(address(asset), false, amount, user);
        vm.stopPrank();
        loggMiniPool(user, 0, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function deposit(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(deployedContracts.lendingPool), amount);
        console.log("Depositing to Pool: %s", address(deployedContracts.lendingPool));
        deployedContracts.lendingPool.deposit(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 0, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrowMiniPool(address user, IERC20 asset, uint256 amount) internal {
        console.log("Borrowing MiniPool");
        vm.startPrank(user);
        IMiniPool(miniPool).borrow(address(asset), false, amount, user);
        vm.stopPrank();
        loggMiniPool(user, 1, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrow(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 1, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrowWithoutSkip(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(asset), true, amount, user);
        vm.stopPrank();
        loggMiniPool(user, 1, address(asset));
    }

    function withdraw(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.withdraw(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 2, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function withdrawMiniPool(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        IMiniPool(miniPool).withdraw(address(asset), false, amount, user);
        vm.stopPrank();
        loggMiniPool(user, 2, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function repay(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.repay(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 3, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function repayMiniPool(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(miniPool, amount);
        IMiniPool(miniPool).repay(address(asset), false, amount, user);
        vm.stopPrank();
        loggMiniPool(user, 3, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function plateau(uint256 period) public {
        ERC20 dai = erc20Tokens[3];
        for (uint256 i = 0; i < period; i++) {
            repay(users[0], dai, 1);
            borrow(users[0], dai, 1);

            // logg(address(0), 1, address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1));
            // skip(DEFAULT_TIME_BEFORE_OP);
            // logg(address(1), 1, address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1));
            // skip(DEFAULT_TIME_BEFORE_OP);
        }
    }

    function plateauMiniPool(uint256 period) public {
        ERC20 dai = erc20Tokens[3];
        for (uint256 i = 0; i < period; i++) {
            repayMiniPool(users[0], dai, 1);
            borrowMiniPool(users[0], dai, 1);

            // logg(address(0), 1, address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1));
            // skip(DEFAULT_TIME_BEFORE_OP);
            // logg(address(1), 1, address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1));
            // skip(DEFAULT_TIME_BEFORE_OP);
        }
    }

    function logg(address user, uint256 action, address asset) public {
        (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate, uint256 utilizationRate) =
            pidStrat.getCurrentInterestRates();

        // console.log("MINI POOL: ", address(miniPool));
        // console.log("MAIN LENDING POOL: ", address(deployedContracts.lendingPool));
        // int256 errI = pidStrat._errI();
        // console.log("miniErrI in logg: ", uint256(miniPoolPidStrat._errI()));
        // console.log("mainErrI in logg: ", uint256(pidStrat._errI()));
        // console.log("ki: ", pidStrat._ki());

        string memory data = string(
            abi.encodePacked(
                Strings.toString(block.timestamp),
                ",",
                Strings.toHexString(user),
                ",",
                Strings.toString(action),
                ",",
                Strings.toHexString(asset),
                ",",
                Strings.toString(utilizationRate),
                ",",
                Strings.toString(currentLiquidityRate),
                ",",
                Strings.toString(currentVariableBorrowRate)
            )
        );
        // ",",
        // Strings.toString(availableLiquidity),
        // ",",
        // Strings.toString(currentDebt),
        // ",",
        // Strings.toString(uint256(errI))

        vm.writeLine(path, data);
    }

    function loggMiniPool(address user, uint256 action, address asset) public {
        (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate, uint256 utilizationRate) =
            miniPoolPidStrat.getCurrentInterestRates();

        // console.log("MAIN STRAT: ", address(pidStrat));
        // console.log("MINI STRAT: ", address(miniPoolPidStrat));
        // int256 errI = miniPoolPidStrat._errI();
        // console.log("miniErrI in logg: ", uint256(miniPoolPidStrat._errI()));
        // console.log("mainErrI in logg: ", uint256(pidStrat._errI()));
        // console.log("ki: ", miniPoolPidStrat._ki());

        string memory data = string(
            abi.encodePacked(
                Strings.toString(block.timestamp),
                ",",
                Strings.toHexString(user),
                ",",
                Strings.toString(action),
                ",",
                Strings.toHexString(asset),
                ",",
                Strings.toString(utilizationRate),
                ",",
                Strings.toString(currentLiquidityRate),
                ",",
                Strings.toString(currentVariableBorrowRate)
            )
        );
        // ",",
        // Strings.toString(uint256(errI))

        vm.writeLine(pathMiniPool, data);
    }

    function plateauMiniPool_(uint256 period, address token, address user) public {
        console.log("1.Token:", token);
        // deal(address(token), users[0], 10);
        for (uint256 i = 0; i < period; i++) {
            vm.startPrank(user);
            console.log("Approve");
            IERC20(token).approve(miniPool, 1);
            console.log("Repay");
            IMiniPool(miniPool).repay(address(token), false, 1, user);
            vm.stopPrank();
            skip(DEFAULT_TIME_BEFORE_OP);

            console.log("Borrowing MiniPool");
            vm.startPrank(user);
            IMiniPool(miniPool).borrow(address(token), false, 1, user);
            vm.stopPrank();
            skip(DEFAULT_TIME_BEFORE_OP);
        }
    }

    struct TestVars {
        address user;
        address whaleUser;
        uint256 mpId;
        address mp;
        address flowLimiter;
        IAERC6909 aErc6909Token;
        ERC20 underlying;
        ERC20 counterUnderlying;
        AToken aToken;
        VariableDebtToken debtToken;
        uint256 amount;
        uint256 underlyingPrice;
        uint256 counterUnderlyingPrice;
    }

    function testMiniPoolFlowLimiterDust(uint256 offset1, uint256 offset2) public {
        TestVars memory vars;
        offset1 = bound(offset1, 0, 3);
        offset2 = bound(offset2, 0, 3);

        uint256 debtToSet = 100000;
        vars.user = makeAddr("user");
        vars.mpId = 0;
        vars.mp = deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPool(vars.mpId);
        vm.label(vars.mp, "MiniPool");
        vars.aErc6909Token = IAERC6909(
            deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(vars.mp)
        );
        vm.label(address(vars.aErc6909Token), "aErc6909Token");

        vars.whaleUser = makeAddr("whaleUser");

        vars.underlying = erc20Tokens[offset1];
        vars.aToken = commonContracts.aTokensWrapper[offset1];
        vars.debtToken = commonContracts.variableDebtTokens[offset1];
        vars.amount = 1000 * 10 ** ERC20(vars.underlying).decimals();
        vars.counterUnderlying = erc20Tokens[offset2];
        vars.underlyingPrice = commonContracts.oracle.getAssetPrice(address(vars.underlying));
        vars.counterUnderlyingPrice =
            commonContracts.oracle.getAssetPrice(address(vars.counterUnderlying));

        deal(address(vars.underlying), vars.whaleUser, 1e26);
        deal(address(vars.counterUnderlying), vars.user, 1e26);

        vm.startPrank(deployedMiniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        deployedMiniPoolContracts.miniPoolConfigurator.setMinDebtThreshold(
            debtToSet, IMiniPool(vars.mp)
        );
        deployedMiniPoolContracts.miniPoolConfigurator.setCod3xTreasury(vars.user);
        vm.stopPrank();

        vm.startPrank(vars.whaleUser);
        vars.underlying.approve(address(deployedContracts.lendingPool), vars.amount * 1000); //500000 USDC
        deployedContracts.lendingPool.deposit(
            address(vars.underlying), true, vars.amount * 1000, vars.whaleUser
        );
        vm.stopPrank();

        console.log("Underlying: ", vars.underlying.symbol());
        console.log("Counter underlying: ", vars.counterUnderlying.symbol());

        vm.startPrank(vars.user);
        uint256 counterAmount = fixture_convertWithDecimals(
            vars.amount, vars.counterUnderlying.decimals(), vars.underlying.decimals()
        );
        console.log(
            "Counter amount: %s decimals counter: %s decimals under: %s",
            counterAmount,
            vars.counterUnderlying.decimals(),
            vars.underlying.decimals()
        );
        vars.counterUnderlying.approve(address(vars.mp), counterAmount);
        console.log("User balance: ", vars.counterUnderlying.balanceOf(vars.user));
        console.log("User depositAmount: %s %s", counterAmount, vars.counterUnderlying.symbol());
        IMiniPool(vars.mp).deposit(address(vars.counterUnderlying), false, counterAmount, vars.user);
        vm.stopPrank();

        vars.flowLimiter = address(deployedMiniPoolContracts.flowLimiter);

        console.log("UnderlyingPrice", vars.underlyingPrice);
        console.log("CounterUnderlyingPrice", vars.counterUnderlyingPrice);

        uint256 dust = 2 * (debtToSet * 10 ** vars.underlying.decimals()) / vars.underlyingPrice;

        console.log("Calculated DUST: ", dust);

        vm.prank(address(deployedMiniPoolContracts.miniPoolAddressesProvider));
        deployedMiniPoolContracts.flowLimiter.setFlowLimit(
            address(vars.underlying), vars.mp, dust * 10
        );

        //@audit borrow dust from empty minipool
        vm.startPrank(vars.user);
        console.log("User borrows %s %s", dust, vars.aToken.symbol());
        IMiniPool(vars.mp).borrow(address(vars.aToken), false, dust, vars.user); // Utilization becomes 1000000000000000000000000000 (RAY)
        assertEq(vars.debtToken.balanceOf(vars.mp), dust);

        //@audit Donate usdc to aErc6909 token
        vm.startPrank(vars.whaleUser);
        vars.underlying.approve(address(deployedContracts.lendingPool), vars.amount * 2); //500000 USDC
        console.log("User deposits %s %s", dust, vars.aToken.symbol());
        deployedContracts.lendingPool.deposit(
            address(vars.underlying), true, vars.amount, address(vars.aErc6909Token)
        );
        vm.stopPrank();

        vm.startPrank(address(deployedMiniPoolContracts.miniPoolConfigurator));
        IMiniPool(vars.mp).syncRatesState(address(vars.aToken)); // Utilization is 19999999999600000 (~2e16)
        vm.stopPrank();

        console.log("Time travel 1");
        vm.warp(block.timestamp + 4000);
        vm.roll(block.number + 1);

        console.log("Deposit");
        vm.startPrank(vars.whaleUser);
        vars.aToken.approve(vars.mp, 1 ether);
        IMiniPool(vars.mp).deposit(address(vars.aToken), false, dust, vars.user);
        vm.stopPrank();
    }

    // function testMiniPoolFlowLimiterDust(uint256 debtToSet) public {
    //     TestVars memory vars;
    //     debtToSet = bound(debtToSet, 1e2, 1e8);
    //     vars.user = makeAddr("user");
    //     vars.mpId = 0;
    //     vars.mp = deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPool(vars.mpId);
    //     vm.label(vars.mp, "MiniPool");
    //     vars.aErc6909Token = IAERC6909(
    //         deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(vars.mp)
    //     );
    //     vm.label(address(vars.aErc6909Token), "aErc6909Token");

    //     vars.whaleUser = makeAddr("whaleUser");

    //     vars.usdc = erc20Tokens[0];
    //     vars.grainUSDC = commonContracts.aTokensWrapper[0];
    //     vars.debtUSDC = commonContracts.variableDebtTokens[0];
    //     vars.amount = 5e8; //bound(amount, 1E6, 1E13); /* $500 */ // consider fuzzing here
    //     vars.dai = erc20Tokens[3];

    //     deal(address(vars.usdc), vars.whaleUser, vars.amount * 2000);
    //     deal(address(vars.dai), vars.user, 100000 ether);

    //     vm.prank(deployedMiniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
    //     deployedMiniPoolContracts.miniPoolConfigurator.setMinDebtThreshold(
    //         debtToSet, IMiniPool(vars.mp)
    //     );

    //     vm.startPrank(vars.whaleUser);
    //     vars.usdc.approve(address(deployedContracts.lendingPool), vars.amount * 1000); //500000 USDC
    //     deployedContracts.lendingPool.deposit(
    //         address(vars.usdc), true, vars.amount * 1000, vars.whaleUser
    //     );
    //     vm.stopPrank();

    //     vm.startPrank(vars.user);
    //     vars.dai.approve(address(vars.mp), vars.amount * 1e14);
    //     console.log("User balance: ", vars.dai.balanceOf(vars.user) / (10 ** 18));
    //     console.log("User depositAmount: ", vars.amount * 1e14 / (10 ** 18));
    //     IMiniPool(vars.mp).deposit(address(vars.dai), false, vars.amount * 1e14, vars.user);
    //     vm.stopPrank();

    //     vars.flowLimiter = address(deployedMiniPoolContracts.flowLimiter);

    //     uint256 dust = IMiniPool(vars.mp).getMinDebtThreshold();

    //     vm.prank(address(deployedMiniPoolContracts.miniPoolAddressesProvider));
    //     deployedMiniPoolContracts.flowLimiter.setFlowLimit(address(vars.usdc), vars.mp, dust * 10); // 50000 USDC

    //     //@audit borrow dust from empty minipool
    //     vm.startPrank(vars.user);

    //     IMiniPool(vars.mp).borrow(address(vars.grainUSDC), false, dust, vars.user); // Utilization becomes 1000000000000000000000000000 (RAY)
    //     assertEq(vars.debtUSDC.balanceOf(vars.mp), dust);

    //     //@audit Donate usdc to aErc6909 token
    //     vm.startPrank(vars.whaleUser);
    //     vars.usdc.approve(address(deployedContracts.lendingPool), vars.amount * 1000); //500000 USDC
    //     deployedContracts.lendingPool.deposit(
    //         address(vars.usdc), true, vars.amount * 1000, address(vars.aErc6909Token)
    //     );
    //     vm.stopPrank();

    //     vm.startPrank(address(deployedMiniPoolContracts.miniPoolConfigurator));
    //     IMiniPool(vars.mp).syncRatesState(address(vars.grainUSDC)); // Utilization is 19999999999600000 (~2e16)
    //     vm.stopPrank();

    //     console.log("Time travel 1");
    //     vm.warp(block.timestamp + 4000);
    //     vm.roll(block.number + 1);

    //     console.log("Deposit");
    //     vm.startPrank(vars.whaleUser);
    //     vars.grainUSDC.approve(vars.mp, 1 ether);
    //     IMiniPool(vars.mp).deposit(address(vars.grainUSDC), false, dust, vars.user);
    //     vm.stopPrank();

    // }
}
