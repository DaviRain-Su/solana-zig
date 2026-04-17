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

// --- Decode tables and helpers ---

const BASE58_INVERSE_TABLE_OFFSET: u8 = '1';
const BASE58_INVERSE_TABLE_SENTINEL: u8 = 1 + 'z' - BASE58_INVERSE_TABLE_OFFSET; // 74
const BASE58_INVALID_CHAR: u8 = 255;

const BASE58_INVERSE: [75]u8 = .{
    0,  1,  2,  3,  4,  5,  6,  7,  8,  BASE58_INVALID_CHAR, BASE58_INVALID_CHAR,
    BASE58_INVALID_CHAR, BASE58_INVALID_CHAR, BASE58_INVALID_CHAR, BASE58_INVALID_CHAR,
    BASE58_INVALID_CHAR, 9,  10, 11, 12, 13, 14, 15, 16, BASE58_INVALID_CHAR, 17, 18,
    19, 20, 21, BASE58_INVALID_CHAR, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    BASE58_INVALID_CHAR, BASE58_INVALID_CHAR, BASE58_INVALID_CHAR, BASE58_INVALID_CHAR,
    BASE58_INVALID_CHAR, BASE58_INVALID_CHAR, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42,
    43, BASE58_INVALID_CHAR, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
    BASE58_INVALID_CHAR,
};

const BINARY_SZ_32 = 8;
const BINARY_SZ_64 = 16;

const DEC_TABLE_32: [INTERMEDIATE_SZ_32][BINARY_SZ_32]u32 = .{
    .{ 1277, 2650397687, 3801011509, 2074386530, 3248244966, 687255411, 2959155456, 0 },
    .{ 0, 8360, 1184754854, 3047609191, 3418394749, 132556120, 1199103528, 0 },
    .{ 0, 0, 54706, 2996985344, 1834629191, 3964963911, 485140318, 1073741824 },
    .{ 0, 0, 0, 357981, 1476998812, 3337178590, 1483338760, 4194304000 },
    .{ 0, 0, 0, 0, 2342503, 3052466824, 2595180627, 17825792 },
    .{ 0, 0, 0, 0, 0, 15328518, 1933902296, 4063920128 },
    .{ 0, 0, 0, 0, 0, 0, 100304420, 3355157504 },
    .{ 0, 0, 0, 0, 0, 0, 0, 656356768 },
    .{ 0, 0, 0, 0, 0, 0, 0, 1 },
};

