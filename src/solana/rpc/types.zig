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
