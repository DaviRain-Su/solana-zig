const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const instruction_mod = @import("../tx/instruction.zig");
const hash_mod = @import("../core/hash.zig");
const keypair_mod = @import("../core/keypair.zig");
const message_mod = @import("../tx/message.zig");
const transaction_mod = @import("../tx/transaction.zig");
const system = @import("system.zig");
const token = @import("token.zig");

const ATA_PROGRAM_ID_STR = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";

/// SPL Associated Token Account program ID.
pub fn ataProgramId() pubkey_mod.Pubkey {
    return pubkey_mod.Pubkey.fromBase58(ATA_PROGRAM_ID_STR) catch unreachable;
}

/// System program ID.
pub fn systemProgramId() pubkey_mod.Pubkey {
    return system.SYSTEM_PROGRAM_ID;
}

/// SPL Token program ID.
pub fn tokenProgramId() pubkey_mod.Pubkey {
    return token.programId();
}

/// Find the associated token address for a wallet, mint and token program.
/// Seeds: [wallet, token_program, mint].
pub fn findAssociatedTokenAddress(
    wallet: pubkey_mod.Pubkey,
    mint: pubkey_mod.Pubkey,
    token_program_id: pubkey_mod.Pubkey,
) error{InvalidSeeds}!struct { pubkey_mod.Pubkey, u8 } {
    const seeds = &[_][]const u8{
        &wallet.bytes,
        &token_program_id.bytes,
        &mint.bytes,
    };
    return pubkey_mod.findProgramAddress(seeds, ataProgramId());
}

pub const CreateATAParams = struct {
    payer: pubkey_mod.Pubkey,
    associated_token: pubkey_mod.Pubkey,
    owner: pubkey_mod.Pubkey,
    mint: pubkey_mod.Pubkey,
};

/// Build SPL Associated Token Account `Create` instruction.
///
/// Data layout: empty (0 bytes).
/// Accounts:
/// 0. payer [signer, writable]
/// 1. associated_token [writable]
/// 2. owner []
/// 3. mint []
/// 4. system_program []
/// 5. token_program []
pub fn buildCreateAssociatedTokenAccountInstruction(
    allocator: std.mem.Allocator,
    params: CreateATAParams,
) !instruction_mod.Instruction {
    const data = try allocator.alloc(u8, 0);
    errdefer allocator.free(data);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 6);
    errdefer allocator.free(accounts);

    accounts[0] = .{
        .pubkey = params.payer,
        .is_signer = true,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.associated_token,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[2] = .{
        .pubkey = params.owner,
        .is_signer = false,
        .is_writable = false,
    };
    accounts[3] = .{
        .pubkey = params.mint,
        .is_signer = false,
        .is_writable = false,
    };
    accounts[4] = .{
        .pubkey = systemProgramId(),
        .is_signer = false,
        .is_writable = false,
    };
    accounts[5] = .{
        .pubkey = tokenProgramId(),
        .is_signer = false,
        .is_writable = false,
    };

    return .{
        .program_id = ataProgramId(),
        .accounts = accounts,
        .data = data,
    };
}

test "ATA program ID is ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL" {
    const allocator = std.testing.allocator;
    const id = ataProgramId();
    const b58 = try id.toBase58Alloc(allocator);
    defer allocator.free(b58);
    try std.testing.expectEqualStrings(ATA_PROGRAM_ID_STR, b58);
}

test "findAssociatedTokenAddress returns valid PDA with default token program" {
    const wallet = pubkey_mod.Pubkey.init([_]u8{0xA1} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0xB2} ** 32);
    const token_program = tokenProgramId();

    const result = try findAssociatedTokenAddress(wallet, mint, token_program);
    const ata = result[0];
    const bump = result[1];

    try std.testing.expect(bump >= 0 and bump <= 255);

    // Verify by recreating with the bump.
    const seeds = &[_][]const u8{
        &wallet.bytes,
        &token_program.bytes,
        &mint.bytes,
        &[_]u8{bump},
    };
    const recreated = try pubkey_mod.createProgramAddress(seeds, ataProgramId());
    try std.testing.expect(ata.eql(recreated));
}

