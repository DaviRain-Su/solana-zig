const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const hash_mod = @import("../core/hash.zig");
const keypair_mod = @import("../core/keypair.zig");
const instruction_mod = @import("../tx/instruction.zig");
const message_mod = @import("../tx/message.zig");
const transaction_mod = @import("../tx/transaction.zig");

const MEMO_PROGRAM_ID_STR = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr";

pub const MemoParams = struct {
    signer: pubkey_mod.Pubkey,
    memo: []const u8,
};

/// SPL Memo program ID: MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr
pub fn programId() pubkey_mod.Pubkey {
    return pubkey_mod.Pubkey.fromBase58(MEMO_PROGRAM_ID_STR) catch unreachable;
}

/// Build SPL Memo instruction.
///
/// Data layout: raw UTF-8 memo bytes.
/// Accounts:
/// 0. signer (readonly signer)
pub fn buildMemoInstruction(
    allocator: std.mem.Allocator,
    params: MemoParams,
) !instruction_mod.Instruction {
    const data = try allocator.alloc(u8, params.memo.len);
    errdefer allocator.free(data);
    @memcpy(data, params.memo);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 1);
    errdefer allocator.free(accounts);
    accounts[0] = .{
        .pubkey = params.signer,
        .is_signer = true,
        .is_writable = false,
    };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

test "memo instruction byte layout and account metas" {
    const allocator = std.testing.allocator;
    const signer = pubkey_mod.Pubkey.init([_]u8{0x42} ** 32);
    const memo_text = "phase3-batch2-memo";

    const ix = try buildMemoInstruction(allocator, .{
        .signer = signer,
        .memo = memo_text,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expect(ix.program_id.eql(programId()));
    try std.testing.expectEqual(@as(usize, memo_text.len), ix.data.len);
    try std.testing.expect(std.mem.eql(u8, ix.data, memo_text));
    try std.testing.expectEqual(@as(usize, 1), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(signer));
    try std.testing.expectEqual(true, ix.accounts[0].is_signer);
    try std.testing.expectEqual(false, ix.accounts[0].is_writable);
}

test "memo instruction supports empty memo" {
    const allocator = std.testing.allocator;
    const signer = pubkey_mod.Pubkey.init([_]u8{0x55} ** 32);

    const ix = try buildMemoInstruction(allocator, .{
        .signer = signer,
        .memo = "",
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(usize, 0), ix.data.len);
    try std.testing.expectEqual(@as(usize, 1), ix.accounts.len);
}

test "memo builder compile-sign evidence" {
    const allocator = std.testing.allocator;

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{0x7A} ** 32);
    const memo_ix = try buildMemoInstruction(allocator, .{
        .signer = payer.pubkey(),
        .memo = "memo-compile-sign",
    });
    defer allocator.free(memo_ix.data);
    defer allocator.free(memo_ix.accounts);

    const ixs = [_]instruction_mod.Instruction{memo_ix};
    const recent_blockhash = hash_mod.Hash.init([_]u8{0x9A} ** 32);
    const msg = try message_mod.Message.compileLegacy(allocator, payer.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{payer});
    try tx.verifySignatures();
}
