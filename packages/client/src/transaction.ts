/**
 * Transaction helpers — mirrors solana-zig tx module surface.
 *
 * Uses @solana/web3.js under the hood for crypto and serialization.
 * Contract: AC-04 (sign + verifySignatures), AC-05 (compileLegacy param order)
 */

import {
  Keypair as SolKeypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  SystemProgram,
} from "@solana/web3.js";
import type { AccountMeta, Instruction } from "./types.js";

// --- Keypair wrapper (mirrors core/keypair.zig) ---

export class Keypair {
  private inner: SolKeypair;

  private constructor(inner: SolKeypair) {
    this.inner = inner;
  }

  /** Deterministic keypair from 32-byte seed (mirrors Keypair.fromSeed) */
  static fromSeed(seed: Uint8Array): Keypair {
    if (seed.length !== 32) {
      throw new Error(`Seed must be 32 bytes, got ${seed.length}`);
    }
    return new Keypair(SolKeypair.fromSeed(seed));
  }

  /** Generate a random keypair */
  static generate(): Keypair {
    return new Keypair(SolKeypair.generate());
  }

  /** Public key (mirrors keypair.pubkey()) */
  pubkey(): string {
    return this.inner.publicKey.toBase58();
  }

  /** Raw public key as PublicKey */
  publicKey(): PublicKey {
    return this.inner.publicKey;
  }

  /** Access the underlying @solana/web3.js Keypair for signing */
  get solKeypair(): SolKeypair {
    return this.inner;
  }

  /** Secret key bytes (64 bytes: seed + public) */
  get secretKey(): Uint8Array {
    return this.inner.secretKey;
  }
}

// --- Message wrapper ---

export interface CompiledMessage {
  /** Serialized transaction (unsigned) for RPC submission */
  transaction: Transaction;
  /** The payer public key */
  payer: string;
}

/**
 * AC-05: compileLegacy — parameter order matches Zig SDK:
 *   (payer, instructions, recent_blockhash)
 *
 * Note: allocator is not needed in JS. The param order
 * (payer, instructions, blockhash) is preserved per contract.
 */
export function compileLegacy(
  payer: string,
  instructions: Instruction[],
  recentBlockhash: string
): CompiledMessage {
  const payerPubkey = new PublicKey(payer);

  const tx = new Transaction();
  tx.recentBlockhash = recentBlockhash;
  tx.feePayer = payerPubkey;

  for (const ix of instructions) {
    const keys = ix.accounts.map((acc) => ({
      pubkey: new PublicKey(acc.pubkey),
      isSigner: acc.is_signer,
      isWritable: acc.is_writable,
    }));

    tx.add(
      new TransactionInstruction({
        programId: new PublicKey(ix.program_id),
        keys,
        data: Buffer.from(ix.data),
      })
    );
  }

  return { transaction: tx, payer };
}

// --- VersionedTransaction wrapper ---

export class VersionedTransaction {
  private tx: Transaction;
  private signed: boolean = false;

  private constructor(tx: Transaction) {
    this.tx = tx;
  }

  /** Mirrors VersionedTransaction.initUnsigned(allocator, message) */
  static initUnsigned(message: CompiledMessage): VersionedTransaction {
    return new VersionedTransaction(message.transaction);
  }

  /**
   * AC-04: sign accepts signer slice; mirrors tx.sign(&[_]Keypair{payer}).
   */
  sign(signers: Keypair[]): void {
    const solSigners = signers.map((s) => s.solKeypair);
    this.tx.sign(...solSigners);
    this.signed = true;
  }

  /**
   * AC-04: verifySignatures is independently callable after sign.
   */
  verifySignatures(): boolean {
    if (!this.signed) {
      return false;
    }
    return this.tx.verifySignatures();
  }

  /** Get signatures (each 64 bytes) */
  get signatures(): Uint8Array[] {
    return this.tx.signatures.map((s) => {
      if (!s.signature) {
        return new Uint8Array(64); // zero-filled for unsigned
      }
      return new Uint8Array(s.signature);
    });
  }

  /**
   * Serialize to base64 for RPC submission.
   * Used as input to simulateTransaction / sendTransaction.
   */
  serializeBase64(): string {
    const buf = this.tx.serialize({
      requireAllSignatures: false,
      verifySignatures: false,
    });
    return Buffer.from(buf).toString("base64");
  }

  /** Access the underlying @solana/web3.js Transaction */
  get inner(): Transaction {
    return this.tx;
  }
}
