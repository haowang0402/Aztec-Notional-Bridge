// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {ERC20Burnable} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


contract FCashToken is ERC20Burnable {
    address public immutable owner;
    uint8 public immutable setDecimals;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        owner = msg.sender;
        setDecimals = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return setDecimals;
    }

    function mint(address to, uint256 amount) external {
        require(owner == msg.sender, "ZkAToken: INVALID OWNER");
        _mint(to, amount);
    }
}