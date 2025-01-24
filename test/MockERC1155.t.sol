// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DLCNode is ERC1155, Ownable {
    constructor(address owner) ERC1155("") Ownable(owner) {}

    function mint(address to, uint256 level, uint256 amount) public {
        _mint(to, level, amount, "");
    }
}