test "findAssociatedTokenAddress returns valid PDA with custom token program" {
    const wallet = pubkey_mod.Pubkey.init([_]u8{0xC3} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0xD4} ** 32);
    const custom_token_program = pubkey_mod.Pubkey.init([_]u8{0xE5} ** 32);

    const result = try findAssociatedTokenAddress(wallet, mint, custom_token_program);
    const ata = result[0];
    const bump = result[1];

    try std.testing.expect(bump >= 0 and bump <= 255);

    // Verify by recreating with the bump and custom program id.
    const seeds = &[_][]const u8{
        &wallet.bytes,
        &custom_token_program.bytes,
        &mint.bytes,
        &[_]u8{bump},
    };
    const recreated = try pubkey_mod.createProgramAddress(seeds, ataProgramId());
    try std.testing.expect(ata.eql(recreated));
}

test "buildCreateAssociatedTokenAccountInstruction account metas and empty data" {
    const allocator = std.testing.allocator;

    const payer = pubkey_mod.Pubkey.init([_]u8{0x01} ** 32);
    const ata = pubkey_mod.Pubkey.init([_]u8{0x02} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{0x03} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0x04} ** 32);

    const ix = try buildCreateAssociatedTokenAccountInstruction(allocator, .{
        .payer = payer,
        .associated_token = ata,
        .owner = owner,
        .mint = mint,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expect(ix.program_id.eql(ataProgramId()));
    try std.testing.expectEqual(@as(usize, 0), ix.data.len);
    try std.testing.expectEqual(@as(usize, 6), ix.accounts.len);

    try std.testing.expect(ix.accounts[0].pubkey.eql(payer));
    try std.testing.expectEqual(true, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);

    try std.testing.expect(ix.accounts[1].pubkey.eql(ata));
    try std.testing.expectEqual(false, ix.accounts[1].is_signer);
    try std.testing.expectEqual(true, ix.accounts[1].is_writable);

    try std.testing.expect(ix.accounts[2].pubkey.eql(owner));
    try std.testing.expectEqual(false, ix.accounts[2].is_signer);
    try std.testing.expectEqual(false, ix.accounts[2].is_writable);

    try std.testing.expect(ix.accounts[3].pubkey.eql(mint));
    try std.testing.expectEqual(false, ix.accounts[3].is_signer);
    try std.testing.expectEqual(false, ix.accounts[3].is_writable);

    try std.testing.expect(ix.accounts[4].pubkey.eql(systemProgramId()));
    try std.testing.expectEqual(false, ix.accounts[4].is_signer);
    try std.testing.expectEqual(false, ix.accounts[4].is_writable);

    try std.testing.expect(ix.accounts[5].pubkey.eql(tokenProgramId()));
    try std.testing.expectEqual(false, ix.accounts[5].is_signer);
    try std.testing.expectEqual(false, ix.accounts[5].is_writable);
}

test "ATA builder compiles into signed legacy transaction" {
    const allocator = std.testing.allocator;

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{0x2A} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{0x03} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0x04} ** 32);

    const ata_result = try findAssociatedTokenAddress(owner, mint, tokenProgramId());
    const ata = ata_result[0];

    const ix = try buildCreateAssociatedTokenAccountInstruction(allocator, .{
        .payer = payer.pubkey(),
        .associated_token = ata,
        .owner = owner,
        .mint = mint,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    const ixs = [_]instruction_mod.Instruction{ix};
    const recent_blockhash = hash_mod.Hash.init([_]u8{0xAB} ** 32);
    const msg = try message_mod.Message.compileLegacy(allocator, payer.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{payer});
    try tx.verifySignatures();
}
