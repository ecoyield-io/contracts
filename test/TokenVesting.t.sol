// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice A mock ERC20 token for testing purposes.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract TokenVestingTest is Test {
    TokenVesting public tokenVesting;
    MockERC20 public mockToken;

    address public owner;
    address public nonOwner;

    bytes32 public bucketId;

    address public beneficiary1 = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    uint256 public totalAllocation1 = 1000e18;

    address public beneficiary2 = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);
    uint256 public totalAllocation2 = 2000e18;

    address public beneficiary3 = address(0x90F79bf6EB2c4f870365E785982E1f101E93b906);
    uint256 public totalAllocation3 = 3000e18;

    bytes32 public merkleRoot = 0xb0e86cd6d658e82f00ff51fbfc32a33916ed20be027462e5b1b24f084cb49f43;
    bytes32[] public merkleProof1;
    bytes32[] public merkleProof2;
    bytes32[] public merkleProof3;

    function setUp() public {
        owner = makeAddr("owner");
        nonOwner = beneficiary1; // Use beneficiary1 as a non-owner for tests

        mockToken = new MockERC20();

        vm.prank(owner);
        tokenVesting = new TokenVesting(address(mockToken));

        merkleProof1 = new bytes32[](2);
        merkleProof1[0] = 0x55adace9df60e28ec414bb4747100128ce1823e65e7e9dfdb8eeed9eed1a304c;
        merkleProof1[1] = 0x0c70ee9bb261c4a663607c7fea30f02cc4783e22989ca24eb239bc1b3026af96;

        merkleProof2 = new bytes32[](2);
        merkleProof2[0] = 0xc7b7ae57e5237ed40dcc17165f98e2bb1761c63c9f0b61b33b076962436c1a56;
        merkleProof2[1] = 0x0c70ee9bb261c4a663607c7fea30f02cc4783e22989ca24eb239bc1b3026af96;

        merkleProof3 = new bytes32[](1);
        merkleProof3[0] = 0xc5ffcb879a592bd1ed8d67b5d06d8880c67cf97b0121170bd8337223b4641e53;

        bucketId = keccak256(abi.encodePacked("TEAM_VESTING"));

        vm.prank(owner);
        mockToken.mint(address(tokenVesting), 1_000_000_000 ether);
    }

    /// @notice This test verifies the correct initialization of a vesting bucket's properties.
    /// It ensures that when the owner creates a new vesting bucket, the Merkle root,
    /// immediate unlock percentage, and other parameters are set as expected.
    function test_CreateVestingBucket() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            6000e18,
            1000, // 10%
            30,
            365,
            block.timestamp + 1,
            "proofs_cid"
        );

        (bool initialized, bytes32 merkleRootValue,,, uint256 immediateUnlockBpsValue,,,) =
            tokenVesting.vestingBuckets(bucketId);
        assertTrue(initialized);
        assertEq(merkleRootValue, merkleRoot);
        assertEq(immediateUnlockBpsValue, 1000);
    }

    /// @notice This test ensures that only the contract owner can create a vesting bucket.
    /// It attempts to create a bucket from a non-owner account and expects the transaction
    /// to revert with an `OwnableUnauthorizedAccount` error.
    function test_FailCreateVestingBucket_NotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        tokenVesting.createVestingBucket(
            keccak256(abi.encodePacked("bucket_2")),
            merkleRoot,
            6000e18,
            1000,
            30,
            365,
            block.timestamp + 1,
            "proofs_cid"
        );
    }

    /// @notice This test simulates a beneficiary's initial token claim.
    /// It verifies that the amount of tokens received correctly corresponds to the immediate
    /// unlock percentage defined in the vesting bucket.
    function test_Claim() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            6000e18,
            1000, // 10%
            30,
            365,
            block.timestamp + 1,
            "proofs_cid"
        );

        uint256 initialBalance = mockToken.balanceOf(beneficiary1);

        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);

        uint256 expectedAmount = (totalAllocation1 * 1000) / 10000;
        uint256 finalBalance = mockToken.balanceOf(beneficiary1);

        assertEq(finalBalance, initialBalance + expectedAmount);
    }

    function test_SimpleClaim() public {
        bytes32 simpleMerkleRoot = 0xc7b7ae57e5237ed40dcc17165f98e2bb1761c63c9f0b61b33b076962436c1a56;
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            simpleMerkleRoot,
            1000e18,
            1000, // 10%
            30,
            365,
            block.timestamp + 1,
            "proofs_cid"
        );

        uint256 initialBalance = mockToken.balanceOf(beneficiary1);

        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, emptyProof);

        uint256 expectedAmount = (totalAllocation1 * 1000) / 10000;
        uint256 finalBalance = mockToken.balanceOf(beneficiary1);

        assertEq(finalBalance, initialBalance + expectedAmount);
    }

    /// @notice This test confirms the security of the claiming process.
    /// It attempts a claim with an incorrect Merkle proof and expects the transaction
    /// to revert with a "Vesting: Invalid Merkle proof" error.
    function test_FailClaim_InvalidProof() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp + 1, "proofs_cid"
        );

        vm.prank(beneficiary1);
        vm.expectRevert(TokenVesting.InvalidMerkleProof.selector);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof2); // Wrong proof
    }

    /// @notice This test covers the entire vesting timeline in multiple stages.
    /// 1. It first confirms the correct disbursement of tokens from the immediate unlock.
    /// 2. Then, it verifies that no tokens can be claimed before the cliff period ends.
    /// 3. Next, it simulates time passing beyond the cliff and confirms that the vested amount
    ///    claimable is proportional to the elapsed time.
    /// 4. Finally, it simulates time passing beyond the full vesting duration and verifies
    ///    that the beneficiary can claim their entire allocation.
    function test_VestingSchedule() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            6000e18,
            1000, // 10%
            30,
            365,
            block.timestamp + 1,
            "proofs_cid"
        );

        // 1. Immediate unlock
        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);
        assertEq(mockToken.balanceOf(beneficiary1), 100e18);

        // 2. Before cliff
        skip(29 days);
        vm.prank(beneficiary1);
        vm.expectRevert(TokenVesting.NoTokensToRelease.selector);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);

        // 3. After cliff
        skip(2 days); // Total 31 days
        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);
        (,,,,,, uint256 startTimestamp, uint256 durationSeconds) = tokenVesting.vestingBuckets(bucketId);
        uint256 timeElapsed = block.timestamp - startTimestamp;
        uint256 vestedAmount = 100e18 + (900e18 * timeElapsed) / durationSeconds;
        assertEq(mockToken.balanceOf(beneficiary1), vestedAmount);

        // 4. After duration
        skip(334 days + 1); // Total 365 days and 1 second
        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);
        assertEq(mockToken.balanceOf(beneficiary1), totalAllocation1);
    }

    /// @notice This test validates the two-step emergency withdrawal process.
    /// It first confirms that a withdrawal cannot be made while the contract is operational.
    /// It then pauses the contract and confirms that the owner can successfully withdraw all
    /// remaining tokens from the contract.
    function test_EmergencyWithdraw() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp + 1, "proofs_cid"
        );

        vm.prank(owner);
        vm.expectRevert(TokenVesting.ContractNotPaused.selector);
        tokenVesting.emergencyWithdraw();

        vm.prank(owner);
        tokenVesting.emergencyPause();

        uint256 contractBalance = mockToken.balanceOf(address(tokenVesting));
        uint256 ownerBalance = mockToken.balanceOf(owner);

        vm.prank(owner);
        tokenVesting.emergencyWithdraw();

        assertEq(mockToken.balanceOf(address(tokenVesting)), 0);
        assertEq(mockToken.balanceOf(owner), ownerBalance + contractBalance);
    }

    /// @notice This test verifies the owner's ability to retroactively set the amount of tokens
    /// already released to a beneficiary. This is a crucial feature for migrating existing
    /// vesting schedules or correcting discrepancies.
    function test_SetInitialReleasedAmounts() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp + 1, "proofs_cid"
        );

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50e18;

        vm.prank(owner);
        tokenVesting.setInitialReleasedAmounts(bucketId, beneficiaries, amounts);

        assertEq(tokenVesting.releasedAmounts(bucketId, beneficiary1), 50e18);
    }

    // New tests for increased coverage

    function test_Constructor_FailZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TokenVesting.ZeroAddress.selector);
        new TokenVesting(address(0));
    }

    function test_FailCreateVestingBucket_AlreadyExists() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp + 1, "proofs_cid"
        );
        vm.prank(owner);
        vm.expectRevert(TokenVesting.BucketAlreadyExists.selector);
        tokenVesting.createVestingBucket(
            bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp + 1, "proofs_cid"
        );
    }

    function test_FailCreateVestingBucket_EmptyMerkleRoot() public {
        vm.prank(owner);
        vm.expectRevert(TokenVesting.EmptyMerkleRoot.selector);
        tokenVesting.createVestingBucket(
            bucketId, bytes32(0), 6000e18, 1000, 30, 365, block.timestamp + 1, "proofs_cid"
        );
    }

    function test_FailCreateVestingBucket_EmptyProofsCID() public {
        vm.prank(owner);
        vm.expectRevert(TokenVesting.EmptyProofsCID.selector);
        tokenVesting.createVestingBucket(bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp + 1, "");
    }

    function test_FailCreateVestingBucket_InvalidBps() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TokenVesting.InvalidBps.selector, 10001));
        tokenVesting.createVestingBucket(
            bucketId, merkleRoot, 6000e18, 10001, 30, 365, block.timestamp + 1, "proofs_cid"
        );
    }

    function test_FailCreateVestingBucket_InvalidTimestamp() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TokenVesting.InvalidTimestamp.selector, block.timestamp));
        tokenVesting.createVestingBucket(bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp, "proofs_cid");
    }

    function test_FailClaim_NonExistentBucket() public {
        vm.prank(beneficiary1);
        vm.expectRevert(TokenVesting.BucketDoesNotExist.selector);
        tokenVesting.claim(beneficiary1, bytes32(0), totalAllocation1, merkleProof1);
    }

    function test_FailClaim_NothingToRelease() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            6000e18,
            1000, // 10%
            30,
            365,
            block.timestamp + 1,
            "proofs_cid"
        );

        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);

        // Try to claim again immediately
        vm.prank(beneficiary1);
        vm.expectRevert(TokenVesting.NoTokensToRelease.selector);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);
    }

    function test_FailSetInitialReleasedAmounts_ArrayMismatch() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp + 1, "proofs_cid"
        );

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50e18;
        amounts[1] = 50e18;

        vm.prank(owner);
        vm.expectRevert(TokenVesting.ArrayLengthMismatch.selector);
        tokenVesting.setInitialReleasedAmounts(bucketId, beneficiaries, amounts);
    }

    function test_FailSetInitialReleasedAmounts_NonExistentBucket() public {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50e18;

        vm.prank(owner);
        vm.expectRevert(TokenVesting.BucketMustExist.selector);
        tokenVesting.setInitialReleasedAmounts(bytes32(0), beneficiaries, amounts);
    }

    function test_FailEmergencyWithdraw_NoBalance() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId, merkleRoot, 6000e18, 1000, 30, 365, block.timestamp + 1, "proofs_cid"
        );

        vm.prank(owner);
        tokenVesting.emergencyPause();

        // Withdraw all tokens
        mockToken.balanceOf(address(tokenVesting));
        vm.prank(owner);
        tokenVesting.emergencyWithdraw();

        // Try to withdraw again
        vm.prank(owner);
        vm.expectRevert(TokenVesting.NoTokensToWithdraw.selector);
        tokenVesting.emergencyWithdraw();
    }

    function test_GetReleasableAmount() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            6000e18,
            1000, // 10%
            30,
            365,
            block.timestamp + 1,
            "proofs_cid"
        );

        uint256 releasable = tokenVesting.getReleasableAmount(bucketId, beneficiary1, totalAllocation1);
        uint256 expectedAmount = (totalAllocation1 * 1000) / 10000;
        assertEq(releasable, expectedAmount);

        // Claim
        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);

        // Check again
        releasable = tokenVesting.getReleasableAmount(bucketId, beneficiary1, totalAllocation1);
        assertEq(releasable, 0);
    }

    function test_GetReleasableAmount_NonExistentBucket() public view {
        uint256 releasable = tokenVesting.getReleasableAmount(bytes32(0), beneficiary1, totalAllocation1);
        assertEq(releasable, 0);
    }

    function test_GetReleasableAmount_FullyClaimed() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            6000e18,
            1000, // 10%
            30,
            365,
            block.timestamp + 1,
            "proofs_cid"
        );

        // Fast forward to after the vesting period
        skip(366 days);

        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);

        uint256 releasable = tokenVesting.getReleasableAmount(bucketId, beneficiary1, totalAllocation1);
        assertEq(releasable, 0);
    }

    function test_VestingSchedule_ZeroDuration() public {
        vm.prank(owner);
        tokenVesting.createVestingBucket(
            bucketId,
            merkleRoot,
            6000e18,
            1000, // 10%
            30,
            0, // 0 days vesting
            block.timestamp + 1,
            "proofs_cid"
        );

        // Before cliff
        skip(29 days);
        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);
        assertEq(mockToken.balanceOf(beneficiary1), 100e18); // Only immediate unlock

        // After cliff
        skip(2 days); // Total 31 days
        vm.prank(beneficiary1);
        tokenVesting.claim(beneficiary1, bucketId, totalAllocation1, merkleProof1);
        assertEq(mockToken.balanceOf(beneficiary1), totalAllocation1); // Full amount
    }
}
