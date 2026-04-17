const std = @import("std");

pub const DecodeResult = struct {
    value: usize,
    consumed: usize,
};

const MAX_ENCODING_LENGTH: usize = 3;
const MAX_VALUE = std.math.maxInt(u16);

const VisitStatus = union(enum) {
    done: u16,
    more: u16,
};

fn visitByte(elem: u8, value: u16, nth_byte: usize) !VisitStatus {
    if (elem == 0 and nth_byte != 0) return error.InvalidShortVec;
    if (nth_byte >= MAX_ENCODING_LENGTH) return error.InvalidShortVec;

    const done = (elem & 0x80) == 0;
    if (nth_byte == MAX_ENCODING_LENGTH - 1 and !done) return error.InvalidShortVec;

    const shift: u5 = @intCast(nth_byte * 7);
    const shifted = @as(u32, elem & 0x7f) << shift;
    const new_value = @as(u32, value) | shifted;
    if (new_value > MAX_VALUE) return error.IntegerOverflow;

    const next_value: u16 = @intCast(new_value);
    return if (done)
        .{ .done = next_value }
    else
        .{ .more = next_value };
}

pub fn encodeToList(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: usize) !void {
    if (value > MAX_VALUE) return error.IntegerOverflow;

    var v: u16 = @intCast(value);
    while (true) {
        var b: u8 = @intCast(v & 0x7f);
        v >>= 7;
        if (v == 0) {
            try list.append(allocator, b);
            break;
        }

        b |= 0x80;
        try list.append(allocator, b);
    }
}

pub fn encodeAlloc(allocator: std.mem.Allocator, value: usize) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    try encodeToList(&list, allocator, value);
    return try list.toOwnedSlice(allocator);
}

pub fn decode(input: []const u8) !DecodeResult {
    var value: u16 = 0;
    const limit = @min(input.len, MAX_ENCODING_LENGTH);

    for (input[0..limit], 0..) |elem, nth_byte| {
        switch (try visitByte(elem, value, nth_byte)) {
            .done => |next_value| {
                return .{
                    .value = next_value,
                    .consumed = nth_byte + 1,
                };
            },
            .more => |next_value| value = next_value,
        }
    }

    return error.InvalidShortVec;
}

const ShortvecCase = struct {
    value: usize,
    encoded: []const u8,
};

const boundary_cases = [_]ShortvecCase{
    .{ .value = 0, .encoded = &[_]u8{0x00} },
    .{ .value = 127, .encoded = &[_]u8{0x7f} },
    .{ .value = 128, .encoded = &[_]u8{ 0x80, 0x01 } },
    .{ .value = 255, .encoded = &[_]u8{ 0xff, 0x01 } },
    .{ .value = 256, .encoded = &[_]u8{ 0x80, 0x02 } },
    .{ .value = 16_383, .encoded = &[_]u8{ 0xff, 0x7f } },
    .{ .value = 16_384, .encoded = &[_]u8{ 0x80, 0x80, 0x01 } },
    .{ .value = MAX_VALUE, .encoded = &[_]u8{ 0xff, 0xff, 0x03 } },
};

test "shortvec encodes canonical boundary values" {
    const gpa = std.testing.allocator;

    for (boundary_cases) |case| {
        const encoded = try encodeAlloc(gpa, case.value);
        defer gpa.free(encoded);

        try std.testing.expectEqualSlices(u8, case.encoded, encoded);
    }
}

test "shortvec decodes canonical boundary values" {
    for (boundary_cases) |case| {
        const decoded = try decode(case.encoded);
        try std.testing.expectEqual(case.value, decoded.value);
        try std.testing.expectEqual(case.encoded.len, decoded.consumed);
    }
}

test "shortvec decode reports bytes consumed" {
    const decoded = try decode(&[_]u8{ 0x80, 0x01, 0xff });
    try std.testing.expectEqual(@as(usize, 128), decoded.value);
    try std.testing.expectEqual(@as(usize, 2), decoded.consumed);
}

test "shortvec rejects aliased encodings" {
    const invalid_cases = [_][]const u8{
        &[_]u8{ 0x80, 0x00 },
        &[_]u8{ 0x80, 0x80, 0x00 },
        &[_]u8{ 0xff, 0x00 },
        &[_]u8{ 0xff, 0x80, 0x00 },
        &[_]u8{ 0x80, 0x81, 0x00 },
        &[_]u8{ 0xff, 0x81, 0x00 },
        &[_]u8{ 0x80, 0x82, 0x00 },
        &[_]u8{ 0xff, 0x8f, 0x00 },
        &[_]u8{ 0xff, 0xff, 0x00 },
    };

    for (invalid_cases) |bytes| {
        try std.testing.expectError(error.InvalidShortVec, decode(bytes));
    }
}

test "shortvec rejects truncated and oversized encodings" {
    try std.testing.expectError(error.InvalidShortVec, decode(&[_]u8{}));
    try std.testing.expectError(error.InvalidShortVec, decode(&[_]u8{0x80}));
    try std.testing.expectError(error.InvalidShortVec, decode(&[_]u8{ 0x80, 0x80 }));
    try std.testing.expectError(error.InvalidShortVec, decode(&[_]u8{ 0x80, 0x80, 0x80, 0x00 }));
    try std.testing.expectError(error.IntegerOverflow, decode(&[_]u8{ 0x80, 0x80, 0x04 }));
    try std.testing.expectError(error.IntegerOverflow, decode(&[_]u8{ 0x80, 0x80, 0x06 }));
    try std.testing.expectError(error.IntegerOverflow, encodeAlloc(std.testing.allocator, MAX_VALUE + 1));
}

test "shortvec encodes and decodes 256 accounts length" {
    const gpa = std.testing.allocator;
    const encoded = try encodeAlloc(gpa, 256);
    defer gpa.free(encoded);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x80, 0x02 }, encoded);

    const decoded = try decode(encoded);
    try std.testing.expectEqual(@as(usize, 256), decoded.value);
}

test "shortvec roundtrip at max value" {
    const gpa = std.testing.allocator;
    const encoded = try encodeAlloc(gpa, MAX_VALUE);
    defer gpa.free(encoded);

    const decoded = try decode(encoded);
    try std.testing.expectEqual(@as(usize, MAX_VALUE), decoded.value);
}
