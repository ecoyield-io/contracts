// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title TokenVesting
 * @author woodybriggs
 * @notice A smart contract for handling token vesting schedules for multiple beneficiaries
 * using a gas-efficient Merkle proof system. Each vesting "bucket" (e.g., for team,
 * advisors) has its own Merkle root and vesting parameters.
 * @dev This contract allows an owner to create vesting buckets, each defined by a Merkle root
 * representing the allocations for all beneficiaries within that bucket. This is highly
 * gas-efficient for setup, regardless of the number of beneficiaries. It uses OpenZeppelin
 * contracts for security.
 */
contract TokenVesting is Context, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct VestingBucket {
        bool initialized; // Flag to check if the bucket has been set
        bytes32 merkleRoot; // The Merkle root of the beneficiaries in this bucket
        string proofsCID; // The IPFS/Arweave CID where the proofs are stored
        uint256 totalAllocatedAmount; // The total amount of tokens for this entire bucket
        uint256 immediateUnlockBps; // Percentage to unlock at TGE, in basis points (1% = 100)
        uint256 cliffTimestamp; // Timestamp after which linear vesting starts
        uint256 startTimestamp; // Timestamp when the vesting schedule begins
        uint256 durationSeconds; // Duration of the vesting period in seconds
    }

    IERC20 public immutable TOKEN;

    // Mapping from a bucket ID (keccak256 of bucket name) to its VestingBucket struct
    mapping(bytes32 => VestingBucket) public vestingBuckets;

    // Mapping from bucket ID => beneficiary address => amount of tokens released
    mapping(bytes32 => mapping(address => uint256)) public releasedAmounts;

    // Event emitted when a new vesting bucket is created
    event VestingBucketCreated(
        bytes32 indexed bucketId, bytes32 merkleRoot, uint256 totalAllocatedAmount, string proofsCID
    );

    // Event emitted when a beneficiary claims their vested tokens
    event TokensClaimed(bytes32 indexed bucketId, address indexed beneficiary, uint256 amount);

    // Event emitted when the owner performs an emergency withdrawal
    event EmergencyWithdrawal(address indexed owner, uint256 amount);

    // Custom Errors
    error ZeroAddress();
    error BucketAlreadyExists();
    error EmptyMerkleRoot();
    error EmptyProofsCID();
    error InvalidBps(uint256 bps);
    error BucketDoesNotExist();
    error InvalidMerkleProof();
    error NoTokensToRelease();
    error ArrayLengthMismatch();
    error ContractNotPaused();
    error NoTokensToWithdraw();
    error BucketMustExist();
    error InvalidTimestamp(uint256 timestamp);

    /**
     * @notice Constructor to initialize the vesting contract.
     * @param _tokenAddress The address of the ERC20 token to be vested.
     */
    constructor(address _tokenAddress) Ownable(msg.sender) {
        if (_tokenAddress == address(0)) revert ZeroAddress();
        TOKEN = IERC20(_tokenAddress);
    }

    /**
     * @notice Creates a new vesting bucket with its own schedule and allocation root.
     * @param _bucketId A unique ID for the bucket (e.g., keccak(abi.encodePacked("TEAM_VESTING"))).
     * @param _merkleRoot The Merkle root of the beneficiary allocation data.
     * @param _totalAllocatedAmount The total amount of tokens allocated to this bucket.
     * @param _immediateUnlockBps The percentage of tokens to unlock immediately at TGE, in basis points (1% = 100).
     * @param _cliffInDays The cliff period in days for the remaining tokens.
     * @param _vestingInDays The total vesting period in days for the remaining tokens.
     * @param _proofsCID The IPFS/Arweave CID where the JSON file containing proofs is stored.
     */
    function createVestingBucket(
        bytes32 _bucketId,
        bytes32 _merkleRoot,
        uint256 _totalAllocatedAmount,
        uint256 _immediateUnlockBps,
        uint256 _cliffInDays,
        uint256 _vestingInDays,
        uint256 _startTimestamp,
        string memory _proofsCID
    ) public onlyOwner {
        bytes32 bucketId = _bucketId;
        if (vestingBuckets[bucketId].initialized) revert BucketAlreadyExists();
        if (_merkleRoot == bytes32(0)) revert EmptyMerkleRoot();
        if (bytes(_proofsCID).length == 0) revert EmptyProofsCID();
        if (_immediateUnlockBps > 10000) revert InvalidBps(_immediateUnlockBps);
        if (_startTimestamp <= block.timestamp) revert InvalidTimestamp(_startTimestamp); // solhint-disable-line not-rely-on-time

        uint256 cliffDurationSeconds = _cliffInDays * 1 days;
        uint256 vestingDurationSeconds = _vestingInDays * 1 days;

        vestingBuckets[bucketId] = VestingBucket({
            initialized: true,
            merkleRoot: _merkleRoot,
            proofsCID: _proofsCID,
            totalAllocatedAmount: _totalAllocatedAmount,
            immediateUnlockBps: _immediateUnlockBps,
            startTimestamp: _startTimestamp,
            cliffTimestamp: _startTimestamp + cliffDurationSeconds,
            durationSeconds: vestingDurationSeconds
        });

        emit VestingBucketCreated(bucketId, _merkleRoot, _totalAllocatedAmount, _proofsCID);
    }

    /**
     * @notice Allows a beneficiary to claim their vested tokens.
     * @param account The account to claim tokens for.
     * @param bucketId The ID of the vesting bucket they belong to.
     * @param totalAllocation The total token amount allocated to the beneficiary.
     * @param merkleProof The Merkle proof to verify the beneficiary's inclusion.
     */
    function claim(address account, bytes32 bucketId, uint256 totalAllocation, bytes32[] calldata merkleProof)
        external
        nonReentrant
        whenNotPaused
    {
        VestingBucket storage bucket = vestingBuckets[bucketId];
        if (!bucket.initialized) revert BucketDoesNotExist();

        // Verify the beneficiary's allocation using the Merkle proof.
        bytes32 leaf = keccak256(abi.encode(account, totalAllocation));
        if (!MerkleProof.verify(merkleProof, bucket.merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        uint256 totalVested = _calculateVested(bucket, totalAllocation);
        uint256 alreadyReleased = releasedAmounts[bucketId][account];
        uint256 releasableAmount = totalVested - alreadyReleased;

        if (releasableAmount == 0) revert NoTokensToRelease();

        releasedAmounts[bucketId][account] += releasableAmount;
        TOKEN.safeTransfer(account, releasableAmount);

        emit TokensClaimed(bucketId, account, releasableAmount);
    }

    /**
     * @notice [MIGRATION] Sets the initial released amounts for beneficiaries in a bucket.
     * @dev Can only be called by the owner. This is intended for use only during a
     * contract migration to import state from a previous version.
     * @param _bucketId The ID of the vesting bucket.
     * @param _beneficiaries An array of beneficiary addresses.
     * @param _amounts An array of their corresponding already-claimed amounts.
     */
    function setInitialReleasedAmounts(
        bytes32 _bucketId,
        address[] calldata _beneficiaries,
        uint256[] calldata _amounts
    ) external onlyOwner {
        if (_beneficiaries.length != _amounts.length) revert ArrayLengthMismatch();
        if (!vestingBuckets[_bucketId].initialized) revert BucketMustExist();

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            releasedAmounts[_bucketId][_beneficiaries[i]] = _amounts[i];
        }
    }

    /**
     * @notice Pauses all claim activities in an emergency.
     * @dev Can only be called by the owner. This is a one-way action and cannot be unpaused.
     */
    function emergencyPause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Allows the owner to withdraw all tokens from the contract in an emergency.
     * @dev This function can only be called after the contract has been paused.
     * It is intended as a recovery mechanism in case of a critical vulnerability
     * or other unforeseen circumstances.
     */
    function emergencyWithdraw() external onlyOwner {
        if (!paused()) revert ContractNotPaused();
        uint256 balance = TOKEN.balanceOf(address(this));
        if (balance == 0) revert NoTokensToWithdraw();

        TOKEN.safeTransfer(owner(), balance);

        emit EmergencyWithdrawal(owner(), balance);
    }

    /**
     * @notice A view function to check the releasable amount for a beneficiary.
     * @param _bucketId The ID of the vesting bucket.
     * @param _beneficiary The address of the beneficiary.
     * @param _totalAllocation The total allocation for the beneficiary.
     * @return The amount of tokens the beneficiary can currently claim.
     */
    function getReleasableAmount(bytes32 _bucketId, address _beneficiary, uint256 _totalAllocation)
        public
        view
        returns (uint256)
    {
        VestingBucket memory bucket = vestingBuckets[_bucketId];
        if (!bucket.initialized) {
            return 0;
        }

        uint256 totalVested = _calculateVested(bucket, _totalAllocation);
        uint256 alreadyReleased = releasedAmounts[_bucketId][_beneficiary];

        if (totalVested <= alreadyReleased) {
            return 0;
        }
        return totalVested - alreadyReleased;
    }

    /**
     * @notice Internal function to calculate the total vested amount for an allocation.
     * @param _bucket The vesting bucket's data.
     * @param _totalAllocation The total allocation for a single beneficiary.
     * @return The total amount of vested tokens for the beneficiary at the current time.
     */
    function _calculateVested(VestingBucket memory _bucket, uint256 _totalAllocation) internal view returns (uint256) {
        // 1. Calculate the TGE amount. This is available from the start.
        uint256 immediateAmount = (_totalAllocation * _bucket.immediateUnlockBps) / 10000;

        // 2. Calculate the portion subject to linear vesting.
        uint256 linearlyVestedAmount = 0;
        uint256 remainingAllocation = _totalAllocation - immediateAmount;

        // The linear vesting portion is only available after the cliff.
        if (block.timestamp >= _bucket.cliffTimestamp) {
            if (_bucket.durationSeconds == 0) {
                // If duration is 0, the entire remaining amount vests after the cliff.
                linearlyVestedAmount = remainingAllocation;
            } else {
                uint256 timeElapsed = block.timestamp - _bucket.startTimestamp;

                if (timeElapsed >= _bucket.durationSeconds) {
                    linearlyVestedAmount = remainingAllocation;
                } else {
                    // Calculate linear vesting on the remaining part.
                    linearlyVestedAmount = (remainingAllocation * timeElapsed) / _bucket.durationSeconds;
                }
            }
        }

        // 3. Total vested is the sum of TGE + the linearly vested part.
        return immediateAmount + linearlyVestedAmount;
    }
}
