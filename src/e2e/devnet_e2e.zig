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
const MAX_ALT_DISCOVERY_BLOCKS: u64 = 32;
const WRAPPED_SOL_MINT_STR = "So11111111111111111111111111111111111111112";

fn isRateLimitedRpcError(code: i64, message: []const u8) bool {
    if (code == -32005) return true;
    if (std.mem.indexOf(u8, message, "429") != null) return true;
    if (std.mem.indexOf(u8, message, "rate limit") != null) return true;
    if (std.mem.indexOf(u8, message, "Rate limit") != null) return true;
    if (std.mem.indexOf(u8, message, "Too Many Requests") != null) return true;
    return false;
}

// --- Mock Transport (scripted sequence) ---

const ScriptedMock = struct {
    responses: []const []const u8,
    call_index: usize = 0,

    fn postJson(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) transport_mod.PostJsonError!transport_mod.PostJsonResponse {
        _ = url;
        _ = payload;
        const self: *ScriptedMock = @ptrCast(@alignCast(ctx));
        if (self.call_index >= self.responses.len) return error.RpcTransport;
        const response = self.responses[self.call_index];
        self.call_index += 1;
        return .{
            .status = .ok,
            .body = try allocator.dupe(u8, response),
        };
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
    defer raw.deinit(gpa);
    // We don't parse — just fire and forget. The validator will fund the account.
}

fn getJsonField(value: *const std.json.Value, field: []const u8) ?*const std.json.Value {
    if (value.* != .object) return null;
    const obj_ptr: *std.json.ObjectMap = @constCast(&value.object);
    return obj_ptr.getPtr(field);
}

fn getJsonStringField(value: *const std.json.Value, field: []const u8) ?[]const u8 {
    const field_value = getJsonField(value, field) orelse return null;
    if (field_value.* != .string) return null;
    return field_value.string;
}

fn getJsonU64Field(value: *const std.json.Value, field: []const u8) ?u64 {
    const field_value = getJsonField(value, field) orelse return null;
    return switch (field_value.*) {
        .integer => |int_value| if (int_value < 0) null else @as(u64, @intCast(int_value)),
        else => null,
    };
}

fn postJsonAndParse(
    client: *RpcClient,
    allocator: std.mem.Allocator,
    payload: []const u8,
) !std.json.Parsed(std.json.Value) {
    const raw = try client.transport.postJson(allocator, client.endpoint, payload);
    defer raw.deinit(allocator);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, raw.body, .{}) catch {
        return error.RpcParse;
    };
    if (parsed.value != .object) {
        parsed.deinit();
        return error.InvalidRpcResponse;
    }
    return parsed;
}

