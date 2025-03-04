// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

/**
 * @title DistributionTypes
 * @author Cod3x
 * @notice Library containing data structures used for reward distribution.
 * @dev Contains core data structures for managing reward distributions and user asset data.
 */
library DistributionTypes {
    /**
     * @notice Configuration parameters for reward distribution.
     * @param emissionPerSecond Amount of rewards emitted per second, expressed in reward token decimals.
     * @param totalSupply Total supply of the asset being incentivized.
     * @param distributionEnd Timestamp when the reward distribution ends.
     * @param asset Address of the incentivized asset.
     * @param reward Address of the reward token being distributed.
     */
    struct RewardsConfigInput {
        uint88 emissionPerSecond;
        uint256 totalSupply;
        uint32 distributionEnd;
        address asset;
        address reward;
    }

    /**
     * @notice Configuration parameters for minipool reward distribution.
     * @param emissionPerSecond Amount of rewards emitted per second, expressed in reward token decimals.
     * @param totalSupply Total supply of the minipool asset being incentivized.
     * @param distributionEnd Timestamp when the reward distribution ends.
     * @param asset ERC6909 asset identifier containing `market6909` and `assetID`.
     * @param reward Address of the reward token being distributed.
     */
    struct MiniPoolRewardsConfigInput {
        uint88 emissionPerSecond;
        uint32 distributionEnd;
        Asset6909 asset;
        address reward;
    }

    /**
     * @notice Input parameters for user asset data.
     * @param underlyingAsset Address of the underlying asset being tracked.
     * @param userBalance User's balance of the `underlyingAsset`.
     * @param totalSupply Total supply of the `underlyingAsset` in the protocol.
     */
    struct UserAssetInput {
        address underlyingAsset;
        uint256 userBalance;
        uint256 totalSupply;
    }

    /**
     * @notice Input parameters for user minipool asset data.
     * @param asset ERC6909 asset identifier containing `market6909` and `assetID`.
     * @param userBalance User's balance of the minipool asset.
     * @param totalSupply Total supply of the minipool asset in the protocol.
     */
    struct UserMiniPoolAssetInput {
        Asset6909 asset;
        uint256 userBalance;
        uint256 totalSupply;
    }

    /**
     * @notice Identifier for an ERC6909 asset.
     * @param market6909 Address of the ERC6909 market contract.
     * @param assetID ID of the asset within the `market6909` contract.
     */
    struct Asset6909 {
        address market6909;
        uint256 assetID;
    }
}
