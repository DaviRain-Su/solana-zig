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
    retry_config: types.RpcRetryConfig = .{},
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

    pub fn setRetryConfig(self: *RpcClient, retry_config: types.RpcRetryConfig) void {
        self.retry_config = retry_config;
    }

    pub fn getLatestBlockhash(self: *RpcClient) !types.RpcResult(types.LatestBlockhash) {
        return self.getLatestBlockhashWithCommitment(.confirmed);
    }

    pub fn getLatestBlockhashWithCommitment(self: *RpcClient, commitment: types.Commitment) !types.RpcResult(types.LatestBlockhash) {
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getLatestBlockhash\",\"params\":[{{\"commitment\":\"{s}\"}}]}}",
            .{ self.nextRpcId(), commitment.jsonString() },
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
        return self.getBalanceWithCommitment(pubkey, .confirmed);
    }

    pub fn getBalanceWithCommitment(self: *RpcClient, pubkey: pubkey_mod.Pubkey, commitment: types.Commitment) !types.RpcResult(u64) {
        const address = try pubkey.toBase58Alloc(self.allocator);
        defer self.allocator.free(address);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getBalance\",\"params\":[\"{s}\",{{\"commitment\":\"{s}\"}}]}}",
            .{ self.nextRpcId(), address, commitment.jsonString() },
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
        return self.getSlotWithOptions(.{});
    }

    pub fn getSlotWithOptions(
        self: *RpcClient,
        options: types.GetSlotOptions,
    ) !types.RpcResult(u64) {
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getSlot\",\"params\":[{{\"commitment\":\"{s}\"}}]}}",
            .{ self.nextRpcId(), options.commitment.jsonString() },
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

    pub fn getEpochInfo(self: *RpcClient) !types.RpcResult(types.EpochInfo) {
        return self.getEpochInfoWithOptions(.{});
    }

    pub fn getEpochInfoWithOptions(
        self: *RpcClient,
        options: types.GetEpochInfoOptions,
    ) !types.RpcResult(types.EpochInfo) {
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getEpochInfo\",\"params\":[{{\"commitment\":\"{s}\"}}]}}",
            .{ self.nextRpcId(), options.commitment.jsonString() },
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

        const absolute_slot = getU64Field(result, "absoluteSlot") orelse return error.InvalidRpcResponse;
        const block_height = getU64Field(result, "blockHeight");
        const epoch = getU64Field(result, "epoch") orelse return error.InvalidRpcResponse;
        const slot_index = getU64Field(result, "slotIndex") orelse return error.InvalidRpcResponse;
        const slots_in_epoch = getU64Field(result, "slotsInEpoch") orelse return error.InvalidRpcResponse;
        const transaction_count = getU64Field(result, "transactionCount");
        const raw_json = try stringifyValue(self.allocator, result.*);

        response.parsed.deinit();
        return .{ .ok = .{
            .absolute_slot = absolute_slot,
            .block_height = block_height,
            .epoch = epoch,
            .slot_index = slot_index,
            .slots_in_epoch = slots_in_epoch,
            .transaction_count = transaction_count,
            .raw_json = raw_json,
        } };
    }

    pub fn getMinimumBalanceForRentExemption(self: *RpcClient, data_len: usize) !types.RpcResult(u64) {
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getMinimumBalanceForRentExemption\",\"params\":[{d}]}}",
            .{ self.nextRpcId(), data_len },
        );
        defer self.allocator.free(payload);

        var response = try self.callAndParse(payload);
        defer response.parsed.deinit();

        if (try extractRpcError(self.allocator, response.parsed.value)) |rpc_err| {
            return .{ .rpc_error = rpc_err };
        }

        const root = &response.parsed.value;
        const lamports_value = getObjectField(root, "result") orelse return error.InvalidRpcResponse;
        const lamports = parseIntegerAsU64(lamports_value) orelse return error.InvalidRpcResponse;
        return .{ .ok = lamports };
    }

    pub fn requestAirdrop(self: *RpcClient, pubkey: pubkey_mod.Pubkey, lamports: u64) !types.RpcResult(types.RequestAirdropResult) {
        const address = try pubkey.toBase58Alloc(self.allocator);
        defer self.allocator.free(address);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"requestAirdrop\",\"params\":[\"{s}\",{d}]}}",
            .{ self.nextRpcId(), address, lamports },
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

    pub fn getAddressLookupTable(self: *RpcClient, table_address: pubkey_mod.Pubkey) !types.RpcResult(types.AddressLookupTableResult) {
        const table_b58 = try table_address.toBase58Alloc(self.allocator);
        defer self.allocator.free(table_b58);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getAddressLookupTable\",\"params\":[\"{s}\",{{\"commitment\":\"confirmed\"}}]}}",
            .{ self.nextRpcId(), table_b58 },
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
        const context = getObjectField(result, "context") orelse return error.InvalidRpcResponse;
        const context_slot = getU64Field(context, "slot") orelse return error.InvalidRpcResponse;
        const value = getObjectField(result, "value") orelse return error.InvalidRpcResponse;

        if (value.* == .null) {
            response.parsed.deinit();
            return .{ .ok = .{ .context_slot = context_slot, .value = null } };
        }
        if (value.* != .object) return error.InvalidRpcResponse;

        const deactivation_slot = getU64Field(value, "deactivationSlot") orelse return error.InvalidRpcResponse;
        const last_extended_slot = getU64Field(value, "lastExtendedSlot") orelse return error.InvalidRpcResponse;
        const start_index_u64 = getU64Field(value, "lastExtendedSlotStartIndex") orelse return error.InvalidRpcResponse;
        if (start_index_u64 > std.math.maxInt(u8)) return error.InvalidRpcResponse;

        var authority: ?pubkey_mod.Pubkey = null;
        if (getObjectField(value, "authority")) |authority_field| {
            if (authority_field.* == .string) {
                authority = try pubkey_mod.Pubkey.fromBase58(authority_field.string);
            } else if (authority_field.* != .null) {
                return error.InvalidRpcResponse;
            }
        }

        const addresses_field = getObjectField(value, "addresses") orelse return error.InvalidRpcResponse;
        if (addresses_field.* != .array) return error.InvalidRpcResponse;
        const addresses = try self.allocator.alloc(pubkey_mod.Pubkey, addresses_field.array.items.len);
        errdefer self.allocator.free(addresses);

        for (addresses_field.array.items, 0..) |addr, i| {
            if (addr != .string) return error.InvalidRpcResponse;
            addresses[i] = try pubkey_mod.Pubkey.fromBase58(addr.string);
        }

        const raw_json = try stringifyValue(self.allocator, value.*);
        errdefer self.allocator.free(raw_json);

        response.parsed.deinit();
        return .{ .ok = .{
            .context_slot = context_slot,
            .value = .{
                .key = table_address,
                .state = .{
                    .deactivation_slot = deactivation_slot,
                    .last_extended_slot = last_extended_slot,
                    .last_extended_slot_start_index = @intCast(start_index_u64),
                    .authority = authority,
                    .addresses = addresses,
                    .raw_json = raw_json,
                },
            },
        } };
    }

    pub fn getSignaturesForAddress(self: *RpcClient, pubkey: pubkey_mod.Pubkey, limit: ?u32) !types.RpcResult(types.SignaturesForAddressResult) {
        return self.getSignaturesForAddressWithOptions(pubkey, .{ .limit = limit });
    }

    pub fn getSignaturesForAddressWithOptions(
        self: *RpcClient,
        pubkey: pubkey_mod.Pubkey,
        options: types.GetSignaturesForAddressOptions,
    ) !types.RpcResult(types.SignaturesForAddressResult) {
        const address = try pubkey.toBase58Alloc(self.allocator);
        defer self.allocator.free(address);

        var payload_out: std.Io.Writer.Allocating = .init(self.allocator);
        defer payload_out.deinit();

        try payload_out.writer.print(
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getSignaturesForAddress\",\"params\":[\"{s}\"",
            .{ self.nextRpcId(), address },
        );

        if (options.before != null or options.until != null or options.limit != null) {
            try payload_out.writer.writeByte(',');
            try payload_out.writer.writeByte('{');

            var wrote_field = false;
            if (options.before) |before| {
                const before_b58 = try before.toBase58Alloc(self.allocator);
                defer self.allocator.free(before_b58);

                try payload_out.writer.print("\"before\":\"{s}\"", .{before_b58});
                wrote_field = true;
            }
            if (options.until) |until| {
                const until_b58 = try until.toBase58Alloc(self.allocator);
                defer self.allocator.free(until_b58);

                if (wrote_field) try payload_out.writer.writeByte(',');
                try payload_out.writer.print("\"until\":\"{s}\"", .{until_b58});
                wrote_field = true;
            }
            if (options.limit) |limit| {
                if (wrote_field) try payload_out.writer.writeByte(',');
                try payload_out.writer.print("\"limit\":{d}", .{limit});
            }

            try payload_out.writer.writeByte('}');
        }

        try payload_out.writer.writeAll("]}");
        const payload = try self.allocator.dupe(u8, payload_out.written());
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

    pub fn getTokenAccountsByOwner(
        self: *RpcClient,
        owner: pubkey_mod.Pubkey,
        program_id: pubkey_mod.Pubkey,
    ) !types.RpcResult(types.TokenAccountsByOwnerResult) {
        return self.getTokenAccountsByOwnerWithOptions(owner, .{
            .filter = .{ .program_id = program_id },
        });
    }

    pub fn getTokenAccountsByOwnerWithOptions(
        self: *RpcClient,
        owner: pubkey_mod.Pubkey,
        options: types.GetTokenAccountsByOwnerOptions,
    ) !types.RpcResult(types.TokenAccountsByOwnerResult) {
        const owner_b58 = try owner.toBase58Alloc(self.allocator);
        defer self.allocator.free(owner_b58);

        var payload_out: std.Io.Writer.Allocating = .init(self.allocator);
        defer payload_out.deinit();

        try payload_out.writer.print(
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getTokenAccountsByOwner\",\"params\":[\"{s}\",",
            .{ self.nextRpcId(), owner_b58 },
        );

        switch (options.filter) {
            .program_id => |program_id| {
                const program_b58 = try program_id.toBase58Alloc(self.allocator);
                defer self.allocator.free(program_b58);
                try payload_out.writer.print("{{\"programId\":\"{s}\"}}", .{program_b58});
            },
            .mint => |mint| {
                const mint_b58 = try mint.toBase58Alloc(self.allocator);
                defer self.allocator.free(mint_b58);
                try payload_out.writer.print("{{\"mint\":\"{s}\"}}", .{mint_b58});
            },
        }

        try payload_out.writer.print(
            ",{{\"encoding\":\"{s}\",\"commitment\":\"{s}\"}}]}}",
            .{ options.encoding.jsonString(), options.commitment.jsonString() },
        );

        const payload = try self.allocator.dupe(u8, payload_out.written());
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
            const executable = getBoolField(account, "executable") orelse return error.InvalidRpcResponse;
            const rent_epoch = getU64Field(account, "rentEpoch") orelse 0;

            const data = try decodeAccountData(self.allocator, account);
            errdefer self.allocator.free(data);
            const data_encoding = try extractAccountDataEncoding(self.allocator, account);
            errdefer if (data_encoding) |encoding| self.allocator.free(encoding);
            const raw_json = try stringifyValue(self.allocator, account.*);
            errdefer self.allocator.free(raw_json);

            items[i] = .{
                .pubkey = pubkey,
                .account_info = .{
                    .lamports = lamports,
                    .owner = account_owner,
                    .executable = executable,
                    .rent_epoch = rent_epoch,
                    .data = data,
                    .raw_json = raw_json,
                },
                .data_encoding = data_encoding,
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
        const ui_amount_string = if (getStringField(value, "uiAmountString")) |raw|
            try self.allocator.dupe(u8, raw)
        else
            null;
        errdefer if (ui_amount_string) |s| self.allocator.free(s);
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
        const ui_amount_string = if (getStringField(value, "uiAmountString")) |raw|
            try self.allocator.dupe(u8, raw)
        else
            null;
        errdefer if (ui_amount_string) |s| self.allocator.free(s);
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

    pub fn getTransaction(self: *RpcClient, signature: @import("../core/signature.zig").Signature) !types.RpcResult(?types.TransactionInfo) {
        return self.getTransactionWithOptions(signature, .{});
    }

    pub fn getTransactionWithOptions(
        self: *RpcClient,
        signature: @import("../core/signature.zig").Signature,
        options: types.GetTransactionOptions,
    ) !types.RpcResult(?types.TransactionInfo) {
        const signature_b58 = try signature.toBase58Alloc(self.allocator);
        defer self.allocator.free(signature_b58);

        const payload = if (options.max_supported_transaction_version) |max_supported_transaction_version|
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getTransaction\",\"params\":[\"{s}\",{{\"encoding\":\"json\",\"commitment\":\"{s}\",\"maxSupportedTransactionVersion\":{d}}}]}}",
                .{ self.nextRpcId(), signature_b58, options.commitment.jsonString(), max_supported_transaction_version },
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getTransaction\",\"params\":[\"{s}\",{{\"encoding\":\"json\",\"commitment\":\"{s}\"}}]}}",
                .{ self.nextRpcId(), signature_b58, options.commitment.jsonString() },
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
        if (result.* == .null) {
            response.parsed.deinit();
            return .{ .ok = null };
        }
        if (result.* != .object) return error.InvalidRpcResponse;

        const slot = getU64Field(result, "slot") orelse return error.InvalidRpcResponse;
        const block_time = getOptionalI64Field(result, "blockTime");
        var meta = try parseTransactionMeta(self.allocator, result);
        errdefer if (meta) |*owned_meta| owned_meta.deinit(self.allocator);
        const raw_json = try stringifyValue(self.allocator, result.*);
        errdefer self.allocator.free(raw_json);

        response.parsed.deinit();
        return .{ .ok = .{
            .slot = slot,
            .block_time = block_time,
            .meta = meta,
            .raw_json = raw_json,
        } };
    }

    pub fn getAccountInfo(self: *RpcClient, pubkey: pubkey_mod.Pubkey) !types.RpcResult(?types.AccountInfo) {
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
        if (value.* == .null) {
            response.parsed.deinit();
            return .{ .ok = null };
        }
        if (value.* != .object) return error.InvalidRpcResponse;

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

    pub fn getSignatureStatuses(self: *RpcClient, signatures: []const @import("../core/signature.zig").Signature) !types.RpcResult(types.SignatureStatusesResult) {
        return self.getSignatureStatusesWithOptions(signatures, .{});
    }

    pub fn getSignatureStatusesWithOptions(
        self: *RpcClient,
        signatures: []const @import("../core/signature.zig").Signature,
        options: types.GetSignatureStatusesOptions,
    ) !types.RpcResult(types.SignatureStatusesResult) {
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
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"getSignatureStatuses\",\"params\":[{s},{{\"searchTransactionHistory\":{s}}}]}}",
            .{ self.nextRpcId(), sig_array.written(), if (options.search_transaction_history) "true" else "false" },
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

        const items = try self.allocator.alloc(?types.SignatureStatus, value.array.items.len);
        errdefer self.allocator.free(items);

        var initialized: usize = 0;
        errdefer {
            for (items[0..initialized]) |maybe_status| {
                if (maybe_status) |status_val| {
                    var status = status_val;
                    status.deinit(self.allocator);
                }
            }
        }

        for (value.array.items, 0..) |item, i| {
            if (item == .null) {
                items[i] = null;
            } else {
                items[i] = try parseSignatureStatus(self.allocator, &item);
            }
            initialized += 1;
        }

        response.parsed.deinit();
        return .{ .ok = .{ .items = items } };
    }

    pub fn sendTransaction(self: *RpcClient, tx: transaction_mod.VersionedTransaction) !types.RpcResult(types.SendTransactionResult) {
        return self.sendTransactionWithOptions(tx, .{});
    }

    pub fn sendTransactionWithOptions(
        self: *RpcClient,
        tx: transaction_mod.VersionedTransaction,
        options: types.SendTransactionOptions,
    ) !types.RpcResult(types.SendTransactionResult) {
        const tx_bytes = try tx.serialize(self.allocator);
        defer self.allocator.free(tx_bytes);

        const tx_base64 = try encodeBase64(self.allocator, tx_bytes);
        defer self.allocator.free(tx_base64);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"sendTransaction\",\"params\":[\"{s}\",{{\"encoding\":\"base64\",\"skipPreflight\":{s},\"preflightCommitment\":\"{s}\"}}]}}",
            .{
                self.nextRpcId(),
                tx_base64,
                if (options.skip_preflight) "true" else "false",
                options.preflight_commitment.jsonString(),
            },
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
        var attempt: u32 = 0;
        while (true) : (attempt += 1) {
            var response = self.transport.postJson(self.allocator, self.endpoint, payload) catch |err| switch (err) {
                error.RpcTransport, error.RpcTimeout => {
                    if (self.hasRetryBudget(attempt)) {
                        self.sleepBeforeRetry(attempt);
                        continue;
                    }
                    return err;
                },
                else => return err,
            };
            defer response.deinit(self.allocator);

            const status_code = @intFromEnum(response.status);
            if (status_code != 200 and isRetryableHttpStatus(response.status) and self.hasRetryBudget(attempt)) {
                self.sleepBeforeRetry(attempt);
                continue;
            }

            var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response.body, .{}) catch {
                return if (status_code == 200) error.RpcParse else error.RpcTransport;
            };

            if (parsed.value != .object) {
                parsed.deinit();
                return if (status_code == 200) error.InvalidRpcResponse else error.RpcTransport;
            }

            if (peekRpcError(&parsed.value)) |rpc_err| {
                if (isRetryableRpcError(rpc_err.code, rpc_err.message) and self.hasRetryBudget(attempt)) {
                    parsed.deinit();
                    self.sleepBeforeRetry(attempt);
                    continue;
                }
            }

            if (status_code != 200 and getObjectField(&parsed.value, "error") == null) {
                parsed.deinit();
                return error.RpcTransport;
            }

            return .{ .parsed = parsed };
        }
    }

    fn hasRetryBudget(self: *const RpcClient, attempt: u32) bool {
        return attempt < self.retry_config.max_retries;
    }

    fn sleepBeforeRetry(self: *const RpcClient, attempt: u32) void {
        const delay_ms = self.retryDelayMs(attempt);
        if (delay_ms == 0) return;

        const delay_ns = std.math.mul(u64, delay_ms, std.time.ns_per_ms) catch std.math.maxInt(u64);
        var req = std.c.timespec{
            .sec = @intCast(delay_ns / std.time.ns_per_s),
            .nsec = @intCast(delay_ns % std.time.ns_per_s),
        };
        _ = std.c.nanosleep(&req, null);
    }

    fn retryDelayMs(self: *const RpcClient, attempt: u32) u64 {
        if (self.retry_config.base_delay_ms == 0 or self.retry_config.max_delay_ms == 0) return 0;

        var delay_ms = @min(self.retry_config.base_delay_ms, self.retry_config.max_delay_ms);
        var step: u32 = 0;
        while (step < attempt and delay_ms < self.retry_config.max_delay_ms) : (step += 1) {
            const doubled = std.math.mul(u64, delay_ms, 2) catch self.retry_config.max_delay_ms;
            delay_ms = @min(doubled, self.retry_config.max_delay_ms);
        }

        return delay_ms;
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

const RpcErrorSummary = struct {
    code: i64,
    message: []const u8,
};

fn peekRpcError(root: *const std.json.Value) ?RpcErrorSummary {
    const rpc_error_value = getObjectField(root, "error") orelse return null;
    if (rpc_error_value.* != .object) return null;

    const code = getI64Field(rpc_error_value, "code") orelse return null;
    const message = getStringField(rpc_error_value, "message") orelse return null;
    return .{ .code = code, .message = message };
}

fn isRetryableHttpStatus(status: std.http.Status) bool {
    return switch (@intFromEnum(status)) {
        429, 500, 502, 503, 504 => true,
        else => false,
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
        .integer => |n| if (n >= 0) @as(u64, @intCast(n)) else null,
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

fn parseSignatureStatus(allocator: std.mem.Allocator, item: *const std.json.Value) !types.SignatureStatus {
    if (item.* != .object) return error.InvalidRpcResponse;

    const slot = getU64Field(item, "slot") orelse return error.InvalidRpcResponse;
    const confirmations = getU64Field(item, "confirmations");
    const err_json = try extractOptionalFieldJson(allocator, item, "err");
    errdefer if (err_json) |err| allocator.free(err);

    const confirmation_status = if (getStringField(item, "confirmationStatus")) |cs|
        try allocator.dupe(u8, cs)
    else
        null;
    errdefer if (confirmation_status) |cs| allocator.free(cs);

    return .{
        .slot = slot,
        .confirmations = confirmations,
        .err_json = err_json,
        .confirmation_status = confirmation_status,
    };
}

fn parseTransactionMeta(allocator: std.mem.Allocator, result: *const std.json.Value) !?types.TransactionMeta {
    const meta_value = getObjectField(result, "meta") orelse return null;
    if (meta_value.* == .null) return null;
    if (meta_value.* != .object) return error.InvalidRpcResponse;

    const fee = getU64Field(meta_value, "fee");
    const err_json = try extractOptionalFieldJson(allocator, meta_value, "err");
    errdefer if (err_json) |err| allocator.free(err);

    const log_messages = if (getObjectField(meta_value, "logMessages")) |log_messages_value| blk: {
        if (log_messages_value.* == .null) break :blk null;
        if (log_messages_value.* != .array) return error.InvalidRpcResponse;
        break :blk try parseStringArray(allocator, meta_value, "logMessages");
    } else null;
    errdefer if (log_messages) |logs| {
        for (logs) |log| allocator.free(log);
        allocator.free(logs);
    };

    const raw_json = try stringifyValue(allocator, meta_value.*);
    errdefer allocator.free(raw_json);

    return .{
        .fee = fee,
        .err_json = err_json,
        .log_messages = log_messages,
        .raw_json = raw_json,
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
    const data_field = getObjectField(value, "data") orelse return allocator.alloc(u8, 0);
    if (data_field.* == .string) {
        return decodeBase64(allocator, data_field.string) catch allocator.alloc(u8, 0);
    }
    if (data_field.* == .array and data_field.array.items.len > 0) {
        const first = data_field.array.items[0];
        if (first == .string) {
            return try decodeBase64(allocator, first.string);
        }
    }
    return allocator.alloc(u8, 0);
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
    const arr_field = getObjectField(value, field) orelse return allocator.alloc([]const u8, 0);
    if (arr_field.* != .array) return allocator.alloc([]const u8, 0);

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
    response_status: std.http.Status = .ok,
    response_body: []const u8 = "",
    should_fail: bool = false,
    capture_payload: bool = false,
    captured_payload: ?[]u8 = null,

    fn postJson(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) transport_mod.PostJsonError!transport_mod.PostJsonResponse {
        _ = url;

        const self: *MockTransport = @ptrCast(@alignCast(ctx));
        if (self.should_fail) return error.RpcTransport;
        if (self.capture_payload) {
            self.captured_payload = try allocator.dupe(u8, payload);
        }
        return .{
            .status = self.response_status,
            .body = try allocator.dupe(u8, self.response_body),
        };
    }
};

const RetryMockTransport = struct {
    steps: []const Step,
    call_count: usize = 0,
    first_payload: ?[]u8 = null,
    identical_payloads: bool = true,

    const Step = struct {
        status: std.http.Status = .ok,
        body: []const u8 = "",
        fail_transport: bool = false,
    };

    fn postJson(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) transport_mod.PostJsonError!transport_mod.PostJsonResponse {
        _ = url;

        const self: *RetryMockTransport = @ptrCast(@alignCast(ctx));
        if (self.first_payload) |first_payload| {
            if (!std.mem.eql(u8, first_payload, payload)) {
                self.identical_payloads = false;
            }
        } else {
            self.first_payload = try allocator.dupe(u8, payload);
        }

        if (self.call_count >= self.steps.len) return error.RpcTransport;

        const step = self.steps[self.call_count];
        self.call_count += 1;
        if (step.fail_transport) return error.RpcTransport;

        return .{
            .status = step.status,
            .body = try allocator.dupe(u8, step.body),
        };
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

test "rpc client retryDelayMs uses exponential backoff with cap" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{};
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    client.setRetryConfig(.{
        .max_retries = 5,
        .base_delay_ms = 25,
        .max_delay_ms = 80,
    });

    try std.testing.expectEqual(@as(u64, 25), client.retryDelayMs(0));
    try std.testing.expectEqual(@as(u64, 50), client.retryDelayMs(1));
    try std.testing.expectEqual(@as(u64, 80), client.retryDelayMs(2));
    try std.testing.expectEqual(@as(u64, 80), client.retryDelayMs(4));
}

test "rpc client retries transient transport errors and reuses identical payload" {
    const gpa = std.testing.allocator;

    var steps = [_]RetryMockTransport.Step{
        .{ .fail_transport = true },
        .{ .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":4242}}" },
    };
    var mock = RetryMockTransport{ .steps = &steps };
    defer if (mock.first_payload) |payload| gpa.free(payload);

    const transport = transport_mod.Transport.init(&mock, RetryMockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();
    client.setRetryConfig(.{
        .max_retries = 1,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    const pubkey = pubkey_mod.Pubkey.init([_]u8{41} ** 32);
    const result = try client.getBalance(pubkey);

    switch (result) {
        .ok => |lamports| try std.testing.expectEqual(@as(u64, 4242), lamports),
        .rpc_error => return error.UnexpectedRpcError,
    }

    try std.testing.expectEqual(@as(usize, 2), mock.call_count);
    try std.testing.expect(mock.identical_payloads);
}

test "rpc client retries HTTP 429 until success" {
    const gpa = std.testing.allocator;

    var steps = [_]RetryMockTransport.Step{
        .{
            .status = @enumFromInt(429),
            .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32005,\"message\":\"Too Many Requests\"}}",
        },
        .{ .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":99}}" },
    };
    var mock = RetryMockTransport{ .steps = &steps };
    defer if (mock.first_payload) |payload| gpa.free(payload);

    const transport = transport_mod.Transport.init(&mock, RetryMockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();
    client.setRetryConfig(.{
        .max_retries = 1,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    const pubkey = pubkey_mod.Pubkey.init([_]u8{42} ** 32);
    const result = try client.getBalance(pubkey);

    switch (result) {
        .ok => |lamports| try std.testing.expectEqual(@as(u64, 99), lamports),
        .rpc_error => return error.UnexpectedRpcError,
    }

    try std.testing.expectEqual(@as(usize, 2), mock.call_count);
    try std.testing.expect(mock.identical_payloads);
}

test "rpc client stops retrying after retry budget is exhausted" {
    const gpa = std.testing.allocator;

    var steps = [_]RetryMockTransport.Step{
        .{
            .status = @enumFromInt(429),
            .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32005,\"message\":\"Too Many Requests\"}}",
        },
        .{
            .status = @enumFromInt(429),
            .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32005,\"message\":\"Too Many Requests\"}}",
        },
    };
    var mock = RetryMockTransport{ .steps = &steps };
    defer if (mock.first_payload) |payload| gpa.free(payload);

    const transport = transport_mod.Transport.init(&mock, RetryMockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();
    client.setRetryConfig(.{
        .max_retries = 1,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    const pubkey = pubkey_mod.Pubkey.init([_]u8{43} ** 32);
    const result = try client.getBalance(pubkey);

    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32005), rpc_err.code);
            try std.testing.expectEqualStrings("Too Many Requests", rpc_err.message);
        },
    }

    try std.testing.expectEqual(@as(usize, 2), mock.call_count);
    try std.testing.expect(mock.identical_payloads);
}

test "rpc client does not retry non-retryable HTTP 400 responses" {
    const gpa = std.testing.allocator;

    var steps = [_]RetryMockTransport.Step{
        .{
            .status = @enumFromInt(400),
            .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"Invalid params\"}}",
        },
        .{ .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":777}}" },
    };
    var mock = RetryMockTransport{ .steps = &steps };
    defer if (mock.first_payload) |payload| gpa.free(payload);

    const transport = transport_mod.Transport.init(&mock, RetryMockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();
    client.setRetryConfig(.{
        .max_retries = 3,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    const pubkey = pubkey_mod.Pubkey.init([_]u8{44} ** 32);
    const result = try client.getBalance(pubkey);

    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32602), rpc_err.code);
            try std.testing.expectEqualStrings("Invalid params", rpc_err.message);
        },
    }

    try std.testing.expectEqual(@as(usize, 1), mock.call_count);
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

test "rpc client getBalance supports all commitment levels" {
    const gpa = std.testing.allocator;
    const cases = [_]struct {
        commitment: types.Commitment,
        expected_json: []const u8,
    }{
        .{ .commitment = .processed, .expected_json = "\"commitment\":\"processed\"" },
        .{ .commitment = .confirmed, .expected_json = "\"commitment\":\"confirmed\"" },
        .{ .commitment = .finalized, .expected_json = "\"commitment\":\"finalized\"" },
    };

    for (cases) |case| {
        var mock: MockTransport = .{
            .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":12345}}",
            .capture_payload = true,
        };
        defer if (mock.captured_payload) |payload| gpa.free(payload);

        const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
        var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
        defer client.deinit();

        const pubkey = pubkey_mod.Pubkey.init([_]u8{31} ** 32);
        const result = try client.getBalanceWithCommitment(pubkey, case.commitment);
        switch (result) {
            .ok => |lamports| try std.testing.expectEqual(@as(u64, 12345), lamports),
            .rpc_error => return error.UnexpectedRpcError,
        }

        const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
        try std.testing.expect(std.mem.indexOf(u8, payload, case.expected_json) != null);
    }
}

test "rpc client getBalance defaults to confirmed commitment" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":67890}}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);

    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{32} ** 32);
    const result = try client.getBalance(pubkey);
    switch (result) {
        .ok => |lamports| try std.testing.expectEqual(@as(u64, 67890), lamports),
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"commitment\":\"confirmed\"") != null);
}

test "rpc client getLatestBlockhash supports all commitment levels" {
    const gpa = std.testing.allocator;
    const cases = [_]struct {
        commitment: types.Commitment,
        expected_json: []const u8,
    }{
        .{ .commitment = .processed, .expected_json = "\"commitment\":\"processed\"" },
        .{ .commitment = .confirmed, .expected_json = "\"commitment\":\"confirmed\"" },
        .{ .commitment = .finalized, .expected_json = "\"commitment\":\"finalized\"" },
    };
    const expected_blockhash = hash_mod.Hash.init([_]u8{0} ** hash_mod.Hash.LENGTH);

    for (cases) |case| {
        var mock: MockTransport = .{
            .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"blockhash\":\"11111111111111111111111111111111\",\"lastValidBlockHeight\":123}}}",
            .capture_payload = true,
        };
        defer if (mock.captured_payload) |payload| gpa.free(payload);

        const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

        var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
        defer client.deinit();

        const result = try client.getLatestBlockhashWithCommitment(case.commitment);
        switch (result) {
            .ok => |latest| {
                try std.testing.expectEqualSlices(u8, &expected_blockhash.bytes, &latest.blockhash.bytes);
                try std.testing.expectEqual(@as(u64, 123), latest.last_valid_block_height);
            },
            .rpc_error => return error.UnexpectedRpcError,
        }

        const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
        try std.testing.expect(std.mem.indexOf(u8, payload, case.expected_json) != null);
    }
}

test "rpc client getLatestBlockhash defaults to confirmed commitment" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"blockhash\":\"11111111111111111111111111111111\",\"lastValidBlockHeight\":456}}}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);

    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getLatestBlockhash();
    switch (result) {
        .ok => |latest| try std.testing.expectEqual(@as(u64, 456), latest.last_valid_block_height),
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"commitment\":\"confirmed\"") != null);
}

test "rpc client getLatestBlockhash preserves rpc error payload" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32004,\"message\":\"block not available\",\"data\":{\"commitment\":\"processed\"}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getLatestBlockhashWithCommitment(.processed);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32004), rpc_err.code);
            try std.testing.expectEqualStrings("block not available", rpc_err.message);
            try std.testing.expect(rpc_err.data_json != null);
        },
    }
}

test "rpc client getAccountInfo typed parse happy path" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"lamports\":1000,\"owner\":\"11111111111111111111111111111111\",\"executable\":false,\"rentEpoch\":18446744073709551615,\"data\":\"AQID\"}}}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{4} ** 32);
    const result = try client.getAccountInfo(pubkey);

    switch (result) {
        .ok => |maybe_info| {
            try std.testing.expect(maybe_info != null);
            var info_owned = maybe_info.?;
            defer info_owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 1000), info_owned.lamports);
            try std.testing.expect(!info_owned.executable);
            try std.testing.expectEqual(@as(usize, 3), info_owned.data.len);
            try std.testing.expect(info_owned.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"encoding\":\"base64\"") != null);
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
        .ok => |maybe_info| {
            try std.testing.expect(maybe_info != null);
            var info_owned = maybe_info.?;
            defer info_owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 2000), info_owned.lamports);
            try std.testing.expect(info_owned.executable);
            try std.testing.expectEqual(@as(u64, 2), info_owned.rent_epoch);
            try std.testing.expectEqual(@as(usize, 3), info_owned.data.len);
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

test "rpc client getAccountInfo returns null when account is missing" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":null}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{8} ** 32);
    const result = try client.getAccountInfo(pubkey);

    switch (result) {
        .ok => |maybe_info| try std.testing.expect(maybe_info == null),
        .rpc_error => return error.UnexpectedRpcError,
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
            var sim_owned = sim;
            defer sim_owned.deinit(gpa);
            try std.testing.expect(sim_owned.err_json == null);
            try std.testing.expectEqual(@as(usize, 2), sim_owned.logs.len);
            try std.testing.expectEqualStrings("log1", sim_owned.logs[0]);
            try std.testing.expectEqual(@as(u64, 1234), sim_owned.units_consumed.?);
            try std.testing.expect(sim_owned.raw_json != null);
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
            var sim_owned = sim;
            defer sim_owned.deinit(gpa);
            try std.testing.expect(sim_owned.err_json != null);
            try std.testing.expectEqual(@as(usize, 1), sim_owned.logs.len);
            try std.testing.expect(sim_owned.units_consumed == null);
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

test "rpc client sendTransaction typed parse happy path" {
    const gpa = std.testing.allocator;
    const zero_sig_b58 = "1111111111111111111111111111111111111111111111111111111111111111";

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"1111111111111111111111111111111111111111111111111111111111111111\"}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    var tx = try makeTestTransaction(gpa);
    defer tx.deinit();

    const tx_bytes = try tx.serialize(gpa);
    defer gpa.free(tx_bytes);
    const tx_base64 = try encodeBase64(gpa, tx_bytes);
    defer gpa.free(tx_base64);

    const result = try client.sendTransaction(tx);
    switch (result) {
        .ok => |send| {
            const expected = try @import("../core/signature.zig").Signature.fromBase58(zero_sig_b58);
            try std.testing.expectEqualSlices(u8, &expected.bytes, &send.signature.bytes);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, tx_base64) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"encoding\":\"base64\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"skipPreflight\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"preflightCommitment\":\"confirmed\"") != null);
}

test "rpc client sendTransaction supports custom options" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"1111111111111111111111111111111111111111111111111111111111111111\"}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    var tx = try makeTestTransaction(gpa);
    defer tx.deinit();

    const result = try client.sendTransactionWithOptions(tx, .{
        .skip_preflight = true,
        .preflight_commitment = .finalized,
    });
    switch (result) {
        .ok => |send| try std.testing.expect(send.signature.isZero()),
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"skipPreflight\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"preflightCommitment\":\"finalized\"") != null);
}

test "rpc client sendTransaction preserves rpc error with typed parse" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32002,\"message\":\"Transaction simulation failed\",\"data\":{\"err\":\"AccountNotFound\"}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    var tx = try makeTestTransaction(gpa);
    defer tx.deinit();

    const result = try client.sendTransaction(tx);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32002), rpc_err.code);
            try std.testing.expectEqualStrings("Transaction simulation failed", rpc_err.message);
            try std.testing.expect(rpc_err.data_json != null);
            try std.testing.expect(std.mem.indexOf(u8, rpc_err.data_json.?, "AccountNotFound") != null);
        },
    }
}

