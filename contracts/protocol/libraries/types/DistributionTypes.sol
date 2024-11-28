// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @title DistributionTypes
 * @author Cod3x
 * @notice Library containing data structures used for reward distribution
 */
library DistributionTypes {
    /**
     * @notice Configuration parameters for reward distribution
     * @param emissionPerSecond Amount of rewards emitted per second
     * @param totalSupply Total supply of the asset being incentivized
     * @param distributionEnd Timestamp when the reward distribution ends
     * @param asset Address of the incentivized asset
     * @param reward Address of the reward token
     */
    struct RewardsConfigInput {
        uint88 emissionPerSecond;
        uint256 totalSupply;
        uint32 distributionEnd;
        address asset;
        address reward;
    }

    /**
     * @notice Configuration parameters for minipool reward distribution
     * @param emissionPerSecond Amount of rewards emitted per second
     * @param totalSupply Total supply of the minipool asset being incentivized
     * @param distributionEnd Timestamp when the reward distribution ends
     * @param asset ERC6909 asset identifier
     * @param reward Address of the reward token
     */
    struct MiniPoolRewardsConfigInput {
        uint88 emissionPerSecond;
        uint256 totalSupply;
        uint32 distributionEnd;
        Asset6909 asset;
        address reward;
    }

    /**
     * @notice Input parameters for user asset data
     * @param underlyingAsset Address of the underlying asset
     * @param userBalance User's balance of the asset
     * @param totalSupply Total supply of the asset
     */
    struct UserAssetInput {
        address underlyingAsset;
        uint256 userBalance;
        uint256 totalSupply;
    }

    /**
     * @notice Input parameters for user minipool asset data
     * @param asset ERC6909 asset identifier
     * @param userBalance User's balance of the minipool asset
     * @param totalSupply Total supply of the minipool asset
     */
    struct UserMiniPoolAssetInput {
        Asset6909 asset;
        uint256 userBalance;
        uint256 totalSupply;
    }

    /**
     * @notice Identifier for an ERC6909 asset
     * @param market6909 Address of the ERC6909 market contract
     * @param assetID ID of the asset within the ERC6909 contract
     */
    struct Asset6909 {
        address market6909;
        uint256 assetID;
    }
}
