const std = @import("std");

const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

fn decodeValue(c: u8) error{InvalidBase58}!u8 {
    return switch (c) {
        '1'...'9' => c - '1',
        'A'...'H' => 9 + (c - 'A'),
        'J'...'N' => 17 + (c - 'J'),
        'P'...'Z' => 22 + (c - 'P'),
        'a'...'k' => 33 + (c - 'a'),
        'm'...'z' => 44 + (c - 'm'),
        else => error.InvalidBase58,
    };
}

pub fn encodeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return allocator.alloc(u8, 0);

    var zeros: usize = 0;
    while (zeros < input.len and input[zeros] == 0) : (zeros += 1) {}

    var digits: std.ArrayList(u8) = .empty;
    defer digits.deinit(allocator);

    var i: usize = zeros;
    while (i < input.len) : (i += 1) {
        var carry: u32 = input[i];

        var j: usize = 0;
        while (j < digits.items.len) : (j += 1) {
            carry += @as(u32, digits.items[j]) * 256;
            digits.items[j] = @intCast(carry % 58);
            carry /= 58;
        }

        while (carry > 0) {
            try digits.append(allocator, @intCast(carry % 58));
            carry /= 58;
        }
    }

    const encoded_len = zeros + digits.items.len;
    var out = try allocator.alloc(u8, encoded_len);

    @memset(out, '1');

    var k: usize = 0;
    while (k < digits.items.len) : (k += 1) {
        out[encoded_len - 1 - k] = alphabet[digits.items[k]];
    }

    return out;
}

/// Encode `input` into caller-provided `out` buffer without heap allocation for small inputs.
/// Returns the number of bytes written.
/// For common small inputs (e.g. 32-byte pubkey) this path is allocation-free.
pub fn encodeToBuf(out: []u8, input: []const u8) !usize {
    if (input.len == 32) {
        const bytes: *const [32]u8 = @ptrCast(input.ptr);
        const len = @import("base58_fast.zig").encode32(bytes, out);
        if (len == 0) return error.NoSpaceLeft;
        return len;
    }
    if (input.len == 64) {
        const bytes: *const [64]u8 = @ptrCast(input.ptr);
        const len = @import("base58_fast.zig").encode64(bytes, out);
        if (len == 0) return error.NoSpaceLeft;
        return len;
    }
    if (input.len == 0) return 0;

    var zeros: usize = 0;
    while (zeros < input.len and input[zeros] == 0) : (zeros += 1) {}

    // Upper-bound estimate: each input byte adds at most ~1.37 base58 chars.
    const max_digits = (input.len * 137) / 100 + 1;

    // Stack fallback ensures small inputs (pubkey etc.) require zero heap allocations.
    var fallback = std.heap.stackFallback(256, std.heap.page_allocator);
    const allocator = fallback.get();

    var digits: std.ArrayList(u8) = .empty;
    defer digits.deinit(allocator);
    try digits.ensureTotalCapacity(allocator, max_digits);

    var i: usize = zeros;
    while (i < input.len) : (i += 1) {
        var carry: u32 = input[i];
        var j: usize = 0;
        while (j < digits.items.len) : (j += 1) {
            carry += @as(u32, digits.items[j]) * 256;
            digits.items[j] = @intCast(carry % 58);
            carry /= 58;
        }
        while (carry > 0) {
            digits.appendAssumeCapacity(@intCast(carry % 58));
            carry /= 58;
        }
    }

    const encoded_len = zeros + digits.items.len;
    if (out.len < encoded_len) return error.NoSpaceLeft;

    @memset(out[0..encoded_len], '1');
    for (digits.items, 0..) |digit, k| {
        out[encoded_len - 1 - k] = alphabet[digit];
    }
    return encoded_len;
}

