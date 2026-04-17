const std = @import("std");

// Fast base58 encoding for 32-byte and 64-byte inputs, adapted from five8/firedancer.
// Uses precomputed tables to avoid the O(N^2) big-integer division of the generic algorithm.

const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const r1div: u64 = 656356768; // 58^5

const INTERMEDIATE_SZ_32 = 9;
const RAW58_SZ_32 = INTERMEDIATE_SZ_32 * 5; // 45
const BASE58_ENCODED_32_MAX_LEN = 44;

const INTERMEDIATE_SZ_64 = 18;
const RAW58_SZ_64 = INTERMEDIATE_SZ_64 * 5; // 90
const BASE58_ENCODED_64_MAX_LEN = 88;

const enc_table_32 = [8][8]u32{
    .{ 513735, 77223048, 437087610, 300156666, 605448490, 214625350, 141436834, 379377856 },
    .{ 0, 78508, 646269101, 118408823, 91512303, 209184527, 413102373, 153715680 },
    .{ 0, 0, 11997, 486083817, 3737691, 294005210, 247894721, 289024608 },
    .{ 0, 0, 0, 1833, 324463681, 385795061, 551597588, 21339008 },
    .{ 0, 0, 0, 0, 280, 127692781, 389432875, 357132832 },
    .{ 0, 0, 0, 0, 0, 42, 537767569, 410450016 },
    .{ 0, 0, 0, 0, 0, 0, 6, 356826688 },
    .{ 0, 0, 0, 0, 0, 0, 0, 1 },
};

