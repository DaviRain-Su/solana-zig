# Quickstart and API Examples

This guide covers the current public API surface:
- off-chain client/sdk path
- core types (`Pubkey/Signature/Keypair/Hash`)
- tx build/sign/serialize
- high-frequency RPC calls
- signer abstraction (Phase 3)
- C ABI minimal example (Phase 3)
- interfaces (system, token, compute-budget, memo, stake)

Websocket remains documented in `docs/websocket-guide.md`.

---

## 1. Quickstart

### 1.1 Run baseline tests

```bash
zig build test
```

### 1.2 Optional Devnet acceptance paths

```bash
SOLANA_RPC_URL=https://api.devnet.solana.com zig build devnet-e2e
SOLANA_RPC_URL=https://api.devnet.solana.com scripts/devnet/phase1_acceptance.sh
```

Notes:
- `zig build devnet-e2e` 是当前真实 in-tree live harness，已覆盖 `construct -> sign -> simulate -> send -> confirm`。
- `zig build nonce-e2e` — Nonce 账户完整 E2E 流程。
- `zig build e2e` — Surfpool 本地验证（K3-H1 + K3-F1）。
- Phase 1/2/3 全部完成，208 tests pass。

---

## 2. Minimal Zig Integration

### 2.1 `build.zig.zon`

```zig
.dependencies = .{
    .solana_zig = .{
        .url = "https://github.com/<your-org>/solana-zig/archive/<commit-or-tag>.tar.gz",
        .hash = "<fill-after-fetch>",
    },
},
```

### 2.2 `build.zig`

```zig
const solana_dep = b.dependency("solana_zig", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("solana_zig", solana_dep.module("solana_zig"));
```

### 2.3 In source code

```zig
const sol = @import("solana_zig");
```

---

## 3. API Examples

### 3.1 Core: deterministic keypair + sign/verify

```zig
const std = @import("std");
const sol = @import("solana_zig");

test "core sign verify example" {
    const seed: [32]u8 = [_]u8{1} ** 32;
    const kp = try sol.core.Keypair.fromSeed(seed);
    const sig = try kp.sign("hello-solana-zig");
    try sig.verify("hello-solana-zig", kp.pubkey());
}
```

### 3.2 Tx: compile legacy message + sign transaction

```zig
const std = @import("std");
const sol = @import("solana_zig");

test "legacy message + transaction example" {
    const alloc = std.testing.allocator;

    const payer_seed: [32]u8 = [_]u8{2} ** 32;
    const payer = try sol.core.Keypair.fromSeed(payer_seed);

    const program = sol.core.Pubkey.init([_]u8{3} ** 32);
    const recent = sol.core.Hash.fromData("example-recent-blockhash");

    const metas = [_]sol.tx.AccountMeta{
        .{
            .pubkey = payer.pubkey(),
            .is_signer = true,
            .is_writable = true,
        },
    };

    const instructions = [_]sol.tx.Instruction{
        .{
            .program_id = program,
            .accounts = &metas,
            .data = "hello",
        },
    };

    var msg = try sol.tx.Message.compileLegacy(
        alloc,
        payer.pubkey(),
        &instructions,
        recent,
    );

    // Ownership of `msg` moves into `tx` here; do not call `msg.deinit()` after this.
    var tx = try sol.tx.VersionedTransaction.initUnsigned(alloc, msg);
    defer tx.deinit();

    try tx.sign(&[_]sol.core.Keypair{payer});
    try tx.verifySignatures();
}
```

### 3.3 RPC: getLatestBlockhash

```zig
const std = @import("std");
const sol = @import("solana_zig");

test "rpc getLatestBlockhash example" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    var client = try sol.rpc.RpcClient.init(
        alloc,
        io,
        "https://api.devnet.solana.com",
    );
    defer client.deinit();

    const result = try client.getLatestBlockhash();
    switch (result) {
        .ok => |v| {
            const b58 = try v.blockhash.toBase58Alloc(alloc);
            defer alloc.free(b58);
            try std.testing.expect(v.last_valid_block_height > 0);
            try std.testing.expect(b58.len > 0);
        },
        .rpc_error => |e| {
            defer e.deinit(alloc);
        },
    }
}
```

