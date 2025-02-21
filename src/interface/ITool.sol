// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITool {
    /**
     * @notice Calculates the natural logarithm of a uint256 value.
     * @param value The input value for which the natural logarithm will be calculated.
     * @return The natural logarithm of the input value scaled by DECIMALS.
     */
    function LnUint256(uint256 value) external pure returns (uint256);

    /**
     * @notice Scales a bytes16 value of a logarithm result by DECIMALS.
     * @param value The input logarithm result as a bytes16 value.
     * @return The scaled logarithm value as a uint256.
     */
    function getLnValue(bytes16 value) external pure returns (uint256);

    /**
     * @notice Safely divides two uint256 values, ensuring no division by zero occurs.
     * @param a The numerator value.
     * @param b The denominator value.
     * @return The result of the division scaled by DECIMALS.
     */
    function safeDiv(uint256 a, uint256 b) external pure returns (uint256);

    /**
     * @notice Retrieves the constant DECIMALS value.
     * @return The DECIMALS value used for scaling.
     */
    function getDecimals() external pure returns (uint256);

    function checkString(string memory text) external pure returns (bool);
}
