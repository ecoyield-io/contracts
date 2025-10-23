// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract EcoYieldToken is ERC20, ERC20Capped, ERC20Permit {
    string private constant _NAME = "EcoYield";
    string private constant _SYMBOL = "EYE";
    uint256 private constant _TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor(address recipient_) ERC20(_NAME, _SYMBOL) ERC20Capped(_TOTAL_SUPPLY) ERC20Permit(_NAME) {
        _mint(recipient_, _TOTAL_SUPPLY);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20Capped, ERC20) {
        super._update(from, to, value);
    }
}
