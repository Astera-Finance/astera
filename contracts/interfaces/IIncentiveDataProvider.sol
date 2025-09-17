// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {ILendingPoolAddressesProvider} from "contracts/interfaces/ILendingPoolAddressesProvider.sol";

struct AggregatedReserveIncentiveData {
    address miniPool;
    address underlyingAsset;
    address erc6909;
    uint256 asTokenId;
    uint256 asDebtTokenId;
    address incentiveControllerAddress;
    RewardInfo[] asIncentiveData;
    RewardInfo[] asDebtIncentiveData;
}

struct RewardInfo {
    string rewardTokenSymbol;
    address rewardTokenAddress;
    address rewardOracleAddress;
    uint256 emissionPerSecond;
    uint256 incentivesLastUpdateTimestamp;
    uint256 tokenIncentivesIndex;
    uint256 emissionEndTimestamp;
    int256 rewardPriceFeed;
    uint8 rewardTokenDecimals;
    uint8 precision;
    uint8 priceFeedDecimals;
}

struct UserReserveIncentiveData {
    address miniPool;
    address underlyingAsset;
    address erc6909;
    uint256 asTokenId;
    uint256 asDebtTokenId;
    address incentiveControllerAddress;
    UserRewardInfo[] asTokenIncentivesUserData;
    UserRewardInfo[] asDebtTokenIncentivesUserData;
}

struct UserRewardInfo {
    string rewardTokenSymbol;
    address rewardOracleAddress;
    address rewardTokenAddress;
    uint256 userUnclaimedRewards;
    uint256 tokenIncentivesUserIndex;
    int256 rewardPriceFeed;
    uint8 priceFeedDecimals;
    uint8 rewardTokenDecimals;
}

interface IIncentiveDataProvider {
    function getReservesIncentivesData()
        external
        view
        returns (AggregatedReserveIncentiveData[] memory);

    function getUserReservesIncentivesData(address user)
        external
        view
        returns (UserReserveIncentiveData[] memory);

    // generic method with full data
    function getFullReservesIncentiveData(address user)
        external
        view
        returns (AggregatedReserveIncentiveData[] memory, UserReserveIncentiveData[] memory);
}
