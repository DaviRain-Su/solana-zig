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

    pub fn getSlot(self: *RpcClient) !types.RpcResult(u64) {
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getSlot\",\"params\":[{{\"commitment\":\"confirmed\"}}]}}",
            .{self.nextRpcId()},
        );
        defer self.allocator.free(payload);

        var response = try self.callAndParse(payload);
        defer response.parsed.deinit();

        if (try extractRpcError(self.allocator, response.parsed.value)) |rpc_err| {
            return .{ .rpc_error = rpc_err };
        }

        const root = &response.parsed.value;
        const slot_value = getObjectField(root, "result") orelse return error.InvalidRpcResponse;
        const slot = parseIntegerAsU64(slot_value) orelse return error.InvalidRpcResponse;
        return .{ .ok = slot };
    }

    pub fn getSignaturesForAddress(self: *RpcClient, pubkey: pubkey_mod.Pubkey, limit: ?u32) !types.RpcResult(types.SignaturesForAddressResult) {
        const address = try pubkey.toBase58Alloc(self.allocator);
        defer self.allocator.free(address);

        const payload = if (limit) |l|
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getSignaturesForAddress\",\"params\":[\"{s}\",{{\"limit\":{d}}}]}}",
                .{ self.nextRpcId(), address, l },
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getSignaturesForAddress\",\"params\":[\"{s}\"]}}",
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
        if (result.* != .array) return error.InvalidRpcResponse;

        const items = try self.allocator.alloc(types.SignatureStatusInfo, result.array.items.len);
        errdefer self.allocator.free(items);

        var initialized: usize = 0;
        errdefer {
            for (items[0..initialized]) |*item| item.deinit(self.allocator);
        }

        for (result.array.items, 0..) |item, i| {
            if (item != .object) return error.InvalidRpcResponse;

            const signature_str = getStringField(&item, "signature") orelse return error.InvalidRpcResponse;
            const slot = getU64Field(&item, "slot") orelse return error.InvalidRpcResponse;
            const signature = try @import("../core/signature.zig").Signature.fromBase58(signature_str);

            const err_json = try extractOptionalFieldJson(self.allocator, &item, "err");
            errdefer if (err_json) |err| self.allocator.free(err);

            const memo = try extractOptionalString(self.allocator, &item, "memo");
            errdefer if (memo) |m| self.allocator.free(m);

            const block_time = getOptionalI64Field(&item, "blockTime");
            const raw_json = try stringifyValue(self.allocator, item);
            errdefer self.allocator.free(raw_json);

            items[i] = .{
                .signature = signature,
                .slot = slot,
                .err_json = err_json,
                .memo = memo,
                .block_time = block_time,
                .raw_json = raw_json,
            };
            initialized += 1;
        }

        response.parsed.deinit();
        return .{ .ok = .{ .items = items } };
    }

    pub fn getTokenAccountsByOwner(self: *RpcClient, owner: pubkey_mod.Pubkey, program_id: pubkey_mod.Pubkey) !types.RpcResult(types.TokenAccountsByOwnerResult) {
        const owner_b58 = try owner.toBase58Alloc(self.allocator);
        defer self.allocator.free(owner_b58);
        const program_b58 = try program_id.toBase58Alloc(self.allocator);
        defer self.allocator.free(program_b58);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getTokenAccountsByOwner\",\"params\":[\"{s}\",{{\"programId\":\"{s}\"}},{{\"encoding\":\"base64\",\"commitment\":\"confirmed\"}}]}}",
            .{ self.nextRpcId(), owner_b58, program_b58 },
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
        if (value.* != .array) return error.InvalidRpcResponse;

        const items = try self.allocator.alloc(types.TokenAccountInfo, value.array.items.len);
        errdefer self.allocator.free(items);

        var initialized: usize = 0;
        errdefer {
            for (items[0..initialized]) |*item| item.deinit(self.allocator);
        }

        for (value.array.items, 0..) |entry, i| {
            if (entry != .object) return error.InvalidRpcResponse;

            const pubkey_str = getStringField(&entry, "pubkey") orelse return error.InvalidRpcResponse;
            const pubkey = try pubkey_mod.Pubkey.fromBase58(pubkey_str);
            const account = getObjectField(&entry, "account") orelse return error.InvalidRpcResponse;

            const lamports = getU64Field(account, "lamports") orelse return error.InvalidRpcResponse;
            const account_owner_str = getStringField(account, "owner") orelse return error.InvalidRpcResponse;
            const account_owner = try pubkey_mod.Pubkey.fromBase58(account_owner_str);

            const data = try decodeAccountData(self.allocator, account);
            errdefer self.allocator.free(data);
            const data_encoding = try extractAccountDataEncoding(self.allocator, account);
            errdefer if (data_encoding) |encoding| self.allocator.free(encoding);
            const raw_json = try stringifyValue(self.allocator, account.*);
            errdefer self.allocator.free(raw_json);

            items[i] = .{
                .pubkey = pubkey,
                .owner = account_owner,
                .lamports = lamports,
                .data = data,
                .data_encoding = data_encoding,
                .raw_json = raw_json,
            };
            initialized += 1;
        }

        response.parsed.deinit();
        return .{ .ok = .{ .items = items } };
    }

    pub fn getTokenAccountBalance(self: *RpcClient, token_account: pubkey_mod.Pubkey) !types.RpcResult(types.TokenAmount) {
        const account_b58 = try token_account.toBase58Alloc(self.allocator);
        defer self.allocator.free(account_b58);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getTokenAccountBalance\",\"params\":[\"{s}\",{{\"commitment\":\"confirmed\"}}]}}",
            .{ self.nextRpcId(), account_b58 },
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
        if (value.* != .object) return error.InvalidRpcResponse;

        const amount_u64 = parseTokenAmountField(value, "amount") orelse return error.InvalidRpcResponse;
        const decimals_u64 = getU64Field(value, "decimals") orelse return error.InvalidRpcResponse;
        if (decimals_u64 > std.math.maxInt(u8)) return error.InvalidRpcResponse;
        const ui_amount_string_raw = getStringField(value, "uiAmountString") orelse return error.InvalidRpcResponse;
        const ui_amount_string = try self.allocator.dupe(u8, ui_amount_string_raw);
        errdefer self.allocator.free(ui_amount_string);
        const raw_json = try stringifyValue(self.allocator, value.*);
        errdefer self.allocator.free(raw_json);

        response.parsed.deinit();
        return .{ .ok = .{
            .amount = amount_u64,
            .decimals = @intCast(decimals_u64),
            .ui_amount_string = ui_amount_string,
            .raw_json = raw_json,
        } };
    }

    pub fn getTokenSupply(self: *RpcClient, mint: pubkey_mod.Pubkey) !types.RpcResult(types.TokenAmount) {
        const mint_b58 = try mint.toBase58Alloc(self.allocator);
        defer self.allocator.free(mint_b58);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getTokenSupply\",\"params\":[\"{s}\",{{\"commitment\":\"confirmed\"}}]}}",
            .{ self.nextRpcId(), mint_b58 },
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
        if (value.* != .object) return error.InvalidRpcResponse;

        const amount_u64 = parseTokenAmountField(value, "amount") orelse return error.InvalidRpcResponse;
        const decimals_u64 = getU64Field(value, "decimals") orelse return error.InvalidRpcResponse;
        if (decimals_u64 > std.math.maxInt(u8)) return error.InvalidRpcResponse;
        const ui_amount_string_raw = getStringField(value, "uiAmountString") orelse return error.InvalidRpcResponse;
        const ui_amount_string = try self.allocator.dupe(u8, ui_amount_string_raw);
        errdefer self.allocator.free(ui_amount_string);
        const raw_json = try stringifyValue(self.allocator, value.*);
        errdefer self.allocator.free(raw_json);

        response.parsed.deinit();
        return .{ .ok = .{
            .amount = amount_u64,
            .decimals = @intCast(decimals_u64),
            .ui_amount_string = ui_amount_string,
            .raw_json = raw_json,
        } };
    }

    pub fn getTransaction(self: *RpcClient, signature: @import("../core/signature.zig").Signature) !types.RpcResult(types.TransactionInfo) {
        const signature_b58 = try signature.toBase58Alloc(self.allocator);
        defer self.allocator.free(signature_b58);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getTransaction\",\"params\":[\"{s}\",{{\"encoding\":\"json\",\"commitment\":\"confirmed\",\"maxSupportedTransactionVersion\":0}}]}}",
            .{ self.nextRpcId(), signature_b58 },
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
        if (result.* != .object) return error.InvalidRpcResponse;

        const slot = getU64Field(result, "slot") orelse return error.InvalidRpcResponse;
        const block_time = getOptionalI64Field(result, "blockTime");
        const raw_json = try stringifyValue(self.allocator, result.*);

        response.parsed.deinit();
        return .{ .ok = .{
            .slot = slot,
            .block_time = block_time,
            .raw_json = raw_json,
        } };
    }

    pub fn getAccountInfo(self: *RpcClient, pubkey: pubkey_mod.Pubkey) !types.RpcResult(types.AccountInfo) {
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
        const value = getObjectField(result, "value") orelse return error.InvalidRpcResponse;

        const lamports = getU64Field(value, "lamports") orelse return error.InvalidRpcResponse;
        const owner_str = getStringField(value, "owner") orelse return error.InvalidRpcResponse;
        const owner = try pubkey_mod.Pubkey.fromBase58(owner_str);
        const executable = getBoolField(value, "executable") orelse return error.InvalidRpcResponse;
        const rent_epoch = getU64Field(value, "rentEpoch") orelse 0;

        const data_decoded = try decodeAccountData(self.allocator, value);
        errdefer self.allocator.free(data_decoded);

        const raw_json = try stringifyValue(self.allocator, value.*);
        errdefer self.allocator.free(raw_json);

        response.parsed.deinit();
        return .{ .ok = .{
            .lamports = lamports,
            .owner = owner,
            .executable = executable,
            .rent_epoch = rent_epoch,
            .data = data_decoded,
            .raw_json = raw_json,
        } };
    }

    pub fn simulateTransaction(self: *RpcClient, tx: transaction_mod.VersionedTransaction) !types.RpcResult(types.SimulateTransactionResult) {
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
        const value = getObjectField(result, "value") orelse return error.InvalidRpcResponse;

        const err_json = try extractSimulationError(self.allocator, value);
        errdefer if (err_json) |err| self.allocator.free(err);

        const logs = try parseStringArray(self.allocator, value, "logs");
        errdefer {
            for (logs) |log| self.allocator.free(log);
            self.allocator.free(logs);
        }

        const units_consumed = getU64Field(value, "unitsConsumed");

        const raw_json = try stringifyValue(self.allocator, value.*);
        errdefer self.allocator.free(raw_json);

        response.parsed.deinit();
        return .{ .ok = .{
            .err_json = err_json,
            .logs = logs,
            .units_consumed = units_consumed,
            .raw_json = raw_json,
        } };
    }

    pub fn getSignatureStatuses(self: *RpcClient, signatures: []const @import("../core/signature.zig").Signature) !types.RpcResult(?types.SignatureStatus) {
        // Build JSON array of signature strings
        var sig_array: std.Io.Writer.Allocating = .init(self.allocator);
        defer sig_array.deinit();
        try sig_array.writer.writeByte('[');
        for (signatures, 0..) |sig, i| {
            if (i > 0) try sig_array.writer.writeByte(',');
            try sig_array.writer.writeByte('"');
            const sig_b58 = try sig.toBase58Alloc(self.allocator);
            defer self.allocator.free(sig_b58);
            try sig_array.writer.writeAll(sig_b58);
            try sig_array.writer.writeByte('"');
        }
        try sig_array.writer.writeByte(']');

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getSignatureStatuses\",\"params\":[{s},{{\"searchTransactionHistory\":true}}]}}",
            .{ self.nextRpcId(), sig_array.written() },
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
        if (value.* != .array) return error.InvalidRpcResponse;

        // Return first status (or null if not found yet)
        if (value.array.items.len == 0 or value.array.items[0] == .null) {
            response.parsed.deinit();
            return .{ .ok = null };
        }

        const item = &value.array.items[0];
        if (item.* != .object) return error.InvalidRpcResponse;

        const slot = getU64Field(item, "slot") orelse return error.InvalidRpcResponse;
        const confirmations = getU64Field(item, "confirmations");
        const err_json = try extractOptionalFieldJson(self.allocator, item, "err");
        errdefer if (err_json) |err| self.allocator.free(err);
        const confirmation_status = if (getStringField(item, "confirmationStatus")) |cs|
            try self.allocator.dupe(u8, cs)
        else
            null;
        errdefer if (confirmation_status) |cs| self.allocator.free(cs);

        response.parsed.deinit();
        return .{ .ok = .{
            .slot = slot,
            .confirmations = confirmations,
            .err_json = err_json,
            .confirmation_status = confirmation_status,
        } };
    }

    pub fn sendTransaction(self: *RpcClient, tx: transaction_mod.VersionedTransaction) !types.RpcResult(types.SendTransactionResult) {
        const tx_bytes = try tx.serialize(self.allocator);
        defer self.allocator.free(tx_bytes);

        const tx_base64 = try encodeBase64(self.allocator, tx_bytes);
        defer self.allocator.free(tx_base64);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"sendTransaction\",\"params\":[\"{s}\",{{\"encoding\":\"base64\",\"skipPreflight\":false,\"preflightCommitment\":\"confirmed\"}}]}}",
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

fn parseTokenAmountField(root: *const std.json.Value, field: []const u8) ?u64 {
    const value = getObjectField(root, field) orelse return null;
    return switch (value.*) {
        .integer => |n| if (n >= 0) @intCast(n) else null,
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch null,
        .string => |s| std.fmt.parseInt(u64, s, 10) catch null,
        else => null,
    };
}

fn parseIntegerAsI64(value: *const std.json.Value) ?i64 {
    return switch (value.*) {
        .integer => |n| n,
        .number_string => |s| std.fmt.parseInt(i64, s, 10) catch null,
        else => null,
    };
}

fn getOptionalI64Field(root: *const std.json.Value, field: []const u8) ?i64 {
    const value = getObjectField(root, field) orelse return null;
    if (value.* == .null) return null;
    return parseIntegerAsI64(value);
}

fn extractOptionalFieldJson(allocator: std.mem.Allocator, root: *const std.json.Value, field: []const u8) !?[]const u8 {
    const value = getObjectField(root, field) orelse return null;
    if (value.* == .null) return null;
    return try stringifyValue(allocator, value.*);
}

fn extractOptionalString(allocator: std.mem.Allocator, root: *const std.json.Value, field: []const u8) !?[]const u8 {
    const value = getObjectField(root, field) orelse return null;
    if (value.* == .null) return null;
    if (value.* != .string) return error.InvalidRpcResponse;
    return try allocator.dupe(u8, value.string);
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

fn getBoolField(root: *const std.json.Value, field: []const u8) ?bool {
    const value = getObjectField(root, field) orelse return null;
    if (value.* != .bool) return null;
    return value.bool;
}

fn decodeBase64(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
    const out = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(out);
    try std.base64.standard.Decoder.decode(out, encoded);
    return out;
}

fn decodeAccountData(allocator: std.mem.Allocator, value: *const std.json.Value) ![]u8 {
    const data_field = getObjectField(value, "data") orelse return &[_]u8{};
    if (data_field.* == .string) {
        return decodeBase64(allocator, data_field.string) catch &[_]u8{};
    }
    if (data_field.* == .array and data_field.array.items.len > 0) {
        const first = data_field.array.items[0];
        if (first == .string) {
            return try decodeBase64(allocator, first.string);
        }
    }
    return &[_]u8{};
}

fn extractAccountDataEncoding(allocator: std.mem.Allocator, value: *const std.json.Value) !?[]const u8 {
    const data_field = getObjectField(value, "data") orelse return null;
    if (data_field.* == .array and data_field.array.items.len > 1) {
        const second = data_field.array.items[1];
        if (second == .string) return @as([]const u8, try allocator.dupe(u8, second.string));
    }
    if (data_field.* == .string) return @as([]const u8, try allocator.dupe(u8, "base64"));
    return null;
}

fn extractSimulationError(allocator: std.mem.Allocator, value: *const std.json.Value) !?[]const u8 {
    const err_field = getObjectField(value, "err") orelse return null;
    if (err_field.* == .null) return null;
    return try stringifyValue(allocator, err_field.*);
}

fn parseStringArray(allocator: std.mem.Allocator, value: *const std.json.Value, field: []const u8) ![][]const u8 {
    const arr_field = getObjectField(value, field) orelse return &[_][]const u8{};
    if (arr_field.* != .array) return &[_][]const u8{};

    const items = arr_field.array.items;
    const out = try allocator.alloc([]const u8, items.len);
    errdefer allocator.free(out);

    for (items, 0..) |item, i| {
        if (item != .string) {
            for (0..i) |j| allocator.free(out[j]);
            allocator.free(out);
            return error.InvalidRpcResponse;
        }
        out[i] = try allocator.dupe(u8, item.string);
    }
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

test "rpc client getAccountInfo typed parse happy path" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"lamports\":1000,\"owner\":\"11111111111111111111111111111111\",\"executable\":false,\"rentEpoch\":18446744073709551615,\"data\":\"AQID\"}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{4} ** 32);
    const result = try client.getAccountInfo(pubkey);

    switch (result) {
        .ok => |info| {
            defer info.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 1000), info.lamports);
            try std.testing.expect(!info.executable);
            try std.testing.expectEqual(@as(usize, 3), info.data.len);
            try std.testing.expect(info.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getAccountInfo typed parse with data array format" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"lamports\":2000,\"owner\":\"11111111111111111111111111111111\",\"executable\":true,\"rentEpoch\":2,\"data\":[\"AQID\",\"base64\"]}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{5} ** 32);
    const result = try client.getAccountInfo(pubkey);

    switch (result) {
        .ok => |info| {
            defer info.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 2000), info.lamports);
            try std.testing.expect(info.executable);
            try std.testing.expectEqual(@as(u64, 2), info.rent_epoch);
            try std.testing.expectEqual(@as(usize, 3), info.data.len);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getAccountInfo preserves rpc error with typed parse" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"Invalid param\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{6} ** 32);
    const result = try client.getAccountInfo(pubkey);

    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32602), rpc_err.code);
        },
    }
}

