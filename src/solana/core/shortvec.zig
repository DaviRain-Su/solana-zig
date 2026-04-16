const std = @import("std");

pub const DecodeResult = struct {
    value: usize,
    consumed: usize,
};

pub fn encodeToList(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: usize) !void {
    var v = value;
    while (true) {
        var b: u8 = @intCast(v & 0x7f);
        v >>= 7;
        if (v != 0) b |= 0x80;
        try list.append(allocator, b);
        if (v == 0) break;
    }
}

pub fn encodeAlloc(allocator: std.mem.Allocator, value: usize) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    try encodeToList(&list, allocator, value);
    return try list.toOwnedSlice(allocator);
}

pub fn decode(input: []const u8) !DecodeResult {
    var value: usize = 0;
    var shift: u6 = 0;
    var consumed: usize = 0;

    while (consumed < input.len) : (consumed += 1) {
        const b = input[consumed];
        const chunk: usize = @as(usize, b & 0x7f);

        if (shift >= @bitSizeOf(usize)) return error.IntegerOverflow;
        value |= chunk << shift;

        if ((b & 0x80) == 0) {
            return .{ .value = value, .consumed = consumed + 1 };
        }

        shift += 7;
        if (shift > @bitSizeOf(usize) - 1) return error.IntegerOverflow;
    }

    return error.InvalidShortVec;
}

test "shortvec roundtrip" {
    const gpa = std.testing.allocator;

    const values = [_]usize{ 0, 1, 127, 128, 255, 16384, 1_000_000 };
    for (values) |value| {
        const encoded = try encodeAlloc(gpa, value);
        defer gpa.free(encoded);

        const decoded = try decode(encoded);
        try std.testing.expectEqual(value, decoded.value);
        try std.testing.expectEqual(encoded.len, decoded.consumed);
    }
}


test "shortvec invalid" {
    try std.testing.expectError(error.InvalidShortVec, decode(&[_]u8{0x80}));
}
