# solana-zig

Zig implementation roadmap for Solana capabilities, aligned to Rust SDK semantics.

## Current Status (M1)
Current implementation is **off-chain first** (host/client path), not full on-chain parity yet; core structures are implemented, and remaining tests and benchmarks are in progress.

- Core: `Pubkey`, `Signature`, `Keypair`, `Hash`, `base58`, `shortvec`
- Tx: `Instruction`, `Message` (legacy + v0), `VersionedTransaction`
- RPC: `RpcClient` with
  - `getLatestBlockhash`
  - `getAccountInfo`
  - `getBalance`
  - `simulateTransaction`
  - `sendTransaction`
- RPC transport abstraction: injectable transport for mocking/tests
- Compat: oracle vector loader + bincode helpers

## Build & Test
```bash
zig build test
```

## Optional Devnet Usage
Set `SOLANA_RPC_URL` and call the RPC client from your own integration harness.

## Scope Strategy: Off-chain + On-chain
Yes, target is to cover both, but in staged tracks:

- Track A (current): off-chain SDK foundations (`core/tx/rpc`)
- Track B (next): interface modules (`system/token/token-2022/...`)
- Track C: signer backends (pluggable key management)
- Track D: on-chain semantics as a **separate subproject/lifecycle** to avoid coupling with client SDK stability

This keeps current client path stable while enabling eventual full-scope implementation.

## Roadmap Documents
- PRD: `docs/01-prd.md`
- Architecture: `docs/02-architecture.md`
- Technical Spec: `docs/03-technical-spec.md`
- Task Breakdown: `docs/04-task-breakdown.md`
- Test Spec: `docs/05-test-spec.md`
- Evolution: `docs/08-evolution.md`

## Official Reference Repositories
Aligned with Solana official Rust SDK page:

- `solana-sdk` + component crates: https://github.com/anza-xyz/solana-sdk
- `solana-client` implementation: https://github.com/anza-xyz/agave/tree/master/client
- `pinocchio` and program-specific crates: https://github.com/anza-xyz/pinocchio
- SPL interface repositories:
  - https://github.com/solana-program/token/tree/main/interface
  - https://github.com/solana-program/token-2022/tree/main/interface
  - https://github.com/solana-program/associated-token-account/tree/main/interface
  - https://github.com/solana-program/memo/tree/main/interface
  - https://github.com/solana-program/token-metadata/tree/main/interface
  - https://github.com/solana-program/token-group/tree/main/interface
- Signer backend reference (`solana-keychain`): https://github.com/solana-foundation/solana-keychain

## Oracle Vectors
- Static vectors live in `testdata/oracle_vectors.json`
- Rust generator skeleton in `scripts/oracle/`
