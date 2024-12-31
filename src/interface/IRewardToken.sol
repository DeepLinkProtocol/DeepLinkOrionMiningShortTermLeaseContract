pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardToken is IERC20 {
    function burnFrom(address account, uint256 value) external;
}
