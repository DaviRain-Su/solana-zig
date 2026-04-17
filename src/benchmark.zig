// Benchmark Harness
// Spec: docs/13-benchmark-baseline-spec.md
//
// Measures: Pubkey base58 encode/decode, shortvec encode/decode,
//           legacy/v0 message serialize/deserialize,
//           versioned transaction serialize/deserialize,
//           sign/verify operations,
//           RPC response parsing for extended methods,
//           WebSocket subscribe serialization and notification parsing.
//
// Build & run: zig build bench

const builtin = @import("builtin");
const std = @import("std");
const solana = @import("solana/mod.zig");
const transport_mod = @import("solana/rpc/transport.zig");
const ws_rpc = solana.rpc.ws_client;

const shortvec = solana.core.shortvec;
const Pubkey = solana.core.Pubkey;
const Hash = solana.core.Hash;
const Keypair = solana.core.Keypair;
const Signature = solana.core.Signature;
const Instruction = solana.tx.Instruction;
const AccountMeta = solana.tx.AccountMeta;
const Message = solana.tx.Message;
const VersionedTransaction = solana.tx.VersionedTransaction;
const AddressLookupTable = solana.tx.AddressLookupTable;
const LookupEntry = solana.tx.address_lookup_table.LookupEntry;
const RpcClient = solana.rpc.RpcClient;

// --- Configuration ---

const WARMUP_ITERS: usize = 100;
const BENCH_ITERS: usize = 10_000;
const RPC_PARSE_WARMUP_ITERS: usize = 100;
const RPC_PARSE_BENCH_ITERS: usize = 10_000;
const RPC_ACCOUNT_DATA_BYTES: usize = 8 * 1024;
const RPC_TRANSACTION_LOG_COUNT: usize = 24;
const RPC_TRANSACTION_INNER_INSTRUCTION_COUNT: usize = 8;
const RPC_SIGNATURE_STATUSES_BATCH_SIZE: usize = 64;
const WS_CODEC_WARMUP_ITERS: usize = 50;
const WS_CODEC_BENCH_ITERS: usize = 2_500;
const WS_NOTIFICATION_DATA_BYTES: usize = 4 * 1024;
const WS_NOTIFICATION_LOG_COUNT: usize = 12;

const PROFILE_SMALL = "small";
const PROFILE_PHASE1_REALISTIC = "phase1-realistic";
const PROFILE_RPC_LARGE_DATA = "rpc-large-data";
const PROFILE_RPC_COMPLEX_META = "rpc-complex-meta";
const PROFILE_RPC_BATCH = "rpc-batch";
const PROFILE_WS_SUBSCRIBE = "ws-subscribe";
const PROFILE_WS_ACCOUNT_NOTIFICATION = "ws-account-notification";
const PROFILE_WS_PROGRAM_NOTIFICATION = "ws-program-notification";
const PROFILE_WS_LOGS_NOTIFICATION = "ws-logs-notification";

// --- Timing ---

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts) != 0) unreachable;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

// --- Input Fixtures ---

const PUBKEY_BYTES = [_]u8{0x0A} ** 32;
const HASH_BYTES = [_]u8{0x05} ** 32;
const SEED_BYTES = [_]u8{0x08} ** 32;

// --- Message / Transaction Helpers ---

fn buildLegacyMessage(allocator: std.mem.Allocator, payer: Keypair) !Message {
    const receiver = Pubkey.init([_]u8{0x07} ** 32);
    const program = Pubkey.init([_]u8{0x06} ** 32);
    const blockhash = Hash.init(HASH_BYTES);

    const accounts = [_]AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const payload = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const ixs = [_]Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    return try Message.compileLegacy(allocator, payer.pubkey(), &ixs, blockhash);
}

fn buildV0Message(allocator: std.mem.Allocator, payer: Keypair) !Message {
    const receiver = Pubkey.init([_]u8{0x07} ** 32);
    const program = Pubkey.init([_]u8{0x06} ** 32);
    const lookup_key1 = Pubkey.init([_]u8{0x0B} ** 32);
    const lookup_account = Pubkey.init([_]u8{0x0C} ** 32);
    const blockhash = Hash.init(HASH_BYTES);

    const accounts = [_]AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
        .{ .pubkey = lookup_account, .is_signer = false, .is_writable = false },
    };
    const payload = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const ixs = [_]Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    const writable_entries = [_]LookupEntry{
        .{ .index = 0, .pubkey = receiver },
    };
    const readonly_entries = [_]LookupEntry{
        .{ .index = 1, .pubkey = lookup_account },
    };
    const lookup_tables = [_]AddressLookupTable{
        .{
            .account_key = lookup_key1,
            .writable = &writable_entries,
            .readonly = &readonly_entries,
        },
    };

    return try Message.compileV0(allocator, payer.pubkey(), &ixs, blockhash, &lookup_tables);
}

