// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./MiniPoolFixtures.t.sol";
import "../../contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "../../contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "../../contracts/protocol/libraries/math/PercentageMath.sol";

contract MiniPoolLendingPoolFixRateStrategyTest is MiniPoolFixtures {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    ERC20[] erc20Tokens;

    function setUp() public override {
        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);

        // Deploy and configure main LendingPool with default strategies
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

        erc20Tokens = fixture_getErc20Tokens(tokens);
        fixture_transferTokensToTestContract(erc20Tokens, 1_000_000 ether, address(this));

        // Deploy MiniPool infra (addresses provider, configurator, aERC6909, etc.)
        uint256 miniPoolId;
        (miniPoolContracts, miniPoolId) = fixture_deployMiniPoolSetup(
            address(deployedContracts.lendingPoolAddressesProvider),
            address(deployedContracts.lendingPool),
            address(deployedContracts.asteraDataProvider),
            miniPoolContracts
        );

        // Create fixed-rate strategy bound to this MiniPool ID
        miniPoolContracts.fixStrategy = new MiniPoolFixReserveInterestRate(
            0.1e27 // 10% annualized borrow rate in ray
        );

        // Configure MiniPool reserves (use default strategies initially)
        address[] memory reserves = new address[](2 * tokens.length);
        for (uint8 idx = 0; idx < (2 * tokens.length); idx++) {
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
        miniPool = fixture_configureMiniPoolReserves(
            reserves, configLpAddresses, miniPoolContracts, miniPoolId
        );

        // Lower min debt threshold for tests
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setMinDebtThreshold(0, IMiniPool(miniPool));

        // Switch WBTC (underlying) to the fixed-rate strategy
        vm.prank(miniPoolContracts.miniPoolAddressesProvider.getMainPoolAdmin());
        miniPoolContracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
            address(erc20Tokens[WBTC_OFFSET]),
            address(miniPoolContracts.fixStrategy),
            IMiniPool(miniPool)
        );

        vm.label(miniPool, "MiniPool");
    }

    function testMiniPoolFixRateStrategy() public {
        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        // Collateral: deposit USDC into MiniPool for user
        TokenParams memory usdcParams = TokenParams(
            erc20Tokens[USDC_OFFSET],
            commonContracts.aTokensWrapper[USDC_OFFSET],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[USDC_OFFSET]))
        );
        // Liquidity: deposit WBTC into MiniPool for user2
        TokenParams memory wbtcParams = TokenParams(
            erc20Tokens[WBTC_OFFSET],
            commonContracts.aTokensWrapper[WBTC_OFFSET],
            commonContracts.oracle.getAssetPrice(address(erc20Tokens[WBTC_OFFSET]))
        );

        // Prepare liquidity and collateral
        fixture_depositTokensToMiniPool(
            1e8,
            1128 + WBTC_OFFSET,
            user2,
            wbtcParams,
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool))
        );
        fixture_depositTokensToMiniPool(
            33_500e6,
            1128 + USDC_OFFSET,
            user,
            usdcParams,
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool))
        );

        // user borrows 0.25 WBTC
        vm.prank(user);
        IMiniPool(miniPool).borrow(address(erc20Tokens[WBTC_OFFSET]), false, 0.25e8, user);

        // Advance 1 year, then touch WBTC reserve to realize interest
        skip(365 days);
        fixture_depositTokensToMiniPool(
            10,
            1128 + WBTC_OFFSET,
            user2,
            wbtcParams,
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool))
        );

        IAERC6909 aErc6909 =
            IAERC6909(miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(miniPool));

        // Debt should have grown ~10%
        assertApproxEqRel(
            aErc6909.balanceOf(user, 2128 + WBTC_OFFSET),
            0.276e8, // ~0.25e8 * 1.104 (compounded) ~ 0.275—0.276e8
            0.01e18
        );

        // Lender should earn some interest (strictly greater than principal)
        assertGt(aErc6909.balanceOf(user2, 1128 + WBTC_OFFSET), 1e8);
    }
}
