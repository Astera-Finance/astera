// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @title DistributionTypes
 * @author Cod3x
 */
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
        Asset6909 asset;
        address reward;
    }

    struct UserAssetInput {
        address underlyingAsset;
        uint256 userBalance;
        uint256 totalSupply;
    }

    struct UserMiniPoolAssetInput {
        Asset6909 asset;
        uint256 userBalance;
        uint256 totalSupply;
    }

    struct Asset6909 {
        address market6909;
        uint256 assetID;
    }
}
