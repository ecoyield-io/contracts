// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {EcoYieldToken} from "../src/EcoYieldToken.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ERC20CappedUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";

contract EcoYieldTokenTest is Test {
    EcoYieldToken public ecoYieldToken;

    address public owner;
    address public user1;
    address public user2;
    address public proxyAdmin;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        proxyAdmin = makeAddr("proxyAdmin");

        // 1. Deploy the implementation contract
        EcoYieldToken implementation = new EcoYieldToken();

        // 2. Prepare the initializer function call
        bytes memory data = abi.encodeWithSelector(EcoYieldToken.initialize.selector, owner);

        // 3. Deploy the proxy and initialize it
        ecoYieldToken =
            EcoYieldToken(address(new TransparentUpgradeableProxy(address(implementation), proxyAdmin, data)));
    }

    function test_InitialState() public view {
        assertEq(ecoYieldToken.name(), "EcoYield");
        assertEq(ecoYieldToken.symbol(), "EYE");
        assertEq(ecoYieldToken.decimals(), 18);
        assertEq(ecoYieldToken.owner(), owner);
        assertEq(ecoYieldToken.cap(), 1_000_000_000 ether);
        assertEq(ecoYieldToken.totalSupply(), 0);
    }

    function test_Mint() public {
        uint256 amount = 1000 ether;
        vm.prank(owner);
        ecoYieldToken.mint(user1, amount);

        assertEq(ecoYieldToken.balanceOf(user1), amount);
        assertEq(ecoYieldToken.totalSupply(), amount);
    }

    function test_FailMint_NotOwner() public {
        uint256 amount = 1000 ether;
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        ecoYieldToken.mint(user1, amount);
    }

    function test_FailMint_ExceedsCap() public {
        uint256 cap = ecoYieldToken.cap();
        uint256 amount = cap + 1;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ERC20CappedUpgradeable.ERC20ExceededCap.selector, amount, cap));
        ecoYieldToken.mint(user1, amount);
    }

    function test_Mint_ExactlyCap() public {
        uint256 cap = ecoYieldToken.cap();
        vm.prank(owner);
        ecoYieldToken.mint(user1, cap);
        assertEq(ecoYieldToken.balanceOf(user1), cap);
    }

    function test_Transfer() public {
        uint256 amount = 1000e18;
        vm.prank(owner);
        ecoYieldToken.mint(user1, amount);

        vm.prank(user1);
        bool success = ecoYieldToken.transfer(user2, amount);
        assertTrue(success);
        assertEq(ecoYieldToken.balanceOf(user1), 0);
        assertEq(ecoYieldToken.balanceOf(user2), amount);
    }

    function test_ApproveAndTransferFrom() public {
        uint256 amount = 1000e18;
        vm.prank(owner);
        ecoYieldToken.mint(owner, amount);

        vm.prank(owner);
        ecoYieldToken.approve(user1, amount);

        assertEq(ecoYieldToken.allowance(owner, user1), amount);

        vm.prank(user1);
        bool success = ecoYieldToken.transferFrom(owner, user2, amount);

        assertTrue(success);
        assertEq(ecoYieldToken.balanceOf(owner), 0);
        assertEq(ecoYieldToken.balanceOf(user2), amount);
    }
}
