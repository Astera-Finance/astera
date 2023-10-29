// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

contract MockAggregator {
  int256 private _latestAnswer;

  int256 private _decimals;

  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 timestamp);

  constructor(int256 _initialAnswer, int256 decimals) public {
    _latestAnswer = _initialAnswer;
    _decimals = decimals;
    emit AnswerUpdated(_initialAnswer, 0, now);
  }

  function latestAnswer() external view returns (int256) {
    return _latestAnswer;
  }

  function decimals() external view returns (int256) {
    return _decimals;
  }

  function getTokenType() external view returns (uint256) {
    return 1;
  }

  // function getSubTokens() external view returns (address[] memory) {
  // TODO: implement mock for when multiple subtokens. Maybe we need to create diff mock contract
  // to call it from the migration for this case??
  // }
}
