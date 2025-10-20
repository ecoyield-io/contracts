// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract VestingMerkles {
    address public beneficiary1 = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    uint256 public totalAllocation1 = 1000e18;

    address public beneficiary2 = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);
    uint256 public totalAllocation2 = 2000e18;

    address public beneficiary3 = address(0x90F79bf6EB2c4f870365E785982E1f101E93b906);
    uint256 public totalAllocation3 = 3000e18;

    bytes32 public merkleRoot = 0xbcd50390423ed3f762e1800f78adeb9d9fde408982b26f8efe690ee6cde5bf72;
    bytes32[] public merkleProof1;
    bytes32[] public merkleProof2;
    bytes32[] public merkleProof3;

    constructor() {
        merkleProof1 = new bytes32[](1);
        merkleProof1[0] = 0x0541e61141afebb0011a050b0dc862e275923d181980e9109cd367b08ad30255;

        merkleProof2 = new bytes32[](2);
        merkleProof2[0] = 0x6a9198834da4a56f6401053b95eb60aaa5cdb9a6bc2c5c124c77bd8f4a6ec557;
        merkleProof2[1] = 0xcf3c6863bafbe17e6c7ddb9cd7e0aa1851d06a1f17b60825e6991f59c408219f;
        
        merkleProof3 = new bytes32[](2);
        merkleProof3[0] = 0x944d16a73645b412501a366f0742db0ae0003a1eb02d7935239893fc720f439f;
        merkleProof3[1] = 0xcf3c6863bafbe17e6c7ddb9cd7e0aa1851d06a1f17b60825e6991f59c408219f;
    }
}
