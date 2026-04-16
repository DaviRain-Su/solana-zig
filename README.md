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

## Quickstart (Phase 1)

This repo currently targets **Product Phase 1 closeout** (off-chain SDK foundations).

### 1) Use as a Zig dependency

`build.zig.zon`:

```zig
.dependencies = .{
    .solana_zig = .{
        .url = "https://github.com/<your-org>/solana-zig/archive/<commit-or-tag>.tar.gz",
        .hash = "<fill-after-fetch>",
    },
},
```

`build.zig`:

```zig
const solana_dep = b.dependency("solana_zig", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("solana_zig", solana_dep.module("solana_zig"));
```

### 2) Run local verification

```bash
zig build test
```

### 3) Optional Devnet acceptance wrapper

```bash
SOLANA_RPC_URL=<your-devnet-endpoint> scripts/devnet/phase1_acceptance.sh
```

For now this wrapper records env metadata and runs `zig build test`; it is not yet an in-tree full Devnet harness.

## API Usage Examples

For complete snippets, see `docs/17-quickstart-and-api-examples.md`.

Minimal examples:

```zig
const std = @import("std");
const sol = @import("solana_zig");

// Core: deterministic keypair and signature verify
var seed: [32]u8 = [_]u8{1} ** 32;
const kp = try sol.core.Keypair.fromSeed(seed);
const sig = try kp.sign("hello");
try sig.verify("hello", kp.pubkey());
```

```zig
const std = @import("std");
const sol = @import("solana_zig");

// RPC: get latest blockhash
var client = try sol.rpc.RpcClient.init(std.heap.page_allocator, .default, "https://api.devnet.solana.com");
defer client.deinit();

const latest = try client.getLatestBlockhash();
switch (latest) {
    .ok => |v| std.debug.print("last_valid_block_height={d}\n", .{v.last_valid_block_height}),
    .rpc_error => |e| {
        defer e.deinit(std.heap.page_allocator);
        std.debug.print("rpc error: {d} {s}\n", .{ e.code, e.message });
    },
}
```

## Optional Devnet Usage
Set `SOLANA_RPC_URL` and call the RPC client from your own integration harness.

For the current Phase 1 acceptance wrapper (it only records env metadata and runs `zig build test`; it is not yet a true in-tree Devnet E2E harness), run:

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
- Docs Index: `docs/README.md`
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
- Benchmark Baseline Results Template: `docs/13a-benchmark-baseline-results.md`
- Devnet E2E Acceptance Guide: `docs/14-devnet-e2e-acceptance.md`
- Devnet E2E Run Log Template: `docs/14a-devnet-e2e-run-log.md`
- Phase 1 Execution Matrix: `docs/15-phase1-execution-matrix.md`
- Consumer / Security Notes: `docs/16-consumer-profiles-and-security-notes.md`
- Quickstart + API Examples: `docs/17-quickstart-and-api-examples.md`
- Future Specs:
  - Interfaces: `docs/03a-interfaces-spec.md`
  - Signers: `docs/03b-signers-spec.md`
  - RPC Extended: `docs/03c-rpc-extended-spec.md`
  - C ABI: `docs/03d-cabi-spec.md`
- ADR:
  - Index: `docs/adr/README.md`
  - Template: `docs/adr/ADR-template.md`

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
- Rust `v2` core generator is available in `scripts/oracle/`; keypair / message / transaction vectors are still being filled in
