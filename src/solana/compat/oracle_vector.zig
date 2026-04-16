const std = @import("std");
const hash_mod = @import("../core/hash.zig");
const pubkey_mod = @import("../core/pubkey.zig");
const shortvec = @import("../core/shortvec.zig");

pub const OracleVectors = struct {
    meta: Meta,
    core: Core,

    pub const Meta = struct {
        schema_version: u32,
        solana_sdk_version: []const u8,
        generator: []const u8,
    };

    pub const Base58HexCase = struct {
        base58: []const u8,
        hex: []const u8,
    };

    pub const HexCase = struct {
        hex: []const u8,
    };

    pub const ShortvecCases = struct {
        @"0": []const u8,
        @"127": []const u8,
        @"128": []const u8,
        @"300": []const u8,
        @"16384": []const u8,
    };

    pub const Core = struct {
        pubkey_zero: Base58HexCase,
        pubkey_nonzero: Base58HexCase,
        pubkey_leading_zero_bytes: Base58HexCase,
        hash_nonzero: HexCase,
        shortvec: ShortvecCases,
    };
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

fn expectPubkeyCase(vector: OracleVectors.Base58HexCase) !void {
    const expected_bytes = try hexToBytes(vector.hex);
    const pk = try pubkey_mod.Pubkey.fromBase58(vector.base58);
    try std.testing.expectEqualSlices(u8, &expected_bytes, &pk.bytes);
}

fn expectShortvecCase(value: usize, hex: []const u8) !void {
    const encoded = try shortvec.encodeAlloc(std.testing.allocator, value);
    defer std.testing.allocator.free(encoded);
    const expected = try hexToAlloc(std.testing.allocator, hex);
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualSlices(u8, expected, encoded);
}

test "oracle vectors validate v2 schema core cases" {
    var parsed = try loadEmbeddedVectors();
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 2), parsed.value.meta.schema_version);

    try expectPubkeyCase(parsed.value.core.pubkey_zero);
    try expectPubkeyCase(parsed.value.core.pubkey_nonzero);
    try expectPubkeyCase(parsed.value.core.pubkey_leading_zero_bytes);

    const expected_hash_bytes = try hexToBytes(parsed.value.core.hash_nonzero.hex);
    const hash = hash_mod.Hash.init(expected_hash_bytes);
    try std.testing.expectEqualSlices(u8, &expected_hash_bytes, &hash.bytes);

    try expectShortvecCase(0, parsed.value.core.shortvec.@"0");
    try expectShortvecCase(127, parsed.value.core.shortvec.@"127");
    try expectShortvecCase(128, parsed.value.core.shortvec.@"128");
    try expectShortvecCase(300, parsed.value.core.shortvec.@"300");
    try expectShortvecCase(16384, parsed.value.core.shortvec.@"16384");
}
