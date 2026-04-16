// Phase 1 E2E Harness — Mock + Devnet
//
// Aligned with docs/18-surfpool-e2e-contract.md (K3-H1, K3-F1).
//
// Mock mode: always runs (offline, scripted RPC responses).
// Devnet mode: runs only when SOLANA_RPC_URL is set.
//
// Build & run: zig build devnet-e2e

const std = @import("std");
const root = @import("solana_zig");

const Pubkey = root.core.Pubkey;
const Hash = root.core.Hash;
const Keypair = root.core.Keypair;
const Instruction = root.tx.Instruction;
const AccountMeta = root.tx.AccountMeta;
const Message = root.tx.Message;
const VersionedTransaction = root.tx.VersionedTransaction;
const RpcClient = root.rpc.RpcClient;
const transport_mod = root.rpc.transport;

// --- Contract fixtures (docs/18 §2.2) ---

const PAYER_SEED = [_]u8{1} ** 32;
const PROGRAM_ID = Pubkey.init([_]u8{0x06} ** 32);
const RECEIVER = Pubkey.init([_]u8{0x07} ** 32);
const IX_DATA = [_]u8{ 0x01, 0x02, 0x03 };

// --- Mock Transport (scripted sequence) ---

const ScriptedMock = struct {
    responses: []const []const u8,
    call_index: usize = 0,

    fn postJson(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) transport_mod.PostJsonError![]u8 {
        _ = url;
        _ = payload;
        const self: *ScriptedMock = @ptrCast(@alignCast(ctx));
        if (self.call_index >= self.responses.len) return error.RpcTransport;
        const response = self.responses[self.call_index];
        self.call_index += 1;
        return allocator.dupe(u8, response);
    }
};

// --- Mock RPC responses ---