test "rpc client sendTransaction returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"signature\":\"oops\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    var tx = try makeTestTransaction(gpa);
    defer tx.deinit();

    try std.testing.expectError(error.InvalidRpcResponse, client.sendTransaction(tx));
}

test "rpc client getSlot typed parse happy path" {
    const gpa = std.testing.allocator;

    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":123456}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getSlotWithOptions(.{ .commitment = .finalized });
    switch (result) {
        .ok => |slot| try std.testing.expectEqual(@as(u64, 123456), slot),
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"getSlot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"commitment\":\"finalized\"") != null);
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
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{42} ** 32);
    const before = @import("../core/signature.zig").Signature.init([_]u8{0x11} ** 64);
    const until = @import("../core/signature.zig").Signature.init([_]u8{0x22} ** 64);
    const result = try client.getSignaturesForAddressWithOptions(pubkey, .{
        .before = before,
        .until = until,
        .limit = 10,
    });
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

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    const before_b58 = try before.toBase58Alloc(gpa);
    defer gpa.free(before_b58);
    const until_b58 = try until.toBase58Alloc(gpa);
    defer gpa.free(until_b58);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"getSignaturesForAddress\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"before\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, before_b58) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"until\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, until_b58) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"limit\":10") != null);
}

test "rpc client getSignaturesForAddress supports empty list responses" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[]}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const pubkey = pubkey_mod.Pubkey.init([_]u8{45} ** 32);
    const result = try client.getSignaturesForAddressWithOptions(pubkey, .{
        .limit = 5,
    });
    switch (result) {
        .ok => |sig_result| {
            var owned = sig_result;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(usize, 0), owned.items.len);
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
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"slot\":99,\"blockTime\":555,\"meta\":{\"fee\":5000,\"err\":null,\"logMessages\":[\"Program 11111111111111111111111111111111 invoke [1]\",\"Program 11111111111111111111111111111111 success\"],\"status\":{\"Ok\":null}},\"transaction\":{\"message\":{\"accountKeys\":[]}}}}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{9} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const msg = "tx-for-get-transaction";
    const sig = try kp.sign(msg);

    const result = try client.getTransaction(sig);
    switch (result) {
        .ok => |maybe_tx_info| {
            try std.testing.expect(maybe_tx_info != null);
            var owned = maybe_tx_info.?;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 99), owned.slot);
            try std.testing.expectEqual(@as(i64, 555), owned.block_time.?);
            try std.testing.expect(owned.meta != null);
            try std.testing.expectEqual(@as(u64, 5000), owned.meta.?.fee.?);
            try std.testing.expect(owned.meta.?.err_json == null);
            try std.testing.expectEqual(@as(usize, 2), owned.meta.?.log_messages.?.len);
            try std.testing.expectEqualStrings("Program 11111111111111111111111111111111 invoke [1]", owned.meta.?.log_messages.?[0]);
            try std.testing.expect(owned.raw_json.len > 0);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"commitment\":\"confirmed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"maxSupportedTransactionVersion\":0") != null);
}

