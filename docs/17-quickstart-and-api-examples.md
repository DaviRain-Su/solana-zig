# Quickstart and API Examples (Phase 1)

This guide is for **Product Phase 1 closeout scope only**:
- off-chain client/sdk path
- core types (`Pubkey/Signature/Keypair/Hash`)
- tx build/sign/serialize
- high-frequency RPC calls (`getLatestBlockhash/getAccountInfo/getBalance/simulateTransaction/sendTransaction`)

It does **not** claim Phase 2/3 capabilities (websocket/signers/C ABI/interfaces).

---

## 1. Quickstart

### 1.1 Run baseline tests

```bash
zig build test
```

### 1.2 Optional Devnet acceptance wrapper

```bash
SOLANA_RPC_URL=https://api.devnet.solana.com scripts/devnet/phase1_acceptance.sh
```

Note: this wrapper currently records environment metadata and runs `zig build test`.  
True in-tree full Devnet E2E harness is tracked in closeout items.

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var client = try sol.rpc.RpcClient.init(
        alloc,
        .default,
        "https://api.devnet.solana.com",
    );
    defer client.deinit();

    const result = try client.getLatestBlockhash();
    switch (result) {
        .ok => |v| {
            const b58 = try v.blockhash.toBase58Alloc(alloc);
            defer alloc.free(b58);
            std.debug.print("blockhash={s} last_valid_block_height={d}\n", .{
                b58,
                v.last_valid_block_height,
            });
        },
        .rpc_error => |e| {
            defer e.deinit(alloc);
            std.debug.print("rpc error: code={d} message={s}\n", .{ e.code, e.message });
        },
    }
}
```

---

## 4. External Messaging Guardrails

For hackathon/demo messaging, keep claims within Phase 1:

- Allowed:
  - "off-chain Zig Solana SDK foundations"
  - "core + tx + 5 high-frequency RPC methods"
  - "Phase 1 closeout in progress"
- Not allowed:
  - "full Solana SDK parity shipped"
  - "Phase 2/3 capabilities already complete"

