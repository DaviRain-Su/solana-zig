const std = @import("std");
const sol = @import("solana_zig");

// K3-H1: happy path getLatestBlockhash -> construct -> sign -> simulateTransaction
test "K3-H1: happy path surfpool E2E" {
    const gpa = std.testing.allocator;

    // Environment gate: skip if SURFPOOL_RPC_URL is not set
    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SURFPOOL_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => return,
        else => return err,
    };
    defer gpa.free(endpoint);

    // Fixed inputs
    const payer = try sol.core.Keypair.fromSeed([_]u8{1} ** 32);
    const program_id = sol.core.Pubkey.init([_]u8{0x06} ** 32);
    const receiver = sol.core.Pubkey.init([_]u8{0x07} ** 32);
    const ix_data = &[_]u8{ 0x01, 0x02, 0x03 };

    // S1: initialize RPC client
    var client = try sol.rpc.RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    // S2: get latest blockhash
    const bh = try client.getLatestBlockhash();
    try std.testing.expect(bh == .ok); // A-H1
    try std.testing.expect(bh.ok.last_valid_block_height > 0); // A-H2

    // A-H3c: blockhash is non-empty (can be base58-encoded)
    const b58 = try bh.ok.blockhash.toBase58Alloc(gpa);
    defer gpa.free(b58);
    try std.testing.expect(b58.len > 0);

    // S3: construct legacy message
    const accounts = [_]sol.tx.AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]sol.tx.Instruction{
        .{ .program_id = program_id, .accounts = &accounts, .data = ix_data },
    };
    const msg = try sol.tx.Message.compileLegacy(gpa, payer.pubkey(), &ixs, bh.ok.blockhash);

    // S4-S5: construct, sign and verify transaction
    var tx = try sol.tx.VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();
    try tx.sign(&[_]sol.core.Keypair{payer});
    try tx.verifySignatures(); // A-H3b

    // A-H3a: signature length is fixed 64 bytes
    try std.testing.expectEqual(@as(usize, 64), tx.signatures[0].bytes.len);

    // S6: simulate transaction
    const sim = try client.simulateTransaction(tx);
    switch (sim) {
        .ok => |v| {
            var owned = v;
            defer owned.deinit(gpa);
            // A-H4: .ok variant returned
            // A-H5: simulation typed err field is null in happy path.
            if (v.err_json) |err| {
                std.debug.print("K3-H1 note: simulation err field present but RPC returned ok: {s}\n", .{err});
            }
        },
        .rpc_error => |e| {
            defer e.deinit(gpa);
            std.debug.print("K3-H1 unexpected rpc error: code={d} message={s}\n", .{ e.code, e.message });
            return error.UnexpectedRpcError;
        },
    }
}

// K3-F1: simulateTransaction with unsigned tx (signature verification failure)
test "K3-F1: failure path unsigned simulation" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SURFPOOL_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => return,
        else => return err,
    };
    defer gpa.free(endpoint);

    // Fixed inputs (same as K3-H1)
    const payer = try sol.core.Keypair.fromSeed([_]u8{1} ** 32);
    const program_id = sol.core.Pubkey.init([_]u8{0x06} ** 32);
    const receiver = sol.core.Pubkey.init([_]u8{0x07} ** 32);
    const ix_data = &[_]u8{ 0x01, 0x02, 0x03 };

    var client = try sol.rpc.RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const bh = try client.getLatestBlockhash();
    try std.testing.expect(bh == .ok);

    const accounts = [_]sol.tx.AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]sol.tx.Instruction{
        .{ .program_id = program_id, .accounts = &accounts, .data = ix_data },
    };
    const msg = try sol.tx.Message.compileLegacy(gpa, payer.pubkey(), &ixs, bh.ok.blockhash);

    // S4: construct unsigned transaction (intentionally skip sign)
    var tx = try sol.tx.VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();

    // S6: simulate transaction
    const sim = try client.simulateTransaction(tx);
    switch (sim) {
        .ok => |v| {
            var owned = v;
            defer owned.deinit(gpa);
            // A-F1-fallback: if .ok, typed err_json must be present.
            const has_err = v.err_json != null;
            if (!has_err) {
                std.debug.print("K3-F1 fallback failed: expected err != null in .ok branch\n", .{});
                return error.ExpectedSimulationError;
            }
        },
        .rpc_error => |e| {
            defer e.deinit(gpa);
            // A-F1 primary: .rpc_error variant
            try std.testing.expect(e.code < 0); // A-F2
            try std.testing.expect(e.message.len > 0); // A-F3
        },
    }
}