test "rpc client getAccountInfo returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{7} ** 32);
    try std.testing.expectError(error.InvalidRpcResponse, client.getAccountInfo(pubkey));
}

test "rpc client simulateTransaction typed parse happy path" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"err\":null,\"logs\":[\"log1\",\"log2\"],\"unitsConsumed\":1234}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    var tx = try makeTestTransaction(gpa);
    defer tx.deinit();

    const result = try client.simulateTransaction(tx);
    switch (result) {
        .ok => |sim| {
            defer sim.deinit(gpa);
            try std.testing.expect(sim.err_json == null);
            try std.testing.expectEqual(@as(usize, 2), sim.logs.len);
            try std.testing.expectEqualStrings("log1", sim.logs[0]);
            try std.testing.expectEqual(@as(u64, 1234), sim.units_consumed.?);
            try std.testing.expect(sim.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client simulateTransaction typed parse with err object" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"err\":{\"InstructionError\":[0,\"Custom\",1]},\"logs\":[\"failed\"]}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    var tx = try makeTestTransaction(gpa);
    defer tx.deinit();

    const result = try client.simulateTransaction(tx);
    switch (result) {
        .ok => |sim| {
            defer sim.deinit(gpa);
            try std.testing.expect(sim.err_json != null);
            try std.testing.expectEqual(@as(usize, 1), sim.logs.len);
            try std.testing.expect(sim.units_consumed == null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client simulateTransaction preserves rpc error with typed parse" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32002,\"message\":\"node unhealthy\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    var tx = try makeTestTransaction(gpa);
    defer tx.deinit();

    const result = try client.simulateTransaction(tx);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32002), rpc_err.code);
        },
    }
}

test "rpc client simulateTransaction returns InvalidRpcResponse on malformed success" {
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

test "rpc client getSlot typed parse happy path" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":123456}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getSlot();
    switch (result) {
        .ok => |slot| try std.testing.expectEqual(@as(u64, 123456), slot),
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getSlot preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32000,\"message\":\"slot unavailable\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getSlot();
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32000), rpc_err.code);
        },
    }
}