const StaticResponseTransport = struct {
    response_body: []const u8,
    response_status: std.http.Status = .ok,

    fn postJson(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) transport_mod.PostJsonError!transport_mod.PostJsonResponse {
        _ = url;
        _ = payload;

        const self: *StaticResponseTransport = @ptrCast(@alignCast(ctx));
        return .{
            .status = self.response_status,
            .body = try allocator.dupe(u8, self.response_body),
        };
    }
};

fn staticTransportDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    _ = ctx;
    _ = allocator;
}

fn encodeBase64(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const out = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(out, bytes);
    return out;
}

fn buildLargeAccountInfoResponse(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, RPC_ACCOUNT_DATA_BYTES);
    defer allocator.free(bytes);

    for (bytes, 0..) |*byte, i| {
        byte.* = @intCast((i * 31 + 7) % 251);
    }

    const encoded = try encodeBase64(allocator, bytes);
    defer allocator.free(encoded);

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"lamports\":424242,\"owner\":\"11111111111111111111111111111111\",\"executable\":false,\"rentEpoch\":18446744073709551615,\"data\":[\"");
    try out.writer.writeAll(encoded);
    try out.writer.writeAll("\",\"base64\"]}}}");

    return try allocator.dupe(u8, out.written());
}

fn buildComplexTransactionResponse(allocator: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"slot\":987654321,\"blockTime\":1712345678,\"meta\":{");
    try out.writer.writeAll("\"fee\":5000,");
    try out.writer.writeAll("\"err\":{\"InstructionError\":[2,{\"Custom\":42}]},");
    try out.writer.writeAll("\"logMessages\":[");
    for (0..RPC_TRANSACTION_LOG_COUNT) |i| {
        if (i > 0) try out.writer.writeByte(',');
        try out.writer.print("\"Program benchmark log {d}: processed account {d}\"", .{ i, i % 7 });
    }
    try out.writer.writeAll("],");
    try out.writer.writeAll("\"preBalances\":[");
    for (0..16) |i| {
        if (i > 0) try out.writer.writeByte(',');
        try out.writer.print("{d}", .{1_000_000 + (i * 10_000)});
    }
    try out.writer.writeAll("],\"postBalances\":[");
    for (0..16) |i| {
        if (i > 0) try out.writer.writeByte(',');
        try out.writer.print("{d}", .{995_000 + (i * 9_500)});
    }
    try out.writer.writeAll("],\"innerInstructions\":[");
    for (0..RPC_TRANSACTION_INNER_INSTRUCTION_COUNT) |i| {
        if (i > 0) try out.writer.writeByte(',');
        try out.writer.print(
            "{{\"index\":{d},\"instructions\":[{{\"programIdIndex\":1,\"accounts\":[0,1,2],\"data\":\"AQIDBA==\"}},{{\"programIdIndex\":2,\"accounts\":[2,3],\"data\":\"BQYHCA==\"}}]}}",
            .{i},
        );
    }
    try out.writer.writeAll("],");
    try out.writer.writeAll("\"loadedAddresses\":{\"writable\":[\"11111111111111111111111111111111\",\"11111111111111111111111111111111\"],\"readonly\":[\"11111111111111111111111111111111\"]},");
    try out.writer.writeAll("\"returnData\":{\"programId\":\"11111111111111111111111111111111\",\"data\":[\"AQIDBAUGBwg=\",\"base64\"]},");
    try out.writer.writeAll("\"rewards\":[{\"pubkey\":\"11111111111111111111111111111111\",\"lamports\":5,\"postBalance\":10,\"rewardType\":\"fee\",\"commission\":null}],");
    try out.writer.writeAll("\"computeUnitsConsumed\":456789,");
    try out.writer.writeAll("\"status\":{\"Err\":{\"InstructionError\":[1,\"Custom\"]}}");
    try out.writer.writeAll("},\"transaction\":{\"message\":{\"accountKeys\":[\"11111111111111111111111111111111\",\"11111111111111111111111111111111\"],\"instructions\":[]}}}}");

    return try allocator.dupe(u8, out.written());
}

fn buildBenchmarkSignatures(allocator: std.mem.Allocator, count: usize) ![]Signature {
    const signatures = try allocator.alloc(Signature, count);
    errdefer allocator.free(signatures);

    for (signatures, 0..) |*signature, i| {
        var bytes: [Signature.LENGTH]u8 = undefined;
        for (&bytes, 0..) |*byte, j| {
            byte.* = @intCast((i * 17 + j * 13 + 9) % 251);
        }
        signature.* = Signature.init(bytes);
    }

    return signatures;
}

