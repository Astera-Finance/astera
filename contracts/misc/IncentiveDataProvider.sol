// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20Detailed} from
    "../../contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";

import {IMiniPool} from "../../contracts/interfaces/IMiniPool.sol";
import {IAERC6909} from "../../contracts/interfaces/IAERC6909.sol";
import {Ownable} from "../../contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IChainlinkAggregator} from "../../contracts/interfaces/base/IChainlinkAggregator.sol";
import {
    IIncentiveDataProvider,
    AggregatedReserveIncentiveData,
    RewardInfo,
    UserReserveIncentiveData,
    UserRewardInfo
} from "../../contracts/interfaces/IIncentiveDataProvider.sol";
import {IMiniPoolAddressesProvider} from "../../contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";
import {IMiniPoolRewarder} from "../../contracts/interfaces/IMiniPoolRewarder.sol";
import {IMiniPoolRewardsDistributor} from
    "../../contracts/interfaces/IMiniPoolRewardsDistributor.sol";
import {DistributionTypes} from "../../contracts/protocol/libraries/types/DistributionTypes.sol";
import {IAToken} from "../../contracts/interfaces/IAToken.sol";

contract IncentiveDataProvider is Ownable, IIncentiveDataProvider {
    IMiniPoolAddressesProvider miniPoolAddressProvider;

    constructor(address _miniPoolAddressProvider) Ownable(msg.sender) {
        miniPoolAddressProvider = IMiniPoolAddressesProvider(_miniPoolAddressProvider);
    }

    function getReservesIncentivesData()
        external
        view
        returns (AggregatedReserveIncentiveData[] memory)
    {
        return _getReservesIncentivesData();
    }

    function getUserReservesIncentivesData(address user)
        external
        view
        returns (UserReserveIncentiveData[] memory)
    {
        return _getUserReservesIncentivesData(user);
    }

    // generic method with full data
    function getFullReservesIncentiveData(address user)
        external
        view
        returns (AggregatedReserveIncentiveData[] memory, UserReserveIncentiveData[] memory)
    {
        return (_getReservesIncentivesData(), _getUserReservesIncentivesData(user));
    }

    function _getReservesIncentivesData()
        private
        view
        returns (AggregatedReserveIncentiveData[] memory aggregatedReserveIncentiveData)
    {
        uint256 miniPoolCount = miniPoolAddressProvider.getMiniPoolCount();

        // Keeping 1d array prevents stack too deep
        {
            uint256 reservesAcrossAllMiniPools;
            for (uint256 idx = 0; idx < miniPoolCount; idx++) {
                IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(idx));
                (address[] memory reserves,) = miniPool.getReservesList();
                reservesAcrossAllMiniPools += reserves.length;
            }
            aggregatedReserveIncentiveData =
                new AggregatedReserveIncentiveData[](reservesAcrossAllMiniPools);
        }
        uint256 previousIdx = 0;
        for (uint256 idx = 0; idx < miniPoolCount; idx++) {
            IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(idx));
            (address[] memory reserves,) = miniPool.getReservesList();

            for (uint256 i = previousIdx; i < (previousIdx + reserves.length); i++) {
                AggregatedReserveIncentiveData memory reserveIncentiveData =
                    aggregatedReserveIncentiveData[i];
                reserveIncentiveData.underlyingAsset = reserves[i - previousIdx];
                reserveIncentiveData.miniPool = address(miniPool);

                DataTypes.MiniPoolReserveData memory reserveData =
                    miniPool.getReserveData(reserveIncentiveData.underlyingAsset);

                // aToken
                address miniPoolRewarder =
                    address(IAERC6909(reserveData.aErc6909).getIncentivesController());

                DistributionTypes.Asset6909 memory asset6909 =
                    DistributionTypes.Asset6909(reserveData.aErc6909, reserveData.aTokenID);

                reserveIncentiveData.erc6909 = reserveData.aErc6909;
                reserveIncentiveData.asTokenId = reserveData.aTokenID;
                reserveIncentiveData.asDebtTokenId = reserveData.variableDebtTokenID;
                reserveIncentiveData.incentiveControllerAddress = miniPoolRewarder;

                reserveIncentiveData.asIncentiveData = _getIncentiveData(
                    miniPoolRewarder, reserveIncentiveData.underlyingAsset, asset6909
                );

                asset6909 = DistributionTypes.Asset6909(
                    reserveData.aErc6909, reserveData.variableDebtTokenID
                );

                reserveIncentiveData.asDebtIncentiveData = _getIncentiveData(
                    miniPoolRewarder, reserveIncentiveData.underlyingAsset, asset6909
                );
            }
            previousIdx += reserves.length;
        }
        return aggregatedReserveIncentiveData;
    }

    function _getIncentiveData(
        address _miniPoolRewarder,
        address _underlyingAsset,
        DistributionTypes.Asset6909 memory _asset6909
    ) private view returns (RewardInfo[] memory incentiveData) {
        RewardInfo[] memory rewardsInformation;
        if (address(_miniPoolRewarder) != address(0)) {
            address[] memory rewardsForReserve = IMiniPoolRewardsDistributor(_miniPoolRewarder)
                .getRewardsByAsset(_asset6909.market6909, _asset6909.assetID);
            rewardsInformation = new RewardInfo[](rewardsForReserve.length);
            for (uint256 j = 0; j < rewardsForReserve.length; ++j) {
                RewardInfo memory rewardInformation;

                rewardInformation.rewardTokenAddress = rewardsForReserve[j];

                (
                    rewardInformation.tokenIncentivesIndex,
                    rewardInformation.emissionPerSecond,
                    rewardInformation.incentivesLastUpdateTimestamp,
                    rewardInformation.emissionEndTimestamp
                ) = IMiniPoolRewardsDistributor(_miniPoolRewarder).getRewardsData(
                    _asset6909.market6909, _asset6909.assetID, rewardInformation.rewardTokenAddress
                );

                rewardInformation.precision =
                    IMiniPoolRewardsDistributor(_miniPoolRewarder).getAssetDecimals(_asset6909);
                rewardInformation.rewardTokenDecimals =
                    IERC20Detailed(rewardInformation.rewardTokenAddress).decimals();
                rewardInformation.rewardTokenSymbol =
                    IERC20Detailed(rewardInformation.rewardTokenAddress).symbol();

                rewardInformation.rewardOracleAddress = IOracle(
                    miniPoolAddressProvider.getPriceOracle()
                ).getSourceOfAsset(_underlyingAsset);
                rewardInformation.rewardOracleAddress = rewardInformation.rewardOracleAddress
                    != address(0)
                    ? rewardInformation.rewardOracleAddress
                    : IOracle(miniPoolAddressProvider.getPriceOracle()).getSourceOfAsset(
                        IAToken(_underlyingAsset).UNDERLYING_ASSET_ADDRESS()
                    );
                rewardInformation.priceFeedDecimals =
                    IChainlinkAggregator(rewardInformation.rewardOracleAddress).decimals();
                rewardInformation.rewardPriceFeed =
                    IChainlinkAggregator(rewardInformation.rewardOracleAddress).latestAnswer();

                rewardsInformation[j] = rewardInformation;
            }
        }
        return rewardsInformation;
    }

    function _getUserReservesIncentivesData(address user)
        private
        view
        returns (UserReserveIncentiveData[] memory userReservesIncentivesData)
    {
        uint256 miniPoolCount = miniPoolAddressProvider.getMiniPoolCount();
        if (user == address(0)) {
            return userReservesIncentivesData;
        }
        // Keeping 1d array prevents stack too deep
        {
            uint256 reservesAcrossAllMiniPools;
            for (uint256 idx = 0; idx < miniPoolCount; idx++) {
                IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(idx));
                (address[] memory reserves,) = miniPool.getReservesList();
                reservesAcrossAllMiniPools += reserves.length;
            }
            userReservesIncentivesData = new UserReserveIncentiveData[](reservesAcrossAllMiniPools);
        }
        uint256 previousIdx = 0;
        for (uint256 idx = 0; idx < miniPoolCount; idx++) {
            IMiniPool miniPool = IMiniPool(miniPoolAddressProvider.getMiniPool(idx));
            (address[] memory reserves,) = miniPool.getReservesList();

            for (uint256 i = previousIdx; i < previousIdx + reserves.length; i++) {
                UserReserveIncentiveData memory userReservesIncentiveData =
                    userReservesIncentivesData[i];
                userReservesIncentiveData.underlyingAsset = reserves[i - previousIdx];
                userReservesIncentiveData.miniPool = address(miniPool);

                DataTypes.MiniPoolReserveData memory reserveData =
                    miniPool.getReserveData(userReservesIncentiveData.underlyingAsset);

                // aToken
                address miniPoolRewarder =
                    address(IAERC6909(reserveData.aErc6909).getIncentivesController());

                DistributionTypes.Asset6909 memory asset6909 =
                    DistributionTypes.Asset6909(reserveData.aErc6909, reserveData.aTokenID);

                userReservesIncentiveData.erc6909 = reserveData.aErc6909;
                userReservesIncentiveData.asTokenId = reserveData.aTokenID;
                userReservesIncentiveData.asDebtTokenId = reserveData.variableDebtTokenID;
                userReservesIncentiveData.incentiveControllerAddress = miniPoolRewarder;

                userReservesIncentiveData.asTokenIncentivesUserData = _getUserIncentiveData(
                    user, miniPoolRewarder, userReservesIncentiveData.underlyingAsset, asset6909
                );
                asset6909 = DistributionTypes.Asset6909(
                    reserveData.aErc6909, reserveData.variableDebtTokenID
                );
                userReservesIncentiveData.asDebtTokenIncentivesUserData = _getUserIncentiveData(
                    user, miniPoolRewarder, userReservesIncentiveData.underlyingAsset, asset6909
                );
            }
            previousIdx += reserves.length;
        }
        return userReservesIncentivesData;
    }

    function _getUserIncentiveData(
        address user,
        address _miniPoolRewarder,
        address _underlyingAsset,
        DistributionTypes.Asset6909 memory _asset6909
    ) private view returns (UserRewardInfo[] memory userIncentiveData) {
        UserRewardInfo[] memory userRewardsInformation;
        if (address(_miniPoolRewarder) != address(0)) {
            address[] memory rewardsForReserve = IMiniPoolRewardsDistributor(_miniPoolRewarder)
                .getRewardsByAsset(_asset6909.market6909, _asset6909.assetID);
            userRewardsInformation = new UserRewardInfo[](rewardsForReserve.length);
            for (uint256 j = 0; j < rewardsForReserve.length; ++j) {
                UserRewardInfo memory userRewardInformation;
                userRewardInformation.rewardTokenAddress = rewardsForReserve[j];

                userRewardInformation.tokenIncentivesUserIndex = IMiniPoolRewardsDistributor(
                    _miniPoolRewarder
                ).getUserAssetData(
                    user,
                    _asset6909.market6909,
                    _asset6909.assetID,
                    userRewardInformation.rewardTokenAddress
                );

                userRewardInformation.userUnclaimedRewards = IMiniPoolRewardsDistributor(
                    _miniPoolRewarder
                ).getUserUnclaimedRewardsFromStorage(user, userRewardInformation.rewardTokenAddress);
                userRewardInformation.rewardTokenDecimals =
                    IERC20Detailed(userRewardInformation.rewardTokenAddress).decimals();
                userRewardInformation.rewardTokenSymbol =
                    IERC20Detailed(userRewardInformation.rewardTokenAddress).symbol();

                userRewardInformation.rewardOracleAddress = IOracle(
                    miniPoolAddressProvider.getPriceOracle()
                ).getSourceOfAsset(_underlyingAsset);
                userRewardInformation.rewardOracleAddress = userRewardInformation
                    .rewardOracleAddress != address(0)
                    ? userRewardInformation.rewardOracleAddress
                    : IOracle(miniPoolAddressProvider.getPriceOracle()).getSourceOfAsset(
                        IAToken(_underlyingAsset).UNDERLYING_ASSET_ADDRESS()
                    );
                userRewardInformation.priceFeedDecimals =
                    IChainlinkAggregator(userRewardInformation.rewardOracleAddress).decimals();
                userRewardInformation.rewardPriceFeed =
                    IChainlinkAggregator(userRewardInformation.rewardOracleAddress).latestAnswer();

                userRewardsInformation[j] = userRewardInformation;
            }
        }
        return userRewardsInformation;
    }
}
