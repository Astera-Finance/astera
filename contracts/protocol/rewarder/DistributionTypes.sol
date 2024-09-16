// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library DistributionTypes {
    struct RewardsConfigInput {
        uint88 emissionPerSecond;
        uint256 totalSupply;
        uint32 distributionEnd;
        address asset;
        address reward;
    }

    struct MiniPoolRewardsConfigInput {
        uint88 emissionPerSecond;
        uint256 totalSupply;
        uint32 distributionEnd;
        asset6909 asset;
        address reward;
    }

    struct UserAssetInput {
        address underlyingAsset;
        uint256 userBalance;
        uint256 totalSupply;
    }

    struct UserMiniPoolAssetInput {
        asset6909 asset;
        uint256 userBalance;
        uint256 totalSupply;
    }

    struct asset6909 {
        address market6909;
        uint256 assetID;
    }
}