fn buildSignatureStatusesResponse(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":424242},\"value\":[");
    for (0..count) |i| {
        if (i > 0) try out.writer.writeByte(',');
        if (i % 17 == 0) {
            try out.writer.writeAll("null");
            continue;
        }

        const confirmation_status = switch (i % 3) {
            0 => "processed",
            1 => "confirmed",
            else => "finalized",
        };

        try out.writer.print("{{\"slot\":{d},\"confirmations\":", .{900_000 + i});
        if (i % 3 == 2) {
            try out.writer.writeAll("null");
        } else {
            try out.writer.print("{d}", .{64 - (i % 16)});
        }
        try out.writer.writeAll(",\"err\":");
        if (i % 11 == 0) {
            try out.writer.print("{{\"InstructionError\":[{d},{{\"Custom\":{d}}}]}}", .{ i % 4, 600 + i });
        } else {
            try out.writer.writeAll("null");
        }
        try out.writer.print(",\"confirmationStatus\":\"{s}\"}}", .{confirmation_status});
    }
    try out.writer.writeAll("]}}");

    return try allocator.dupe(u8, out.written());
}

fn buildWsAccountNotificationMessage(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, WS_NOTIFICATION_DATA_BYTES);
    defer allocator.free(bytes);

    for (bytes, 0..) |*byte, i| {
        byte.* = @intCast((i * 19 + 5) % 251);
    }

    const encoded = try encodeBase64(allocator, bytes);
    defer allocator.free(encoded);

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"accountNotification\",\"params\":{\"result\":{\"context\":{\"slot\":42424242},\"value\":{\"lamports\":123456789,\"owner\":\"11111111111111111111111111111111\",\"executable\":false,\"rentEpoch\":18446744073709551615,\"data\":[\"");
    try out.writer.writeAll(encoded);
    try out.writer.writeAll("\",\"base64\"]}},\"subscription\":91}}");

    return try allocator.dupe(u8, out.written());
}

fn buildWsProgramNotificationMessage(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, WS_NOTIFICATION_DATA_BYTES);
    defer allocator.free(bytes);

    for (bytes, 0..) |*byte, i| {
        byte.* = @intCast((i * 23 + 11) % 251);
    }

    const encoded = try encodeBase64(allocator, bytes);
    defer allocator.free(encoded);

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"programNotification\",\"params\":{\"result\":{\"context\":{\"slot\":42424243},\"value\":{\"pubkey\":\"ProgramDerived1111111111111111111111111111\",\"account\":{\"lamports\":987654321,\"owner\":\"BPFLoaderUpgradeab1e11111111111111111111111\",\"executable\":false,\"rentEpoch\":23,\"data\":[\"");
    try out.writer.writeAll(encoded);
    try out.writer.writeAll("\",\"base64\"]}}},\"subscription\":92}}");

    return try allocator.dupe(u8, out.written());
}

fn buildWsLogsNotificationMessage(allocator: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"logsNotification\",\"params\":{\"result\":{\"context\":{\"slot\":42424244},\"value\":{\"signature\":\"5h6xBEauJ3PK6SWtSj71G1tQJZD2JQQn4tR6N9Vf6hLJx6X8M9cL6N9WQ2V4NqRj5L1m7s2V4Q8Vf1aB6P7\",\"err\":{\"InstructionError\":[1,{\"Custom\":17}]},\"logs\":[");
    for (0..WS_NOTIFICATION_LOG_COUNT) |i| {
        if (i > 0) try out.writer.writeByte(',');
        try out.writer.print("\"Program benchmark log {d}: processed account {d} and emitted compute trace\"", .{ i, i % 5 });
    }
    try out.writer.writeAll("]}},\"subscription\":93}}");

    return try allocator.dupe(u8, out.written());
}

fn runGetAccountInfoParseBenchmark(
    allocator: std.mem.Allocator,
    response_body: []const u8,
    pubkey: Pubkey,
) !void {
    var mock_transport: StaticResponseTransport = .{ .response_body = response_body };
    const transport = transport_mod.Transport.init(&mock_transport, StaticResponseTransport.postJson, staticTransportDeinit);
    var client = try RpcClient.initWithTransport(allocator, "http://benchmark.local", transport);
    defer client.deinit();

    var total_decoded_bytes: usize = 0;

    for (0..RPC_PARSE_WARMUP_ITERS) |_| {
        const result = try client.getAccountInfo(pubkey);
        switch (result) {
            .ok => |maybe_info| {
                const info_val = maybe_info orelse return error.ExpectedAccountInfo;
                var info = info_val;
                total_decoded_bytes += info.data.len;
                info.deinit(allocator);
            },
            .rpc_error => return error.UnexpectedRpcError,
        }
    }

    const start = nowNs();
    for (0..RPC_PARSE_BENCH_ITERS) |_| {
        const result = try client.getAccountInfo(pubkey);
        switch (result) {
            .ok => |maybe_info| {
                const info_val = maybe_info orelse return error.ExpectedAccountInfo;
                var info = info_val;
                total_decoded_bytes += info.data.len;
                info.deinit(allocator);
            },
            .rpc_error => return error.UnexpectedRpcError,
        }
    }
    std.mem.doNotOptimizeAway(&total_decoded_bytes);
    printResult("rpc_getAccountInfo_parse", PROFILE_RPC_LARGE_DATA, RPC_PARSE_BENCH_ITERS, nowNs() - start);
}

