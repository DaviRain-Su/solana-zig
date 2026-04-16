const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const hash_mod = @import("../core/hash.zig");
const transaction_mod = @import("../tx/transaction.zig");
const types = @import("types.zig");
const transport_mod = @import("transport.zig");

pub const RpcClient = struct {
    allocator: std.mem.Allocator,
    transport: transport_mod.Transport,
    endpoint: []const u8,
    next_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, endpoint: []const u8) !RpcClient {
        const transport = try transport_mod.initHttpTransport(allocator, io);
        errdefer transport.deinit(allocator);
        return initWithTransport(allocator, endpoint, transport);
    }

    pub fn initWithTransport(allocator: std.mem.Allocator, endpoint: []const u8, transport: transport_mod.Transport) !RpcClient {
        const endpoint_copy = allocator.dupe(u8, endpoint) catch |err| {
            transport.deinit(allocator);
            return err;
        };

        return .{
            .allocator = allocator,
            .transport = transport,
            .endpoint = endpoint_copy,
        };
    }

    pub fn deinit(self: *RpcClient) void {
        self.transport.deinit(self.allocator);
        self.allocator.free(self.endpoint);
    }

    pub fn getLatestBlockhash(self: *RpcClient) !types.RpcResult(types.LatestBlockhash) {
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getLatestBlockhash\",\"params\":[{{\"commitment\":\"confirmed\"}}]}}",
            .{self.nextRpcId()},
        );
        defer self.allocator.free(payload);

        var response = try self.callAndParse(payload);
        errdefer response.parsed.deinit();

        if (try extractRpcError(self.allocator, response.parsed.value)) |rpc_err| {
            response.parsed.deinit();
            return .{ .rpc_error = rpc_err };
        }

        const root = &response.parsed.value;
        const result = getObjectField(root, "result") orelse return error.InvalidRpcResponse;
        const value = getObjectField(result, "value") orelse return error.InvalidRpcResponse;

        const blockhash_str = getStringField(value, "blockhash") orelse return error.InvalidRpcResponse;
        const blockhash = try hash_mod.Hash.fromBase58(blockhash_str);
        const last_height = getU64Field(value, "lastValidBlockHeight") orelse return error.InvalidRpcResponse;

        response.parsed.deinit();
        return .{ .ok = .{ .blockhash = blockhash, .last_valid_block_height = last_height } };
    }

    pub fn getBalance(self: *RpcClient, pubkey: pubkey_mod.Pubkey) !types.RpcResult(u64) {
        const address = try pubkey.toBase58Alloc(self.allocator);
        defer self.allocator.free(address);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getBalance\",\"params\":[\"{s}\"]}}",
            .{ self.nextRpcId(), address },
        );
        defer self.allocator.free(payload);

        var response = try self.callAndParse(payload);
        defer response.parsed.deinit();

        if (try extractRpcError(self.allocator, response.parsed.value)) |rpc_err| {
            return .{ .rpc_error = rpc_err };
        }

        const root = &response.parsed.value;
        const result = getObjectField(root, "result") orelse return error.InvalidRpcResponse;
        const value = getObjectField(result, "value") orelse return error.InvalidRpcResponse;
        const lamports = parseIntegerAsU64(value) orelse return error.InvalidRpcResponse;

        return .{ .ok = lamports };
    }

    pub fn getAccountInfo(self: *RpcClient, pubkey: pubkey_mod.Pubkey) !types.RpcResult(types.OwnedJson) {
        const address = try pubkey.toBase58Alloc(self.allocator);
        defer self.allocator.free(address);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getAccountInfo\",\"params\":[\"{s}\",{{\"encoding\":\"base64\"}}]}}",
            .{ self.nextRpcId(), address },
        );
        defer self.allocator.free(payload);

        var response = try self.callAndParse(payload);
        errdefer response.parsed.deinit();

        if (try extractRpcError(self.allocator, response.parsed.value)) |rpc_err| {
            response.parsed.deinit();
            return .{ .rpc_error = rpc_err };
        }

        const root = &response.parsed.value;
        const result = getObjectField(root, "result") orelse return error.InvalidRpcResponse;

        return .{ .ok = .{ .parsed = response.parsed, .value = result.* } };
    }

    pub fn simulateTransaction(self: *RpcClient, tx: transaction_mod.VersionedTransaction) !types.RpcResult(types.OwnedJson) {
        const tx_bytes = try tx.serialize(self.allocator);
        defer self.allocator.free(tx_bytes);

        const tx_base64 = try encodeBase64(self.allocator, tx_bytes);
        defer self.allocator.free(tx_base64);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"simulateTransaction\",\"params\":[\"{s}\",{{\"encoding\":\"base64\",\"sigVerify\":true}}]}}",
            .{ self.nextRpcId(), tx_base64 },
        );
        defer self.allocator.free(payload);

        var response = try self.callAndParse(payload);
        errdefer response.parsed.deinit();

        if (try extractRpcError(self.allocator, response.parsed.value)) |rpc_err| {
            response.parsed.deinit();
            return .{ .rpc_error = rpc_err };
        }

        const root = &response.parsed.value;
        const result = getObjectField(root, "result") orelse return error.InvalidRpcResponse;
        return .{ .ok = .{ .parsed = response.parsed, .value = result.* } };
    }

    pub fn sendTransaction(self: *RpcClient, tx: transaction_mod.VersionedTransaction) !types.RpcResult(types.SendTransactionResult) {
        const tx_bytes = try tx.serialize(self.allocator);
        defer self.allocator.free(tx_bytes);

        const tx_base64 = try encodeBase64(self.allocator, tx_bytes);
        defer self.allocator.free(tx_base64);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"sendTransaction\",\"params\":[\"{s}\",{{\"encoding\":\"base64\",\"skipPreflight\":false}}]}}",
            .{ self.nextRpcId(), tx_base64 },
        );
        defer self.allocator.free(payload);

        var response = try self.callAndParse(payload);
        defer response.parsed.deinit();

        if (try extractRpcError(self.allocator, response.parsed.value)) |rpc_err| {
            return .{ .rpc_error = rpc_err };
        }

        const root = &response.parsed.value;
        const sig_text = getStringField(root, "result") orelse return error.InvalidRpcResponse;
        const signature = try @import("../core/signature.zig").Signature.fromBase58(sig_text);

        return .{ .ok = .{ .signature = signature } };
    }

    fn nextRpcId(self: *RpcClient) u64 {
        const current = self.next_id;
        self.next_id += 1;
        return current;
    }

    const ParsedEnvelope = struct {
        parsed: std.json.Parsed(std.json.Value),
    };

    fn callAndParse(self: *RpcClient, payload: []const u8) !ParsedEnvelope {
        const response_body = try self.transport.postJson(self.allocator, self.endpoint, payload);
        defer self.allocator.free(response_body);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{}) catch {
            return error.RpcParse;
        };

        if (parsed.value != .object) {
            parsed.deinit();
            return error.InvalidRpcResponse;
        }

        return .{ .parsed = parsed };
    }
};

