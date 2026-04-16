const std = @import("std");
const base58 = @import("base58.zig");

pub const Hash = struct {
    pub const LENGTH: usize = 32;

    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Hash {
        return .{ .bytes = bytes };
    }

    pub fn fromSlice(slice: []const u8) !Hash {
        if (slice.len != LENGTH) return error.InvalidLength;
        var out: [LENGTH]u8 = undefined;
        @memcpy(&out, slice);
        return .{ .bytes = out };
    }

    pub fn fromBase58(input: []const u8) !Hash {
        return .{ .bytes = try base58.decodeFixed(LENGTH, input) };
    }

    pub fn toBase58Alloc(self: Hash, allocator: std.mem.Allocator) ![]u8 {
        return base58.encodeAlloc(allocator, &self.bytes);
    }

    pub fn fromData(data: []const u8) Hash {
        var digest: [LENGTH]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
        return .{ .bytes = digest };
    }
};

test "hash from data" {
    const h = Hash.fromData("abc");
    try std.testing.expect(h.bytes[0] != 0 or h.bytes[1] != 0);
}