fn runGetTransactionParseBenchmark(
    allocator: std.mem.Allocator,
    response_body: []const u8,
    signature: Signature,
) !void {
    var mock_transport: StaticResponseTransport = .{ .response_body = response_body };
    const transport = transport_mod.Transport.init(&mock_transport, StaticResponseTransport.postJson, staticTransportDeinit);
    var client = try RpcClient.initWithTransport(allocator, "http://benchmark.local", transport);
    defer client.deinit();

    var total_meta_bytes: usize = 0;

    for (0..RPC_PARSE_WARMUP_ITERS) |_| {
        const result = try client.getTransaction(signature);
        switch (result) {
            .ok => |maybe_tx| {
                const tx_val = maybe_tx orelse return error.ExpectedTransaction;
                var tx = tx_val;
                total_meta_bytes += tx.raw_json.len;
                if (tx.meta) |meta| {
                    total_meta_bytes += meta.raw_json.?.len;
                }
                tx.deinit(allocator);
            },
            .rpc_error => return error.UnexpectedRpcError,
        }
    }

    const start = nowNs();
    for (0..RPC_PARSE_BENCH_ITERS) |_| {
        const result = try client.getTransaction(signature);
        switch (result) {
            .ok => |maybe_tx| {
                const tx_val = maybe_tx orelse return error.ExpectedTransaction;
                var tx = tx_val;
                total_meta_bytes += tx.raw_json.len;
                if (tx.meta) |meta| {
                    total_meta_bytes += meta.raw_json.?.len;
                }
                tx.deinit(allocator);
            },
            .rpc_error => return error.UnexpectedRpcError,
        }
    }
    std.mem.doNotOptimizeAway(&total_meta_bytes);
    printResult("rpc_getTransaction_parse", PROFILE_RPC_COMPLEX_META, RPC_PARSE_BENCH_ITERS, nowNs() - start);
}

fn runGetSignatureStatusesParseBenchmark(
    allocator: std.mem.Allocator,
    response_body: []const u8,
    signatures: []const Signature,
) !void {
    var mock_transport: StaticResponseTransport = .{ .response_body = response_body };
    const transport = transport_mod.Transport.init(&mock_transport, StaticResponseTransport.postJson, staticTransportDeinit);
    var client = try RpcClient.initWithTransport(allocator, "http://benchmark.local", transport);
    defer client.deinit();

    var total_status_items: usize = 0;

    for (0..RPC_PARSE_WARMUP_ITERS) |_| {
        const result = try client.getSignatureStatuses(signatures);
        switch (result) {
            .ok => |statuses_val| {
                var statuses = statuses_val;
                total_status_items += statuses.items.len;
                statuses.deinit(allocator);
            },
            .rpc_error => return error.UnexpectedRpcError,
        }
    }

    const start = nowNs();
    for (0..RPC_PARSE_BENCH_ITERS) |_| {
        const result = try client.getSignatureStatuses(signatures);
        switch (result) {
            .ok => |statuses_val| {
                var statuses = statuses_val;
                total_status_items += statuses.items.len;
                statuses.deinit(allocator);
            },
            .rpc_error => return error.UnexpectedRpcError,
        }
    }
    std.mem.doNotOptimizeAway(&total_status_items);
    printResult("rpc_getSignatureStatuses_parse", PROFILE_RPC_BATCH, RPC_PARSE_BENCH_ITERS, nowNs() - start);
}

fn runWsSubscribeSerializeBenchmark(
    comptime name: []const u8,
    allocator: std.mem.Allocator,
    value: []const u8,
    comptime serializer: anytype,
    commitment: solana.rpc.types.Commitment,
) !void {
    var total_payload_bytes: usize = 0;
    var rpc_id: u64 = 1;

    for (0..WS_CODEC_WARMUP_ITERS) |_| {
        const payload = try serializer(allocator, rpc_id, value, commitment);
        rpc_id += 1;
        total_payload_bytes += payload.len;
        allocator.free(payload);
    }

    const start = nowNs();
    for (0..WS_CODEC_BENCH_ITERS) |_| {
        const payload = try serializer(allocator, rpc_id, value, commitment);
        rpc_id += 1;
        total_payload_bytes += payload.len;
        allocator.free(payload);
    }
    std.mem.doNotOptimizeAway(&total_payload_bytes);
    printResult(name, PROFILE_WS_SUBSCRIBE, WS_CODEC_BENCH_ITERS, nowNs() - start);
}

