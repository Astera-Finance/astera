// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import "contracts/protocol/core/Oracle.sol";
import "contracts/misc/ProtocolDataProvider.sol";
import "contracts/misc/Treasury.sol";
import "contracts/misc/UiPoolDataProviderV2.sol";
import "contracts/misc/WETHGateway.sol";
import "contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import "contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
import "contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import "contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.sol";
import
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import "contracts/protocol/core/lendingpool/LendingPool.sol";
import "contracts/protocol/core/lendingpool/LendingPoolCollateralManager.sol";
import "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import "contracts/protocol/core/minipool/MiniPool.sol";
import "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import "contracts/protocol/core/minipool/FlowLimiter.sol";

import "contracts/deployments/ATokensAndRatesHelper.sol";
import "contracts/protocol/tokenization/ERC20/AToken.sol";
import "contracts/protocol/tokenization/ERC20/ATokenERC6909.sol";
import "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import "contracts/mocks/tokens/MintableERC20.sol";
import "contracts/mocks/tokens/WETH9Mocked.sol";
import "contracts/mocks/oracle/MockAggregator.sol";
import "contracts/mocks/tokens/MockVault.sol";
import "contracts/mocks/tokens/MockStrat.sol";
import "contracts/mocks/tokens/ExternalContract.sol";
import "contracts/mocks/dependencies/IStrategy.sol";
import "contracts/mocks/dependencies/IExternalContract.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

import "contracts/protocol/core/minipool/MiniPoolDefaultReserveInterestRate.sol";
import "contracts/mocks/oracle/PriceOracle.sol";
import "contracts/protocol/core/minipool/MiniPoolCollateralManager.sol";


// Structures
    struct DeployedContracts {
        LendingPoolAddressesProviderRegistry lendingPoolAddressesProviderRegistry;
        Rewarder rewarder;
        LendingPoolAddressesProvider lendingPoolAddressesProvider;
        LendingPool lendingPool;
        Treasury treasury;
        LendingPoolConfigurator lendingPoolConfigurator;
        DefaultReserveInterestRateStrategy stableStrategy;
        DefaultReserveInterestRateStrategy volatileStrategy;
        ProtocolDataProvider protocolDataProvider;
        ATokensAndRatesHelper aTokensAndRatesHelper;
        AToken aToken;
        VariableDebtToken variableDebtToken;
        WETHGateway wETHGateway;
        LendingPoolCollateralManager lendingPoolCollateralManager;
        ATokenERC6909 aTokenErc6909;
        MiniPool miniPoolImpl;
        MiniPoolAddressesProvider miniPoolAddressesProvider;
        MiniPoolConfigurator miniPoolConfigurator;
        flowLimiter flowLimiter;
    }

    struct TokenParams {
        ERC20 token;
        AToken aToken;
        uint256 price;
    }

    struct ConfigParams{
        uint256[] baseLTVs;
        uint256[] liquidationThresholds;
        uint256[] liquidationBonuses;
        uint256[] reserveFactors;
        bool[] borrowingEnabled;
        bool[] reserveTypes;
        bool[] isStableStrategy;
    }

    struct MiniPoolConfigParams{
        address[] mainPoolAssets;
        ConfigParams mainPoolConfig;
        address[] miniPoolAssets;
        ConfigParams miniPoolConfig;
    }