fn discoverRecentAddressLookupTable(client: *RpcClient, allocator: std.mem.Allocator) !?Pubkey {
    const slot_result = try client.getSlot();
    const latest_slot = switch (slot_result) {
        .ok => |slot| slot,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(allocator);
            std.debug.print("[US-007 live] getSlot rpc_error during ALT discovery: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    };

    var offset: u64 = 0;
    while (offset < MAX_ALT_DISCOVERY_BLOCKS and latest_slot >= offset) : (offset += 1) {
        const slot = latest_slot - offset;
        const payload = try std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":200,\"method\":\"getBlock\",\"params\":[{d},{{\"encoding\":\"json\",\"transactionDetails\":\"full\",\"rewards\":false,\"maxSupportedTransactionVersion\":0}}]}}",
            .{slot},
        );
        defer allocator.free(payload);

        var parsed = postJsonAndParse(client, allocator, payload) catch |err| switch (err) {
            error.RpcTransport, error.RpcParse, error.InvalidRpcResponse => continue,
            else => return err,
        };
        defer parsed.deinit();

        const root_value = &parsed.value;
        if (getJsonField(root_value, "error") != null) continue;

        const result = getJsonField(root_value, "result") orelse continue;
        if (result.* != .object) continue;

        const transactions = getJsonField(result, "transactions") orelse continue;
        if (transactions.* != .array) continue;

        for (transactions.array.items) |tx_item| {
            const tx_value = getJsonField(&tx_item, "transaction") orelse continue;
            const message = getJsonField(tx_value, "message") orelse continue;
            const lookups = getJsonField(message, "addressTableLookups") orelse continue;
            if (lookups.* != .array or lookups.array.items.len == 0) continue;

            for (lookups.array.items) |lookup_item| {
                const account_key = getJsonStringField(&lookup_item, "accountKey") orelse continue;
                return try Pubkey.fromBase58(account_key);
            }
        }
    }

    return null;
}

const DiscoveredTokenOwner = struct {
    token_account: Pubkey,
    owner: Pubkey,
};

fn discoverTokenOwnerForMint(
    client: *RpcClient,
    allocator: std.mem.Allocator,
    mint: Pubkey,
) !?DiscoveredTokenOwner {
    const mint_b58 = try mint.toBase58Alloc(allocator);
    defer allocator.free(mint_b58);

    const payload = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":201,\"method\":\"getTokenLargestAccounts\",\"params\":[\"{s}\",{{\"commitment\":\"confirmed\"}}]}}",
        .{mint_b58},
    );
    defer allocator.free(payload);

    var parsed = postJsonAndParse(client, allocator, payload) catch |err| switch (err) {
        error.RpcTransport, error.RpcParse, error.InvalidRpcResponse => return null,
        else => return err,
    };
    defer parsed.deinit();

    const root_value = &parsed.value;
    if (getJsonField(root_value, "error") != null) return null;

    const result = getJsonField(root_value, "result") orelse return null;
    const value = getJsonField(result, "value") orelse return null;
    if (value.* != .array) return null;

    const token_program = root.interfaces.token.programId();
    for (value.array.items) |item| {
        const token_account_str = getJsonStringField(&item, "address") orelse continue;
        const token_account = Pubkey.fromBase58(token_account_str) catch continue;

        const account_result = try client.getAccountInfo(token_account);
        switch (account_result) {
            .ok => |maybe_account| {
                if (maybe_account == null) continue;

                var account_info = maybe_account.?;
                defer account_info.deinit(allocator);

                if (!account_info.owner.eql(token_program)) continue;
                if (account_info.data.len < (Pubkey.LENGTH * 2)) continue;

                const discovered_mint = try Pubkey.fromSlice(account_info.data[0..Pubkey.LENGTH]);
                if (!discovered_mint.eql(mint)) continue;

                const owner = try Pubkey.fromSlice(account_info.data[Pubkey.LENGTH .. Pubkey.LENGTH * 2]);
                return .{
                    .token_account = token_account,
                    .owner = owner,
                };
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(allocator);
                std.debug.print(
                    "[US-008 live] getAccountInfo rpc_error during owner discovery for {s}: {s}\n",
                    .{ token_account_str, rpc_err.message },
                );
            },
        }
    }

    return null;
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
            .ok => |statuses_val| {
                var statuses = statuses_val;
                defer statuses.deinit(allocator);

                if (statuses.items.len == 0 or statuses.items[0] == null) {
                    std.debug.print("[{s}] confirm poll {d}: not found yet\n", .{ log_prefix, confirm_attempts });
                    continue;
                }

                const status = statuses.items[0].?;
                if (status.slot == 0) return error.InvalidRpcResponse;
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
        .ok => |statuses_val| {
            var statuses = statuses_val;
            defer statuses.deinit(gpa);
            try std.testing.expectEqual(@as(usize, 1), statuses.items.len);
            try std.testing.expect(statuses.items[0] != null);
            const status = statuses.items[0].?;
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

test "US-002 live: getSignaturesForAddress returns history for an active address" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-002 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-002 live] endpoint: {s}\n", .{endpoint});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const result = try client.getSignaturesForAddressWithOptions(SYSTEM_PROGRAM, .{
        .limit = 2,
    });
    switch (result) {
        .ok => |history_result| {
            var history = history_result;
            defer history.deinit(gpa);

            try std.testing.expect(history.items.len > 0);
            try std.testing.expect(history.items[0].slot > 0);
            try std.testing.expect(history.items[0].raw_json != null);

            const first_sig_b58 = try history.items[0].signature.toBase58Alloc(gpa);
            defer gpa.free(first_sig_b58);
            std.debug.print(
                "[US-002 live] getSignaturesForAddress .ok — count={d}, first_sig={s}, first_slot={d}\n",
                .{ history.items.len, first_sig_b58, history.items[0].slot },
            );
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-002 live] getSignaturesForAddress rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }
}

