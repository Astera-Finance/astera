// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

contract MockAggregator {
    int256 private _latestAnswer;
    int256 private _decimals;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 timestamp);

    constructor(int256 initialAnswer_, int256 decimals_) {
        _latestAnswer = initialAnswer_;
        _decimals = decimals_;
        emit AnswerUpdated(initialAnswer_, 0, block.timestamp);
    }

    function latestAnswer() external view returns (int256) {
        return _latestAnswer;
    }

    function decimals() external view returns (int256) {
        return _decimals;
    }

    function getTokenType() external pure returns (uint256) {
        return 1;
    }

    function setLastAnswer(int256 _newAnswer) external {
        _latestAnswer = _newAnswer;
        emit AnswerUpdated(_newAnswer, 0, block.timestamp);
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
        return (1, _latestAnswer, 1, block.timestamp, 0);
    }
}
