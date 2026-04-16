# solana-zig

Zig rewrite of selected Solana Rust SDK 4.0.1 client-side capabilities.

## Implemented (Phase 1)
- Core: `Pubkey`, `Signature`, `Keypair`, `Hash`, `base58`, `shortvec`
- Tx: `Instruction`, `Message` (legacy + v0), `VersionedTransaction`
- RPC: `RpcClient` with
  - `getLatestBlockhash`
  - `getAccountInfo`
  - `getBalance`
  - `simulateTransaction`
  - `sendTransaction`
- Compat: oracle vector loader + bincode helpers

## Build & Test
```bash
zig build test
```

## Optional Devnet usage
Set `SOLANA_RPC_URL` and call the RPC client from your own integration harness.

## Oracle vectors
- Static vectors live in `testdata/oracle_vectors.json`
- Rust generator skeleton in `scripts/oracle/`
