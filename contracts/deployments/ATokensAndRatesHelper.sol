// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

import {LendingPool} from "../../contracts/protocol/core/lendingpool/LendingPool.sol";
import {
    LendingPoolAddressesProvider
} from "../../contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import {
    LendingPoolConfigurator
} from "../../contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import {AToken} from "../../contracts/protocol/tokenization/ERC20/AToken.sol";
import {
    DefaultReserveInterestRateStrategy
} from "../../contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import {Ownable} from "../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";

/**
 * @title ATokensAndRatesHelper
 * @notice AToken deployer helper
 * @author Conclave
 */
contract ATokensAndRatesHelper is Ownable {
    address private pool;
    address private addressesProvider;
    address private poolConfigurator;

    event deployedContracts(address aToken, address strategy);

    struct ConfigureReserveInput {
        address asset;
        bool reserveType;
        uint256 baseLTV;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
        bool borrowingEnabled;
    }

    constructor(address payable _pool, address _addressesProvider, address _poolConfigurator)
        Ownable(msg.sender)
    {
        pool = _pool;
        addressesProvider = _addressesProvider;
        poolConfigurator = _poolConfigurator;
    }

    function configureReserves(ConfigureReserveInput[] calldata inputParams) external onlyOwner {
        LendingPoolConfigurator configurator = LendingPoolConfigurator(poolConfigurator);
        for (uint256 i = 0; i < inputParams.length; i++) {
            configurator.configureReserveAsCollateral(
                inputParams[i].asset,
                inputParams[i].reserveType,
                inputParams[i].baseLTV,
                inputParams[i].liquidationThreshold,
                inputParams[i].liquidationBonus
            );

            if (inputParams[i].borrowingEnabled) {
                configurator.enableBorrowingOnReserve(
                    inputParams[i].asset, inputParams[i].reserveType
                );
            }
            configurator.setAsteraReserveFactor(
                inputParams[i].asset, inputParams[i].reserveType, inputParams[i].reserveFactor
            );
        }
    }
}