fn runWsLogsSubscribeSerializeBenchmark(
    comptime name: []const u8,
    allocator: std.mem.Allocator,
    value: []const u8,
    comptime serializer: anytype,
) !void {
    var total_payload_bytes: usize = 0;
    var rpc_id: u64 = 1;

    for (0..WS_CODEC_WARMUP_ITERS) |_| {
        const payload = try serializer(allocator, rpc_id, value);
        rpc_id += 1;
        total_payload_bytes += payload.len;
        allocator.free(payload);
    }

    const start = nowNs();
    for (0..WS_CODEC_BENCH_ITERS) |_| {
        const payload = try serializer(allocator, rpc_id, value);
        rpc_id += 1;
        total_payload_bytes += payload.len;
        allocator.free(payload);
    }
    std.mem.doNotOptimizeAway(&total_payload_bytes);
    printResult(name, PROFILE_WS_SUBSCRIBE, WS_CODEC_BENCH_ITERS, nowNs() - start);
}

fn runWsAccountNotificationParseBenchmark(allocator: std.mem.Allocator, raw_message: []const u8) !void {
    var total_account_bytes: usize = 0;

    for (0..WS_CODEC_WARMUP_ITERS) |_| {
        var notification = try ws_rpc.parseAccountNotificationMessage(allocator, raw_message);
        total_account_bytes += @as(usize, @intCast(notification.context_slot)) + notification.account.owner.len;
        if (notification.account.data_encoding) |encoding| total_account_bytes += encoding.len;
        notification.deinit(allocator);
    }

    const start = nowNs();
    for (0..WS_CODEC_BENCH_ITERS) |_| {
        var notification = try ws_rpc.parseAccountNotificationMessage(allocator, raw_message);
        total_account_bytes += @as(usize, @intCast(notification.context_slot)) + notification.account.owner.len;
        if (notification.account.data_encoding) |encoding| total_account_bytes += encoding.len;
        notification.deinit(allocator);
    }
    std.mem.doNotOptimizeAway(&total_account_bytes);
    printResult("ws_accountNotification_parse", PROFILE_WS_ACCOUNT_NOTIFICATION, WS_CODEC_BENCH_ITERS, nowNs() - start);
}

fn runWsProgramNotificationParseBenchmark(allocator: std.mem.Allocator, raw_message: []const u8) !void {
    var total_program_bytes: usize = 0;

    for (0..WS_CODEC_WARMUP_ITERS) |_| {
        var notification = try ws_rpc.parseProgramNotificationMessage(allocator, raw_message);
        total_program_bytes += @as(usize, @intCast(notification.context_slot)) + notification.pubkey.len + notification.account.owner.len;
        if (notification.account.data_encoding) |encoding| total_program_bytes += encoding.len;
        notification.deinit(allocator);
    }

    const start = nowNs();
    for (0..WS_CODEC_BENCH_ITERS) |_| {
        var notification = try ws_rpc.parseProgramNotificationMessage(allocator, raw_message);
        total_program_bytes += @as(usize, @intCast(notification.context_slot)) + notification.pubkey.len + notification.account.owner.len;
        if (notification.account.data_encoding) |encoding| total_program_bytes += encoding.len;
        notification.deinit(allocator);
    }
    std.mem.doNotOptimizeAway(&total_program_bytes);
    printResult("ws_programNotification_parse", PROFILE_WS_PROGRAM_NOTIFICATION, WS_CODEC_BENCH_ITERS, nowNs() - start);
}

fn runWsLogsNotificationParseBenchmark(allocator: std.mem.Allocator, raw_message: []const u8) !void {
    var total_log_bytes: usize = 0;

    for (0..WS_CODEC_WARMUP_ITERS) |_| {
        var notification = try ws_rpc.parseLogsNotificationMessage(allocator, raw_message);
        total_log_bytes += @as(usize, @intCast(notification.context_slot));
        if (notification.signature) |signature| total_log_bytes += signature.len;
        if (notification.err_json) |err_json| total_log_bytes += err_json.len;
        for (notification.logs) |log| total_log_bytes += log.len;
        notification.deinit(allocator);
    }

    const start = nowNs();
    for (0..WS_CODEC_BENCH_ITERS) |_| {
        var notification = try ws_rpc.parseLogsNotificationMessage(allocator, raw_message);
        total_log_bytes += @as(usize, @intCast(notification.context_slot));
        if (notification.signature) |signature| total_log_bytes += signature.len;
        if (notification.err_json) |err_json| total_log_bytes += err_json.len;
        for (notification.logs) |log| total_log_bytes += log.len;
        notification.deinit(allocator);
    }
    std.mem.doNotOptimizeAway(&total_log_bytes);
    printResult("ws_logsNotification_parse", PROFILE_WS_LOGS_NOTIFICATION, WS_CODEC_BENCH_ITERS, nowNs() - start);
}

// --- Benchmark Runner ---

