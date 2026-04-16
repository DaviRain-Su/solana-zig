const std = @import("std");
const hash_mod = @import("../core/hash.zig");
const signature_mod = @import("../core/signature.zig");

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
