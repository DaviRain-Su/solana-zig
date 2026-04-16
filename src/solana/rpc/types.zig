const std = @import("std");
const hash_mod = @import("../core/hash.zig");
const signature_mod = @import("../core/signature.zig");
const pubkey_mod = @import("../core/pubkey.zig");

pub const OwnedJson = struct {
    parsed: std.json.Parsed(std.json.Value),
    value: std.json.Value,

    pub fn deinit(self: *OwnedJson) void {
        self.parsed.deinit();
    }
};

pub const LatestBlockhash = struct {
    blockhash: hash_mod.Hash,
    last_valid_block_height: u64,
};

pub const Commitment = enum {
    processed,
    confirmed,
    finalized,

    pub fn jsonString(self: Commitment) []const u8 {
        return @tagName(self);
    }
};

pub const SendTransactionOptions = struct {
    skip_preflight: bool = false,
    preflight_commitment: Commitment = .confirmed,
};

pub const AccountInfo = struct {
    lamports: u64,
    owner: pubkey_mod.Pubkey,
    executable: bool,
    rent_epoch: u64,
    data: []u8,
    raw_json: ?[]const u8 = null,

    pub fn deinit(self: *AccountInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        if (self.raw_json) |raw| allocator.free(raw);
    }
};

pub const SimulateTransactionResult = struct {
    err_json: ?[]const u8,
    logs: [][]const u8,
    units_consumed: ?u64,
    raw_json: ?[]const u8 = null,

    pub fn deinit(self: *SimulateTransactionResult, allocator: std.mem.Allocator) void {
        if (self.err_json) |err| allocator.free(err);
        for (self.logs) |log| allocator.free(log);
        allocator.free(self.logs);
        if (self.raw_json) |raw| allocator.free(raw);
    }
};

pub const RpcErrorObject = struct {
    code: i64,
    message: []const u8,
    data_json: ?[]const u8 = null,

    pub fn deinit(self: RpcErrorObject, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.data_json) |data| allocator.free(data);
    }
};

pub fn RpcResult(comptime T: type) type {
    return union(enum) {
        ok: T,
        rpc_error: RpcErrorObject,
    };
}

pub const SendTransactionResult = struct {
    signature: signature_mod.Signature,
};

pub const SignatureStatusInfo = struct {
    signature: signature_mod.Signature,
    slot: u64,
    err_json: ?[]const u8 = null,
    memo: ?[]const u8 = null,
    block_time: ?i64 = null,
    raw_json: ?[]const u8 = null,

    pub fn deinit(self: *SignatureStatusInfo, allocator: std.mem.Allocator) void {
        if (self.err_json) |err| allocator.free(err);
        if (self.memo) |memo| allocator.free(memo);
        if (self.raw_json) |raw| allocator.free(raw);
    }
};

pub const SignaturesForAddressResult = struct {
    items: []SignatureStatusInfo,

    pub fn deinit(self: *SignaturesForAddressResult, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const SignatureStatus = struct {
    slot: u64,
    confirmations: ?u64 = null,
    err_json: ?[]const u8 = null,
    confirmation_status: ?[]const u8 = null,

    pub fn deinit(self: *SignatureStatus, allocator: std.mem.Allocator) void {
        if (self.err_json) |err| allocator.free(err);
        if (self.confirmation_status) |cs| allocator.free(cs);
    }
};

pub const TransactionInfo = struct {
    slot: u64,
    block_time: ?i64 = null,
    raw_json: []const u8,

    pub fn deinit(self: *TransactionInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.raw_json);
    }
};

pub const EpochInfo = struct {
    absolute_slot: u64,
    block_height: ?u64 = null,
    epoch: u64,
    slot_index: u64,
    slots_in_epoch: u64,
    transaction_count: ?u64 = null,
    raw_json: ?[]const u8 = null,

    pub fn deinit(self: *EpochInfo, allocator: std.mem.Allocator) void {
        if (self.raw_json) |raw| allocator.free(raw);
    }
};

pub const TokenAccountInfo = struct {
    pubkey: pubkey_mod.Pubkey,
    owner: pubkey_mod.Pubkey,
    lamports: u64,
    data: []u8,
    data_encoding: ?[]const u8 = null,
    raw_json: ?[]const u8 = null,

    pub fn deinit(self: *TokenAccountInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        if (self.data_encoding) |encoding| allocator.free(encoding);
        if (self.raw_json) |raw| allocator.free(raw);
    }
};

pub const TokenAccountsByOwnerResult = struct {
    items: []TokenAccountInfo,

    pub fn deinit(self: *TokenAccountsByOwnerResult, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const TokenAmount = struct {
    amount: u64,
    decimals: u8,
    ui_amount_string: []const u8,
    raw_json: ?[]const u8 = null,

    pub fn deinit(self: *TokenAmount, allocator: std.mem.Allocator) void {
        allocator.free(self.ui_amount_string);
        if (self.raw_json) |raw| allocator.free(raw);
    }
};

pub const RequestAirdropResult = struct {
    signature: signature_mod.Signature,
};

pub const AddressLookupTableInfo = struct {
    deactivation_slot: u64,
    last_extended_slot: u64,
    last_extended_slot_start_index: u8,
    authority: ?pubkey_mod.Pubkey = null,
    addresses: []pubkey_mod.Pubkey,
    raw_json: ?[]const u8 = null,

    pub fn deinit(self: *AddressLookupTableInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.addresses);
        if (self.raw_json) |raw| allocator.free(raw);
    }
};

pub const AddressLookupTableResult = struct {
    context_slot: u64,
    value: ?AddressLookupTableInfo,

    pub fn deinit(self: *AddressLookupTableResult, allocator: std.mem.Allocator) void {
        if (self.value) |*v| v.deinit(allocator);
    }
};
