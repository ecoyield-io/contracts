// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {EcoYieldTokenVesting, VestingBucketData} from "../src/EcoYieldTokenVesting.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {EcoYieldToken} from "../src/EcoYieldToken.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract EcoYieldTokenVestingTest is Test {
    EcoYieldTokenVesting public tokenVesting;
    EcoYieldToken public ecoYieldToken;

    address public owner;
    address public nonOwner;

    address public beneficiary1;
    address public beneficiary2;

    address public proxyAdmin;

    bytes32 public merkleRoot;
    bytes32[] public merkleProof1;
    bytes32[] public merkleProof2;

    uint256 public totalAllocation1 = 1000e18;
    uint256 public totalAllocation2 = 2000e18;
    uint256 public totalAllocation3 = 3000e18;

    function setUp() public {
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");

        beneficiary1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        beneficiary2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        beneficiary3 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

        proxyAdmin = makeAddr("proxyAdmin");

        // 1. Deploy the EcoYieldToken implementation
        EcoYieldToken implementation = new EcoYieldToken();
        // 2. Prepare the initializer function call for EcoYieldToken
        bytes memory data = abi.encodeWithSelector(EcoYieldToken.initialize.selector, owner);
        // 3. Deploy the proxy for EcoYieldToken and initialize it
        ecoYieldToken = EcoYieldToken(address(new TransparentUpgradeableProxy(address(implementation), proxyAdmin, data)));

        vm.prank(owner);
        tokenVesting = new EcoYieldTokenVesting(address(ecoYieldToken));

        merkleRoot = 0xb6ca1073130689fdbf9763129a6b4557851bb77a371eae96598fdf90ec18e97c;

        merkleProof1 = new bytes32[](1);
        merkleProof1[0] = 0x9b0bc27a9e8f6a8a4b2e92b71ac31b44ef9bd5a54f150ed7b7c2668c6b9be039;

        merkleProof2 = new bytes32[](1);
        merkleProof2[0] = 0x208697df1b2d4c083944c10909fe1ed6e99c1eaccff33ba129464b28f8245f01;

        vm.prank(owner);
        ecoYieldToken.mint(address(tokenVesting), 1_000_000_000 ether);
    }

    /// @notice This test verifies that the owner can create multiple vesting buckets at once.
    function test_CreateVestingBuckets() public {
        VestingBucketData[] memory buckets = new VestingBucketData[](2);

        bytes32 bucketId1 = keccak256(abi.encodePacked("BUCKET_1"));
        buckets[0] = VestingBucketData({
            bucketId: bucketId1,
            merkleRoot: merkleRoot,
            totalAllocatedAmount: 1000e18,
            immediateUnlockBps: 1000, // 10%
            cliffInDays: 30,
            vestingInDays: 365,
            startTimestamp: block.timestamp + 1,
            proofsCID: "cid1"
        });

        bytes32 bucketId2 = keccak256(abi.encodePacked("BUCKET_2"));
        buckets[1] = VestingBucketData({
            bucketId: bucketId2,
            merkleRoot: merkleRoot,
            totalAllocatedAmount: 2000e18,
            immediateUnlockBps: 2000, // 20%
            cliffInDays: 60,
            vestingInDays: 730,
            startTimestamp: block.timestamp + 1,
            proofsCID: "cid2"
        });

        vm.prank(owner);
        tokenVesting.createVestingBuckets(buckets);

        (bool initialized1, bytes32 merkleRootValue1, , , uint256 immediateUnlockBpsValue1, , , ) = tokenVesting.vestingBuckets(bucketId1);
        assertTrue(initialized1, "Bucket 1 should be initialized");
        assertEq(merkleRootValue1, merkleRoot, "Bucket 1 merkle root mismatch");
        assertEq(immediateUnlockBpsValue1, 1000, "Bucket 1 immediate unlock bps mismatch");

        (bool initialized2, bytes32 merkleRootValue2, , , uint256 immediateUnlockBpsValue2, , , ) = tokenVesting.vestingBuckets(bucketId2);
        assertTrue(initialized2, "Bucket 2 should be initialized");
        assertEq(merkleRootValue2, merkleRoot, "Bucket 2 merkle root mismatch");
        assertEq(immediateUnlockBpsValue2, 2000, "Bucket 2 immediate unlock bps mismatch");
    }

    /// @notice This test ensures that only the owner can create vesting buckets.
    function test_FailCreateVestingBuckets_NotOwner() public {
        VestingBucketData[] memory buckets = new VestingBucketData[](1);

        bytes32 bucketId1 = keccak256(abi.encodePacked("BUCKET_1"));
        buckets[0] = VestingBucketData({
            bucketId: bucketId1,
            merkleRoot: merkleRoot,
            totalAllocatedAmount: 1000e18,
            immediateUnlockBps: 1000,
            cliffInDays: 30,
            vestingInDays: 365,
            startTimestamp: block.timestamp + 1,
            proofsCID: "cid1"
        });

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        tokenVesting.createVestingBuckets(buckets);
    }

    /// @notice This test verifies that the transaction reverts if one of the buckets already exists.
    function test_FailCreateVestingBuckets_BucketAlreadyExists() public {
        // Create one bucket first
        bytes32 bucketId1 = keccak256(abi.encodePacked("BUCKET_1"));
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId1,
            merkleRoot,
            1000e18,
            1000,
            30,
            365,
            block.timestamp + 1,
            "cid1"
        );

        // Prepare an array with a new bucket and the existing one
        VestingBucketData[] memory buckets = new VestingBucketData[](2);
        bytes32 bucketId2 = keccak256(abi.encodePacked("BUCKET_2"));
        buckets[0] = VestingBucketData({
            bucketId: bucketId2,
            merkleRoot: merkleRoot,
            totalAllocatedAmount: 2000e18,
            immediateUnlockBps: 2000,
            cliffInDays: 60,
            vestingInDays: 730,
            startTimestamp: block.timestamp + 1,
            proofsCID: "cid2"
        });
        buckets[1] = VestingBucketData({
            bucketId: bucketId1, // Existing bucket
            merkleRoot: merkleRoot,
            totalAllocatedAmount: 1000e18,
            immediateUnlockBps: 1000,
            cliffInDays: 30,
            vestingInDays: 365,
            startTimestamp: block.timestamp + 1,
            proofsCID: "cid1"
        });

        vm.prank(owner);
        vm.expectRevert(TokenVesting.BucketAlreadyExists.selector);
        tokenVesting.createVestingBuckets(buckets);
    }

    function test_SuccessfulClaim() public {
        bytes32 bucketId = keccak256(abi.encodePacked("SUCCESSFUL_CLAIM_BUCKET"));

        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            totalAllocation1 + totalAllocation2,
            1000, // 10% immediate unlock
            30,   // 30-day cliff
            365,  // 365-day vesting
            block.timestamp + 1,
            "cid1"
        );

        // Claim initial TGE amount
        uint256 expectedVestedAmount = tokenVesting.getReleasableAmount(bucketId, beneficiary1, totalAllocation1);
        assertEq(expectedVestedAmount, totalAllocation1 * 10 / 100);

        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);

        assertEq(ecoYieldToken.balanceOf(beneficiary1), expectedVestedAmount, "Beneficiary should receive the TGE tokens");
    }

    function test_FailClaim_InvalidProof() public {
        bytes32 bucketId = keccak256(abi.encodePacked("INVALID_PROOF_BUCKET"));

        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            totalAllocation1 + totalAllocation2,
            1000, // 10% immediate unlock
            30,   // 30-day cliff
            365,  // 365-day vesting
            block.timestamp + 1,
            "cid1"
        );

        // Attempt to claim with an invalid proof (proof for another user)
        vm.prank(beneficiary1);
        vm.expectRevert(TokenVesting.InvalidMerkleProof.selector);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof2);

        // Attempt to claim with a completely invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("invalid"));

        vm.prank(beneficiary1);
        vm.expectRevert(TokenVesting.InvalidMerkleProof.selector);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, invalidProof);
    }

    function test_Claim_BeforeCliff() public {
        bytes32 bucketId = keccak256(abi.encodePacked("BEFORE_CLIFF_BUCKET"));

        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            totalAllocation1 + totalAllocation2,
            1000, // 10% immediate unlock
            30,   // 30-day cliff
            365,  // 365-day vesting
            block.timestamp + 1,
            "cid1"
        );

        // 1. Claim immediate unlock
        uint256 expectedTGE = (totalAllocation1 * 1000) / 10000;
        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);
        assertEq(ecoYieldToken.balanceOf(beneficiary1), expectedTGE, "Beneficiary should only receive the immediate unlock amount");

        // 2. Attempt to claim again before cliff, should fail
        vm.warp(block.timestamp + 20 days);
        vm.prank(beneficiary1);
        vm.expectRevert(TokenVesting.NoTokensToRelease.selector);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);
    }

    function test_Claim_AfterVestingEnds() public {
        bytes32 bucketId = keccak256(abi.encodePacked("AFTER_VESTING_ENDS_BUCKET"));

        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            totalAllocation1 + totalAllocation2,
            1000, // 10% immediate unlock
            30,   // 30-day cliff
            365,  // 365-day vesting
            block.timestamp + 1,
            "cid1"
        );

        // Fast-forward time to after the vesting period
        vm.warp(block.timestamp + 400 days);

        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);

        assertEq(ecoYieldToken.balanceOf(beneficiary1), totalAllocation1, "Beneficiary should receive the total allocation");
    }
}