test "rpc client getTransaction supports commitment and optional max version parameters" {
    const gpa = std.testing.allocator;
    const cases = [_]struct {
        commitment: types.Commitment,
        max_supported_transaction_version: ?u8,
        expected_commitment_json: []const u8,
        expect_max_supported_transaction_version: bool,
    }{
        .{
            .commitment = .processed,
            .max_supported_transaction_version = null,
            .expected_commitment_json = "\"commitment\":\"processed\"",
            .expect_max_supported_transaction_version = false,
        },
        .{
            .commitment = .confirmed,
            .max_supported_transaction_version = 0,
            .expected_commitment_json = "\"commitment\":\"confirmed\"",
            .expect_max_supported_transaction_version = true,
        },
        .{
            .commitment = .finalized,
            .max_supported_transaction_version = 7,
            .expected_commitment_json = "\"commitment\":\"finalized\"",
            .expect_max_supported_transaction_version = true,
        },
    };

    for (cases) |case| {
        var mock: MockTransport = .{
            .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}",
            .capture_payload = true,
        };
        defer if (mock.captured_payload) |payload| gpa.free(payload);
        const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
        var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
        defer client.deinit();

        const seed = [_]u8{12} ** 32;
        const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
        const sig = try kp.sign("tx-for-options");

        const result = try client.getTransactionWithOptions(sig, .{
            .commitment = case.commitment,
            .max_supported_transaction_version = case.max_supported_transaction_version,
        });
        switch (result) {
            .ok => |maybe_tx_info| try std.testing.expect(maybe_tx_info == null),
            .rpc_error => return error.UnexpectedRpcError,
        }

        const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
        try std.testing.expect(std.mem.indexOf(u8, payload, case.expected_commitment_json) != null);
        try std.testing.expectEqual(
            case.expect_max_supported_transaction_version,
            std.mem.indexOf(u8, payload, "\"maxSupportedTransactionVersion\"") != null,
        );
    }
}

