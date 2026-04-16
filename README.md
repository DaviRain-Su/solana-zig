# solana-zig

Zig implementation roadmap for Solana capabilities, aligned to Rust SDK semantics.

## Current Status (Product Phase 1 / Milestone M2-M3)
Current implementation is in **Product Phase 1 closeout**: the project is still off-chain first (host/client path), not full on-chain parity yet; core structures are implemented, and the remaining work is mainly test expansion, minimal typed RPC parse tightening for the current high-frequency methods, Devnet E2E, oracle enrichment, and benchmark baselining.

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

For the current Phase 1 acceptance wrapper, run:

```bash
SOLANA_RPC_URL=<your-devnet-endpoint> scripts/devnet/phase1_acceptance.sh
```

## Scope Strategy: Product Roadmap Phases
Yes, target is to cover both off-chain and, eventually, on-chain capabilities, but under one unified product roadmap:

- Phase 1 (current): off-chain SDK foundations (`core/tx/rpc`) + compatibility/test closeout
- Phase 2: extended RPC, websocket subscriptions, nonce workflow, and compute-budget helpers
- Phase 3: interface modules (`system/token/token-2022/...`), signer backends, and C ABI
- Phase 4: on-chain semantics as a **separate subproject/lifecycle** to avoid coupling with client SDK stability

This keeps the current client path stable while making later expansion stages explicit and traceable.

## Roadmap Documents
- PRD: `docs/01-prd.md`
- Architecture: `docs/02-architecture.md`
- Technical Spec: `docs/03-technical-spec.md`
- Task Breakdown: `docs/04-task-breakdown.md`
- Test Spec: `docs/05-test-spec.md`
- Evolution: `docs/08-evolution.md`
- Doc Consistency Checklist: `docs/09-doc-consistency-checklist.md`
- Coverage Matrix: `docs/10-coverage-matrix.md`
- Phase 1 Closeout Checklist: `docs/11-phase1-closeout-checklist.md`
- Oracle Vector Expansion Plan: `docs/12-oracle-vector-expansion-plan.md`
- Benchmark Baseline Spec: `docs/13-benchmark-baseline-spec.md`
- Devnet E2E Acceptance Guide: `docs/14-devnet-e2e-acceptance.md`
- Phase 1 Execution Matrix: `docs/15-phase1-execution-matrix.md`
- Future Specs:
  - Interfaces: `docs/03a-interfaces-spec.md`
  - Signers: `docs/03b-signers-spec.md`
  - RPC Extended: `docs/03c-rpc-extended-spec.md`

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
