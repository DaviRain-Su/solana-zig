# solana-zig

Zig implementation of Solana SDK, aligned to Rust SDK 4.0.1 semantics.

## Current Status

**Phase 1 / Phase 2 have shipped. Phase 3 Batch 5 is complete.**
The aggregate verdict is `有条件发布` (2 open exceptions: `requestAirdrop` partial, `getAddressLookupTable` accepted). The authoritative status is `docs/10-coverage-matrix.md` and `docs/39-phase3-batch5-release-readiness.md`.

| Phase | Scope | Status |
|-------|-------|--------|
| **Phase 1** — Core / Tx / RPC foundations | `core`, `tx`, 5 RPC methods, oracle vectors, Devnet E2E | ✅ Complete |
| **Phase 2** — Extended RPC / WebSocket / Nonce | 11 extended RPC methods, WebSocket (7 subscription types), Durable Nonce, ComputeBudget | ✅ Complete |
| **Phase 3** — Interfaces / Signers / C ABI | System/Token/Token-2022/Memo/Stake builders, Signer abstraction (vtable), C ABI export | In closeout review |

### Capabilities

- **Core**: `Pubkey` (32B), `Signature` (64B), `Keypair`, `Hash` (32B), `base58`, `shortvec`
- **Tx**: `Instruction`, `AccountMeta`, `Message` (legacy + v0), `AddressLookupTable`, `VersionedTransaction`
- **RPC**: `RpcClient` with **16 methods** — `getLatestBlockhash`, `getAccountInfo`, `getBalance`, `simulateTransaction`, `sendTransaction`, `getSlot`, `getEpochInfo`, `getMinimumBalanceForRentExemption`, `requestAirdrop`, `getAddressLookupTable`, `getSignaturesForAddress`, `getTokenAccountsByOwner`, `getTokenAccountBalance`, `getTokenSupply`, `getTransaction`, `getSignatureStatuses`
- **RPC retry**: exponential backoff, rate-limit aware (HTTP 429/5xx)
- **WebSocket**: `WsRpcClient` — 7 subscription types (`account`/`program`/`signature`/`slot`/`root`/`logs`/`block`), auto-reconnect with backoff, dedup ring buffer, `WsStats` observability
- **Interfaces**: `system` (Transfer/CreateAccount/AdvanceNonceAccount), `token` (TransferChecked/CloseAccount/MintTo/Approve/Burn), `token_2022`, `compute_budget` (SetComputeUnitLimit/SetComputeUnitPrice), `memo`, `stake` (Create/Delegate/Deactivate/Withdraw), `ata` (Associated Token Account)
- **Signers**: `Signer` vtable abstraction, `InMemorySigner`, `MockExternalSigner` (final correctness closeout pending)
- **C ABI**: Core types + tx build + RPC with live HTTP transport exported (`include/solana_zig.h`)
- **E2E**: Devnet (`zig build devnet-e2e`), Nonce (`zig build nonce-e2e`), Surfpool (`zig build e2e`)
- **Benchmark**: `zig build bench` — serialization/deserialization baseline

## Build & Test

```bash
zig build test          # 239 tests
zig build bench         # benchmark baseline
```

## Quickstart

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
SOLANA_RPC_URL=<your-devnet-endpoint> zig build nonce-e2e
```

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
var client = try sol.rpc.RpcClient.init(std.heap.page_allocator, std.io.default, "https://api.devnet.solana.com");
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

Minimal TypeScript helper shim for hackathon/demo adoption:

- Path: `packages/client`
- Scope: mirrors `docs/18` AC-01~AC-07 only
- Status: `v0.1.0` (minimal shim, not full SDK parity with Zig typed RPC API)

```bash
cd packages/client
npm test
```

Contract mapping: `packages/client/AC-MAPPING.md`, `docs/18-surfpool-e2e-contract.md`

## Scope Strategy: Product Roadmap Phases

- **Phase 1** ✅: off-chain SDK foundations (`core/tx/rpc`) + compatibility closeout
- **Phase 2** ✅: extended RPC (16 methods total), WebSocket subscriptions (7 types), Durable Nonce workflow, ComputeBudget helpers
- **Phase 3**: interface modules (system/token/token-2022/memo/stake/ata), signer backends, C ABI export — main surface landed, Batch 4 closeout in progress
- **Phase 4** (future): on-chain semantics as a **separate subproject** (`solana-program-zig`)

## Roadmap Documents

- Docs Index: `docs/README.md`
- PRD: `docs/01-prd.md`
- Architecture: `docs/02-architecture.md`
- Technical Spec: `docs/03-technical-spec.md`
- Task Breakdown: `docs/04-task-breakdown.md`
- Test Spec: `docs/05-test-spec.md`
- Evolution: `docs/08-evolution.md`
- Coverage Matrix: `docs/10-coverage-matrix.md`
- Phase 3 Batch 5 Release Readiness: `docs/39-phase3-batch5-release-readiness.md`
- Quickstart + API Examples: `docs/17-quickstart-and-api-examples.md`
- WebSocket Guide: `docs/websocket-guide.md`
- RPC Examples: `docs/rpc-examples.md`
- Phase 1 PRD: `docs/prd-phase-1-solana-zig-sdk.md`
- Phase 2 PRD: `docs/prd-phase-2-solana-zig-sdk-rpcwebsocket.md`
- Phase 3 PRD: `docs/prd-phase-3-batch-3-solana-zig-sdk-signersc-abi-stake.md`
- ADR: `docs/adr/README.md`

## Official Reference Repositories

- `solana-sdk` + component crates: https://github.com/anza-xyz/solana-sdk
- `solana-client` implementation: https://github.com/anza-xyz/agave/tree/master/client
- `pinocchio` and program-specific crates: https://github.com/anza-xyz/pinocchio
- SPL interface repositories:
  - https://github.com/solana-program/token/tree/main/interface
  - https://github.com/solana-program/token-2022/tree/main/interface
  - https://github.com/solana-program/associated-token-account/tree/main/interface
  - https://github.com/solana-program/memo/tree/main/interface
- Signer backend reference (`solana-keychain`): https://github.com/solana-foundation/solana-keychain

## Oracle Vectors

- Static vectors: `testdata/oracle_vectors.json` (core + keypair + message + transaction)
- Rust generator: `scripts/oracle/`
