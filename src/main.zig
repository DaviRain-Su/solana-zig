const std = @import("std");
const solana_zig = @import("solana_zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const out = &stdout_file_writer.interface;

    const seed = [_]u8{1} ** 32;
    const kp = try solana_zig.core.Keypair.fromSeed(seed);
    const pk_b58 = try kp.pubkey().toBase58Alloc(init.arena.allocator());

    try out.print("solana-zig keypair pubkey: {s}\n", .{pk_b58});
    try out.flush();
}
