const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const instruction_mod = @import("../tx/instruction.zig");
const hash_mod = @import("../core/hash.zig");
const keypair_mod = @import("../core/keypair.zig");
const message_mod = @import("../tx/message.zig");
const transaction_mod = @import("../tx/transaction.zig");

const TOKEN_2022_PROGRAM_ID_STR = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";

const Discriminant = enum(u8) {
    approve = 4,
    mint_to = 7,
    burn = 8,
};

pub const MintParams = struct {
    mint: pubkey_mod.Pubkey,
    destination: pubkey_mod.Pubkey,
    authority: pubkey_mod.Pubkey,
    amount: u64,
};

pub const ApproveParams = struct {
    source: pubkey_mod.Pubkey,
    delegate: pubkey_mod.Pubkey,
    owner: pubkey_mod.Pubkey,
    amount: u64,
};

pub const BurnParams = struct {
    source: pubkey_mod.Pubkey,
    mint: pubkey_mod.Pubkey,
    owner: pubkey_mod.Pubkey,
    amount: u64,
};

/// SPL Token-2022 program ID.
pub fn programId() pubkey_mod.Pubkey {
    return pubkey_mod.Pubkey.fromBase58(TOKEN_2022_PROGRAM_ID_STR) catch unreachable;
}

/// Build SPL Token-2022 `MintTo` instruction.
///
/// Data layout: [0x07] ++ little-endian u64 amount.
/// Accounts:
/// 0. mint (writable)
/// 1. destination token account (writable)
/// 2. authority (readonly signer)
pub fn buildMintInstruction(
    allocator: std.mem.Allocator,
    params: MintParams,
) !instruction_mod.Instruction {
    const data = try allocator.alloc(u8, 9);
    errdefer allocator.free(data);
    data[0] = @intFromEnum(Discriminant.mint_to);
    std.mem.writeInt(u64, data[1..9], params.amount, .little);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 3);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = params.mint, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = params.destination, .is_signer = false, .is_writable = true };
    accounts[2] = .{ .pubkey = params.authority, .is_signer = true, .is_writable = false };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

/// Build SPL Token-2022 `Approve` instruction.
///
/// Data layout: [0x04] ++ little-endian u64 amount.
/// Accounts:
/// 0. source token account (writable)
/// 1. delegate (readonly)
/// 2. owner (readonly signer)
pub fn buildApproveInstruction(
    allocator: std.mem.Allocator,
    params: ApproveParams,
) !instruction_mod.Instruction {
    const data = try allocator.alloc(u8, 9);
    errdefer allocator.free(data);
    data[0] = @intFromEnum(Discriminant.approve);
    std.mem.writeInt(u64, data[1..9], params.amount, .little);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 3);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = params.source, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = params.delegate, .is_signer = false, .is_writable = false };
    accounts[2] = .{ .pubkey = params.owner, .is_signer = true, .is_writable = false };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

/// Build SPL Token-2022 `Burn` instruction.
///
/// Data layout: [0x08] ++ little-endian u64 amount.
/// Accounts:
/// 0. source token account (writable)
/// 1. mint (writable)
/// 2. owner (readonly signer)
pub fn buildBurnInstruction(
    allocator: std.mem.Allocator,
    params: BurnParams,
) !instruction_mod.Instruction {
    const data = try allocator.alloc(u8, 9);
    errdefer allocator.free(data);
    data[0] = @intFromEnum(Discriminant.burn);
    std.mem.writeInt(u64, data[1..9], params.amount, .little);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 3);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = params.source, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = params.mint, .is_signer = false, .is_writable = true };
    accounts[2] = .{ .pubkey = params.owner, .is_signer = true, .is_writable = false };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