test "US-003 live: getSignatureStatuses returns status for a recent signature" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-003 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-003 live] endpoint: {s}\n", .{endpoint});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const history_result = try client.getSignaturesForAddressWithOptions(SYSTEM_PROGRAM, .{
        .limit = 1,
    });
    const signature = switch (history_result) {
        .ok => |history_result_ok| blk: {
            var history = history_result_ok;
            defer history.deinit(gpa);

            try std.testing.expect(history.items.len > 0);
            break :blk history.items[0].signature;
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-003 live] getSignaturesForAddress rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    };

    const sig_b58 = try signature.toBase58Alloc(gpa);
    defer gpa.free(sig_b58);

    const statuses_result = try client.getSignatureStatusesWithOptions(&[_]root.core.Signature{signature}, .{
        .search_transaction_history = true,
    });
    switch (statuses_result) {
        .ok => |statuses_result_ok| {
            var statuses = statuses_result_ok;
            defer statuses.deinit(gpa);

            try std.testing.expectEqual(@as(usize, 1), statuses.items.len);
            try std.testing.expect(statuses.items[0] != null);

            const status = statuses.items[0].?;
            try std.testing.expect(status.slot > 0);
            try std.testing.expect(status.confirmation_status != null);

            std.debug.print(
                "[US-003 live] getSignatureStatuses .ok — signature={s}, slot={d}, confirmationStatus={s}\n",
                .{ sig_b58, status.slot, status.confirmation_status.? },
            );
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-003 live] getSignatureStatuses rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }
}

test "US-004 live: getSlot and getEpochInfo return positive values and structure" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-004 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-004 live] endpoint: {s}\n", .{endpoint});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const slot_result = try client.getSlotWithOptions(.{ .commitment = .finalized });
    switch (slot_result) {
        .ok => |slot| {
            try std.testing.expect(slot > 0);
            std.debug.print("[US-004 live] getSlot .ok — slot={d}\n", .{slot});
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-004 live] getSlot rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }

    const epoch_info_result = try client.getEpochInfoWithOptions(.{ .commitment = .confirmed });
    switch (epoch_info_result) {
        .ok => |epoch_info| {
            var owned = epoch_info;
            defer owned.deinit(gpa);

            try std.testing.expect(owned.absolute_slot > 0);
            try std.testing.expect(owned.epoch > 0);
            try std.testing.expect(owned.slots_in_epoch > 0);
            try std.testing.expect(owned.block_height != null);
            try std.testing.expect(owned.block_height.? > 0);
            try std.testing.expect(owned.transaction_count != null);
            try std.testing.expect(owned.transaction_count.? > 0);
            try std.testing.expect(owned.raw_json != null);

            std.debug.print(
                "[US-004 live] getEpochInfo .ok — epoch={d}, slotIndex={d}, slotsInEpoch={d}, absoluteSlot={d}, blockHeight={d}, transactionCount={d}\n",
                .{
                    owned.epoch,
                    owned.slot_index,
                    owned.slots_in_epoch,
                    owned.absolute_slot,
                    owned.block_height.?,
                    owned.transaction_count.?,
                },
            );
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-004 live] getEpochInfo rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }
}