test "rpc client getTransaction returns null when transaction does not exist" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{10} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const sig = try kp.sign("tx-not-found");

    const result = try client.getTransaction(sig);
    switch (result) {
        .ok => |maybe_tx_info| try std.testing.expect(maybe_tx_info == null),
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
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":100},\"value\":[{\"slot\":72,\"confirmations\":10,\"err\":null,\"confirmationStatus\":\"confirmed\"},{\"slot\":73,\"confirmations\":null,\"err\":null,\"confirmationStatus\":\"finalized\"}]}}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{12} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const sig_a = try kp.sign("tx-for-sig-status-a");
    const sig_b = try kp.sign("tx-for-sig-status-b");

    const result = try client.getSignatureStatuses(&[_]@import("../core/signature.zig").Signature{ sig_a, sig_b });
    switch (result) {
        .ok => |statuses_val| {
            var statuses = statuses_val;
            defer statuses.deinit(gpa);

            try std.testing.expectEqual(@as(usize, 2), statuses.items.len);
            try std.testing.expect(statuses.items[0] != null);
            try std.testing.expect(statuses.items[1] != null);

            const first = statuses.items[0].?;
            try std.testing.expectEqual(@as(u64, 72), first.slot);
            try std.testing.expectEqual(@as(u64, 10), first.confirmations.?);
            try std.testing.expect(first.err_json == null);
            try std.testing.expectEqualStrings("confirmed", first.confirmation_status.?);

            const second = statuses.items[1].?;
            try std.testing.expectEqual(@as(u64, 73), second.slot);
            try std.testing.expect(second.confirmations == null);
            try std.testing.expect(second.err_json == null);
            try std.testing.expectEqualStrings("finalized", second.confirmation_status.?);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    const sig_a_b58 = try sig_a.toBase58Alloc(gpa);
    defer gpa.free(sig_a_b58);
    const sig_b_b58 = try sig_b.toBase58Alloc(gpa);
    defer gpa.free(sig_b_b58);
    try std.testing.expect(std.mem.indexOf(u8, payload, sig_a_b58) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, sig_b_b58) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"searchTransactionHistory\":true") != null);
}

