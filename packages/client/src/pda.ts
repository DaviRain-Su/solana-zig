/**
 * Minimal PDA (Program Derived Address) helper.
 *
 * Mirrors the deterministic address derivation from Solana's
 * findProgramAddress / createProgramAddress.
 */

import { PublicKey } from "@solana/web3.js";

/**
 * Find a program-derived address and its bump seed.
 *
 * @param seeds - Array of seed buffers
 * @param programId - Program public key (base58 string)
 * @returns [address, bump] tuple
 */
export async function findProgramAddress(
  seeds: Uint8Array[],
  programId: string
): Promise<[string, number]> {
  const [pubkey, bump] = await PublicKey.findProgramAddress(
    seeds.map((s) => Buffer.from(s)),
    new PublicKey(programId)
  );
  return [pubkey.toBase58(), bump];
}

/**
 * Create a program-derived address with a known bump seed.
 *
 * @param seeds - Array of seed buffers (must include bump as last seed)
 * @param programId - Program public key (base58 string)
 * @returns The derived address
 */
export function createProgramAddress(
  seeds: Uint8Array[],
  programId: string
): string {
  const pubkey = PublicKey.createProgramAddressSync(
    seeds.map((s) => Buffer.from(s)),
    new PublicKey(programId)
  );
  return pubkey.toBase58();
}
