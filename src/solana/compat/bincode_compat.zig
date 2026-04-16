const std = @import("std");

pub fn appendU16Le(list: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, v, .little);
    try list.appendSlice(allocator, &bytes);
}

pub fn appendU32Le(list: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, v, .little);
    try list.appendSlice(allocator, &bytes);
}

pub fn appendU64Le(list: *std.ArrayList(u8), allocator: std.mem.Allocator, v: u64) !void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, v, .little);
    try list.appendSlice(allocator, &bytes);
}

pub fn readU64Le(bytes: []const u8) !u64 {
    if (bytes.len != 8) return error.InvalidLength;
    return std.mem.readInt(u64, bytes[0..8], .little);
}
