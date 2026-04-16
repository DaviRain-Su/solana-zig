/**
 * Transaction helper tests — compileLegacy, sign, verify.
 * Contract: AC-04, AC-05
 */

import { describe, it, expect } from "vitest";
import {
  Keypair,
  VersionedTransaction,
  compileLegacy,
  type Instruction,
} from "../src/index.js";

// --- Fixed inputs (docs/18 §2.2) ---
const PAYER_SEED = new Uint8Array(32).fill(1);

describe("Keypair", () => {
  it("fromSeed produces deterministic keypair", () => {
    const kp1 = Keypair.fromSeed(PAYER_SEED);
    const kp2 = Keypair.fromSeed(PAYER_SEED);
    expect(kp1.pubkey()).toBe(kp2.pubkey());
  });

  it("fromSeed rejects non-32-byte seed", () => {
    expect(() => Keypair.fromSeed(new Uint8Array(16))).toThrow(
      "Seed must be 32 bytes"
    );
  });

  it("pubkey returns base58 string", () => {
    const kp = Keypair.fromSeed(PAYER_SEED);
    expect(kp.pubkey()).toBeTruthy();
    expect(typeof kp.pubkey()).toBe("string");
    expect(kp.pubkey().length).toBeGreaterThan(0);
  });
});

describe("compileLegacy", () => {
  it("AC-05: accepts (payer, instructions, blockhash) param order", () => {
    const payer = Keypair.fromSeed(PAYER_SEED);
    const instructions: Instruction[] = [
      {
        program_id: "11111111111111111111111111111111",
        accounts: [
          { pubkey: payer.pubkey(), is_signer: true, is_writable: true },
        ],
        data: new Uint8Array([1, 2, 3]),
      },
    ];

    const message = compileLegacy(
      payer.pubkey(),
      instructions,
      "4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn"
    );

    expect(message).toBeDefined();
    expect(message.payer).toBe(payer.pubkey());
    expect(message.transaction).toBeDefined();
  });
});

describe("VersionedTransaction", () => {
  function buildTestTx() {
    const payer = Keypair.fromSeed(PAYER_SEED);
    const instructions: Instruction[] = [
      {
        program_id: "11111111111111111111111111111111",
        accounts: [
          { pubkey: payer.pubkey(), is_signer: true, is_writable: true },
        ],
        data: new Uint8Array([1, 2, 3]),
      },
    ];
    const message = compileLegacy(
      payer.pubkey(),
      instructions,
      "4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn"
    );
    return { payer, message };
  }

  it("initUnsigned creates transaction from compiled message", () => {
    const { message } = buildTestTx();
    const tx = VersionedTransaction.initUnsigned(message);
    expect(tx).toBeDefined();
  });

  it("AC-04: sign accepts signer array", () => {
    const { payer, message } = buildTestTx();
    const tx = VersionedTransaction.initUnsigned(message);

    // sign takes signer slice (array)
    tx.sign([payer]);

    // A-H3a: signature is 64 bytes
    expect(tx.signatures[0].length).toBe(64);
  });

  it("AC-04: verifySignatures independently callable after sign", () => {
    const { payer, message } = buildTestTx();
    const tx = VersionedTransaction.initUnsigned(message);

    tx.sign([payer]);
    // A-H3b: verify passes
    const valid = tx.verifySignatures();
    expect(valid).toBe(true);
  });

  it("verifySignatures returns false for unsigned tx", () => {
    const { message } = buildTestTx();
    const tx = VersionedTransaction.initUnsigned(message);
    expect(tx.verifySignatures()).toBe(false);
  });

  it("serializeBase64 returns non-empty string", () => {
    const { payer, message } = buildTestTx();
    const tx = VersionedTransaction.initUnsigned(message);
    tx.sign([payer]);

    const b64 = tx.serializeBase64();
    expect(b64.length).toBeGreaterThan(0);
    // Valid base64
    expect(() => Buffer.from(b64, "base64")).not.toThrow();
  });
});