test "US-005 live: getMinimumBalanceForRentExemption returns expected lamports for common lengths" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-005 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-005 live] endpoint: {s}\n", .{endpoint});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const cases = [_]struct {
        data_len: usize,
        expected_lamports: u64,
    }{
        .{ .data_len = 0, .expected_lamports = 890_880 },
        .{ .data_len = 80, .expected_lamports = 1_447_680 },
        .{ .data_len = 128, .expected_lamports = 1_781_760 },
    };

    for (cases) |case| {
        const result = try client.getMinimumBalanceForRentExemption(case.data_len);
        switch (result) {
            .ok => |lamports| {
                try std.testing.expectEqual(case.expected_lamports, lamports);
                std.debug.print(
                    "[US-005 live] getMinimumBalanceForRentExemption({d}) .ok — lamports={d}\n",
                    .{ case.data_len, lamports },
                );
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(gpa);
                std.debug.print(
                    "[US-005 live] getMinimumBalanceForRentExemption({d}) rpc_error: {s}\n",
                    .{ case.data_len, rpc_err.message },
                );
                return error.DevnetRpcError;
            },
        }
    }
}

test "US-006 live: requestAirdrop returns a signature and increases balance" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-006 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-006 live] endpoint: {s}\n", .{endpoint});

    const AIRDROP_SEED = [_]u8{ 163, 94, 11, 207, 58, 149, 222, 17, 241, 76, 132, 9, 188, 45, 201, 114, 6, 173, 39, 250, 97, 140, 28, 219, 84, 161, 33, 246, 72, 119, 154, 5 };
    const recipient = try Keypair.fromSeed(AIRDROP_SEED);
    const recipient_b58 = try recipient.pubkey().toBase58Alloc(gpa);
    defer gpa.free(recipient_b58);

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const before_result = try client.getBalance(recipient.pubkey());
    const before_balance = switch (before_result) {
        .ok => |balance| balance,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-006 live] initial getBalance rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    };
    std.debug.print("[US-006 live] recipient: {s}, before_balance={d}\n", .{ recipient_b58, before_balance });

    const lamports: u64 = 1_000_000;
    const airdrop_result = try client.requestAirdrop(recipient.pubkey(), lamports);
    switch (airdrop_result) {
        .ok => |airdrop| {
            const sig_b58 = try airdrop.signature.toBase58Alloc(gpa);
            defer gpa.free(sig_b58);
            try std.testing.expect(sig_b58.len > 0);
            std.debug.print("[US-006 live] requestAirdrop .ok — sig={s}, lamports={d}\n", .{ sig_b58, lamports });
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            if (isRateLimitedRpcError(rpc_err.code, rpc_err.message)) {
                std.debug.print("[US-006 live] skip: requestAirdrop rate-limited: {s}\n", .{rpc_err.message});
                return;
            }
            std.debug.print("[US-006 live] requestAirdrop rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }

    var after_balance = before_balance;
    var attempts: u32 = 0;
    while (attempts < MAX_BALANCE_POLLS) : (attempts += 1) {
        const balance_result = try client.getBalance(recipient.pubkey());
        switch (balance_result) {
            .ok => |balance| {
                after_balance = balance;
                if (after_balance > before_balance) break;
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(gpa);
                std.debug.print("[US-006 live] balance poll {d}: rpc_error: {s}\n", .{ attempts, rpc_err.message });
            },
        }
    }

    try std.testing.expect(after_balance > before_balance);
    std.debug.print(
        "[US-006 live] balance increased: before={d}, after={d}, delta={d}\n",
        .{ before_balance, after_balance, after_balance - before_balance },
    );
}

test "US-007 live: getAddressLookupTable returns account state for a recent devnet ALT" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-007 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-007 live] endpoint: {s}\n", .{endpoint});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const table_address = (try discoverRecentAddressLookupTable(&client, gpa)) orelse {
        std.debug.print("[US-007 live] skip: no recent address lookup table activity found on Devnet\n", .{});
        return;
    };
    const table_b58 = try table_address.toBase58Alloc(gpa);
    defer gpa.free(table_b58);

    std.debug.print("[US-007 live] discovered ALT: {s}\n", .{table_b58});

    const result = try client.getAddressLookupTable(table_address);
    switch (result) {
        .ok => |table_result| {
            var owned = table_result;
            defer owned.deinit(gpa);
            try std.testing.expect(owned.value != null);

            const account = owned.value.?;
            try std.testing.expect(account.key.eql(table_address));
            try std.testing.expect(account.state.addresses.len > 0);
            try std.testing.expect(account.state.raw_json != null);

            std.debug.print(
                "[US-007 live] getAddressLookupTable .ok — key={s}, addresses={d}, lastExtendedSlot={d}\n",
                .{ table_b58, account.state.addresses.len, account.state.last_extended_slot },
            );
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-007 live] getAddressLookupTable rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }
}

