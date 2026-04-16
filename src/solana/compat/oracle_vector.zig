const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const shortvec = @import("../core/shortvec.zig");

pub const OracleVectors = struct {
    pubkey_base58: []const u8,
    pubkey_hex: []const u8,
    shortvec_300_hex: []const u8,
};

pub fn loadEmbeddedVectors() !std.json.Parsed(OracleVectors) {
    return std.json.parseFromSlice(
        OracleVectors,
        std.heap.page_allocator,
        @embedFile("../../../testdata/oracle_vectors.json"),
        .{},
    );
}

fn hexToBytes(input: []const u8) ![32]u8 {
    if (input.len != 64) return error.InvalidLength;

    var out: [32]u8 = undefined;
    for (0..32) |i| {
        const hi = try std.fmt.charToDigit(input[i * 2], 16);
        const lo = try std.fmt.charToDigit(input[i * 2 + 1], 16);
        out[i] = @as(u8, @intCast((hi << 4) | lo));
    }

    return out;
}

fn hexToAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if ((input.len & 1) != 0) return error.InvalidLength;
    const out = try allocator.alloc(u8, input.len / 2);
    errdefer allocator.free(out);

    for (0..out.len) |i| {
        const hi = try std.fmt.charToDigit(input[i * 2], 16);
        const lo = try std.fmt.charToDigit(input[i * 2 + 1], 16);
        out[i] = @as(u8, @intCast((hi << 4) | lo));
    }

    return out;
}

test "oracle vectors validate pubkey and shortvec" {
    var parsed = try loadEmbeddedVectors();
    defer parsed.deinit();

    const expected_bytes = try hexToBytes(parsed.value.pubkey_hex);
    const pk = try pubkey_mod.Pubkey.fromBase58(parsed.value.pubkey_base58);
    try std.testing.expectEqualSlices(u8, &expected_bytes, &pk.bytes);

    const encoded_300 = try shortvec.encodeAlloc(std.testing.allocator, 300);
    defer std.testing.allocator.free(encoded_300);
    const expected_300 = try hexToAlloc(std.testing.allocator, parsed.value.shortvec_300_hex);
    defer std.testing.allocator.free(expected_300);
    try std.testing.expectEqualSlices(u8, expected_300, encoded_300);
}