fn extractRpcError(allocator: std.mem.Allocator, root: std.json.Value) !?types.RpcErrorObject {
    const rpc_error_value = getObjectField(&root, "error") orelse return null;
    if (rpc_error_value.* != .object) return error.InvalidRpcResponse;

    const code = getI64Field(rpc_error_value, "code") orelse return error.InvalidRpcResponse;
    const message = getStringField(rpc_error_value, "message") orelse return error.InvalidRpcResponse;

    const data_value = getObjectField(rpc_error_value, "data");
    var data_json: ?[]const u8 = null;
    if (data_value) |dv| {
        data_json = try stringifyValue(allocator, dv.*);
    }

    return .{
        .code = code,
        .message = try allocator.dupe(u8, message),
        .data_json = data_json,
    };
}

fn getObjectField(root: *const std.json.Value, field: []const u8) ?*const std.json.Value {
    if (root.* != .object) return null;
    // Zig 0.16: ObjectMap.get() returns ?V (by value); use getPtr() for ?*V.
    // We need to access via the mutable alias since getPtr requires non-const.
    const obj_ptr: *std.json.ObjectMap = @constCast(&root.object);
    return obj_ptr.getPtr(field);
}

fn getStringField(root: *const std.json.Value, field: []const u8) ?[]const u8 {
    const value = getObjectField(root, field) orelse return null;
    if (value.* != .string) return null;
    return value.string;
}

