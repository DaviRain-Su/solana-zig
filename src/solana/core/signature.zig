const std = @import("std");
const base58 = @import("base58.zig");
const pubkey_mod = @import("pubkey.zig");

pub const Signature = struct {
    pub const LENGTH: usize = 64;

    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Signature {
        return .{ .bytes = bytes };
    }

    pub fn zero() Signature {
        return .{ .bytes = [_]u8{0} ** LENGTH };
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

    pub fn toBase58Buf(self: Signature, out: []u8) !usize {
        return base58.encodeToBuf(out, &self.bytes);
    }

    pub fn toBase58Fast(self: Signature, out: []u8) usize {
        return @import("base58_fast.zig").encode64(&self.bytes, out);
    }

    pub fn verify(self: Signature, msg: []const u8, pubkey: pubkey_mod.Pubkey) !void {
        try @import("ed25519.zig").verify(&self.bytes, msg, &pubkey.bytes);
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

test "signature zero default is unsigned" {
    const signature = Signature.zero();
    const expected = [_]u8{0} ** Signature.LENGTH;

    try std.testing.expect(signature.isZero());
    try std.testing.expectEqualSlices(u8, &expected, &signature.bytes);
}

test "signature base58 roundtrip" {
    const gpa = std.testing.allocator;

    var bytes: [Signature.LENGTH]u8 = undefined;
    for (&bytes, 0..) |*byte, i| byte.* = @intCast(i);
    bytes[0] = 0;
    bytes[1] = 0;

    const signature = Signature.init(bytes);
    const encoded = try signature.toBase58Alloc(gpa);
    defer gpa.free(encoded);

    const decoded = try Signature.fromBase58(encoded);
    try std.testing.expectEqualSlices(u8, &signature.bytes, &decoded.bytes);
}

test "signature fromBase58 returns clear invalid input errors" {
    const gpa = std.testing.allocator;

    const short_bytes = [_]u8{7} ** 63;
    const encoded_short = try base58.encodeAlloc(gpa, &short_bytes);
    defer gpa.free(encoded_short);

    try std.testing.expectError(error.InvalidLength, Signature.fromBase58(encoded_short));
    try std.testing.expectError(error.InvalidBase58, Signature.fromBase58("0OIl"));
}
