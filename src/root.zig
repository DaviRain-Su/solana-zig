const std = @import("std");

pub const solana = @import("solana/mod.zig");
pub const core = solana.core;
pub const tx = solana.tx;
pub const rpc = solana.rpc;
pub const interfaces = solana.interfaces;
pub const signers = solana.signers;
pub const cabi = solana.cabi;
pub const compat = solana.compat;

const c_abi = @cImport({
    @cInclude("solana_zig.h");
});

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

test "public MessageAddressTableLookup type is usable through package exports" {
    const MessageAddressTableLookup = tx.MessageAddressTableLookup;
    _ = MessageAddressTableLookup;
}

test "compute budget interface compiles" {
    _ = interfaces.compute_budget;
}

test "system interface compiles" {
    _ = interfaces.system;
}

test "token interface compiles" {
    _ = interfaces.token;
}

test "token-2022 interface compiles" {
    _ = interfaces.token_2022;
}

test "ata interface compiles" {
    _ = interfaces.ata;
}

test "stake interface compiles" {
    _ = interfaces.stake;
}

test "signers compile" {
    _ = signers.InMemorySigner;
    _ = signers.MockExternalSigner;
}

test "c abi compiles" {
    _ = cabi.core;
    _ = cabi.transaction;
    _ = cabi.rpc;
}

test "c abi header compiles through cImport" {
    _ = c_abi.SolanaPubkey;
    _ = c_abi.SolanaSignature;
    _ = c_abi.SolanaHash;
    _ = c_abi.solana_pubkey_from_bytes;
    _ = c_abi.solana_hash_equal;
    _ = c_abi.solana_zig_abi_version;
    try std.testing.expectEqual(@as(c_int, c_abi.SOLANA_ZIG_ABI_VERSION), cabi.core.solana_zig_abi_version());
}

test "websocket client compiles" {
    _ = rpc.WsClient;
    _ = rpc.WsRpcClient;
}