fn getI64Field(root: *const std.json.Value, field: []const u8) ?i64 {
    const value = getObjectField(root, field) orelse return null;
    return switch (value.*) {
        .integer => |n| n,
        .number_string => |s| std.fmt.parseInt(i64, s, 10) catch null,
        else => null,
    };
}

fn getU64Field(root: *const std.json.Value, field: []const u8) ?u64 {
    const value = getObjectField(root, field) orelse return null;
    return parseIntegerAsU64(value);
}

fn parseIntegerAsU64(value: *const std.json.Value) ?u64 {
    return switch (value.*) {
        .integer => |n| if (n >= 0) @as(u64, @intCast(n)) else null,
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch null,
        else => null,
    };
}

fn stringifyValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try std.json.Stringify.value(value, .{}, &out.writer);
    return allocator.dupe(u8, out.written());
}

fn encodeBase64(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const out = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(out, bytes);
    return out;
}

const MockTransport = struct {
    response_body: []const u8 = "",
    should_fail: bool = false,

    fn postJson(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) transport_mod.PostJsonError![]u8 {
        _ = url;
        _ = payload;

        const self: *MockTransport = @ptrCast(@alignCast(ctx));
        if (self.should_fail) return error.RpcTransport;
        return allocator.dupe(u8, self.response_body);
    }
};

fn makeTestTransaction(allocator: std.mem.Allocator) !transaction_mod.VersionedTransaction {
    const keypair = try @import("../core/keypair.zig").Keypair.fromSeed([_]u8{8} ** 32);
    const receiver = pubkey_mod.Pubkey.init([_]u8{7} ** 32);
    const program = pubkey_mod.Pubkey.init([_]u8{6} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{5} ** 32);
    const instruction_mod = @import("../tx/instruction.zig");

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = keypair.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const payload = [_]u8{ 1, 2, 3 };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    var message = try @import("../tx/message.zig").Message.compileLegacy(allocator, keypair.pubkey(), &ixs, blockhash);
    errdefer message.deinit();

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, message);
    errdefer tx.deinit();

    try tx.sign(&[_]@import("../core/keypair.zig").Keypair{keypair});
    return tx;
}

test "rpc client supports injected transport for happy path" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":12345}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{1} ** 32);
    const result = try client.getBalance(pubkey);

    switch (result) {
        .ok => |lamports| try std.testing.expectEqual(@as(u64, 12345), lamports),
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client preserves rpc error payload with injected transport" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32002,\"message\":\"node unhealthy\",\"data\":{\"retries\":3}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{2} ** 32);
    const result = try client.getBalance(pubkey);

    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32002), rpc_err.code);
            try std.testing.expectEqualStrings("node unhealthy", rpc_err.message);
            try std.testing.expect(rpc_err.data_json != null);
        },
    }
}

test "rpc client returns transport error with injected transport" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{ .should_fail = true };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{3} ** 32);
    try std.testing.expectError(error.RpcTransport, client.getBalance(pubkey));
}

test "rpc client getAccountInfo cleans up parsed json on malformed success response" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{4} ** 32);
    try std.testing.expectError(error.InvalidRpcResponse, client.getAccountInfo(pubkey));
}

test "rpc client simulateTransaction cleans up parsed json on malformed success response" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    var tx = try makeTestTransaction(gpa);
    defer tx.deinit();

    try std.testing.expectError(error.InvalidRpcResponse, client.simulateTransaction(tx));
}