pub fn decodeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return allocator.alloc(u8, 0);

    var zeros: usize = 0;
    while (zeros < input.len and input[zeros] == '1') : (zeros += 1) {}

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);

    var i: usize = zeros;
    while (i < input.len) : (i += 1) {
        var carry: u32 = try decodeValue(input[i]);

        var j: usize = 0;
        while (j < bytes.items.len) : (j += 1) {
            carry += @as(u32, bytes.items[j]) * 58;
            bytes.items[j] = @intCast(carry & 0xff);
            carry >>= 8;
        }

        while (carry > 0) {
            try bytes.append(allocator, @intCast(carry & 0xff));
            carry >>= 8;
        }
    }

    const decoded_len = zeros + bytes.items.len;
    var out = try allocator.alloc(u8, decoded_len);
    @memset(out[0..zeros], 0);

    var k: usize = 0;
    while (k < bytes.items.len) : (k += 1) {
        out[decoded_len - 1 - k] = bytes.items[k];
    }

    return out;
}

pub fn decodeFixed(comptime N: usize, input: []const u8) ![N]u8 {
    switch (N) {
        32 => {
            var out: [32]u8 = undefined;
            if (@import("base58_fast.zig").decode32(input, &out)) {
                return out;
            } else |_| {}
        },
        64 => {
            var out: [64]u8 = undefined;
            if (@import("base58_fast.zig").decode64(input, &out)) {
                return out;
            } else |_| {}
        },
        else => {},
    }

    var gpa = std.heap.stackFallback(2048, std.heap.page_allocator);
    const allocator = gpa.get();

    const decoded = try decodeAlloc(allocator, input);
    defer allocator.free(decoded);

    if (decoded.len != N) return error.InvalidLength;

    var out: [N]u8 = undefined;
    @memcpy(&out, decoded);
    return out;
}

test "base58 roundtrip" {
    const gpa = std.testing.allocator;

    const sample = "\x00\x00hello-solana";
    const encoded = try encodeAlloc(gpa, sample);
    defer gpa.free(encoded);

    const decoded = try decodeAlloc(gpa, encoded);
    defer gpa.free(decoded);

    try std.testing.expectEqualSlices(u8, sample, decoded);
}

test "base58 invalid character" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.InvalidBase58, decodeAlloc(gpa, "0OIl"));
}

test "base58 encodes and decodes 1KB input" {
    const gpa = std.testing.allocator;
    const input = [_]u8{0xAB} ** 1024;
    const encoded = try encodeAlloc(gpa, &input);
    defer gpa.free(encoded);

    const decoded = try decodeAlloc(gpa, encoded);
    defer gpa.free(decoded);
    try std.testing.expectEqualSlices(u8, &input, decoded);
}

test "base58 empty input encodes to empty string" {
    const gpa = std.testing.allocator;
    const encoded = try encodeAlloc(gpa, "");
    defer gpa.free(encoded);
    try std.testing.expectEqualSlices(u8, "", encoded);
}

test "base58 roundtrip preserves leading zero bytes" {
    const gpa = std.testing.allocator;
    const input = [_]u8{ 0, 0, 0, 1, 2, 3 };
    const encoded = try encodeAlloc(gpa, &input);
    defer gpa.free(encoded);

    const decoded = try decodeAlloc(gpa, encoded);
    defer gpa.free(decoded);
    try std.testing.expectEqualSlices(u8, &input, decoded);
}

test "encodeToBuf matches encodeAlloc for various inputs" {
    const gpa = std.testing.allocator;
    const cases = &[_][]const u8{
        "",
        &[_]u8{0},
        &[_]u8{ 0, 0, 1, 2, 3 },
        "hello-solana",
        &[_]u8{0xAB} ** 1024,
    };

    var buf: [2048]u8 = undefined;
    for (cases) |input| {
        const expected = try encodeAlloc(gpa, input);
        defer gpa.free(expected);

        const len = try encodeToBuf(&buf, input);
        try std.testing.expectEqual(expected.len, len);
        try std.testing.expectEqualSlices(u8, expected, buf[0..len]);
    }
}

test "encodeToBuf returns NoSpaceLeft when buffer too small" {
    const input = "hello-solana";
    var buf: [4]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, encodeToBuf(&buf, input));
}
