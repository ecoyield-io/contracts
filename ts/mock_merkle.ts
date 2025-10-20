// scripts/generate-merkle.ts
import { StandardMerkleTree } from "https://esm.sh/@openzeppelin/merkle-tree@1.0.5";
import { isAddress, parseEther } from "https://esm.sh/viem@2.7.13";
import { dirname, resolve } from "https://deno.land/std@0.218.2/path/mod.ts";

// Define the structure for a beneficiary in the input file
// Note: Deno can infer types from JSON, but we'll keep this for clarity.
interface Beneficiary {
  address: string;
  amount: string; // Use string for large numbers
}

// Define the structure for the output file
interface MerkleOutput {
  merkleRoot: string;
  totalAllocatedAmount: string;
  claims: {
    [beneficiary: string]: {
      amount: string;
      proof: string[];
    };
  };
}

/**
 * Generates a Merkle tree, root, and proofs from a list of beneficiaries.
 *
 * @param beneficiaries - An array of beneficiary objects, each with an address and amount.
 * @param outputFilePath - The path to write the output JSON file to.
 */
function generateMerkleTree(
  beneficiaries: Beneficiary[],
  outputFilePath: string
): void {
  console.log("Generating Merkle tree...");

  // 1. Validate and format the beneficiary data
  if (!beneficiaries || beneficiaries.length === 0) {
    throw new Error("Beneficiary list is empty. Check your input file.");
  }

  const leaves: [string, bigint][] = beneficiaries.map((b) => {
    if (!isAddress(b.address)) {
      throw new Error(`Invalid address found in beneficiaries list: ${b.address}`);
    }
    try {
      // The amount in the JSON is a string representing the value in ether (e.g., "1000.0")
      // We need to convert it to wei.
      const amountInWei = parseEther(b.amount);
      return [b.address, amountInWei];
    } catch (error) {
      console.error(`Failed to parse amount for address ${b.address}: ${b.amount}`);
      throw error;
    }
  });

  // 2. Create the Merkle tree
  // The leaf format must match the one expected by the smart contract:
  // keccak256(abi.encodePacked(address, uint256))
  const tree = StandardMerkleTree.of(leaves, ["address", "uint256"]);

  // 3. Calculate the total allocation amount
  const totalAllocatedAmount = leaves.reduce(
    (sum, leaf) => sum + leaf[1],
    0n
  );

  // 4. Prepare the output data
  const claims: MerkleOutput["claims"] = {};
  for (const [i, leaf] of tree.entries()) {
    const address = leaf[0];
    const amount = leaf[1].toString();
    const proof = tree.getProof(i);
    claims[address] = { amount, proof };
  }

  const merkleOutput: MerkleOutput = {
    merkleRoot: tree.root,
    totalAllocatedAmount: totalAllocatedAmount.toString(),
    claims: claims,
  };

  // 5. Write the output to a file
  try {
    const outputDir = dirname(outputFilePath);
    // Deno.mkdirSync will create parent directories if they don't exist.
    // We'll use a try-catch block in case the directory already exists.
    try { Deno.mkdirSync(outputDir, { recursive: true }); } catch (e) { if (!(e instanceof Deno.errors.AlreadyExists)) throw e; }
    Deno.writeTextFileSync(
      outputFilePath,
      JSON.stringify(merkleOutput, null, 2)
    );
    console.log(`✅ Merkle tree data saved to ${outputFilePath}`);
    console.log(`   - Merkle Root: ${tree.root}`);
    console.log(`   - Total Allocated (wei): ${totalAllocatedAmount.toString()}`);
    console.log(`   - Total Beneficiaries: ${leaves.length}`);
  } catch (error) {
    console.error("Error writing output file:", error);
    throw error;
  }
}

// --- Main execution ---
function main() {
  // Define the list of beneficiaries directly in the code.
  // You can modify this array with your actual allocation data.
  const beneficiaries: Beneficiary[] = [
    {
      "address": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
      "amount": "1000.0"
    },
    {
      "address": "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
      "amount": "2000.0"
    },
    {
      "address": "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
      "amount": "3000.0"
    }
  ];

  // Define output file path
  const outputFile = "proofs/mock_team_vesting_proofs.json";
  const outputFilePath = resolve(outputFile);

  try {
    console.log(`Generating Merkle tree for ${beneficiaries.length} hardcoded beneficiaries...`);
    generateMerkleTree(beneficiaries, outputFilePath);
  } catch (error) {
    console.error("An unexpected error occurred:", error);
    Deno.exit(1);
  }
}

main();
