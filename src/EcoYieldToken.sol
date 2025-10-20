// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20CappedUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract EcoYieldToken is Initializable, OwnableUpgradeable, ERC20Upgradeable, ERC20CappedUpgradeable, ERC20PermitUpgradeable {

    string private constant _NAME = "EcoYield";
    string private constant _SYMBOL = "EYE";
    uint256 private constant _TOTAL_SUPPLY = 1_000_000_000 ether;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner_) public initializer {
        __Ownable_init(initialOwner_);
        __ERC20_init(_NAME, _SYMBOL);
        __ERC20Capped_init(_TOTAL_SUPPLY);
        __ERC20Permit_init(_NAME);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        super._mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20CappedUpgradeable, ERC20Upgradeable) {
        super._update(from, to, value);
    }
}