const enc_table_64 = [16][17]u32{
    .{ 2631, 149457141, 577092685, 632289089, 81912456, 221591423, 502967496, 403284731, 377738089, 492128779, 746799, 366351977, 190199623, 38066284, 526403762, 650603058, 454901440 },
    .{ 0, 402, 68350375, 30641941, 266024478, 208884256, 571208415, 337765723, 215140626, 129419325, 480359048, 398051646, 635841659, 214020719, 136986618, 626219915, 49699360 },
    .{ 0, 0, 61, 295059608, 141201404, 517024870, 239296485, 527697587, 212906911, 453637228, 467589845, 144614682, 45134568, 184514320, 644355351, 104784612, 308625792 },
    .{ 0, 0, 0, 9, 256449755, 500124311, 479690581, 372802935, 413254725, 487877412, 520263169, 176791855, 78190744, 291820402, 74998585, 496097732, 59100544 },
    .{ 0, 0, 0, 0, 1, 285573662, 455976778, 379818553, 100001224, 448949512, 109507367, 117185012, 347328982, 522665809, 36908802, 577276849, 64504928 },
    .{ 0, 0, 0, 0, 0, 0, 143945778, 651677945, 281429047, 535878743, 264290972, 526964023, 199595821, 597442702, 499113091, 424550935, 458949280 },
    .{ 0, 0, 0, 0, 0, 0, 0, 21997789, 294590275, 148640294, 595017589, 210481832, 404203788, 574729546, 160126051, 430102516, 44963712 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 3361701, 325788598, 30977630, 513969330, 194569730, 164019635, 136596846, 626087230, 503769920 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 513735, 77223048, 437087610, 300156666, 605448490, 214625350, 141436834, 379377856 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 78508, 646269101, 118408823, 91512303, 209184527, 413102373, 153715680 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11997, 486083817, 3737691, 294005210, 247894721, 289024608 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1833, 324463681, 385795061, 551597588, 21339008 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 280, 127692781, 389432875, 357132832 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42, 537767569, 410450016 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 356826688 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
};

fn inLeading0s(bytes: []const u8) usize {
    var i: usize = 0;
    while (i < bytes.len and bytes[i] == 0) : (i += 1) {}
    return i;
}

fn makeBinaryArray32(bytes: *const [32]u8) [8]u32 {
    var out: [8]u32 = undefined;
    for (0..8) |i| {
        const idx = i * 4;
        out[i] = @as(u32, bytes[idx + 3]) |
            (@as(u32, bytes[idx + 2]) << 8) |
            (@as(u32, bytes[idx + 1]) << 16) |
            (@as(u32, bytes[idx]) << 24);
    }
    return out;
}

fn makeBinaryArray64(bytes: *const [64]u8) [16]u32 {
    var out: [16]u32 = undefined;
    for (0..16) |i| {
        const idx = i * 4;
        out[i] = @as(u32, bytes[idx + 3]) |
            (@as(u32, bytes[idx + 2]) << 8) |
            (@as(u32, bytes[idx + 1]) << 16) |
            (@as(u32, bytes[idx]) << 24);
    }
    return out;
}

fn makeIntermediateArray32(binary: [8]u32) [INTERMEDIATE_SZ_32]u64 {
    var intermediate: [INTERMEDIATE_SZ_32]u64 = .{0} ** INTERMEDIATE_SZ_32;
    for (0..8) |i| {
        for (0..INTERMEDIATE_SZ_32 - 1) |j| {
            intermediate[j + 1] += @as(u64, binary[i]) * @as(u64, enc_table_32[i][j]);
        }
    }
    // Adjust so each term < 58^5
    var i: usize = INTERMEDIATE_SZ_32 - 1;
    while (i > 0) : (i -= 1) {
        intermediate[i - 1] += intermediate[i] / r1div;
        intermediate[i] %= r1div;
    }
    return intermediate;
}

fn makeIntermediateArray64(binary: [16]u32) [INTERMEDIATE_SZ_64]u64 {
    var intermediate: [INTERMEDIATE_SZ_64]u64 = .{0} ** INTERMEDIATE_SZ_64;
    for (0..8) |i| {
        for (0..INTERMEDIATE_SZ_64 - 1) |j| {
            intermediate[j + 1] += @as(u64, binary[i]) * @as(u64, enc_table_64[i][j]);
        }
    }
    // Mini-reduction before adding remaining terms
    intermediate[15] += intermediate[16] / r1div;
    intermediate[16] %= r1div;

    for (8..16) |i| {
        for (0..INTERMEDIATE_SZ_64 - 1) |j| {
            intermediate[j + 1] += @as(u64, binary[i]) * @as(u64, enc_table_64[i][j]);
        }
    }
    // Final adjustment
    var i: usize = INTERMEDIATE_SZ_64 - 1;
    while (i > 0) : (i -= 1) {
        intermediate[i - 1] += intermediate[i] / r1div;
        intermediate[i] %= r1div;
    }
    return intermediate;
}

fn intermediateToBase58(
    comptime INTERMEDIATE_SZ: usize,
    comptime RAW58_SZ: usize,
    intermediate: [INTERMEDIATE_SZ]u64,
    in_leading_0s: usize,
    out: []u8,
) usize {
    var raw_base58: [RAW58_SZ]u8 = .{0} ** RAW58_SZ;
    for (0..INTERMEDIATE_SZ) |i| {
        const v: u32 = @intCast(intermediate[i]);
        raw_base58[5 * i + 4] = @intCast(v % 58);
        raw_base58[5 * i + 3] = @intCast((v / 58) % 58);
        raw_base58[5 * i + 2] = @intCast((v / 3364) % 58);
        raw_base58[5 * i + 1] = @intCast((v / 195112) % 58);
        raw_base58[5 * i + 0] = @intCast(v / 11316496);
    }

    var raw_leading_0s: usize = 0;
    while (raw_leading_0s < RAW58_SZ and raw_base58[raw_leading_0s] == 0) : (raw_leading_0s += 1) {}

    const skip = raw_leading_0s - in_leading_0s;
    const encoded_len = RAW58_SZ - skip;
    if (out.len < encoded_len) return 0; // caller should ensure enough space

    for (0..encoded_len) |k| {
        out[k] = alphabet[raw_base58[skip + k]];
    }
    return encoded_len;
}

pub fn encode32(bytes: *const [32]u8, out: []u8) usize {
    const in_leading_0s = inLeading0s(bytes);
    const binary = makeBinaryArray32(bytes);
    const intermediate = makeIntermediateArray32(binary);
    return intermediateToBase58(INTERMEDIATE_SZ_32, RAW58_SZ_32, intermediate, in_leading_0s, out);
}

pub fn encode64(bytes: *const [64]u8, out: []u8) usize {
    const in_leading_0s = inLeading0s(bytes);
    const binary = makeBinaryArray64(bytes);
    const intermediate = makeIntermediateArray64(binary);
    return intermediateToBase58(INTERMEDIATE_SZ_64, RAW58_SZ_64, intermediate, in_leading_0s, out);
}

test "encode32 matches generic for various inputs" {
    const gpa = std.testing.allocator;
    const cases = &[_][32]u8{
        .{0} ** 32,
        .{1} ** 32,
        .{0xAB} ** 32,
        .{0xFF} ** 32,
    };

    for (cases) |input| {
        const expected = try @import("base58.zig").encodeAlloc(gpa, &input);
        defer gpa.free(expected);

        var buf: [44]u8 = undefined;
        const len = encode32(&input, &buf);
        try std.testing.expectEqual(expected.len, len);
        try std.testing.expectEqualSlices(u8, expected, buf[0..len]);
    }
}

test "encode64 matches generic for various inputs" {
    const gpa = std.testing.allocator;
    const cases = &[_][64]u8{
        .{0} ** 64,
        .{1} ** 64,
        .{0xAB} ** 64,
        .{0xFF} ** 64,
    };

    for (cases) |input| {
        const expected = try @import("base58.zig").encodeAlloc(gpa, &input);
        defer gpa.free(expected);

        var buf: [88]u8 = undefined;
        const len = encode64(&input, &buf);
        try std.testing.expectEqual(expected.len, len);
        try std.testing.expectEqualSlices(u8, expected, buf[0..len]);
    }
}