test "rpc client getSlot returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"slot\":1}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();
    try std.testing.expectError(error.InvalidRpcResponse, client.getSlot());
}

test "rpc client getSignaturesForAddress typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[{\"signature\":\"5FtkHfQ5N62hCV7Wz4NQTRz5fWPQjY7Y9YByK7GfP4Hbw7jV4kD5mYTHPwo2fhtxQzpgLQ8vndqaM8UZz2xM4V5d\",\"slot\":777,\"err\":null,\"memo\":\"ok\",\"blockTime\":1234}]}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{42} ** 32);
    const result = try client.getSignaturesForAddress(pubkey, 10);
    switch (result) {
        .ok => |sig_result| {
            var owned = sig_result;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(usize, 1), owned.items.len);
            try std.testing.expectEqual(@as(u64, 777), owned.items[0].slot);
            try std.testing.expectEqual(@as(i64, 1234), owned.items[0].block_time.?);
            try std.testing.expect(owned.items[0].err_json == null);
            try std.testing.expectEqualStrings("ok", owned.items[0].memo.?);
            try std.testing.expect(owned.items[0].raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getSignaturesForAddress preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"bad address\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{43} ** 32);
    const result = try client.getSignaturesForAddress(pubkey, null);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32602), rpc_err.code);
        },
    }
}