const DEC_TABLE_64: [INTERMEDIATE_SZ_64][BINARY_SZ_64]u32 = .{
    .{ 249448, 3719864065, 173911550, 4021557284, 3115810883, 2498525019, 1035889824, 627529458, 3840888383, 3728167192, 2901437456, 3863405776, 1540739182, 1570766848, 0, 0 },
    .{ 0, 1632305, 1882780341, 4128706713, 1023671068, 2618421812, 2005415586, 1062993857, 3577221846, 3960476767, 1695615427, 2597060712, 669472826, 104923136, 0, 0 },
    .{ 0, 0, 10681231, 1422956801, 2406345166, 4058671871, 2143913881, 4169135587, 2414104418, 2549553452, 997594232, 713340517, 2290070198, 1103833088, 0, 0 },
    .{ 0, 0, 0, 69894212, 1038812943, 1785020643, 1285619000, 2301468615, 3492037905, 314610629, 2761740102, 3410618104, 1699516363, 910779968, 0, 0 },
    .{ 0, 0, 0, 0, 457363084, 927569770, 3976106370, 1389513021, 2107865525, 3716679421, 1828091393, 2088408376, 439156799, 2579227194, 0, 0 },
    .{ 0, 0, 0, 0, 0, 2992822783, 383623235, 3862831115, 112778334, 339767049, 1447250220, 486575164, 3495303162, 2209946163, 268435456, 0 },
    .{ 0, 0, 0, 0, 0, 4, 2404108010, 2962826229, 3998086794, 1893006839, 2266258239, 1429430446, 307953032, 2361423716, 176160768, 0 },
    .{ 0, 0, 0, 0, 0, 0, 29, 3596590989, 3044036677, 1332209423, 1014420882, 868688145, 4264082837, 3688771808, 2485387264, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 195, 1054003707, 3711696540, 582574436, 3549229270, 1088536814, 2338440092, 1468637184, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 1277, 2650397687, 3801011509, 2074386530, 3248244966, 687255411, 2959155456, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 8360, 1184754854, 3047609191, 3418394749, 132556120, 1199103528, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 54706, 2996985344, 1834629191, 3964963911, 485140318, 1073741824 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 357981, 1476998812, 3337178590, 1483338760, 4194304000 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2342503, 3052466824, 2595180627, 17825792 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15328518, 1933902296, 4063920128 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100304420, 3355157504 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 656356768 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
};

fn decodeBeforeBeConvert(
    comptime ENCODED_LEN: usize,
    comptime RAW58_SZ: usize,
    comptime INTERMEDIATE_SZ: usize,
    comptime BINARY_SZ: usize,
    encoded: []const u8,
    dec_table: [INTERMEDIATE_SZ][BINARY_SZ]u32,
) ![BINARY_SZ]u64 {
    var char_cnt: usize = 0;
    while (char_cnt < ENCODED_LEN + 1 and char_cnt < encoded.len) {
        const c = encoded[char_cnt];
        const idx: u64 = @as(u64, c) -% BASE58_INVERSE_TABLE_OFFSET;
        const clamped_idx: usize = @intCast(@min(idx, BASE58_INVERSE_TABLE_SENTINEL));
        if (BASE58_INVERSE[clamped_idx] == BASE58_INVALID_CHAR) {
            return error.InvalidBase58;
        }
        char_cnt += 1;
    }
    if (char_cnt == ENCODED_LEN + 1) {
        return error.InvalidBase58; // too long
    }

    const prepend_0 = RAW58_SZ - char_cnt;
    var raw_base58: [RAW58_SZ]u8 = .{0} ** RAW58_SZ;
    for (prepend_0..RAW58_SZ) |j| {
        const c = encoded[j - prepend_0];
        const idx: u64 = @as(u64, c) -% BASE58_INVERSE_TABLE_OFFSET;
        const clamped_idx: usize = @intCast(@min(idx, BASE58_INVERSE_TABLE_SENTINEL));
        raw_base58[j] = BASE58_INVERSE[clamped_idx];
    }

    var intermediate: [INTERMEDIATE_SZ]u64 = .{0} ** INTERMEDIATE_SZ;
    for (0..INTERMEDIATE_SZ) |i| {
        intermediate[i] = @as(u64, raw_base58[5 * i]) * 11316496 +
            @as(u64, raw_base58[5 * i + 1]) * 195112 +
            @as(u64, raw_base58[5 * i + 2]) * 3364 +
            @as(u64, raw_base58[5 * i + 3]) * 58 +
            @as(u64, raw_base58[5 * i + 4]);
    }

    var binary: [BINARY_SZ]u64 = .{0} ** BINARY_SZ;
    for (0..BINARY_SZ) |j| {
        var acc: u128 = 0;
        for (0..INTERMEDIATE_SZ) |i| {
            acc += @as(u128, intermediate[i]) * @as(u128, dec_table[i][j]);
        }
        binary[j] = @intCast(acc);
    }

    var i = BINARY_SZ - 1;
    while (i > 0) : (i -= 1) {
        binary[i - 1] += binary[i] >> 32;
        binary[i] &= 0xFFFFFFFF;
    }

    if (binary[0] > 0xFFFFFFFF) {
        return error.InvalidBase58; // largest term too high
    }

    return binary;
}

fn decodeAfterBeConvert(comptime N: usize, out: *[N]u8, encoded: []const u8) !void {
    var leading_zero_cnt: usize = 0;
    while (leading_zero_cnt < N) {
        if (leading_zero_cnt >= encoded.len) {
            return error.InvalidBase58; // too short
        }
        const out_val = out[leading_zero_cnt];
        if (out_val != 0) break;
        if (encoded[leading_zero_cnt] != '1') {
            return error.InvalidBase58; // too short
        }
        leading_zero_cnt += 1;
    }
    if (leading_zero_cnt < encoded.len and encoded[leading_zero_cnt] == '1') {
        return error.InvalidBase58; // output too long
    }
}

pub fn decode32(encoded: []const u8, out: *[32]u8) !void {
    const binary = try decodeBeforeBeConvert(
        BASE58_ENCODED_32_MAX_LEN,
        RAW58_SZ_32,
        INTERMEDIATE_SZ_32,
        BINARY_SZ_32,
        encoded,
        DEC_TABLE_32,
    );
    for (0..BINARY_SZ_32) |i| {
        const val: u32 = @intCast(binary[i] & 0xFFFFFFFF);
        out[i * 4 + 0] = @intCast(val >> 24);
        out[i * 4 + 1] = @intCast((val >> 16) & 0xFF);
        out[i * 4 + 2] = @intCast((val >> 8) & 0xFF);
        out[i * 4 + 3] = @intCast(val & 0xFF);
    }
    try decodeAfterBeConvert(32, out, encoded);
}

pub fn decode64(encoded: []const u8, out: *[64]u8) !void {
    const binary = try decodeBeforeBeConvert(
        BASE58_ENCODED_64_MAX_LEN,
        RAW58_SZ_64,
        INTERMEDIATE_SZ_64,
        BINARY_SZ_64,
        encoded,
        DEC_TABLE_64,
    );
    for (0..BINARY_SZ_64) |i| {
        const val: u32 = @intCast(binary[i] & 0xFFFFFFFF);
        out[i * 4 + 0] = @intCast(val >> 24);
        out[i * 4 + 1] = @intCast((val >> 16) & 0xFF);
        out[i * 4 + 2] = @intCast((val >> 8) & 0xFF);
        out[i * 4 + 3] = @intCast(val & 0xFF);
    }
    try decodeAfterBeConvert(64, out, encoded);
}

test "decode32 roundtrip for various inputs" {
    const gpa = std.testing.allocator;
    const cases = &[_][32]u8{
        .{0} ** 32,
        .{1} ** 32,
        .{0xAB} ** 32,
        .{0xFF} ** 32,
        .{ 0, 0, 10, 85, 198, 191, 71, 18, 5, 54, 6, 255, 181, 32, 227, 150, 208, 3, 157, 135, 222, 67, 50, 23, 237, 51, 240, 123, 34, 148, 111, 84 },
    };

    for (cases) |input| {
        const encoded = try @import("base58.zig").encodeAlloc(gpa, &input);
        defer gpa.free(encoded);

        var out: [32]u8 = undefined;
        try decode32(encoded, &out);
        try std.testing.expectEqualSlices(u8, &input, &out);
    }
}

test "decode64 roundtrip for various inputs" {
    const gpa = std.testing.allocator;
    const cases = &[_][64]u8{
        .{0} ** 64,
        .{1} ** 64,
        .{0xAB} ** 64,
        .{0xFF} ** 64,
        .{ 0, 0, 10, 85, 198, 191, 71, 18, 5, 54, 6, 255, 181, 32, 227, 150, 208, 3, 157, 135, 222, 67, 50, 23, 237, 51, 240, 123, 34, 148, 111, 84, 98, 162, 236, 133, 31, 93, 185, 142, 108, 41, 191, 1, 138, 6, 192, 0, 46, 93, 25, 65, 243, 223, 225, 225, 85, 55, 82, 251, 109, 132, 165, 2 },
    };

    for (cases) |input| {
        const encoded = try @import("base58.zig").encodeAlloc(gpa, &input);
        defer gpa.free(encoded);

        var out: [64]u8 = undefined;
        try decode64(encoded, &out);
        try std.testing.expectEqualSlices(u8, &input, &out);
    }
}

test "decode32 rejects invalid inputs" {
    var buf32: [32]u8 = undefined;
    try std.testing.expectError(error.InvalidBase58, decode32("1", &buf32));
    try std.testing.expectError(error.InvalidBase58, decode32("1111111111111111111111111111111", &buf32));
    try std.testing.expectError(error.InvalidBase58, decode32("4uQeVj5tqViQh7yWWGStvkEG1Zmhx6uasJtWCJziofLRda4", &buf32));
    try std.testing.expectError(error.InvalidBase58, decode32("111111111111111111111111111111111", &buf32));
    try std.testing.expectError(error.InvalidBase58, decode32("11111111111111111111111111111110", &buf32));
    try std.testing.expectError(error.InvalidBase58, decode32("1111111111111111111111111111111!", &buf32));
    try std.testing.expectError(error.InvalidBase58, decode32("1111111111111111111111111111111I", &buf32));
    try std.testing.expectError(error.InvalidBase58, decode32("1111111111111111111111111111111O", &buf32));
    try std.testing.expectError(error.InvalidBase58, decode32("1111111111111111111111111111111l", &buf32));
}
