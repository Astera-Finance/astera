// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ERC20} from "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {Rewarder} from "contracts/protocol/rewarder/lendingpool/Rewarder.sol";
// import "contracts/protocol/core/Oracle.sol";
import {ProtocolDataProvider} from "contracts/misc/ProtocolDataProvider.sol";
import {Treasury} from "contracts/misc/Treasury.sol";
// import "contracts/misc/UiPoolDataProviderV2.sol";
import {WETHGateway} from "contracts/misc/WETHGateway.sol";
// import "contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
// import "contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
// import "contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import {LendingPoolAddressesProvider} from
    "contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import {DefaultReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import {PiReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";
import {MiniPoolDefaultReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import {MiniPoolPiReserveInterestRateStrategy} from
    "contracts/protocol/core/interestRateStrategies/minipool/MiniPoolPiReserveInterestRateStrategy.sol";
import {LendingPool} from "contracts/protocol/core/lendingpool/LendingPool.sol";
import {LendingPoolCollateralManager} from
    "contracts/protocol/core/lendingpool/LendingPoolCollateralManager.sol";
import {LendingPoolConfigurator} from
    "contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import {MiniPool} from "contracts/protocol/core/minipool/MiniPool.sol";
import {MiniPoolAddressesProvider} from
    "contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import {MiniPoolConfigurator} from "contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import {FlowLimiter} from "contracts/protocol/core/minipool/FlowLimiter.sol";


import {ATokensAndRatesHelper} from "contracts/deployments/ATokensAndRatesHelper.sol";
import {AToken} from "contracts/protocol/tokenization/ERC20/AToken.sol";
import {ATokenERC6909} from "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import {VariableDebtToken} from "contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
// import "contracts/mocks/tokens/MintableERC20.sol";
// import "contracts/mocks/tokens/WETH9Mocked.sol";
// import "contracts/mocks/oracle/MockAggregator.sol";
// import "contracts/mocks/tokens/MockVault.sol";
// import "contracts/mocks/tokens/MockStrat.sol";
// import {ExternalContract} from "contracts/mocks/tokens/ExternalContract.sol";
import {IStrategy} from "contracts/mocks/dependencies/IStrategy.sol";
// import "contracts/mocks/dependencies/IExternalContract.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";

// import "contracts/protocol/core/minipool/MiniPoolDefaultReserveInterestRate.sol";
// import "contracts/mocks/oracle/PriceOracle.sol";
// import "contracts/protocol/core/minipool/MiniPoolCollateralManager.sol";

// Structures
struct DeployedContracts {
    Rewarder rewarder;
    LendingPoolAddressesProvider lendingPoolAddressesProvider;
    LendingPool lendingPool;
    Treasury treasury;
    LendingPoolConfigurator lendingPoolConfigurator;
    DefaultReserveInterestRateStrategy[] stableStrategies;
    DefaultReserveInterestRateStrategy[] volatileStrategies;
    PiReserveInterestRateStrategy[] piStrategies;
    MiniPoolDefaultReserveInterestRateStrategy[] miniPoolVolatileStrategies;
    MiniPoolDefaultReserveInterestRateStrategy[] miniPoolStableStrategies;
    MiniPoolPiReserveInterestRateStrategy[] miniPoolPiStrategies;
    ProtocolDataProvider protocolDataProvider;
    ATokensAndRatesHelper aTokensAndRatesHelper;
    AToken aToken;
    VariableDebtToken variableDebtToken;
    WETHGateway wETHGateway;
    LendingPoolCollateralManager lendingPoolCollateralManager;
    MiniPoolCollateralManager miniPoolCollateralManager;
    ATokenERC6909 aTokenErc6909;
    MiniPool miniPoolImpl;
    MiniPoolAddressesProvider miniPoolAddressesProvider;
    MiniPoolConfigurator miniPoolConfigurator;
    FlowLimiter flowLimiter;
}

struct TokenParams {
    ERC20 token;
    AToken aToken;
    uint256 price;
}

struct ConfigParams {
    uint256[] baseLTVs;
    uint256[] liquidationThresholds;
    uint256[] liquidationBonuses;
    uint256[] reserveFactors;
    bool[] borrowingEnabled;
    bool[] reserveTypes;
    bool[] isStableStrategy;
}

struct MiniPoolConfigParams {
    address[] mainPoolAssets;
    ConfigParams mainPoolConfig;
    address[] miniPoolAssets;
    ConfigParams miniPoolConfig;
}

/**
 * DEPLOYMENT CONFIG STRUCTURES ******************
 */
struct General {
    string aTokenNamePrefix;
    string aTokenSymbolPrefix;
    string debtTokenNamePrefix;
    string debtTokenSymbolPrefix;
}

struct Roles {
    address emergencyAdmin;
    address poolAdmin;
}

struct PoolAddressesProviderConfig {
    string marketId;
    uint256 poolId;
}

struct PoolReserversConfig {
    uint256 baseLtv;
    bool borrowingEnabled;
    string interestStrat;
    uint256 interestStratId;
    uint256 liquidationBonus;
    uint256 liquidationThreshold;
    string params;
    uint256 rates;
    uint256 reserveFactor;
    bool reserveType;
    string symbol;
    address tokenAddress;
}

struct LinearStrategy {
    uint256 baseVariableBorrowRate;
    uint256 optimalUtilizationRate;
    uint256 variableRateSlope1;
    uint256 variableRateSlope2;
}

struct PiStrategy {
    bool assetReserveType;
    uint256 ki;
    uint256 kp;
    int256 maxITimeAmp;
    int256 minControllerError;
    uint256 optimalUtilizationRate;
    string symbol;
    address tokenAddress;
}

struct OracleConfig {
    address[] assets;
    address baseCurrency;
    uint256 baseCurrencyUnit;
    address fallbackOracle;
    address[] sources;
}

struct MockedToken {
    uint256 decimals;
    uint256 prices;
    string symbol;
}

// struct LendingPoolInfra {
//     address lendingPoolAddressesProvider;
//     address lendingPool;
//     address aTokenErc6909;
//     address lendingPoolConfigurator;
// }

/*   
 "piStrategy": {},
 "miniPoolReserves": {} 
 */
// struct PiStrategy {

// }

struct DeploymentConfig {
    General general;
    Roles roles;
    PoolAddressesProviderConfig poolAddressesProviderConfig;
    PoolReserversConfig[] poolReserversConfig;
    LinearStrategy volatileStrategy;
    LinearStrategy stableStrategy;
}

// PoolAddressesProviderConfig poolAddressesProviderConfig;

// LinearStrategy linearStrategy;