fn printResult(comptime name: []const u8, comptime profile: []const u8, iters: usize, elapsed_ns: u64) void {
    const safe_elapsed_ns = if (elapsed_ns == 0) 1 else elapsed_ns;
    const avg_ns = safe_elapsed_ns / iters;
    const ops_per_sec: u64 = @intCast((@as(u128, iters) * std.time.ns_per_s) / safe_elapsed_ns);
    std.debug.print("BENCH|{s}|{s}|{d}|{d}|{d}|{d}\n", .{
        name,
        profile,
        iters,
        safe_elapsed_ns / std.time.ns_per_us,
        avg_ns,
        ops_per_sec,
    });
}

// --- Main ---

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const payer = try Keypair.fromSeed(SEED_BYTES);
    const benchmark_target = comptime std.fmt.comptimePrint("{s}-{s}", .{
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.os.tag),
    });
    const pubkey = Pubkey.init(PUBKEY_BYTES);
    const rpc_account_pubkey = Pubkey.init([_]u8{0x21} ** 32);
    const rpc_transaction_signature = Signature.init([_]u8{0x33} ** Signature.LENGTH);
    const large_account_info_response = try buildLargeAccountInfoResponse(allocator);
    defer allocator.free(large_account_info_response);
    const complex_transaction_response = try buildComplexTransactionResponse(allocator);
    defer allocator.free(complex_transaction_response);
    const signature_statuses = try buildBenchmarkSignatures(allocator, RPC_SIGNATURE_STATUSES_BATCH_SIZE);
    defer allocator.free(signature_statuses);
    const signature_statuses_response = try buildSignatureStatusesResponse(allocator, signature_statuses.len);
    defer allocator.free(signature_statuses_response);
    const ws_account_notification = try buildWsAccountNotificationMessage(allocator);
    defer allocator.free(ws_account_notification);
    const ws_program_notification = try buildWsProgramNotificationMessage(allocator);
    defer allocator.free(ws_program_notification);
    const ws_logs_notification = try buildWsLogsNotificationMessage(allocator);
    defer allocator.free(ws_logs_notification);
    const ws_account_pubkey = "11111111111111111111111111111111";
    const ws_program_id = "BPFLoaderUpgradeab1e11111111111111111111111";
    const ws_logs_filter = "all";

    std.debug.print("=== solana-zig Benchmark Harness ===\n", .{});
    std.debug.print("iterations: {d} (warmup: {d})\n", .{ BENCH_ITERS, WARMUP_ITERS });
    std.debug.print("rpc parse iterations: {d} (warmup: {d})\n", .{ RPC_PARSE_BENCH_ITERS, RPC_PARSE_WARMUP_ITERS });
    std.debug.print("ws codec iterations: {d} (warmup: {d})\n", .{ WS_CODEC_BENCH_ITERS, WS_CODEC_WARMUP_ITERS });
    std.debug.print("target: {s}\n", .{benchmark_target});
    std.debug.print("zig: {d}.{d}.{d}\n", .{
        builtin.zig_version.major,
        builtin.zig_version.minor,
        builtin.zig_version.patch,
    });
    std.debug.print("optimize: ReleaseFast\n", .{});
    std.debug.print("columns: BENCH|op|profile|iters|total_us|ns_op|ops_sec\n", .{});
    std.debug.print("\n", .{});

    // --- Pubkey base58 encode/decode ---
    std.debug.print("--- pubkey base58 ---\n", .{});
    {
        for (0..WARMUP_ITERS) |_| {
            const e = pubkey.toBase58Alloc(allocator) catch continue;
            allocator.free(e);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const e = pubkey.toBase58Alloc(allocator) catch continue;
            allocator.free(e);
        }
        printResult("pubkey_base58_encode", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    {
        const encoded = try pubkey.toBase58Alloc(allocator);
        defer allocator.free(encoded);

        for (0..WARMUP_ITERS) |_| {
            var d = Pubkey.fromBase58(encoded) catch continue;
            std.mem.doNotOptimizeAway(&d);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d = Pubkey.fromBase58(encoded) catch continue;
            std.mem.doNotOptimizeAway(&d);
        }
        printResult("pubkey_base58_decode", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    {
        const encoded = try pubkey.toBase58Alloc(allocator);
        defer allocator.free(encoded);

        for (0..WARMUP_ITERS) |_| {
            var d: [32]u8 = undefined;
            _ = @import("solana/core/base58_fast.zig").decode32(encoded, &d) catch continue;
            std.mem.doNotOptimizeAway(&d);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d: [32]u8 = undefined;
            _ = @import("solana/core/base58_fast.zig").decode32(encoded, &d) catch continue;
            std.mem.doNotOptimizeAway(&d);
        }
        printResult("pubkey_base58_decode_fast", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    {
        var buf: [64]u8 = undefined;
        for (0..WARMUP_ITERS) |_| {
            const len = pubkey.toBase58Buf(&buf) catch continue;
            std.mem.doNotOptimizeAway(buf[0..len]);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const len = pubkey.toBase58Buf(&buf) catch continue;
            std.mem.doNotOptimizeAway(buf[0..len]);
        }
        printResult("pubkey_to_base58_buf", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    {
        var buf: [64]u8 = undefined;
        for (0..WARMUP_ITERS) |_| {
            const len = pubkey.toBase58Fast(&buf);
            std.mem.doNotOptimizeAway(buf[0..len]);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const len = pubkey.toBase58Fast(&buf);
            std.mem.doNotOptimizeAway(buf[0..len]);
        }
        printResult("pubkey_to_base58_fast", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    // --- shortvec ---
    std.debug.print("\n--- shortvec ---\n", .{});
    {
        for (0..WARMUP_ITERS) |_| {
            const e = shortvec.encodeAlloc(allocator, 12345) catch continue;
            allocator.free(e);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const e = shortvec.encodeAlloc(allocator, 12345) catch continue;
            allocator.free(e);
        }
        printResult("shortvec_encode", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }
    {
        const input = [_]u8{ 0xB9, 0x60 };
        for (0..WARMUP_ITERS) |_| {
            const r = shortvec.decode(&input) catch continue;
            std.mem.doNotOptimizeAway(&r);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const r = shortvec.decode(&input) catch continue;
            std.mem.doNotOptimizeAway(&r);
        }
        printResult("shortvec_decode", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    // --- legacy message ---
    std.debug.print("\n--- legacy message ---\n", .{});
    {
        var message = try buildLegacyMessage(allocator, payer);
        defer message.deinit();

        for (0..WARMUP_ITERS) |_| {
            const s = message.serialize(allocator) catch continue;
            allocator.free(s);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const s = message.serialize(allocator) catch continue;
            allocator.free(s);
        }
        printResult("legacy_message_serialize", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }
    {
        var setup_msg = try buildLegacyMessage(allocator, payer);
        const serialized = try setup_msg.serialize(allocator);
        setup_msg.deinit();
        defer allocator.free(serialized);

        for (0..WARMUP_ITERS) |_| {
            var d = Message.deserialize(allocator, serialized) catch continue;
            d.message.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d = Message.deserialize(allocator, serialized) catch continue;
            d.message.deinit();
        }
        printResult("legacy_message_deserialize", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    // --- v0 message ---
    std.debug.print("\n--- v0 message ---\n", .{});
    {
        var message = try buildV0Message(allocator, payer);
        defer message.deinit();

        for (0..WARMUP_ITERS) |_| {
            const s = message.serialize(allocator) catch continue;
            allocator.free(s);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const s = message.serialize(allocator) catch continue;
            allocator.free(s);
        }
        printResult("v0_message_serialize", PROFILE_PHASE1_REALISTIC, BENCH_ITERS, nowNs() - start);
    }
    {
        var setup_msg = try buildV0Message(allocator, payer);
        const serialized = try setup_msg.serialize(allocator);
        setup_msg.deinit();
        defer allocator.free(serialized);

        for (0..WARMUP_ITERS) |_| {
            var d = Message.deserialize(allocator, serialized) catch continue;
            d.message.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d = Message.deserialize(allocator, serialized) catch continue;
            d.message.deinit();
        }
        printResult("v0_message_deserialize", PROFILE_PHASE1_REALISTIC, BENCH_ITERS, nowNs() - start);
    }

    // --- versioned transaction ---
    std.debug.print("\n--- versioned transaction ---\n", .{});
    {
        const setup_msg = try buildV0Message(allocator, payer);
        var tx = try VersionedTransaction.initUnsigned(allocator, setup_msg);
        defer tx.deinit();
        try tx.sign(&[_]Keypair{payer});

        for (0..WARMUP_ITERS) |_| {
            const s = tx.serialize(allocator) catch continue;
            allocator.free(s);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const s = tx.serialize(allocator) catch continue;
            allocator.free(s);
        }
        printResult("transaction_serialize", PROFILE_PHASE1_REALISTIC, BENCH_ITERS, nowNs() - start);
    }
    {
        const setup_msg = try buildV0Message(allocator, payer);
        var tx = try VersionedTransaction.initUnsigned(allocator, setup_msg);
        try tx.sign(&[_]Keypair{payer});
        const serialized = try tx.serialize(allocator);
        tx.deinit();
        defer allocator.free(serialized);

        for (0..WARMUP_ITERS) |_| {
            var d = VersionedTransaction.deserialize(allocator, serialized) catch continue;
            d.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d = VersionedTransaction.deserialize(allocator, serialized) catch continue;
            d.deinit();
        }
        printResult("transaction_deserialize", PROFILE_PHASE1_REALISTIC, BENCH_ITERS, nowNs() - start);
    }

    // --- sign / verify ---
    std.debug.print("\n--- sign / verify ---\n", .{});
    {
        var sign_msg = try buildLegacyMessage(allocator, payer);
        const msg_bytes = try sign_msg.serialize(allocator);
        sign_msg.deinit();
        defer allocator.free(msg_bytes);

        for (0..WARMUP_ITERS) |_| {
            const sig = payer.sign(msg_bytes) catch continue;
            std.mem.doNotOptimizeAway(&sig);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const sig = payer.sign(msg_bytes) catch continue;
            std.mem.doNotOptimizeAway(&sig);
        }
        printResult("ed25519_sign", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }
    {
        var verify_msg = try buildLegacyMessage(allocator, payer);
        const verify_bytes = try verify_msg.serialize(allocator);
        verify_msg.deinit();
        defer allocator.free(verify_bytes);

        const sig = try payer.sign(verify_bytes);

        for (0..WARMUP_ITERS) |_| {
            sig.verify(verify_bytes, payer.pubkey()) catch {};
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            sig.verify(verify_bytes, payer.pubkey()) catch {};
        }
        printResult("ed25519_verify", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    // --- rpc response parsing ---
    std.debug.print("\n--- rpc response parsing ---\n", .{});
    try runGetAccountInfoParseBenchmark(allocator, large_account_info_response, rpc_account_pubkey);
    try runGetTransactionParseBenchmark(allocator, complex_transaction_response, rpc_transaction_signature);
    try runGetSignatureStatusesParseBenchmark(allocator, signature_statuses_response, signature_statuses);

    // --- websocket message codec ---
    std.debug.print("\n--- websocket message codec ---\n", .{});
    try runWsSubscribeSerializeBenchmark("ws_accountSubscribe_serialize", allocator, ws_account_pubkey, ws_rpc.serializeAccountSubscribeRequest, .confirmed);
    try runWsSubscribeSerializeBenchmark("ws_programSubscribe_serialize", allocator, ws_program_id, ws_rpc.serializeProgramSubscribeRequest, .confirmed);
    try runWsLogsSubscribeSerializeBenchmark("ws_logsSubscribe_serialize", allocator, ws_logs_filter, ws_rpc.serializeLogsSubscribeRequest);
    try runWsAccountNotificationParseBenchmark(allocator, ws_account_notification);
    try runWsProgramNotificationParseBenchmark(allocator, ws_program_notification);
    try runWsLogsNotificationParseBenchmark(allocator, ws_logs_notification);

    // --- signer benchmarks ---
    std.debug.print("\n--- signer benchmarks ---\n", .{});
    {
        const InMemorySigner = solana.signers.InMemorySigner;
        var im_signer = InMemorySigner.init(payer);
        const signer = im_signer.asSigner();
        var sign_msg = try buildLegacyMessage(allocator, payer);
        const msg_bytes = try sign_msg.serialize(allocator);
        sign_msg.deinit();
        defer allocator.free(msg_bytes);

        for (0..WARMUP_ITERS) |_| {
            const sig = signer.signMessage(allocator, msg_bytes) catch continue;
            std.mem.doNotOptimizeAway(&sig);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const sig = signer.signMessage(allocator, msg_bytes) catch continue;
            std.mem.doNotOptimizeAway(&sig);
        }
        printResult("signer_in_memory_sign", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    // --- C ABI benchmarks ---
    std.debug.print("\n--- C ABI benchmarks ---\n", .{});
    {
        const pk = Pubkey.init([_]u8{0x0D} ** 32);
        for (0..WARMUP_ITERS) |_| {
            var str: [*c]u8 = undefined;
            var len: usize = 0;
            _ = @import("solana/cabi/core.zig").solana_pubkey_to_base58(&pk, &str, &len);
            @import("solana/cabi/core.zig").solana_string_free(str, len);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var str: [*c]u8 = undefined;
            var len: usize = 0;
            _ = @import("solana/cabi/core.zig").solana_pubkey_to_base58(&pk, &str, &len);
            @import("solana/cabi/core.zig").solana_string_free(str, len);
        }
        printResult("cabi_pubkey_to_base58", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }
    {
        const sig = Signature.init([_]u8{0x0E} ** Signature.LENGTH);
        for (0..WARMUP_ITERS) |_| {
            var str: [*c]u8 = undefined;
            var len: usize = 0;
            _ = @import("solana/cabi/core.zig").solana_signature_to_base58(&sig, &str, &len);
            @import("solana/cabi/core.zig").solana_string_free(str, len);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var str: [*c]u8 = undefined;
            var len: usize = 0;
            _ = @import("solana/cabi/core.zig").solana_signature_to_base58(&sig, &str, &len);
            @import("solana/cabi/core.zig").solana_string_free(str, len);
        }
        printResult("cabi_signature_to_base58", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    std.debug.print("\n=== benchmark complete ===\n", .{});
}
