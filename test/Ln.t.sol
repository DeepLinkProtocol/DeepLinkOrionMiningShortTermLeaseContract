// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/library/Ln.sol";
import "abdk-libraries-solidity/ABDKMathQuad.sol";

contract LogarithmLibraryTest is Test {
    function testLn() public pure {
        uint256 expectLn1W = 9210340371976182736;
        uint256 value = LogarithmLibrary.LnUint256(10000);
        assertEq(value, expectLn1W, "Ln(10000) should be equal to 9210340371976182736");
    }
}