test "US-008 live: getTokenAccountsByOwner returns token accounts for a discovered holder" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-008 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-008 live] endpoint: {s}\n", .{endpoint});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const wrapped_sol_mint = try Pubkey.fromBase58(WRAPPED_SOL_MINT_STR);
    const discovered = (try discoverTokenOwnerForMint(&client, gpa, wrapped_sol_mint)) orelse {
        std.debug.print("[US-008 live] skip: unable to discover a Devnet owner for the wrapped SOL mint\n", .{});
        return;
    };

    const owner_b58 = try discovered.owner.toBase58Alloc(gpa);
    defer gpa.free(owner_b58);
    const token_account_b58 = try discovered.token_account.toBase58Alloc(gpa);
    defer gpa.free(token_account_b58);

    const token_program = root.interfaces.token.programId();

    const program_result = try client.getTokenAccountsByOwner(discovered.owner, token_program);
    switch (program_result) {
        .ok => |token_accounts_result| {
            var token_accounts = token_accounts_result;
            defer token_accounts.deinit(gpa);

            try std.testing.expect(token_accounts.items.len > 0);

            var found_discovered_account = false;
            for (token_accounts.items) |item| {
                if (item.pubkey.eql(discovered.token_account)) {
                    found_discovered_account = true;
                    try std.testing.expect(item.account_info.owner.eql(token_program));
                    try std.testing.expect(item.account_info.data.len >= (Pubkey.LENGTH * 2));
                    try std.testing.expect(item.data_encoding != null);
                    try std.testing.expectEqualStrings("base64", item.data_encoding.?);
                }
            }

            try std.testing.expect(found_discovered_account);
            std.debug.print(
                "[US-008 live] programId filter .ok — owner={s}, count={d}, sample_account={s}\n",
                .{ owner_b58, token_accounts.items.len, token_account_b58 },
            );
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-008 live] getTokenAccountsByOwner(programId) rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }

    const mint_result = try client.getTokenAccountsByOwnerWithOptions(discovered.owner, .{
        .filter = .{ .mint = wrapped_sol_mint },
        .encoding = .base64,
    });
    switch (mint_result) {
        .ok => |token_accounts_result| {
            var token_accounts = token_accounts_result;
            defer token_accounts.deinit(gpa);

            try std.testing.expect(token_accounts.items.len > 0);

            var found_discovered_account = false;
            for (token_accounts.items) |item| {
                try std.testing.expect(item.account_info.owner.eql(token_program));
                try std.testing.expect(item.account_info.data.len >= (Pubkey.LENGTH * 2));
                try std.testing.expect(item.data_encoding != null);
                try std.testing.expectEqualStrings("base64", item.data_encoding.?);

                const item_mint = try Pubkey.fromSlice(item.account_info.data[0..Pubkey.LENGTH]);
                try std.testing.expect(item_mint.eql(wrapped_sol_mint));

                if (item.pubkey.eql(discovered.token_account)) {
                    found_discovered_account = true;
                }
            }

            try std.testing.expect(found_discovered_account);
            std.debug.print(
                "[US-008 live] mint filter .ok — owner={s}, mint={s}, count={d}\n",
                .{ owner_b58, WRAPPED_SOL_MINT_STR, token_accounts.items.len },
            );
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-008 live] getTokenAccountsByOwner(mint) rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }
}

