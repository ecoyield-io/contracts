// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {EcoYieldToken} from "../src/EcoYieldToken.sol";

contract EcoYieldTokenTest is Test {
    EcoYieldToken public ecoYieldToken;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        ecoYieldToken = new EcoYieldToken(owner);
    }

    function test_InitialState() public view {
        assertEq(ecoYieldToken.name(), "EcoYield");
        assertEq(ecoYieldToken.symbol(), "EYE");
        assertEq(ecoYieldToken.decimals(), 18);
        assertEq(ecoYieldToken.cap(), 1_000_000_000 ether);
        assertEq(ecoYieldToken.totalSupply(), 1_000_000_000 ether);
        assertEq(ecoYieldToken.balanceOf(owner), 1_000_000_000 ether);
    }

    function test_Transfer() public {
        uint256 amount = 1000e18;
        vm.prank(owner);
        bool success = ecoYieldToken.transfer(user1, amount);
        assertTrue(success);
        assertEq(ecoYieldToken.balanceOf(owner), 1_000_000_000 ether - amount);
        assertEq(ecoYieldToken.balanceOf(user1), amount);
    }

    function test_ApproveAndTransferFrom() public {
        uint256 amount = 1000e18;

        vm.prank(owner);
        ecoYieldToken.approve(user1, amount);

        assertEq(ecoYieldToken.allowance(owner, user1), amount);

        vm.prank(user1);
        bool success = ecoYieldToken.transferFrom(owner, user2, amount);

        assertTrue(success);
        assertEq(ecoYieldToken.balanceOf(owner), 1_000_000_000 ether - amount);
        assertEq(ecoYieldToken.balanceOf(user2), amount);
    }
}
