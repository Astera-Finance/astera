// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IPiReserveRateStrategy interface.
 * @author Conclave
 */
interface IPiReserveInterestRateStrategy {
    function baseVariableBorrowRate() external view returns (uint256);

    function getMaxVariableBorrowRate() external view returns (uint256);

    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external returns (uint256 liquidityRate, uint256 variableBorrowRate);

    function _minControllerError() external view returns (int256);

    function _maxErrIAmp() external view returns (int256);

    function _optimalUtilizationRate() external view returns (uint256);

    function _kp() external view returns (uint256);

    function _ki() external view returns (uint256);

    function _lastTimestamp() external view returns (uint256);

    function _errI() external view returns (int256);

    function getAvailableLiquidity(address asset, address aToken)
        external
        view
        returns (uint256, address, uint256);

    function getCurrentInterestRates() external view returns (uint256, uint256, uint256);

    function transferFunction(int256 controllerError) external view returns (uint256);
}