test "US-009 live: getTokenAccountBalance and getTokenSupply return typed token amounts" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping US-009 live devnet E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[US-009 live] endpoint: {s}\n", .{endpoint});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const wrapped_sol_mint = try Pubkey.fromBase58(WRAPPED_SOL_MINT_STR);
    const discovered = (try discoverTokenOwnerForMint(&client, gpa, wrapped_sol_mint)) orelse {
        std.debug.print("[US-009 live] skip: unable to discover a Devnet token account for the wrapped SOL mint\n", .{});
        return;
    };

    const token_account_b58 = try discovered.token_account.toBase58Alloc(gpa);
    defer gpa.free(token_account_b58);

    const balance_result = try client.getTokenAccountBalance(discovered.token_account);
    switch (balance_result) {
        .ok => |token_balance| {
            var owned = token_balance;
            defer owned.deinit(gpa);

            try std.testing.expect(owned.amount > 0);
            try std.testing.expectEqual(@as(u8, 9), owned.decimals);
            try std.testing.expect(owned.ui_amount_string.len > 0);
            try std.testing.expect(owned.raw_json != null);

            std.debug.print(
                "[US-009 live] getTokenAccountBalance .ok — account={s}, amount={d}, decimals={d}, uiAmountString={s}\n",
                .{ token_account_b58, owned.amount, owned.decimals, owned.ui_amount_string },
            );
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-009 live] getTokenAccountBalance rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }

    const supply_result = try client.getTokenSupply(wrapped_sol_mint);
    switch (supply_result) {
        .ok => |token_supply| {
            var owned = token_supply;
            defer owned.deinit(gpa);

            try std.testing.expectEqual(@as(u8, 9), owned.decimals);
            try std.testing.expect(owned.ui_amount_string.len > 0);
            try std.testing.expect(owned.raw_json != null);

            std.debug.print(
                "[US-009 live] getTokenSupply .ok — mint={s}, amount={d}, decimals={d}, uiAmountString={s}\n",
                .{ WRAPPED_SOL_MINT_STR, owned.amount, owned.decimals, owned.ui_amount_string },
            );
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-009 live] getTokenSupply rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    }
}

const DevnetLiveEndpoints = struct {
    rpc_endpoint: []u8,
    ws_endpoint: []u8,

    fn deinit(self: *DevnetLiveEndpoints, allocator: std.mem.Allocator) void {
        allocator.free(self.rpc_endpoint);
        allocator.free(self.ws_endpoint);
    }
};

fn resolveDevnetLiveEndpoints(allocator: std.mem.Allocator, label: []const u8) !?DevnetLiveEndpoints {
    const rpc_endpoint = std.process.Environ.getAlloc(std.testing.environ, allocator, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[{s}] skip: SOLANA_RPC_URL not set\n", .{label});
            return null;
        },
        else => return err,
    };
    errdefer allocator.free(rpc_endpoint);

    const ws_endpoint = std.process.Environ.getAlloc(std.testing.environ, allocator, "SOLANA_WS_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[{s}] skip: SOLANA_WS_URL not set\n", .{label});
            allocator.free(rpc_endpoint);
            return null;
        },
        else => return err,
    };
    errdefer allocator.free(ws_endpoint);

    if (!std.mem.startsWith(u8, ws_endpoint, "ws://")) {
        std.debug.print(
            "[{s}] skip: SOLANA_WS_URL must use ws:// because the current websocket transport does not support TLS\n",
            .{label},
        );
        allocator.free(rpc_endpoint);
        allocator.free(ws_endpoint);
        return null;
    }

    return .{
        .rpc_endpoint = rpc_endpoint,
        .ws_endpoint = ws_endpoint,
    };
}

