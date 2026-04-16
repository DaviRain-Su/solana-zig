/**
 * Core types for @zignocchio/client — mirrors solana-zig SDK type surface.
 *
 * Naming convention: field names match the Zig SDK (snake_case) to maintain
 * 1:1 mapping with docs/18 contract and oracle vectors.
 */

// --- RPC Result (tagged union, mirrors Zig RpcResult(T)) ---

export interface RpcOk<T> {
  kind: "ok";
  value: T;
}

export interface RpcError {
  kind: "rpc_error";
  code: number;
  message: string;
  data?: unknown;
}

export type RpcResult<T> = RpcOk<T> | RpcError;

// --- LatestBlockhash (C-02: field names = blockhash + last_valid_block_height) ---

export interface LatestBlockhash {
  blockhash: string;
  last_valid_block_height: number;
}

// --- OwnedJson (C-03: preserves raw JSON, no forced convergence) ---

export interface OwnedJson {
  /** Raw parsed JSON value — consumer can inspect any field */
  value: Record<string, unknown>;
  /** Raw JSON string for debugging / logging */
  raw: string;
}

// --- Instruction / AccountMeta (mirrors tx module) ---

export interface AccountMeta {
  pubkey: string;
  is_signer: boolean;
  is_writable: boolean;
}

export interface Instruction {
  program_id: string;
  accounts: AccountMeta[];
  data: Uint8Array;
}

// --- MessageHeader (mirrors message.zig MessageHeader) ---

export interface MessageHeader {
  num_required_signatures: number;
  num_readonly_signed_accounts: number;
  num_readonly_unsigned_accounts: number;
}

// --- CompiledInstruction ---

export interface CompiledInstruction {
  program_id_index: number;
  account_indexes: number[];
  data: Uint8Array;
}

// --- Transport (C-01: injectable transport) ---

export type PostJsonFn = (
  url: string,
  payload: string
) => Promise<string>;

export interface Transport {
  postJson: PostJsonFn;
}