### 3.4 Signer abstraction

```zig
const std = @import("std");
const sol = @import("solana_zig");

test "signer abstraction example" {
    const alloc = std.testing.allocator;
    const seed: [32]u8 = [_]u8{7} ** 32;
    const kp = try sol.core.Keypair.fromSeed(seed);

    var im_signer = sol.solana.signers.InMemorySigner.init(kp);
    const signer = im_signer.asSigner();

    const pk = try signer.getPubkey();
    _ = pk;

    const sig = try signer.signMessage(alloc, "hello-from-signer");
    _ = sig;
}
```

### 3.5 Stake builder

```zig
const std = @import("std");
const sol = @import("solana_zig");

test "stake builder example" {
    const alloc = std.testing.allocator;
    const from = sol.core.Pubkey.init([_]u8{1} ** 32);
    const stake = sol.core.Pubkey.init([_]u8{2} ** 32);
    const authorized = sol.interfaces.stake.Authorized{
        .staker = from,
        .withdrawer = from,
    };

    var ix = try sol.interfaces.stake.buildCreateStakeAccountInstruction(
        alloc,
        from,
        stake,
        authorized,
        sol.interfaces.stake.Lockup{},
        1_000_000,
    );
    defer ix.deinit(alloc);
}
```

### 3.6 C ABI minimal example

```c
#include "solana_zig.h"
#include <stdio.h>

int main(void) {
    SolanaPubkey pk;
    uint8_t bytes[32] = {0};
    if (solana_pubkey_from_bytes(bytes, 32, &pk) != SOLANA_OK) {
        return 1;
    }

    char *b58 = NULL;
    size_t len = 0;
    if (solana_pubkey_to_base58(&pk, &b58, &len) != SOLANA_OK) {
        return 1;
    }

    printf("pubkey: %.*s\n", (int)len, b58);
    solana_string_free(b58, len);
    return 0;
}
```

---

## 4. External Messaging Guardrails

For hackathon/demo messaging, reflect the current shipped state:

- Allowed:
  - "off-chain Zig Solana SDK foundations + extended RPC/WebSocket shipped"
  - "Phase 3 major surfaces are implemented and in final closeout review"
  - "16 RPC methods, 7 WebSocket subscription types"
  - "7 interface modules (system/token/token-2022/compute_budget/memo/stake/ata)"
  - "Signer abstraction + C ABI export surface landed"
  - "current test suite passes with leak checks"
- Not allowed:
  - "Phase 3 is fully closed"
  - "C ABI RPC is already production/live-ready"
  - "on-chain SBF/no_runtime support" (Phase 4, separate evaluation)

---

## 5. `@zignocchio/client` Quickstart (K2)

`#3 K2` delivered a minimal TypeScript helper/shim under `packages/client`.
This is an adoption layer for Phase 1, not an independent full SDK line.

### 5.1 Install and test

```bash
cd packages/client
npm install
npm test
```

### 5.2 K3-H1 happy-path example

```bash
cd packages/client
SURFPOOL_RPC_URL=http://127.0.0.1:8899 npx tsx examples/k3-h1-happy.ts
```

### 5.3 Contract and acceptance mapping

- Contract source of truth: `docs/18-surfpool-e2e-contract.md`
- AC mapping: `packages/client/AC-MAPPING.md`

### 5.4 Locked scope boundary

`@zignocchio/client v0.1.0` only covers `docs/18` AC-01~AC-07:

- transport injection
- `getLatestBlockhash` typed response
- `simulateTransaction` raw JSON preservation
- `sign` + `verifySignatures`
- `compileLegacy` parameter order
- `sigVerify: true` in simulate payload
- configurable endpoint

Out of scope in this version:

- full Phase 4 capability surface (on-chain SBF runtime parity)
