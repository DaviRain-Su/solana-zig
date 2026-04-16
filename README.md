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

### 3) Optional Devnet acceptance paths

```bash
SOLANA_RPC_URL=<your-devnet-endpoint> zig build devnet-e2e
SOLANA_RPC_URL=<your-devnet-endpoint> scripts/devnet/phase1_acceptance.sh
```

- `zig build devnet-e2e` 是当前仓库内的 live harness：在设置 `SOLANA_RPC_URL` 时已覆盖 `construct -> sign -> simulate`，并补齐 `sendTransaction` live 证据。
- `scripts/devnet/phase1_acceptance.sh` 仍是包装脚本：记录环境元数据并运行离线门禁，本身不等同于真实 harness。
- 是否可以宣称 `Product Phase 1 closeout`，仍取决于 `docs/11` 与 `docs/15` 的整体收口状态，而不是单看 send 证据是否存在。

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

## TypeScript Helper Shim (`@zignocchio/client`)

For hackathon/demo adoption, this repo now includes a minimal TypeScript helper shim:

- Path: `packages/client`
- Scope: mirrors `docs/18` AC-01~AC-07 only
- Status: `v0.1.0` first delivery (minimal helper/shim, not a standalone full SDK；与当前 Zig typed RPC API 仍非完全 parity)

Quick checks:

```bash
cd packages/client
npm test
```

Contract mapping:

- `packages/client/AC-MAPPING.md`
- `docs/18-surfpool-e2e-contract.md`

## Optional Devnet Usage
Set `SOLANA_RPC_URL` and choose one of the two paths below:

```bash
SOLANA_RPC_URL=<your-devnet-endpoint> zig build devnet-e2e
SOLANA_RPC_URL=<your-devnet-endpoint> scripts/devnet/phase1_acceptance.sh
```

说明：
- `zig build devnet-e2e` 是当前真实 in-tree harness，已覆盖 `getLatestBlockhash -> compileLegacy -> sign -> verify -> simulate`，并补齐 `sendTransaction` live 路径。
- `scripts/devnet/phase1_acceptance.sh` 只是包装式验收路径，用于留档环境与离线门禁。
- 若要宣称 `Product Phase 1` 已 closeout，仍需满足 `docs/11` 与 `docs/15` 的整体规则，而不是只看 E2E 单项证据。

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
- Surfpool E2E Contract: `docs/18-surfpool-e2e-contract.md`
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
