// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockTokenA is ERC20, Ownable {
    constructor() ERC20("MockTokenA", "MTA") Ownable(msg.sender) {
    _mint(msg.sender, 1000 * 10**18);
    _mint(0x9f8F02DAB384DDdf1591C3366069Da3Fb0018220, 700000 * 10**18);
}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}