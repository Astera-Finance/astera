// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ERC20} from "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {Rewarder} from "contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import {ProtocolDataProvider} from "contracts/misc/ProtocolDataProvider.sol";
import {Treasury} from "contracts/misc/Treasury.sol";
import {WETHGateway} from "contracts/misc/WETHGateway.sol";
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
import {Oracle} from "contracts/protocol/core/Oracle.sol";
import {IStrategy} from "contracts/mocks/dependencies/IStrategy.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import {MiniPoolCollateralManager} from
    "contracts/protocol/core/minipool/MiniPoolCollateralManager.sol";

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
    Oracle oracle;
}

struct TokenParams {
    ERC20 token;
    AToken aToken;
    uint256 price;
}

/**
 * DEPLOYMENT CONFIG STRUCTURES ******************
 */
struct General {
    string aTokenNamePrefix;
    string aTokenSymbolPrefix;
    string debtTokenNamePrefix;
    string debtTokenSymbolPrefix;
    address wethAddress;
}

struct Roles {
    address addressesProviderOwner;
    address emergencyAdmin;
    address oracleOwner;
    address piInterestStrategiesOwner;
    address poolAdmin;
    address rewarderOwner;
    address treasuryOwner;
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
    uint256[] timeouts;
}

struct MockedToken {
    uint256 decimals;
    uint256 prices;
    string symbol;
}

struct NewPeripherial {
    bool configure;
    address newAddress;
    bool reserveType;
    string symbol;
    address tokenAddress;
}

struct Rehypothecation {
    uint256 claimingThreshold;
    bool configure;
    uint256 drift;
    uint256 farmingPct;
    address profitHandler;
    bool reserveType;
    string symbol;
    address tokenAddress;
    address vault;
}