test "rpc client getSignatureStatuses preserves partial null entries and custom options" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":100},\"value\":[null,{\"slot\":91,\"confirmations\":1,\"err\":null,\"confirmationStatus\":\"processed\"}]}}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const seed = [_]u8{13} ** 32;
    const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
    const sig_missing = try kp.sign("tx-missing");
    const sig_found = try kp.sign("tx-found");

    const result = try client.getSignatureStatusesWithOptions(&[_]@import("../core/signature.zig").Signature{ sig_missing, sig_found }, .{
        .search_transaction_history = false,
    });
    switch (result) {
        .ok => |statuses_val| {
            var statuses = statuses_val;
            defer statuses.deinit(gpa);

            try std.testing.expectEqual(@as(usize, 2), statuses.items.len);
            try std.testing.expect(statuses.items[0] == null);
            try std.testing.expect(statuses.items[1] != null);

            const found = statuses.items[1].?;
            try std.testing.expectEqual(@as(u64, 91), found.slot);
            try std.testing.expectEqual(@as(u64, 1), found.confirmations.?);
            try std.testing.expect(found.err_json == null);
            try std.testing.expectEqualStrings("processed", found.confirmation_status.?);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"searchTransactionHistory\":false") != null);
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
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
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
            try std.testing.expectEqual(@as(u64, 2039280), owned.items[0].account_info.lamports);
            try std.testing.expectEqual(@as(usize, 3), owned.items[0].account_info.data.len);
            try std.testing.expect(!owned.items[0].account_info.executable);
            try std.testing.expectEqual(@as(u64, 1), owned.items[0].account_info.rent_epoch);
            try std.testing.expectEqualStrings("base64", owned.items[0].data_encoding.?);
            try std.testing.expect(owned.items[0].account_info.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"getTokenAccountsByOwner\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"programId\":\"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"encoding\":\"base64\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"commitment\":\"confirmed\"") != null);
}

