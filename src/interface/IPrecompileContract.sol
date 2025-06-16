// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPrecompileContract {
    function getDLCPrice() external view returns (uint256);
}