test "US-012 live devnet: websocket reconnect resumes slot notifications" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var endpoints = (try resolveDevnetLiveEndpoints(gpa, "US-012 live")) orelse return;
    defer endpoints.deinit(gpa);

    std.debug.print("[US-012 live] rpc endpoint: {s}\n", .{endpoints.rpc_endpoint});
    std.debug.print("[US-012 live] ws endpoint: {s}\n", .{endpoints.ws_endpoint});

    var client = try root.rpc.WsRpcClient.connect(gpa, io, endpoints.ws_endpoint);
    defer client.deinit();
    client.setReconnectConfig(.{
        .max_retries = 3,
        .base_delay_ms = 100,
        .max_delay_ms = 1_000,
    });

    const subscription_id = try client.slotSubscribe();
    try std.testing.expect(subscription_id > 0);

    var first = try client.readSlotNotification();
    defer first.deinit(gpa);

    try std.testing.expect(first.slot > 0);
    std.debug.print(
        "[US-012 live] first slot notification — subscription={d}, slot={d}, parent={d}, root={d}\n",
        .{ first.subscription_id, first.slot, first.parent, first.root },
    );

    try client.ws.sendClose();

    var recovered = try client.readSlotNotification();
    defer recovered.deinit(gpa);

    try std.testing.expect(recovered.slot > 0);
    try std.testing.expect(recovered.slot >= first.slot);
    try std.testing.expectEqual(@as(usize, 1), client.subscriptionCount());

    const stats = client.snapshot();
    try std.testing.expect(stats.reconnect_attempts_total >= 1);
    try std.testing.expect(stats.last_reconnect_unix_ms != null);

    std.debug.print(
        "[US-012 live] recovered slot notification — subscription={d}, slot={d}, reconnects={d}\n",
        .{ recovered.subscription_id, recovered.slot, stats.reconnect_attempts_total },
    );
}