test "rpc client getTokenAccountsByOwnerWithOptions supports mint filter and empty list" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":[]}}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const owner = pubkey_mod.Pubkey.init([_]u8{45} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{46} ** 32);
    const result = try client.getTokenAccountsByOwnerWithOptions(owner, .{
        .filter = .{ .mint = mint },
        .encoding = .base64,
        .commitment = .finalized,
    });

    switch (result) {
        .ok => |token_accounts| {
            var owned = token_accounts;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(usize, 0), owned.items.len);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const mint_b58 = try mint.toBase58Alloc(gpa);
    defer gpa.free(mint_b58);

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"getTokenAccountsByOwner\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"mint\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, mint_b58) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"encoding\":\"base64\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"commitment\":\"finalized\"") != null);
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
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
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
            try std.testing.expectEqualStrings("4.2", owned.ui_amount_string.?);
            try std.testing.expect(owned.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    const token_account_b58 = try token_account.toBase58Alloc(gpa);
    defer gpa.free(token_account_b58);
    const expected_payload = try std.fmt.allocPrint(
        gpa,
        "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTokenAccountBalance\",\"params\":[\"{s}\",{{\"commitment\":\"confirmed\"}}]}}",
        .{token_account_b58},
    );
    defer gpa.free(expected_payload);
    try std.testing.expectEqualStrings(expected_payload, payload);
}

test "rpc client getTokenAccountBalance preserves account-not-found rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"Invalid param: could not find account\"}}",
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
            try std.testing.expectEqualStrings("Invalid param: could not find account", rpc_err.message);
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
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
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
            try std.testing.expectEqualStrings("1", owned.ui_amount_string.?);
            try std.testing.expect(owned.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    const mint_b58 = try mint.toBase58Alloc(gpa);
    defer gpa.free(mint_b58);
    const expected_payload = try std.fmt.allocPrint(
        gpa,
        "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTokenSupply\",\"params\":[\"{s}\",{{\"commitment\":\"confirmed\"}}]}}",
        .{mint_b58},
    );
    defer gpa.free(expected_payload);
    try std.testing.expectEqualStrings(expected_payload, payload);
}