test "rpc client getSignaturesForAddress returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[{\"slot\":1}]}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{44} ** 32);
    try std.testing.expectError(error.InvalidRpcResponse, client.getSignaturesForAddress(pubkey, null));
}

test "rpc client getTransaction typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"slot\":99,\"blockTime\":555,\"meta\":{\"status\":{\"Ok\":null}},\"transaction\":{\"message\":{\"accountKeys\":[]}}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{9} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const msg = "tx-for-get-transaction";
    const sig = try kp.sign(msg);

    const result = try client.getTransaction(sig);
    switch (result) {
        .ok => |tx_info| {
            var owned = tx_info;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 99), owned.slot);
            try std.testing.expectEqual(@as(i64, 555), owned.block_time.?);
            try std.testing.expect(owned.raw_json.len > 0);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getTransaction preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32015,\"message\":\"transaction not available\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{10} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const sig = try kp.sign("tx-for-rpc-error");

    const result = try client.getTransaction(sig);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32015), rpc_err.code);
        },
    }
}

test "rpc client getTransaction returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"blockTime\":1}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{11} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const sig = try kp.sign("tx-for-malformed");
    try std.testing.expectError(error.InvalidRpcResponse, client.getTransaction(sig));
}

test "rpc client getSignatureStatuses typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":100},\"value\":[{\"slot\":72,\"confirmations\":10,\"err\":null,\"confirmationStatus\":\"confirmed\"}]}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{12} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const sig = try kp.sign("tx-for-sig-status");

    const result = try client.getSignatureStatuses(&[_]@import("../core/signature.zig").Signature{sig});
    switch (result) {
        .ok => |maybe_status| {
            try std.testing.expect(maybe_status != null);
            var status = maybe_status.?;
            defer status.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 72), status.slot);
            try std.testing.expectEqual(@as(u64, 10), status.confirmations.?);
            try std.testing.expect(status.err_json == null);
            try std.testing.expectEqualStrings("confirmed", status.confirmation_status.?);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getSignatureStatuses returns null for unknown signature" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":100},\"value\":[null]}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{13} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const sig = try kp.sign("tx-unknown");

    const result = try client.getSignatureStatuses(&[_]@import("../core/signature.zig").Signature{sig});
    switch (result) {
        .ok => |maybe_status| try std.testing.expect(maybe_status == null),
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getSignatureStatuses preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32600,\"message\":\"invalid request\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{14} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const sig = try kp.sign("tx-rpc-error");

    const result = try client.getSignatureStatuses(&[_]@import("../core/signature.zig").Signature{sig});
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32600), rpc_err.code);
        },
    }
}

