/**
 * @zignocchio/client — Minimal TypeScript helper SDK for solana-zig.
 *
 * Mirrors the Zig SDK API surface per docs/18 contract (AC-01~AC-07).
 * Uses @solana/web3.js under the hood for crypto and serialization.
 */

// Types
export type {
  RpcResult,
  RpcOk,
  RpcError,
  LatestBlockhash,
  OwnedJson,
  AccountMeta,
  Instruction,
  MessageHeader,
  CompiledInstruction,
  Transport,
  PostJsonFn,
} from "./types.js";

// Connection (RPC client)
export { Connection } from "./connection.js";

// Transaction helpers
export {
  Keypair,
  VersionedTransaction,
  compileLegacy,
} from "./transaction.js";
export type { CompiledMessage } from "./transaction.js";

// PDA helpers
export { findProgramAddress, createProgramAddress } from "./pda.js";
