const std = @import("std");
const base58 = @import("base58.zig");

pub const Pubkey = struct {
    pub const LENGTH: usize = 32;

    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Pubkey {
        return .{ .bytes = bytes };
    }

    pub fn fromSlice(slice: []const u8) !Pubkey {
        if (slice.len != LENGTH) return error.InvalidLength;
        var out: [LENGTH]u8 = undefined;
        @memcpy(&out, slice);
        return .{ .bytes = out };
    }

    pub fn fromBase58(input: []const u8) !Pubkey {
        return .{ .bytes = try base58.decodeFixed(LENGTH, input) };
    }

    pub fn toBase58Alloc(self: Pubkey, allocator: std.mem.Allocator) ![]u8 {
        return base58.encodeAlloc(allocator, &self.bytes);
    }

    pub fn eql(self: Pubkey, other: Pubkey) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

test "pubkey base58 roundtrip" {
    const gpa = std.testing.allocator;

    var bytes: [Pubkey.LENGTH]u8 = undefined;
    @memset(&bytes, 7);
    const key = Pubkey.init(bytes);

    const b58 = try key.toBase58Alloc(gpa);
    defer gpa.free(b58);

    const reparsed = try Pubkey.fromBase58(b58);
    try std.testing.expect(key.eql(reparsed));
}

test "pubkey invalid length" {
    try std.testing.expectError(error.InvalidLength, Pubkey.fromSlice(&[_]u8{0} ** 31));
    try std.testing.expectError(error.InvalidLength, Pubkey.fromSlice(&[_]u8{0} ** 33));
}
