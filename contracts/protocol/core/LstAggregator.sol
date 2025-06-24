// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IChainlinkAggregator} from "../../../contracts/interfaces/base/IChainlinkAggregator.sol";
/**
 * @title LstAggregator
 * @dev This contract is a aggregator for LST (Liquid Staking Token) prices
 * It combines the prices of the underlying asset in USD and the LST in underlying.
 * @author xRave110
 * @notice
 */

contract LstAggregator is IChainlinkAggregator {
    struct AnswerData {
        // Packed to minimize storage costs (32 bytes per slot)
        int256 underlyingAnswer;
        int256 lstAnswer;
        uint256 underlyingStartedAt;
        uint256 lstStartedAt;
        uint256 underlyingUpdatedAt;
        uint256 lstUpdatedAt;
        uint80 underlyingRoundId;
        uint80 lstRoundId;
        uint80 underlyingAnsweredInRound;
        uint80 lstAnsweredInRound;
    }

    error LstAggregator_ServiceNotAvailable();

    IChainlinkAggregator public immutable underlyingPriceFeed;
    IChainlinkAggregator public immutable lstPriceFeed;

    string public aggregatorName;

    /**
     *
     * @param _underlyingPriceFeed - Address of the underlying asset price feed valued in USD
     * @param _lstPriceFeed - Address of the LST price feed valued in underlying asset
     * @param _aggregatorName - aggregator name example: LST/USD
     */
    constructor(
        address _underlyingPriceFeed,
        address _lstPriceFeed,
        string memory _aggregatorName
    ) {
        underlyingPriceFeed = IChainlinkAggregator(_underlyingPriceFeed);
        lstPriceFeed = IChainlinkAggregator(_lstPriceFeed);
        aggregatorName = _aggregatorName;
    }

    function latestAnswer() external view returns (int256) {
        int256 _underlyingLatestAnswer;
        int256 _lstLatestAnswer;
        if (underlyingPriceFeed.decimals() != 18) {
            _underlyingLatestAnswer = (underlyingPriceFeed.latestAnswer())
                * int256(10 ** (18 - underlyingPriceFeed.decimals()));
        } else {
            _underlyingLatestAnswer = (underlyingPriceFeed.latestAnswer());
        }
        if (lstPriceFeed.decimals() != 18) {
            _lstLatestAnswer =
                (lstPriceFeed.latestAnswer()) * int256(10 ** (18 - lstPriceFeed.decimals()));
        } else {
            _lstLatestAnswer = lstPriceFeed.latestAnswer();
        }
        return _underlyingLatestAnswer * _lstLatestAnswer / 1e28; //decimals 8
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestTimestamp() external view returns (uint256) {
        uint256 underlyingLatestTimestamp = underlyingPriceFeed.latestTimestamp();
        uint256 lstLatestTimestamp = lstPriceFeed.latestTimestamp();
        return underlyingLatestTimestamp < lstLatestTimestamp
            ? underlyingLatestTimestamp
            : lstLatestTimestamp;
    }

    function latestRound() external view returns (uint256 roundId) {
        return underlyingPriceFeed.latestRound() < lstPriceFeed.latestRound()
            ? underlyingPriceFeed.latestRound()
            : lstPriceFeed.latestRound();
    }

    function getAnswer(uint256 roundId) external view returns (int256) {
        revert LstAggregator_ServiceNotAvailable();
    }

    function getTimestamp(uint256 roundId) external view returns (uint256) {
        revert LstAggregator_ServiceNotAvailable();
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        revert LstAggregator_ServiceNotAvailable();
    }

    /**
     * @notice get data about the latest round. Consumers are encouraged to check
     * that they're receiving fresh data by inspecting the updatedAt and
     * answeredInRound return values.
     * Note that different underlying implementations of AggregatorV3Interface
     * have slightly different semantics for some of the return values. Consumers
     * should determine what implementations they expect to receive
     * data from and validate that they can properly handle return data from all
     * of them.
     * @return roundId is the round ID from the aggregator for which the data was
     * retrieved combined with an phase to ensure that round IDs get larger as
     * time moves forward.
     * @return answer is the answer for the given round
     * @return startedAt is the timestamp when the round was started.
     * (Only some AggregatorV3Interface implementations return meaningful values)
     * @return updatedAt is the timestamp when the round last was updated (i.e.
     * answer was last computed)
     * @return answeredInRound is the round ID of the round in which the answer
     * was computed.
     * (Only some AggregatorV3Interface implementations return meaningful values)
     * @dev Note that answer and updatedAt may change between queries.
     * @dev Taken the smallest roundId, startedAt and updatedAt from the two price feeds
     * @dev Taken the latest answer from the two price feeds and multiplied them together
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        int256 _underlyingLatestAnswer;
        int256 _lstLatestAnswer;
        AnswerData memory answerData;
        (
            answerData.underlyingRoundId,
            answerData.underlyingAnswer,
            answerData.underlyingStartedAt,
            answerData.underlyingUpdatedAt,
            answerData.underlyingAnsweredInRound
        ) = underlyingPriceFeed.latestRoundData();
        if (underlyingPriceFeed.decimals() != 18) {
            _underlyingLatestAnswer =
                answerData.underlyingAnswer * int256(10 ** (18 - underlyingPriceFeed.decimals()));
        } else {
            _underlyingLatestAnswer = int256(answerData.underlyingAnswer);
        }
        (
            answerData.lstRoundId,
            answerData.lstAnswer,
            answerData.lstStartedAt,
            answerData.lstUpdatedAt,
            answerData.lstAnsweredInRound
        ) = lstPriceFeed.latestRoundData();
        if (lstPriceFeed.decimals() != 18) {
            _lstLatestAnswer = answerData.lstAnswer * int256(10 ** (18 - lstPriceFeed.decimals()));
        } else {
            _lstLatestAnswer = int256(answerData.lstAnswer);
        }
        return (
            answerData.underlyingRoundId < answerData.lstRoundId
                ? answerData.underlyingRoundId
                : answerData.lstRoundId,
            int256(_underlyingLatestAnswer * _lstLatestAnswer / 1e28), // decimals 8
            answerData.underlyingStartedAt < answerData.lstStartedAt
                ? answerData.underlyingStartedAt
                : answerData.lstStartedAt,
            answerData.underlyingUpdatedAt < answerData.lstUpdatedAt
                ? answerData.underlyingUpdatedAt
                : answerData.lstUpdatedAt,
            answerData.underlyingAnsweredInRound < answerData.lstAnsweredInRound
                ? answerData.underlyingAnsweredInRound
                : answerData.lstAnsweredInRound
        );
    }
}
