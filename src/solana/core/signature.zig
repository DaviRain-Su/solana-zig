const std = @import("std");
const base58 = @import("base58.zig");
const pubkey_mod = @import("pubkey.zig");

pub const Signature = struct {
    pub const LENGTH: usize = 64;

    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Signature {
        return .{ .bytes = bytes };
    }

    pub fn fromSlice(slice: []const u8) !Signature {
        if (slice.len != LENGTH) return error.InvalidLength;
        var out: [LENGTH]u8 = undefined;
        @memcpy(&out, slice);
        return .{ .bytes = out };
    }

    pub fn fromBase58(input: []const u8) !Signature {
        return .{ .bytes = try base58.decodeFixed(LENGTH, input) };
    }

    pub fn toBase58Alloc(self: Signature, allocator: std.mem.Allocator) ![]u8 {
        return base58.encodeAlloc(allocator, &self.bytes);
    }

    pub fn verify(self: Signature, msg: []const u8, pubkey: pubkey_mod.Pubkey) !void {
        const Ed25519 = std.crypto.sign.Ed25519;
        const pk = try Ed25519.PublicKey.fromBytes(pubkey.bytes);
        const sig = Ed25519.Signature.fromBytes(self.bytes);
        try sig.verify(msg, pk);
    }

    pub fn isZero(self: Signature) bool {
        for (self.bytes) |b| if (b != 0) return false;
        return true;
    }
};

test "signature invalid length" {
    try std.testing.expectError(error.InvalidLength, Signature.fromSlice(&[_]u8{0} ** 63));
    try std.testing.expectError(error.InvalidLength, Signature.fromSlice(&[_]u8{0} ** 65));
}
