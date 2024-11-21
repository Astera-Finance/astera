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
            address(0)
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
            address(aToken),
            configAddresses,
            deployedContracts.lendingPoolConfigurator,
            deployedContracts.lendingPoolAddressesProvider
        );

        miniPool = deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPool(0);
        console.log("2.Minipool: ", miniPool);

        aTokens = fixture_getATokens(tokens, deployedContracts.cod3xLendDataProvider);
        // variableDebtTokens = fixture_getVarDebtTokens(tokens, deployedContracts.cod3xLendDataProvider);
        mockedVaults = fixture_deployReaperVaultMocks(tokens, address(deployedContracts.treasury));
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
                reserves[idx] = address(aTokens[idx - tokens.length]);
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
        IMiniPool(miniPool).borrow(address(asset), amount, user);
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
        IMiniPool(miniPool).repay(address(asset), amount, user);
        vm.stopPrank();
        loggMiniPool(user, 3, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function plateau(uint256 period) public {
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
}