test "rpc client getTokenAccountsByOwner typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":[{\"pubkey\":\"11111111111111111111111111111111\",\"account\":{\"lamports\":2039280,\"owner\":\"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA\",\"data\":[\"AQID\",\"base64\"],\"executable\":false,\"rentEpoch\":1}}]}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const owner = pubkey_mod.Pubkey.init([_]u8{42} ** 32);
    const token_program = try pubkey_mod.Pubkey.fromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const result = try client.getTokenAccountsByOwner(owner, token_program);

    switch (result) {
        .ok => |token_accounts| {
            var owned = token_accounts;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(usize, 1), owned.items.len);
            try std.testing.expectEqual(@as(u64, 2039280), owned.items[0].lamports);
            try std.testing.expectEqual(@as(usize, 3), owned.items[0].data.len);
            try std.testing.expectEqualStrings("base64", owned.items[0].data_encoding.?);
            try std.testing.expect(owned.items[0].raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getTokenAccountsByOwner preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"invalid owner\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const owner = pubkey_mod.Pubkey.init([_]u8{43} ** 32);
    const token_program = try pubkey_mod.Pubkey.fromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const result = try client.getTokenAccountsByOwner(owner, token_program);

    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32602), rpc_err.code);
        },
    }
}

test "rpc client getTokenAccountsByOwner returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"value\":[{\"account\":{\"lamports\":1}}]}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const owner = pubkey_mod.Pubkey.init([_]u8{44} ** 32);
    const token_program = try pubkey_mod.Pubkey.fromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    try std.testing.expectError(error.InvalidRpcResponse, client.getTokenAccountsByOwner(owner, token_program));
}

