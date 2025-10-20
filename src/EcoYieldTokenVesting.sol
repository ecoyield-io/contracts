// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TokenVesting} from "./TokenVesting.sol";

struct VestingBucketData {
    bytes32 bucketId;
    bytes32 merkleRoot;
    uint256 totalAllocatedAmount;
    uint256 immediateUnlockBps;
    uint256 cliffInDays;
    uint256 vestingInDays;
    uint256 startTimestamp;
    string proofsCID;
}

contract EcoYieldTokenVesting is TokenVesting {

    constructor(address tokenAddress_) TokenVesting(tokenAddress_) {}

    function createVestingBuckets(VestingBucketData[] calldata buckets) public {
        for (uint256 i = 0; i < buckets.length; i++) {
            createVestingBucket(
                buckets[i].bucketId,
                buckets[i].merkleRoot,
                buckets[i].totalAllocatedAmount,
                buckets[i].immediateUnlockBps,
                buckets[i].cliffInDays,
                buckets[i].vestingInDays,
                buckets[i].startTimestamp,
                buckets[i].proofsCID
            );
        }
    }
}
