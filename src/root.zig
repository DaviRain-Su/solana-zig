const std = @import("std");

pub const solana = @import("solana/mod.zig");
pub const core = solana.core;
pub const tx = solana.tx;
pub const rpc = solana.rpc;
pub const interfaces = solana.interfaces;
pub const compat = solana.compat;

test "core exports" {
    const pk = solana.core.Pubkey.init([_]u8{1} ** 32);
    const base58 = try pk.toBase58Alloc(std.testing.allocator);
    defer std.testing.allocator.free(base58);

    const parsed = try solana.core.Pubkey.fromBase58(base58);
    try std.testing.expect(pk.eql(parsed));
}

test "public Message.DecodeResult type is usable through package exports" {
    const DecodeResult = tx.Message.DecodeResult;
    _ = DecodeResult;
}

test "websocket client compiles" {
    _ = rpc.WsClient;
    _ = rpc.ws_client.WsRpcClient;
}

test "compute budget interface compiles" {
    _ = interfaces.compute_budget;
}