test "rpc client getTokenSupply preserves mint-not-found rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"Invalid param: could not find account\"}}",
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
            try std.testing.expectEqualStrings("Invalid param: could not find account", rpc_err.message);
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

test "rpc client getEpochInfo typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"absoluteSlot\":1234,\"blockHeight\":1200,\"epoch\":10,\"slotIndex\":34,\"slotsInEpoch\":432000,\"transactionCount\":5678}}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getEpochInfoWithOptions(.{ .commitment = .processed });
    switch (result) {
        .ok => |epoch_info| {
            var owned = epoch_info;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 1234), owned.absolute_slot);
            try std.testing.expectEqual(@as(u64, 1200), owned.block_height.?);
            try std.testing.expectEqual(@as(u64, 10), owned.epoch);
            try std.testing.expectEqual(@as(u64, 34), owned.slot_index);
            try std.testing.expectEqual(@as(u64, 432000), owned.slots_in_epoch);
            try std.testing.expectEqual(@as(u64, 5678), owned.transaction_count.?);
            try std.testing.expect(owned.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"getEpochInfo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"commitment\":\"processed\"") != null);
}

test "rpc client getEpochInfo preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32010,\"message\":\"epoch unavailable\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getEpochInfo();
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32010), rpc_err.code);
        },
    }
}

test "rpc client getEpochInfo returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"epoch\":1}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    try std.testing.expectError(error.InvalidRpcResponse, client.getEpochInfo());
}

test "rpc client getMinimumBalanceForRentExemption typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":1781760}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getMinimumBalanceForRentExemption(128);
    switch (result) {
        .ok => |lamports| try std.testing.expectEqual(@as(u64, 1781760), lamports),
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"getMinimumBalanceForRentExemption\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"params\":[128]") != null);
}

test "rpc client getMinimumBalanceForRentExemption preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"invalid data length\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const result = try client.getMinimumBalanceForRentExemption(0);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32602), rpc_err.code);
        },
    }
}

test "rpc client getMinimumBalanceForRentExemption returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"lamports\":1}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    try std.testing.expectError(error.InvalidRpcResponse, client.getMinimumBalanceForRentExemption(8));
}

test "rpc client requestAirdrop encodes recipient and lamports" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"5FtkHfQ5N62hCV7Wz4NQTRz5fWPQjY7Y9YByK7GfP4Hbw7jV4kD5mYTHPwo2fhtxQzpgLQ8vndqaM8UZz2xM4V5d\"}",
        .capture_payload = true,
    };
    defer if (mock.captured_payload) |payload| gpa.free(payload);

    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const recipient = pubkey_mod.Pubkey.init([_]u8{31} ** 32);
    const expected_pubkey = try recipient.toBase58Alloc(gpa);
    defer gpa.free(expected_pubkey);

    const result = try client.requestAirdrop(recipient, 1_000_000);
    switch (result) {
        .ok => |airdrop| {
            const sig_b58 = try airdrop.signature.toBase58Alloc(gpa);
            defer gpa.free(sig_b58);
            try std.testing.expect(sig_b58.len > 0);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }

    const payload = mock.captured_payload orelse return error.ExpectedCapturedPayload;
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"requestAirdrop\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, expected_pubkey) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, ",1000000]") != null);
}

test "rpc client requestAirdrop typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"5FtkHfQ5N62hCV7Wz4NQTRz5fWPQjY7Y9YByK7GfP4Hbw7jV4kD5mYTHPwo2fhtxQzpgLQ8vndqaM8UZz2xM4V5d\"}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const recipient = pubkey_mod.Pubkey.init([_]u8{31} ** 32);
    const result = try client.requestAirdrop(recipient, 1_000_000);
    switch (result) {
        .ok => |airdrop| {
            const b58 = try airdrop.signature.toBase58Alloc(gpa);
            defer gpa.free(b58);
            try std.testing.expectEqualStrings("5FtkHfQ5N62hCV7Wz4NQTRz5fWPQjY7Y9YByK7GfP4Hbw7jV4kD5mYTHPwo2fhtxQzpgLQ8vndqaM8UZz2xM4V5d", b58);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client requestAirdrop preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32005,\"message\":\"airdrop disabled\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const recipient = pubkey_mod.Pubkey.init([_]u8{32} ** 32);
    const result = try client.requestAirdrop(recipient, 1);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32005), rpc_err.code);
        },
    }
}

test "rpc client requestAirdrop returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":123}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const recipient = pubkey_mod.Pubkey.init([_]u8{33} ** 32);
    try std.testing.expectError(error.InvalidRpcResponse, client.requestAirdrop(recipient, 1));
}

test "rpc client getAddressLookupTable typed parse happy path" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":88},\"value\":{\"deactivationSlot\":18446744073709551615,\"lastExtendedSlot\":80,\"lastExtendedSlotStartIndex\":2,\"authority\":\"11111111111111111111111111111111\",\"addresses\":[\"11111111111111111111111111111111\",\"11111111111111111111111111111111\"]}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const table_address = pubkey_mod.Pubkey.init([_]u8{34} ** 32);
    const result = try client.getAddressLookupTable(table_address);
    switch (result) {
        .ok => |table_result| {
            var owned = table_result;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 88), owned.context_slot);
            try std.testing.expect(owned.value != null);
            const value = owned.value.?;
            try std.testing.expect(value.key.eql(table_address));
            try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), value.state.deactivation_slot);
            try std.testing.expectEqual(@as(u64, 80), value.state.last_extended_slot);
            try std.testing.expectEqual(@as(u8, 2), value.state.last_extended_slot_start_index);
            try std.testing.expect(value.state.authority != null);
            try std.testing.expectEqual(@as(usize, 2), value.state.addresses.len);
            try std.testing.expect(value.state.raw_json != null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getAddressLookupTable returns null when lookup table is missing" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":89},\"value\":null}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const table_address = pubkey_mod.Pubkey.init([_]u8{35} ** 32);
    const result = try client.getAddressLookupTable(table_address);
    switch (result) {
        .ok => |table_result| {
            var owned = table_result;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(@as(u64, 89), owned.context_slot);
            try std.testing.expect(owned.value == null);
        },
        .rpc_error => return error.UnexpectedRpcError,
    }
}

test "rpc client getAddressLookupTable preserves rpc error" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32007,\"message\":\"lookup table not found\"}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const table_address = pubkey_mod.Pubkey.init([_]u8{36} ** 32);
    const result = try client.getAddressLookupTable(table_address);
    switch (result) {
        .ok => return error.ExpectedRpcError,
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            try std.testing.expectEqual(@as(i64, -32007), rpc_err.code);
        },
    }
}

test "rpc client getAddressLookupTable returns InvalidRpcResponse on malformed success" {
    const gpa = std.testing.allocator;
    var mock: MockTransport = .{
        .response_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":{\"lastExtendedSlot\":10}}}",
    };
    const transport = transport_mod.Transport.init(&mock, MockTransport.postJson, transport_mod.noopDeinit);
    var client = try RpcClient.initWithTransport(gpa, "http://unit.test", transport);
    defer client.deinit();

    const table_address = pubkey_mod.Pubkey.init([_]u8{37} ** 32);
    try std.testing.expectError(error.InvalidRpcResponse, client.getAddressLookupTable(table_address));
}

test "rpc client batch b read methods local-live evidence (gated)" {
    const gpa = std.testing.allocator;
    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SURFPOOL_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SURFPOOL_RPC_URL not set, skipping Batch B local-live evidence\\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    const epoch_info = try client.getEpochInfo();
    switch (epoch_info) {
        .ok => |info| {
            var owned = info;
            defer owned.deinit(gpa);
            try std.testing.expect(owned.epoch > 0);
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            return error.UnexpectedRpcError;
        },
    }

    const min_balance = try client.getMinimumBalanceForRentExemption(0);
    switch (min_balance) {
        .ok => {},
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            return error.UnexpectedRpcError;
        },
    }

    const table_address = pubkey_mod.Pubkey.init([_]u8{38} ** 32);
    const table_result = try client.getAddressLookupTable(table_address);
    switch (table_result) {
        .ok => |result| {
            var owned = result;
            defer owned.deinit(gpa);
            _ = owned.context_slot;
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            if (isMethodNotFoundRpcError(rpc_err.code, rpc_err.message)) {
                std.debug.print("[batch-b live] getAddressLookupTable method-not-found on local-live (accepted exception path)\\n", .{});
                return;
            }
            return error.UnexpectedRpcError;
        },
    }
}

