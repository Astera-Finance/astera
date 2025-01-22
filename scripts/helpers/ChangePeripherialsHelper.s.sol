// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import "contracts/misc/Treasury.sol";
import "contracts/protocol/tokenization/ERC20/AToken.sol";
import "contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import "../DeployDataTypes.sol";
import {DataTypes} from "contracts/protocol/libraries/types/DataTypes.sol";
import {Rewarder6909} from "contracts/protocol/rewarder/minipool/Rewarder6909.sol";

import "forge-std/console.sol";

contract ChangePeripherialsHelper {
    address constant FOUNDRY_DEFAULT = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    DeployedContracts contracts;

    function _changePeripherials(
        NewPeripherial[] memory treasury,
        NewMiniPoolPeripherial memory cod3xTreasury,
        NewPeripherial[] memory vault,
        NewPeripherial[] memory rewarder,
        NewPeripherial[] memory rewarder6909,
        uint256 _miniPoolId
    ) internal {
        require(treasury.length == vault.length, "Lengths of settings must be the same");
        require(treasury.length == rewarder.length, "Lengths settings must be the same");

        if (cod3xTreasury.configure == true) {
            contracts.miniPoolConfigurator.setCod3xTreasury(cod3xTreasury.newAddress);
        }

        for (uint8 idx = 0; idx < treasury.length; idx++) {
            if (treasury[idx].configure == true) {
                (address[] memory list,) = contracts.lendingPool.getReservesList();
                for (uint256 i = 0; i < list.length; i++) {
                    console.log("%s. Address: %s", i, list[i]);
                }
                DataTypes.ReserveData memory data = contracts.lendingPool.getReserveData(
                    treasury[idx].tokenAddress, treasury[idx].reserveType
                );
                require(
                    data.aTokenAddress != address(0), "tokenAddress not available in lendingPool"
                );
                contracts.lendingPoolConfigurator.setTreasury(
                    treasury[idx].tokenAddress, treasury[idx].reserveType, treasury[idx].newAddress
                );
            }
            if (vault[idx].configure == true) {
                DataTypes.ReserveData memory data = contracts.lendingPool.getReserveData(
                    vault[idx].tokenAddress, vault[idx].reserveType
                );
                require(
                    data.aTokenAddress != address(0), "tokenAddress not available in lendingPool"
                );
                contracts.lendingPoolConfigurator.setVault(
                    data.aTokenAddress, vault[idx].newAddress
                );
            }
            if (rewarder[idx].configure == true) {
                DataTypes.ReserveData memory data = contracts.lendingPool.getReserveData(
                    rewarder[idx].tokenAddress, rewarder[idx].reserveType
                );
                require(
                    data.aTokenAddress != address(0), "tokenAddress not available in lendingPool"
                );
                if (address(AToken(data.aTokenAddress).getIncentivesController()) == address(0)) {
                    if (address(contracts.rewarder) == address(0)) {
                        // There is no rewarder -> deploy new one
                        contracts.rewarder = new Rewarder(); // @issue: Rewarder NOT SAFE
                    }

                    contracts.lendingPoolConfigurator.setRewarderForReserve(
                        rewarder[idx].tokenAddress,
                        rewarder[idx].reserveType,
                        address(contracts.rewarder)
                    );
                } else {
                    // Set rewarder defined in config
                    contracts.lendingPoolConfigurator.setRewarderForReserve(
                        rewarder[idx].tokenAddress,
                        rewarder[idx].reserveType,
                        rewarder[idx].newAddress
                    );
                }
            }
            if (rewarder6909[idx].configure == true) {
                address mp = contracts.miniPoolAddressesProvider.getMiniPool(_miniPoolId);
                DataTypes.MiniPoolReserveData memory data =
                    IMiniPool(mp).getReserveData(rewarder6909[idx].tokenAddress);
                console.log("Configuration for: ", rewarder6909[idx].tokenAddress);
                require(data.aErc6909 != address(0), "aErc6909 not available in lendingPool");
                if (address(ATokenERC6909(data.aErc6909).getIncentivesController()) == address(0)) {
                    if (address(contracts.rewarder6909) == address(0)) {
                        // There is no rewarder -> deploy new one
                        contracts.rewarder6909 = new Rewarder6909();
                    }
                    contracts.miniPoolConfigurator.setRewarderForReserve(
                        rewarder6909[idx].tokenAddress,
                        address(contracts.rewarder6909),
                        IMiniPool(mp)
                    );
                } else {
                    // Set rewarder defined in config
                    contracts.miniPoolConfigurator.setRewarderForReserve(
                        rewarder6909[idx].tokenAddress,
                        address(rewarder6909[idx].newAddress),
                        IMiniPool(mp)
                    );
                }
            }
        }
    }

    function _turnOnRehypothecation(Rehypothecation[] memory rehypothecationSettings) internal {
        for (uint8 idx = 0; idx < rehypothecationSettings.length; idx++) {
            Rehypothecation memory rehypothecationSetting = rehypothecationSettings[idx];
            if (rehypothecationSetting.configure == true) {
                DataTypes.ReserveData memory reserveData = contracts.lendingPool.getReserveData(
                    rehypothecationSetting.tokenAddress, rehypothecationSetting.reserveType
                );
                require(
                    reserveData.aTokenAddress != address(0),
                    "aTokenAddress not available in lendingPool"
                );
                if (address(AToken(reserveData.aTokenAddress)._vault()) == address(0)) {
                    contracts.lendingPoolConfigurator.setVault(
                        reserveData.aTokenAddress, rehypothecationSetting.vault
                    );
                }

                contracts.lendingPoolConfigurator.setFarmingPct(
                    reserveData.aTokenAddress, rehypothecationSetting.farmingPct
                );
                contracts.lendingPoolConfigurator.setClaimingThreshold(
                    reserveData.aTokenAddress, rehypothecationSetting.claimingThreshold
                );
                contracts.lendingPoolConfigurator.setFarmingPctDrift(
                    reserveData.aTokenAddress, rehypothecationSetting.drift
                );
                contracts.lendingPoolConfigurator.setProfitHandler(
                    reserveData.aTokenAddress, rehypothecationSetting.profitHandler
                );
            }
        }
    }
}
