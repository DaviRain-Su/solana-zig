// Phase 1+2 E2E Harness — Mock + Devnet
//
// Aligned with docs/18-surfpool-e2e-contract.md (K3-H1, K3-F1).
// Phase 2 addition: sendTransaction live evidence (#17 P2-2).
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
const SYSTEM_PROGRAM = Pubkey.init([_]u8{0x00} ** 32);
const MOCK_SEND_SUCCESS =
    \\{"jsonrpc":"2.0","id":3,"result":"1111111111111111111111111111111111111111111111111111111111111111"}
;
const MOCK_CONFIRM_SUCCESS =
    \\{"jsonrpc":"2.0","id":4,"result":{"context":{"slot":100},"value":[{"slot":99,"confirmations":null,"err":null,"confirmationStatus":"confirmed"}]}}
;
const LIVE_SEND_LAMPORTS: u64 = 1000;
const LIVE_AIRDROP_LAMPORTS: u64 = 100_000_000;
const MAX_BALANCE_POLLS: u32 = 30;
const MAX_CONFIRM_POLLS: u32 = 30;
const MAX_GET_TRANSACTION_POLLS: u32 = 30;

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
                .ok => |sim_val| {
                    // A-H4: ok variant
                    var sim = sim_val;
                    defer sim.deinit(gpa);
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
                .ok => |sim_val| {
                    // A-F1 fallback: if server returns ok, err should not be null
                    var sim = sim_val;
                    defer sim.deinit(gpa);
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
                .ok => |sim_val| {
                    var sim = sim_val;
                    defer sim.deinit(gpa);
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

// --- P2-2: sendTransaction live evidence (#17) ---

/// Helper: request airdrop via raw transport call.
/// Returns immediately after the RPC responds (does not wait for confirmation).
fn requestAirdrop(client: *RpcClient, pubkey_str: []const u8, lamports: u64) !void {
    const gpa = client.allocator;
    const payload = try std.fmt.allocPrint(
        gpa,
        "{{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"requestAirdrop\",\"params\":[\"{s}\",{d}]}}",
        .{ pubkey_str, lamports },
    );
    defer gpa.free(payload);

    const raw = try client.transport.postJson(gpa, client.endpoint, payload);
    defer gpa.free(raw);
    // We don't parse — just fire and forget. The validator will fund the account.
}

/// Build a System Program transfer instruction (instruction index 2).
/// Data layout: [u32 LE instruction index = 2] + [u64 LE lamports]
fn buildTransferData(lamports: u64) [12]u8 {
    var data: [12]u8 = undefined;
    // System instruction index 2 = Transfer
    std.mem.writeInt(u32, data[0..4], 2, .little);
    std.mem.writeInt(u64, data[4..12], lamports, .little);
    return data;
}

fn buildSignedSelfTransferTx(
    allocator: std.mem.Allocator,
    payer: Keypair,
    blockhash: Hash,
    lamports: u64,
) !VersionedTransaction {
    const transfer_data = buildTransferData(lamports);
    const accounts = [_]AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = payer.pubkey(), .is_signer = false, .is_writable = true },
    };
    const ixs = [_]Instruction{
        .{ .program_id = SYSTEM_PROGRAM, .accounts = &accounts, .data = &transfer_data },
    };
    const msg = try Message.compileLegacy(allocator, payer.pubkey(), &ixs, blockhash);

    var tx = try VersionedTransaction.initUnsigned(allocator, msg);
    errdefer tx.deinit();
    try tx.sign(&[_]Keypair{payer});
    try tx.verifySignatures();
    return tx;
}

fn waitForConfirmedSignature(
    client: *RpcClient,
    allocator: std.mem.Allocator,
    signature: @import("solana_zig").core.Signature,
    log_prefix: []const u8,
) !bool {
    const sigs = [_]@import("solana_zig").core.Signature{signature};
    var confirm_attempts: u32 = 0;

    while (confirm_attempts < MAX_CONFIRM_POLLS) : (confirm_attempts += 1) {
        const status_result = try client.getSignatureStatuses(&sigs);
        switch (status_result) {
            .ok => |maybe_status| {
                if (maybe_status) |status_val| {
                    var status = status_val;
                    defer status.deinit(allocator);

                    if (status.confirmation_status) |cs| {
                        std.debug.print("[{s}] confirm poll {d}: status={s}, slot={d}\n", .{ log_prefix, confirm_attempts, cs, status.slot });
                        if (std.mem.eql(u8, cs, "confirmed") or std.mem.eql(u8, cs, "finalized")) {
                            if (status.err_json) |err| {
                                std.debug.print("[{s}] tx confirmed but has error: {s}\n", .{ log_prefix, err });
                                return error.TransactionConfirmedWithError;
                            }
                            return true;
                        }
                    } else {
                        std.debug.print("[{s}] confirm poll {d}: status present but no confirmationStatus yet\n", .{ log_prefix, confirm_attempts });
                    }
                } else {
                    std.debug.print("[{s}] confirm poll {d}: not found yet\n", .{ log_prefix, confirm_attempts });
                }
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(allocator);
                std.debug.print("[{s}] confirm poll {d}: rpc_error: {s}\n", .{ log_prefix, confirm_attempts, rpc_err.message });
            },
        }
    }

    return false;
}

fn waitForTransactionDetails(
    client: *RpcClient,
    allocator: std.mem.Allocator,
    signature: @import("solana_zig").core.Signature,
    log_prefix: []const u8,
) !?root.rpc.types.TransactionInfo {
    var attempts: u32 = 0;

    while (attempts < MAX_GET_TRANSACTION_POLLS) : (attempts += 1) {
        const tx_result = try client.getTransactionWithOptions(signature, .{
            .commitment = .confirmed,
            .max_supported_transaction_version = 0,
        });

        switch (tx_result) {
            .ok => |maybe_tx| {
                if (maybe_tx) |tx_val| {
                    std.debug.print("[{s}] getTransaction poll {d}: slot={d}\n", .{ log_prefix, attempts, tx_val.slot });
                    return tx_val;
                }
                std.debug.print("[{s}] getTransaction poll {d}: transaction not available yet\n", .{ log_prefix, attempts });
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(allocator);
                std.debug.print("[{s}] getTransaction poll {d}: rpc_error: {s}\n", .{ log_prefix, attempts, rpc_err.message });
            },
        }
    }

    return null;
}

test "US-017 mock: construct -> sign -> simulate -> send -> confirm (happy)" {
    const gpa = std.testing.allocator;
    const payer = try Keypair.fromSeed(PAYER_SEED);

    var responses = [_][]const u8{
        MOCK_BLOCKHASH_RESPONSE,
        MOCK_SIMULATE_HAPPY,
        MOCK_SEND_SUCCESS,
        MOCK_CONFIRM_SUCCESS,
    };
    var mock = ScriptedMock{ .responses = &responses };
    const transport = transport_mod.Transport.init(@ptrCast(&mock), ScriptedMock.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://mock.test", transport);
    defer client.deinit();

    const bh_result = try client.getLatestBlockhash();
    switch (bh_result) {
        .ok => |bh| {
            var tx = try buildSignedSelfTransferTx(gpa, payer, bh.blockhash, LIVE_SEND_LAMPORTS);
            defer tx.deinit();

            const sim_result = try client.simulateTransaction(tx);
            switch (sim_result) {
                .ok => |sim_val| {
                    var sim = sim_val;
                    defer sim.deinit(gpa);
                    try std.testing.expect(sim.err_json == null);
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    return error.UnexpectedRpcError;
                },
            }

            const send_result = try client.sendTransaction(tx);
            switch (send_result) {
                .ok => |send| {
                    try std.testing.expectEqual(@as(usize, 64), send.signature.bytes.len);
                    const sig_b58 = try send.signature.toBase58Alloc(gpa);
                    defer gpa.free(sig_b58);
                    std.debug.print("[US-017 mock] sendTransaction .ok — sig: {s}\n", .{sig_b58});
                    try std.testing.expect(try waitForConfirmedSignature(&client, gpa, send.signature, "US-017 mock"));
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

// --- P2-2 Failure Path: sendTransaction rpc_error (Mock) ---

const MOCK_SEND_FAILURE =
    \\{"jsonrpc":"2.0","id":3,"error":{"code":-32002,"message":"Transaction simulation failed: Attempt to debit an account but found no record of a prior credit.","data":{"err":"AccountNotFound"}}}
;

const MOCK_CONFIRM_WITH_ERROR =
    \\{"jsonrpc":"2.0","id":4,"result":{"context":{"slot":100},"value":[{"slot":99,"confirmations":null,"err":{"InstructionError":[0,"Custom",1]},"confirmationStatus":"confirmed"}]}}
;

test "P2-2 mock: send failure path (rpc_error on sendTransaction)" {
    const gpa = std.testing.allocator;
    const payer = try Keypair.fromSeed(PAYER_SEED);

    var responses = [_][]const u8{ MOCK_BLOCKHASH_RESPONSE, MOCK_SEND_FAILURE };
    var mock = ScriptedMock{ .responses = &responses };
    const transport = transport_mod.Transport.init(@ptrCast(&mock), ScriptedMock.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://mock.test", transport);
    defer client.deinit();

    const bh_result = try client.getLatestBlockhash();
    switch (bh_result) {
        .ok => |bh| {
            const transfer_data = buildTransferData(1000);
            const accounts = [_]AccountMeta{
                .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
                .{ .pubkey = payer.pubkey(), .is_signer = false, .is_writable = true },
            };
            const ixs = [_]Instruction{
                .{ .program_id = SYSTEM_PROGRAM, .accounts = &accounts, .data = &transfer_data },
            };
            const msg = try Message.compileLegacy(gpa, payer.pubkey(), &ixs, bh.blockhash);
            var tx = try VersionedTransaction.initUnsigned(gpa, msg);
            defer tx.deinit();
            try tx.sign(&[_]Keypair{payer});

            const send_result = try client.sendTransaction(tx);
            switch (send_result) {
                .ok => return error.ExpectedSendFailure,
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    // A-SEND-F1: code < 0
                    try std.testing.expect(rpc_err.code < 0);
                    // A-SEND-F2: message non-empty
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

test "P2-2 mock: confirm failure path (tx confirmed with error)" {
    const gpa = std.testing.allocator;

    // Single-response mock: getSignatureStatuses returns confirmed status with tx error
    var responses = [_][]const u8{MOCK_CONFIRM_WITH_ERROR};
    var mock = ScriptedMock{ .responses = &responses };
    const transport = transport_mod.Transport.init(@ptrCast(&mock), ScriptedMock.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://mock.test", transport);
    defer client.deinit();

    const dummy_sig = @import("solana_zig").core.Signature.init([_]u8{0xAA} ** 64);
    const sigs = [_]@import("solana_zig").core.Signature{dummy_sig};
    const status_result = try client.getSignatureStatuses(&sigs);
    switch (status_result) {
        .ok => |maybe_status| {
            try std.testing.expect(maybe_status != null);
            var status = maybe_status.?;
            defer status.deinit(gpa);
            // A-CONFIRM-F1: status is confirmed but has transaction error
            try std.testing.expectEqualStrings("confirmed", status.confirmation_status.?);
            try std.testing.expect(status.err_json != null);
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            return error.UnexpectedRpcError;
        },
    }
}

// --- P2-2 Live: sendTransaction + confirm evidence (#17) ---

test "US-017 live: airdrop -> construct -> sign -> simulate -> send -> confirm" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-017 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-017 live] endpoint: {s}\n", .{endpoint});

    // Use a unique seed for the sendTx test to avoid conflicts with other tests
    // and ensure a valid fee-payer keypair.
    const SENDTX_SEED = [_]u8{ 42, 71, 13, 200, 155, 3, 88, 219, 107, 244, 53, 17, 198, 66, 31, 129, 240, 77, 164, 5, 222, 189, 111, 48, 93, 26, 7, 145, 250, 83, 191, 60 };
    const payer = try Keypair.fromSeed(SENDTX_SEED);
    const payer_b58 = try payer.pubkey().toBase58Alloc(gpa);
    defer gpa.free(payer_b58);
    std.debug.print("[US-017 live] payer: {s}\n", .{payer_b58});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    // Step 1: Airdrop 0.1 SOL to payer (best-effort; may fail on rate-limited endpoints)
    requestAirdrop(&client, payer_b58, LIVE_AIRDROP_LAMPORTS) catch |err| {
        std.debug.print("[US-017 live] airdrop failed (may be rate-limited): {}\n", .{err});
        // Continue — account may already have funds from a previous run
    };

    // Step 2: Poll balance until > 0 (airdrop may need a moment)
    var balance: u64 = 0;
    var attempts: u32 = 0;
    while (attempts < MAX_BALANCE_POLLS) : (attempts += 1) {
        const bal_result = try client.getBalance(payer.pubkey());
        switch (bal_result) {
            .ok => |b| {
                balance = b;
                if (balance > 0) break;
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(gpa);
                std.debug.print("[US-017 live] balance poll {d}: rpc_error: {s}\n", .{ attempts, rpc_err.message });
            },
        }
    }
    std.debug.print("[US-017 live] payer balance: {d} lamports (after {d} polls)\n", .{ balance, attempts });
    if (balance == 0) {
        std.debug.print("[US-017 live] skip: payer has no funds (airdrop may be rate-limited)\n", .{});
        return;
    }

    // Step 3: getLatestBlockhash
    const bh_result = try client.getLatestBlockhash();
    switch (bh_result) {
        .ok => |bh| {
            // Step 4 + 5: Build and sign a self-transfer.
            // Self-transfer avoids needing a funded receiver account.
            var tx = try buildSignedSelfTransferTx(gpa, payer, bh.blockhash, LIVE_SEND_LAMPORTS);
            defer tx.deinit();

            // Step 6: simulateTransaction
            const sim_result = try client.simulateTransaction(tx);
            switch (sim_result) {
                .ok => |sim_val| {
                    var sim = sim_val;
                    defer sim.deinit(gpa);
                    try std.testing.expect(sim.err_json == null);
                    std.debug.print(
                        "[US-017 live] simulate .ok — logs={d}, unitsConsumed={any}\n",
                        .{ sim.logs.len, sim.units_consumed },
                    );
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    std.debug.print("[US-017 live] simulate rpc_error: {s}\n", .{rpc_err.message});
                    return error.DevnetSimulateFailed;
                },
            }

            // Step 7: sendTransaction
            const send_result = try client.sendTransaction(tx);
            switch (send_result) {
                .ok => |result| {
                    try std.testing.expectEqual(@as(usize, 64), result.signature.bytes.len);
                    const sig_b58 = try result.signature.toBase58Alloc(gpa);
                    defer gpa.free(sig_b58);
                    std.debug.print("[US-017 live] sendTransaction .ok — sig: {s}\n", .{sig_b58});

                    // Step 8: Confirm — poll getSignatureStatuses until confirmed/finalized.
                    const confirmed = try waitForConfirmedSignature(&client, gpa, result.signature, "US-017 live");
                    try std.testing.expect(confirmed);
                    std.debug.print("[US-017 live] CONFIRMED — sig: {s}\n", .{sig_b58});

                    // Step 9: Query getTransaction and validate parsed slot/blockTime/meta.
                    const maybe_tx = try waitForTransactionDetails(&client, gpa, result.signature, "US-017 live");
                    try std.testing.expect(maybe_tx != null);
                    var tx_info = maybe_tx.?;
                    defer tx_info.deinit(gpa);
                    try std.testing.expect(tx_info.slot > 0);
                    try std.testing.expect(tx_info.block_time != null);
                    try std.testing.expect(tx_info.meta != null);
                    try std.testing.expect(tx_info.meta.?.fee != null);
                    try std.testing.expect(tx_info.meta.?.fee.? > 0);
                    try std.testing.expect(tx_info.meta.?.err_json == null);
                    try std.testing.expect(tx_info.meta.?.log_messages != null);
                    std.debug.print(
                        "[US-017 live] getTransaction .ok — fee={d}, logs={d}\n",
                        .{ tx_info.meta.?.fee.?, tx_info.meta.?.log_messages.?.len },
                    );
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    std.debug.print("[US-017 live] sendTransaction rpc_error: {s}\n", .{rpc_err.message});
                    return error.DevnetSendFailed;
                },
            }
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-017 live] getLatestBlockhash failed: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }
}
