// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

contract MockAggregator {
    int256 private latestAnswer_;
    int256 private decimals_;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 timestamp);

    constructor(int256 _initialAnswer, int256 decimals) {
        latestAnswer_ = _initialAnswer;
        decimals_ = decimals;
        emit AnswerUpdated(_initialAnswer, 0, block.timestamp);
    }

    function setAssetPrice(uint256 _price) external {
        latestAnswer_ = int256(_price);
    }

    function latestAnswer() external view returns (int256) {
        return latestAnswer_;
    }

    function decimals() external view returns (int256) {
        return decimals_;
    }

    function getTokenType() external view returns (uint256) {
        return 1;
    }

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
        return (1, latestAnswer_, 1, block.timestamp, 0);
    }
}