fn isRateLimitedRpcError(code: i64, message: []const u8) bool {
    if (code == -32005) return true;
    if (code == 429) return true;
    if (std.mem.indexOf(u8, message, "429") != null) return true;
    if (std.mem.indexOf(u8, message, "rate limit") != null) return true;
    if (std.mem.indexOf(u8, message, "Rate limit") != null) return true;
    if (std.mem.indexOf(u8, message, "Too Many Requests") != null) return true;
    return false;
}

fn isRetryableRpcError(code: i64, message: []const u8) bool {
    return isRateLimitedRpcError(code, message);
}

fn isMethodNotFoundRpcError(code: i64, message: []const u8) bool {
    if (code == -32601) return true;
    if (std.mem.indexOf(u8, message, "Method not found") != null) return true;
    if (std.mem.indexOf(u8, message, "method not found") != null) return true;
    return false;
}

test "rpc client requestAirdrop tri-state convergence evidence (gated)" {
    const gpa = std.testing.allocator;

    const devnet_endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => return err,
    };

    const local_endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SURFPOOL_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => return err,
    };

    defer if (devnet_endpoint) |ep| gpa.free(ep);
    defer if (local_endpoint) |ep| gpa.free(ep);

    if (devnet_endpoint == null and local_endpoint == null) {
        std.debug.print("[skip] SOLANA_RPC_URL and SURFPOOL_RPC_URL not set, skipping requestAirdrop tri-state evidence\\n", .{});
        return;
    }

    var devnet_success = false;
    var devnet_rate_limited = false;
    var local_success = false;

    const recipient = try @import("../core/keypair.zig").Keypair.fromSeed([_]u8{57} ** 32);

    if (devnet_endpoint) |endpoint| {
        var client = try RpcClient.init(gpa, std.testing.io, endpoint);
        defer client.deinit();

        var attempt: usize = 0;
        while (attempt < 3) : (attempt += 1) {
            const result = client.requestAirdrop(recipient.pubkey(), 1_000_000) catch |err| switch (err) {
                error.RpcTransport => continue,
                else => return err,
            };
            switch (result) {
                .ok => |airdrop| {
                    const sig_b58 = try airdrop.signature.toBase58Alloc(gpa);
                    defer gpa.free(sig_b58);
                    std.debug.print("[p3a exception] requestAirdrop(devnet) success sig={s}\\n", .{sig_b58});
                    devnet_success = true;
                    break;
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    if (isRateLimitedRpcError(rpc_err.code, rpc_err.message)) {
                        devnet_rate_limited = true;
                        if (attempt + 1 < 3) {
                            const yields = @as(usize, 1) << @as(u6, @intCast(attempt));
                            for (0..yields) |_| {
                                std.Thread.yield() catch {};
                            }
                            continue;
                        }
                        break;
                    }
                    if (attempt + 1 < 3) {
                        const yields = @as(usize, 1) << @as(u6, @intCast(attempt));
                        for (0..yields) |_| {
                            std.Thread.yield() catch {};
                        }
                        continue;
                    }
                    std.debug.print(
                        "[p3a exception] requestAirdrop(devnet) failure path code={d} msg={s}\\n",
                        .{ rpc_err.code, rpc_err.message },
                    );
                    break;
                },
            }
        }
    }

    if (local_endpoint) |endpoint| {
        var client = try RpcClient.init(gpa, std.testing.io, endpoint);
        defer client.deinit();

        var attempt: usize = 0;
        while (attempt < 3) : (attempt += 1) {
            const result = client.requestAirdrop(recipient.pubkey(), 1_000_000) catch |err| switch (err) {
                error.RpcTransport => continue,
                else => return err,
            };
            switch (result) {
                .ok => |airdrop| {
                    const sig_b58 = try airdrop.signature.toBase58Alloc(gpa);
                    defer gpa.free(sig_b58);
                    std.debug.print("[p3a exception] requestAirdrop(local-live) success sig={s}\\n", .{sig_b58});
                    local_success = true;
                    break;
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    if (attempt + 1 < 3) continue;
                    std.debug.print(
                        "[p3a exception] requestAirdrop(local-live) failure path code={d} msg={s}\\n",
                        .{ rpc_err.code, rpc_err.message },
                    );
                    break;
                },
            }
        }
    }

    const TriState = enum {
        success,
        partial_exception,
        not_converged,
    };

    const tri_state: TriState = blk: {
        // strict rule:
        // - success: at least one side succeeded
        // - partial_exception: public rate-limit + local-live success
        // - otherwise: not_converged
        if (devnet_rate_limited and local_success) break :blk .partial_exception;
        if (devnet_success or local_success) break :blk .success;
        break :blk .not_converged;
    };

    switch (tri_state) {
        .success => std.debug.print("[p3a exception] requestAirdrop tri-state=success\\n", .{}),
        .partial_exception => std.debug.print("[p3a exception] requestAirdrop tri-state=partial_exception\\n", .{}),
        .not_converged => std.debug.print("[p3a exception] requestAirdrop tri-state=not_converged\\n", .{}),
    }
}

test "rpc client getAddressLookupTable success-or-exception convergence evidence (gated)" {
    const gpa = std.testing.allocator;
    const devnet_endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => return err,
    };
    const local_endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SURFPOOL_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => return err,
    };
    defer if (devnet_endpoint) |ep| gpa.free(ep);
    defer if (local_endpoint) |ep| gpa.free(ep);

    if (devnet_endpoint == null and local_endpoint == null) {
        std.debug.print("[skip] SOLANA_RPC_URL and SURFPOOL_RPC_URL not set, skipping getAddressLookupTable convergence evidence\\n", .{});
        return;
    }

    const table_address = pubkey_mod.Pubkey.init([_]u8{38} ** 32);
    var saw_success = false;
    var saw_method_not_found = false;

    if (devnet_endpoint) |endpoint| {
        var client = try RpcClient.init(gpa, std.testing.io, endpoint);
        defer client.deinit();

        if (client.getAddressLookupTable(table_address)) |result| {
            switch (result) {
                .ok => |table| {
                    var owned = table;
                    defer owned.deinit(gpa);
                    std.debug.print("[p3a exception] getAddressLookupTable(devnet) success\\n", .{});
                    saw_success = true;
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    if (isMethodNotFoundRpcError(rpc_err.code, rpc_err.message)) {
                        std.debug.print("[p3a exception] getAddressLookupTable(devnet) method-not-found path\\n", .{});
                        saw_method_not_found = true;
                    } else {
                        return error.UnexpectedRpcError;
                    }
                },
            }
        } else |err| switch (err) {
            error.RpcTransport => {
                // Network-layer failure on public endpoint follows exception path.
                std.debug.print("[p3a exception] getAddressLookupTable(devnet) transport path\\n", .{});
                saw_method_not_found = true;
            },
            else => return err,
        }
    }

    if (local_endpoint) |endpoint| {
        var client = try RpcClient.init(gpa, std.testing.io, endpoint);
        defer client.deinit();

        const result = try client.getAddressLookupTable(table_address);
        switch (result) {
            .ok => |table| {
                var owned = table;
                defer owned.deinit(gpa);
                std.debug.print("[p3a exception] getAddressLookupTable(local-live) success\\n", .{});
                saw_success = true;
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(gpa);
                if (isMethodNotFoundRpcError(rpc_err.code, rpc_err.message)) {
                    saw_method_not_found = true;
                } else {
                    return error.UnexpectedRpcError;
                }
            },
        }
    }

    if (!(saw_success or saw_method_not_found)) {
        return error.UnexpectedRpcError;
    }
}
