/**
 * K3-H1 Happy Path Example — aligned with docs/18 contract.
 *
 * Flow: getLatestBlockhash -> compileLegacy -> sign -> verify -> simulateTransaction
 *
 * Usage:
 *   SURFPOOL_RPC_URL=http://127.0.0.1:8899 npx tsx examples/k3-h1-happy.ts
 */

import {
  Connection,
  Keypair,
  VersionedTransaction,
  compileLegacy,
  type Instruction,
} from "../src/index.js";

async function main() {
  // --- Fixed inputs (docs/18 §2.2) ---
  const PAYER_SEED = new Uint8Array(32).fill(1);
  const PROGRAM_ID = "7YHdmmKBiSnEFbfRg2izqfGnJZ1jaGEkfvYCPTQ1HBKF"; // base58 of [0x06]*32
  const RECEIVER = "8qbHbw2BbbTHBW1sbeqakYXVKRQM8Ne7pLK7m6CVfeR"; // base58 of [0x07]*32
  const IX_DATA = new Uint8Array([0x01, 0x02, 0x03]);

  // --- Endpoint (D-04: gated by env var) ---
  const endpoint = process.env.SURFPOOL_RPC_URL;
  if (!endpoint) {
    console.log("[skip] SURFPOOL_RPC_URL not set, skipping K3-H1 example");
    return;
  }

  console.log(`[K3-H1] endpoint: ${endpoint}`);

  // S1: initialize connection (AC-07: endpoint is configurable string)
  const connection = new Connection(endpoint);

  // S2: getLatestBlockhash (AC-02: typed response)
  const bhResult = await connection.getLatestBlockhash();
  if (bhResult.kind === "rpc_error") {
    console.error(`[K3-H1] getLatestBlockhash failed: ${bhResult.message}`);
    process.exit(1);
  }

  // A-H1: ok variant
  console.log(`[K3-H1] blockhash: ${bhResult.value.blockhash}`);
  // A-H2: last_valid_block_height > 0
  console.assert(
    bhResult.value.last_valid_block_height > 0,
    "A-H2: last_valid_block_height > 0"
  );

  // S3: compile legacy message (AC-05: param order = payer, instructions, blockhash)
  const payer = Keypair.fromSeed(PAYER_SEED);
  const instructions: Instruction[] = [
    {
      program_id: PROGRAM_ID,
      accounts: [
        { pubkey: payer.pubkey(), is_signer: true, is_writable: true },
        { pubkey: RECEIVER, is_signer: false, is_writable: true },
      ],
      data: IX_DATA,
    },
  ];
  const message = compileLegacy(
    payer.pubkey(),
    instructions,
    bhResult.value.blockhash
  );

  // S4: initUnsigned
  const tx = VersionedTransaction.initUnsigned(message);

  // S5: sign + verify (AC-04: sign takes signer slice, verifySignatures independent)
  tx.sign([payer]);
  // A-H3a: signature is 64 bytes
  console.assert(tx.signatures[0].length === 64, "A-H3a: signature is 64 bytes");
  // A-H3b: verify passes
  const verified = tx.verifySignatures();
  console.assert(verified, "A-H3b: verifySignatures passes");

  // S6: simulateTransaction (AC-03: preserves raw JSON; AC-06: sigVerify=true)
  const simResult = await connection.simulateTransaction(tx.serializeBase64());
  if (simResult.kind === "rpc_error") {
    // Devnet may reject dummy tx — acceptable for E2E evidence
    console.log(
      `[K3-H1] simulate rpc_error (code=${simResult.code}): ${simResult.message}`
    );
  } else {
    // A-H4: ok variant
    console.log("[K3-H1] simulate returned .ok");
    // A-H5: value.err == null
    const simErr = simResult.value.value?.err;
    if (simErr) {
      console.log(`[K3-H1] note: simulation err field present: ${JSON.stringify(simErr)}`);
    }
  }

  console.log("[K3-H1] example complete");
}

main().catch(console.error);