test "US-016 live: websocket accountSubscribe and signatureSubscribe observe a sent transaction" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var endpoints = (try resolveDevnetLiveEndpoints(gpa, "US-016 live")) orelse return;
    defer endpoints.deinit(gpa);

    std.debug.print("[US-016 live] rpc endpoint: {s}\n", .{endpoints.rpc_endpoint});
    std.debug.print("[US-016 live] ws endpoint: {s}\n", .{endpoints.ws_endpoint});

    const WS_SEED = [_]u8{ 91, 24, 167, 8, 53, 219, 112, 64, 15, 231, 4, 178, 89, 143, 34, 201, 76, 155, 18, 240, 61, 132, 17, 222, 105, 40, 193, 7, 148, 58, 211, 99 };
    const payer = try Keypair.fromSeed(WS_SEED);
    const payer_b58 = try payer.pubkey().toBase58Alloc(gpa);
    defer gpa.free(payer_b58);

    var rpc_client = try RpcClient.init(gpa, io, endpoints.rpc_endpoint);
    defer rpc_client.deinit();

    requestAirdrop(&rpc_client, payer_b58, LIVE_AIRDROP_LAMPORTS) catch |err| {
        std.debug.print("[US-016 live] airdrop failed (may be rate-limited): {}\n", .{err});
    };

    var before_balance: u64 = 0;
    var balance_attempts: u32 = 0;
    while (balance_attempts < MAX_BALANCE_POLLS) : (balance_attempts += 1) {
        const balance_result = try rpc_client.getBalance(payer.pubkey());
        switch (balance_result) {
            .ok => |balance| {
                before_balance = balance;
                if (before_balance > 0) break;
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(gpa);
                std.debug.print("[US-016 live] balance poll {d}: rpc_error: {s}\n", .{ balance_attempts, rpc_err.message });
            },
        }
    }

    std.debug.print("[US-016 live] payer={s}, funded_balance={d}\n", .{ payer_b58, before_balance });
    if (before_balance == 0) {
        std.debug.print("[US-016 live] skip: payer has no funds (airdrop may be rate-limited)\n", .{});
        return;
    }

    const blockhash_result = try rpc_client.getLatestBlockhash();
    const blockhash = switch (blockhash_result) {
        .ok => |latest| latest.blockhash,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-016 live] getLatestBlockhash rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetRpcError;
        },
    };

    var tx = try buildSignedSelfTransferTx(gpa, payer, blockhash, LIVE_SEND_LAMPORTS);
    defer tx.deinit();

    const expected_signature = tx.signatures[0];
    const expected_signature_b58 = try expected_signature.toBase58Alloc(gpa);
    defer gpa.free(expected_signature_b58);

    var ws_client = try root.rpc.WsRpcClient.connect(gpa, io, endpoints.ws_endpoint);
    defer ws_client.deinit();

    const account_subscription_id = try ws_client.accountSubscribe(payer_b58);
    const signature_subscription_id = try ws_client.signatureSubscribe(expected_signature_b58);
    std.debug.print(
        "[US-016 live] subscribed — account_sub={d}, signature_sub={d}, signature={s}\n",
        .{ account_subscription_id, signature_subscription_id, expected_signature_b58 },
    );

    const send_result = try rpc_client.sendTransaction(tx);
    switch (send_result) {
        .ok => |send| {
            try std.testing.expectEqualSlices(u8, &expected_signature.bytes, &send.signature.bytes);
            std.debug.print("[US-016 live] sendTransaction .ok — sig: {s}\n", .{expected_signature_b58});
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[US-016 live] sendTransaction rpc_error: {s}\n", .{rpc_err.message});
            return error.DevnetSendFailed;
        },
    }

    var saw_account_notification = false;
    var saw_signature_notification = false;
    var notification_reads: u32 = 0;

    while (!(saw_account_notification and saw_signature_notification)) : (notification_reads += 1) {
        if (notification_reads >= 8) return error.InvalidSubscriptionResponse;

        var notification = try ws_client.readNotification();
        defer notification.deinit();

        if (std.mem.eql(u8, notification.method, "accountNotification")) {
            try std.testing.expectEqual(account_subscription_id, notification.subscription_id);

            const context = getJsonField(&notification.result, "context") orelse return error.InvalidSubscriptionResponse;
            const slot = getJsonU64Field(context, "slot") orelse return error.InvalidSubscriptionResponse;
            const account = getJsonField(&notification.result, "value") orelse return error.InvalidSubscriptionResponse;
            const lamports = getJsonU64Field(account, "lamports") orelse return error.InvalidSubscriptionResponse;
            const owner = getJsonStringField(account, "owner") orelse return error.InvalidSubscriptionResponse;

            try std.testing.expect(slot > 0);
            try std.testing.expect(lamports < before_balance);
            try std.testing.expectEqualStrings("11111111111111111111111111111111", owner);

            saw_account_notification = true;
            std.debug.print(
                "[US-016 live] accountNotification — subscription={d}, slot={d}, before={d}, after={d}\n",
                .{ notification.subscription_id, slot, before_balance, lamports },
            );
            continue;
        }

        if (std.mem.eql(u8, notification.method, "signatureNotification")) {
            try std.testing.expectEqual(signature_subscription_id, notification.subscription_id);

            const context = getJsonField(&notification.result, "context") orelse return error.InvalidSubscriptionResponse;
            const slot = getJsonU64Field(context, "slot") orelse return error.InvalidSubscriptionResponse;
            const signature_value = getJsonField(&notification.result, "value") orelse return error.InvalidSubscriptionResponse;
            const err_value = getJsonField(signature_value, "err") orelse return error.InvalidSubscriptionResponse;

            try std.testing.expect(slot > 0);
            try std.testing.expect(err_value.* == .null);

            saw_signature_notification = true;
            std.debug.print(
                "[US-016 live] signatureNotification — subscription={d}, slot={d}, err=null\n",
                .{ notification.subscription_id, slot },
            );
            continue;
        }

        std.debug.print(
            "[US-016 live] ignoring interleaved {s} notification for subscription={d}\n",
            .{ notification.method, notification.subscription_id },
        );
    }

    try ws_client.accountUnsubscribe(account_subscription_id);
    try ws_client.signatureUnsubscribe(signature_subscription_id);
    std.debug.print("[US-016 live] websocket account/signature subscriptions completed successfully\n", .{});
}
