// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/library/Ln.sol";

contract LogarithmLibraryTest is Test {
    function testLnAsFraction() public pure {
        (uint256 numerator, uint256 denominator) = LogarithmLibrary.lnAsFraction(5, 1);

        uint256 expectedNumerator = 1609437912434100374;
        uint256 expectedDenominator = 1000000000000000000;

        assertEq(numerator, expectedNumerator, "Numerator should be equal");
        assertEq(denominator, expectedDenominator, "Denominator should be equal");
    }

    function testLnAsFractionWithZero() public {
        vm.expectRevert("Numerator must be greater than 0");
        LogarithmLibrary.lnAsFraction(0, 1);
    }
}
