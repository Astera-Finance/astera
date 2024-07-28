// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import "contracts/protocol/lendingpool/InterestRateStrategies/PidReserveInterestRateStrategy.sol";
import "contracts/protocol/lendingpool/InterestRateStrategies/PiReserveInterestRateStrategy.sol";
import "node_modules/@openzeppelin/contracts/utils/Strings.sol";

contract PidReserveInterestRateStrategyTest is Common {
    using WadRayMath for uint256;

    ERC20[] erc20Tokens;
    address[] users;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;
    PiReserveInterestRateStrategy pidStrat;

    string path = "./tests/foundry/pidTests/datas/output.csv";
    uint256 nbUsers = 4;
    uint256 initialAmt = 1e12 ether;
    uint256 DEFAULT_TIME_BEFORE_OP = 6 hours;

    function setUp() public {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);
        deployedContracts = fixture_deployProtocol();

        // pidStrat = new PidReserveInterestRateStrategy(
        //     deployedContracts.lendingPoolAddressesProvider,
        //     DAI,
        //     true,
        //     -80e25, //-192e24, // min rate == 0.5%
        //     20 days, // min I amp
        //     80e25, // Optimal Utilization Rate (80%)
        //     1e27, // Kp
        //     13e19, // Ki
        //     0 // Kd
        // );

        pidStrat = new PiReserveInterestRateStrategy(
            deployedContracts.lendingPoolAddressesProvider,
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
            address(deployedContracts.protocolDataProvider),
            address(pidStrat), // address(deployedContracts.stableStrategy), usdc, dai
            address(deployedContracts.volatileStrategy), // address(deployedContracts.volatileStrategy), wbtc, weth
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
        aTokens = fixture_getATokens(tokens, deployedContracts.protocolDataProvider);
        variableDebtTokens =
            fixture_getVarDebtTokens(tokens, deployedContracts.protocolDataProvider);
        mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 100_000_000 ether, address(this));

        /// users
        for (uint256 i = 0; i < 4; i++) {
            users.push(vm.addr(i + 1));
            for (uint256 j = 1; j < erc20Tokens.length; j++) {
                // Start at j=1 because usdc can't be "deal()".
                deal(address(erc20Tokens[j]), users[i], initialAmt);
            }
        }

        /// file setup
        if (vm.exists(path)) vm.removeFile(path);
        vm.writeLine(
            path,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate"
        );
    }

    function testTF() public view {
        console.log("transferFunction == ", pidStrat.transferFunction(-400e24) / (1e27 / 10000)); // bps
    }

    // 4 users  (users[0], users[1], users[2], users[3])
    // 3 tokens (wbtc, eth, dai)
    function testPid() public {
        IERC20 wbtc = erc20Tokens[1]; // wbtcPrice =  670000,0000000$
        IERC20 eth = erc20Tokens[2]; // ethPrice =  3700,00000000$
        IERC20 dai = erc20Tokens[3]; // daiPrice =  1,00000000$

        deposit(users[0], wbtc, 2e8);
        deposit(users[1], wbtc, 20e8);
        deposit(users[1], dai, 100_000e18);

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
    // ------------------------------
    // ---------- Helpers -----------
    // ------------------------------

    function deposit(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 0, address(asset));
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
        logg(user, 1, address(asset));
    }

    function withdraw(address user, IERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.withdraw(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 2, address(asset));
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

    function logg(address user, uint256 action, address asset) public {
        (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate, uint256 utilizationRate) =
            pidStrat.getCurrentInterestRates();

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

        vm.writeLine(path, data);
    }
}
