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
