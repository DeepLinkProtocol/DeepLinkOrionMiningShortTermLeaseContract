pragma solidity ^0.8.20;

interface IOracle {
    function getTokenPriceInUSD(uint32 secondsAgo,address token) external view returns (uint256);
}