test "token-2022 mint/approve/burn byte layout and account metas" {
    const allocator = std.testing.allocator;
    const mint = pubkey_mod.Pubkey.init([_]u8{0x11} ** 32);
    const source = pubkey_mod.Pubkey.init([_]u8{0x22} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{0x33} ** 32);
    const delegate = pubkey_mod.Pubkey.init([_]u8{0x44} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{0x55} ** 32);
    const authority = pubkey_mod.Pubkey.init([_]u8{0x66} ** 32);

    const mint_ix = try buildMintInstruction(allocator, .{
        .mint = mint,
        .destination = destination,
        .authority = authority,
        .amount = 1_000,
    });
    defer allocator.free(mint_ix.data);
    defer allocator.free(mint_ix.accounts);
    try std.testing.expectEqual(@as(u8, @intFromEnum(Discriminant.mint_to)), mint_ix.data[0]);
    try std.testing.expectEqual(@as(u64, 1_000), std.mem.readInt(u64, mint_ix.data[1..9], .little));
    try std.testing.expect(mint_ix.program_id.eql(programId()));
    try std.testing.expectEqual(@as(usize, 3), mint_ix.accounts.len);
    try std.testing.expect(mint_ix.accounts[0].pubkey.eql(mint));
    try std.testing.expect(!mint_ix.accounts[0].is_signer);
    try std.testing.expect(mint_ix.accounts[0].is_writable);
    try std.testing.expect(mint_ix.accounts[1].pubkey.eql(destination));
    try std.testing.expect(!mint_ix.accounts[1].is_signer);
    try std.testing.expect(mint_ix.accounts[1].is_writable);
    try std.testing.expect(mint_ix.accounts[2].pubkey.eql(authority));
    try std.testing.expect(mint_ix.accounts[2].is_signer);
    try std.testing.expect(!mint_ix.accounts[2].is_writable);

    const approve_ix = try buildApproveInstruction(allocator, .{
        .source = source,
        .delegate = delegate,
        .owner = owner,
        .amount = 2_000,
    });
    defer allocator.free(approve_ix.data);
    defer allocator.free(approve_ix.accounts);
    try std.testing.expectEqual(@as(u8, @intFromEnum(Discriminant.approve)), approve_ix.data[0]);
    try std.testing.expectEqual(@as(u64, 2_000), std.mem.readInt(u64, approve_ix.data[1..9], .little));
    try std.testing.expect(approve_ix.program_id.eql(programId()));
    try std.testing.expectEqual(@as(usize, 3), approve_ix.accounts.len);
    try std.testing.expect(approve_ix.accounts[0].pubkey.eql(source));
    try std.testing.expect(!approve_ix.accounts[0].is_signer);
    try std.testing.expect(approve_ix.accounts[0].is_writable);
    try std.testing.expect(approve_ix.accounts[1].pubkey.eql(delegate));
    try std.testing.expect(!approve_ix.accounts[1].is_signer);
    try std.testing.expect(!approve_ix.accounts[1].is_writable);
    try std.testing.expect(approve_ix.accounts[2].pubkey.eql(owner));
    try std.testing.expect(approve_ix.accounts[2].is_signer);
    try std.testing.expect(!approve_ix.accounts[2].is_writable);

    const burn_ix = try buildBurnInstruction(allocator, .{
        .source = source,
        .mint = mint,
        .owner = owner,
        .amount = 3_000,
    });
    defer allocator.free(burn_ix.data);
    defer allocator.free(burn_ix.accounts);
    try std.testing.expectEqual(@as(u8, @intFromEnum(Discriminant.burn)), burn_ix.data[0]);
    try std.testing.expectEqual(@as(u64, 3_000), std.mem.readInt(u64, burn_ix.data[1..9], .little));
    try std.testing.expect(burn_ix.program_id.eql(programId()));
    try std.testing.expectEqual(@as(usize, 3), burn_ix.accounts.len);
    try std.testing.expect(burn_ix.accounts[0].pubkey.eql(source));
    try std.testing.expect(!burn_ix.accounts[0].is_signer);
    try std.testing.expect(burn_ix.accounts[0].is_writable);
    try std.testing.expect(burn_ix.accounts[1].pubkey.eql(mint));
    try std.testing.expect(!burn_ix.accounts[1].is_signer);
    try std.testing.expect(burn_ix.accounts[1].is_writable);
    try std.testing.expect(burn_ix.accounts[2].pubkey.eql(owner));
    try std.testing.expect(burn_ix.accounts[2].is_signer);
    try std.testing.expect(!burn_ix.accounts[2].is_writable);
}

test "token-2022 program id is mechanically distinct from legacy token id" {
    const legacy_id = @import("token.zig").programId();
    const token_2022_id = programId();
    try std.testing.expect(!legacy_id.eql(token_2022_id));
}

test "token-2022 builders compile into signed legacy transaction" {
    const allocator = std.testing.allocator;

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{0xA1} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0x21} ** 32);
    const source = pubkey_mod.Pubkey.init([_]u8{0x22} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{0x23} ** 32);
    const delegate = pubkey_mod.Pubkey.init([_]u8{0x24} ** 32);

    const mint_ix = try buildMintInstruction(allocator, .{
        .mint = mint,
        .destination = destination,
        .authority = payer.pubkey(),
        .amount = 11,
    });
    defer allocator.free(mint_ix.data);
    defer allocator.free(mint_ix.accounts);

    const approve_ix = try buildApproveInstruction(allocator, .{
        .source = source,
        .delegate = delegate,
        .owner = payer.pubkey(),
        .amount = 22,
    });
    defer allocator.free(approve_ix.data);
    defer allocator.free(approve_ix.accounts);

    const burn_ix = try buildBurnInstruction(allocator, .{
        .source = source,
        .mint = mint,
        .owner = payer.pubkey(),
        .amount = 33,
    });
    defer allocator.free(burn_ix.data);
    defer allocator.free(burn_ix.accounts);

    const ixs = [_]instruction_mod.Instruction{ mint_ix, approve_ix, burn_ix };
    const recent_blockhash = hash_mod.Hash.init([_]u8{0xB1} ** 32);
    const msg = try message_mod.Message.compileLegacy(allocator, payer.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{payer});
    try tx.verifySignatures();
}