test "rpc client getTokenAccountBalance typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":777},\"value\":{\"amount\":\"4200000\",\"decimals\":6,\"uiAmount\":4.2,\"uiAmountString\":\"4.2\"}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const token_account = pubkey_mod.Pubkey.init([_]u8{45} ** 32);
    const result = try client.getTokenAccountBalance(token_account);
    switch (result) {
        .ok => |balance| {
            var owned = balance;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 4_200_000), owned.amount);
            try std.testing.expectEqual(@as(u8, 6), owned.decimals);
            try std.testing.expectEqualStrings("4.2", owned.ui_amount_string);
            try std.testing.expect(owned.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getTokenAccountBalance preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"invalid token account\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const token_account = pubkey_mod.Pubkey.init([_]u8{46} ** 32);
    const result = try client.getTokenAccountBalance(token_account);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32602), rpc_err.code);
        },
    }
}

test "rpc client getTokenAccountBalance returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"value\":{\"decimals\":6,\"uiAmountString\":\"4.2\"}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const token_account = pubkey_mod.Pubkey.init([_]u8{47} ** 32);
    try std.testing.expectError(error.InvalidRpcResponse, client.getTokenAccountBalance(token_account));
}

test "rpc client getTokenSupply typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":778},\"value\":{\"amount\":\"1000000000\",\"decimals\":9,\"uiAmount\":1.0,\"uiAmountString\":\"1\"}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const mint = pubkey_mod.Pubkey.init([_]u8{48} ** 32);
    const result = try client.getTokenSupply(mint);
    switch (result) {
        .ok => |supply| {
            var owned = supply;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 1_000_000_000), owned.amount);
            try std.testing.expectEqual(@as(u8, 9), owned.decimals);
            try std.testing.expectEqualStrings("1", owned.ui_amount_string);
            try std.testing.expect(owned.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getTokenSupply preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"invalid mint\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const mint = pubkey_mod.Pubkey.init([_]u8{49} ** 32);
    const result = try client.getTokenSupply(mint);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32602), rpc_err.code);
        },
    }
}

test "rpc client getTokenSupply returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"value\":{\"amount\":\"1000\",\"uiAmountString\":\"0.001\"}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const mint = pubkey_mod.Pubkey.init([_]u8{50} ** 32);
    try std.testing.expectError(error.InvalidRpcResponse, client.getTokenSupply(mint));
}