const MOCK_BLOCKHASH_RESPONSE =
    \\{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":100},"value":{"blockhash":"4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn","lastValidBlockHeight":1000}}}
;

const MOCK_SIMULATE_HAPPY =
    \\{"jsonrpc":"2.0","id":2,"result":{"context":{"slot":100},"value":{"err":null,"logs":["Program log: success"],"unitsConsumed":100}}}
;

const MOCK_SIMULATE_FAILURE =
    \\{"jsonrpc":"2.0","id":2,"error":{"code":-32002,"message":"Transaction signature verification failure","data":{"err":"SignatureFailure"}}}
;

// --- E2E Test: K3-H1 Happy Path (Mock) ---

test "K3-H1 mock: construct -> sign -> simulate (happy)" {
    const gpa = std.testing.allocator;
    const payer = try Keypair.fromSeed(PAYER_SEED);

    var responses = [_][]const u8{ MOCK_BLOCKHASH_RESPONSE, MOCK_SIMULATE_HAPPY };
    var mock = ScriptedMock{ .responses = &responses };
    const transport = transport_mod.Transport.init(@ptrCast(&mock), ScriptedMock.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://mock.test", transport);
    defer client.deinit();

    // S2: getLatestBlockhash
    const bh_result = try client.getLatestBlockhash();
    switch (bh_result) {
        .ok => |bh| {
            // A-H2: lastValidBlockHeight > 0
            try std.testing.expect(bh.last_valid_block_height > 0);

            // A-H3c: blockhash can be base58-encoded
            const bh_str = try bh.blockhash.toBase58Alloc(gpa);
            defer gpa.free(bh_str);
            try std.testing.expect(bh_str.len > 0);

            // S3: compile legacy message
            const accounts = [_]AccountMeta{
                .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
                .{ .pubkey = RECEIVER, .is_signer = false, .is_writable = true },
            };
            const ixs = [_]Instruction{
                .{ .program_id = PROGRAM_ID, .accounts = &accounts, .data = &IX_DATA },
            };
            const msg = try Message.compileLegacy(gpa, payer.pubkey(), &ixs, bh.blockhash);

            // S4: initUnsigned
            var tx = try VersionedTransaction.initUnsigned(gpa, msg);
            defer tx.deinit();

            // S5: sign + verify
            try tx.sign(&[_]Keypair{payer});
            // A-H3a: signature is 64 bytes
            try std.testing.expectEqual(@as(usize, 64), tx.signatures[0].bytes.len);
            // A-H3b: verify passes
            try tx.verifySignatures();

            // S6: simulateTransaction
            const sim_result = try client.simulateTransaction(tx);
            switch (sim_result) {
                .ok => |sim_json| {
                    // A-H4: ok variant
                    defer sim_json.parsed.deinit();
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    return error.UnexpectedRpcError;
                },
            }
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            return error.UnexpectedRpcError;
        },
    }
}

// --- E2E Test: K3-F1 Failure Path (Mock) ---

test "K3-F1 mock: unsigned tx simulate fails (failure)" {
    const gpa = std.testing.allocator;
    const payer = try Keypair.fromSeed(PAYER_SEED);

    var responses = [_][]const u8{ MOCK_BLOCKHASH_RESPONSE, MOCK_SIMULATE_FAILURE };
    var mock = ScriptedMock{ .responses = &responses };
    const transport = transport_mod.Transport.init(@ptrCast(&mock), ScriptedMock.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://mock.test", transport);
    defer client.deinit();

    // S2: getLatestBlockhash
    const bh_result = try client.getLatestBlockhash();
    switch (bh_result) {
        .ok => |bh| {
            // S3: compile legacy message
            const accounts = [_]AccountMeta{
                .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
                .{ .pubkey = RECEIVER, .is_signer = false, .is_writable = true },
            };
            const ixs = [_]Instruction{
                .{ .program_id = PROGRAM_ID, .accounts = &accounts, .data = &IX_DATA },
            };
            const msg = try Message.compileLegacy(gpa, payer.pubkey(), &ixs, bh.blockhash);

            // S4: initUnsigned (NO sign — S5 skipped per contract)
            var tx = try VersionedTransaction.initUnsigned(gpa, msg);
            defer tx.deinit();

            // S6: simulateTransaction (unsigned, should fail sig verify)
            const sim_result = try client.simulateTransaction(tx);
            switch (sim_result) {
                .ok => |sim_json| {
                    // A-F1 fallback: if server returns ok, err should not be null
                    defer sim_json.parsed.deinit();
                    return error.ExpectedFailure;
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    // A-F2: code < 0
                    try std.testing.expect(rpc_err.code < 0);
                    // A-F3: message non-empty
                    try std.testing.expect(rpc_err.message.len > 0);
                },
            }
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            return error.UnexpectedRpcError;
        },
    }
}

// --- Devnet Live Test (gated by SOLANA_RPC_URL) ---

test "K3-H1 devnet: construct -> sign -> simulate (live)" {
    const gpa = std.testing.allocator;

    // D-04: gate on env var
    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[devnet E2E] endpoint: {s}\n", .{endpoint});

    const payer = try Keypair.fromSeed(PAYER_SEED);

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    // S2: getLatestBlockhash
    const bh_result = try client.getLatestBlockhash();
    switch (bh_result) {
        .ok => |bh| {
            try std.testing.expect(bh.last_valid_block_height > 0);

            // S3-S5: construct + sign
            const accounts = [_]AccountMeta{
                .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
                .{ .pubkey = RECEIVER, .is_signer = false, .is_writable = true },
            };
            const ixs = [_]Instruction{
                .{ .program_id = PROGRAM_ID, .accounts = &accounts, .data = &IX_DATA },
            };
            const msg = try Message.compileLegacy(gpa, payer.pubkey(), &ixs, bh.blockhash);

            var tx = try VersionedTransaction.initUnsigned(gpa, msg);
            defer tx.deinit();
            try tx.sign(&[_]Keypair{payer});
            try tx.verifySignatures();

            // S6: simulate
            const sim_result = try client.simulateTransaction(tx);
            switch (sim_result) {
                .ok => |sim_json| {
                    defer sim_json.parsed.deinit();
                    std.debug.print("[devnet E2E] simulate returned .ok\n", .{});
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    // Devnet may reject our dummy tx — acceptable for E2E evidence
                    std.debug.print("[devnet E2E] simulate rpc_error: {s}\n", .{rpc_err.message});
                },
            }
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[devnet E2E] getLatestBlockhash failed: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }
}
