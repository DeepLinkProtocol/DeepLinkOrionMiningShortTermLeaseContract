// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "abdk-libraries-solidity/ABDKMathQuad.sol";

library LogarithmLibrary {
    uint256 private constant DECIMALS = 1e18;

    function LnUint256(uint256 value) internal pure returns (uint256) {
        bytes16 v = ABDKMathQuad.ln(ABDKMathQuad.fromUInt(value));
        return getLnValue(v);
    }

    function getLnValue(bytes16 value) internal pure returns (uint256) {
        return ABDKMathQuad.toUInt(ABDKMathQuad.mul(value, ABDKMathQuad.fromUInt(DECIMALS)));
    }

    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "Division by zero");

        bytes16 scaledA = ABDKMathQuad.fromUInt(a * DECIMALS);

        bytes16 result = ABDKMathQuad.div(scaledA, ABDKMathQuad.fromUInt(b));

        return ABDKMathQuad.toUInt(result);
    }

    function getDecimals() internal pure returns (uint256) {
        return DECIMALS;
    }
}
