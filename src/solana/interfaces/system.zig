const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const hash_mod = @import("../core/hash.zig");
const instruction_mod = @import("../tx/instruction.zig");

pub const SYSTEM_PROGRAM_ID = pubkey_mod.Pubkey.init([_]u8{0} ** 32);

pub const NonceState = union(enum) {
    uninitialized,
    initialized: struct {
        authority: pubkey_mod.Pubkey,
        blockhash: hash_mod.Hash,
    },
};

pub const ParseNonceError = error{
    InvalidNonceAccountData,
};

pub fn parseNonceAccountData(data: []const u8) ParseNonceError!NonceState {
    if (data.len < 4) return error.InvalidNonceAccountData;

    const first_u32 = std.mem.readInt(u32, data[0..4], .little);
    var offset: usize = 0;

    // Detect Versions wrapper (Legacy=0, Current=1) by checking if second u32 is a valid State discriminant.
    if (data.len >= 8 and (first_u32 == 0 or first_u32 == 1)) {
        const second_u32 = std.mem.readInt(u32, data[4..8], .little);
        if (second_u32 == 0 or second_u32 == 1) {
            offset = 4;
        }
    }

    const state_discriminant = std.mem.readInt(u32, data[offset..][0..4], .little);
    offset += 4;

    switch (state_discriminant) {
        0 => return .uninitialized,
        1 => {
            if (data.len < offset + 64) return error.InvalidNonceAccountData;
            const authority = pubkey_mod.Pubkey.fromSlice(data[offset..][0..32]) catch return error.InvalidNonceAccountData;
            offset += 32;
            const blockhash = hash_mod.Hash.fromSlice(data[offset..][0..32]) catch return error.InvalidNonceAccountData;
            return .{ .initialized = .{
                .authority = authority,
                .blockhash = blockhash,
            } };
        },
        else => return error.InvalidNonceAccountData,
    }
}

pub const AdvanceNonceAccountParams = struct {
    nonce_account: pubkey_mod.Pubkey,
    recent_blockhashes_sysvar: pubkey_mod.Pubkey,
    nonce_authority: pubkey_mod.Pubkey,
};

pub fn buildAdvanceNonceAccountInstruction(
    allocator: std.mem.Allocator,
    params: AdvanceNonceAccountParams,
) !instruction_mod.Instruction {
    var data = try allocator.alloc(u8, 4);
    errdefer allocator.free(data);
    std.mem.writeInt(u32, data[0..4], 4, .little);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 3);
    errdefer allocator.free(accounts);
    accounts[0] = .{
        .pubkey = params.nonce_account,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.recent_blockhashes_sysvar,
        .is_signer = false,
        .is_writable = false,
    };
    accounts[2] = .{
        .pubkey = params.nonce_authority,
        .is_signer = true,
        .is_writable = false,
    };

    return .{
        .program_id = SYSTEM_PROGRAM_ID,
        .accounts = accounts,
        .data = data,
    };
}

test "parseNonceAccountData direct state initialized" {
    var data: [68]u8 = undefined;
    // State::Initialized discriminant (u32 LE = 1)
    std.mem.writeInt(u32, data[0..4], 1, .little);
    // authority pubkey
    @memset(data[4..36], 0xAA);
    // blockhash
    @memset(data[36..68], 0xBB);

    const state = try parseNonceAccountData(&data);
    try std.testing.expect(state == .initialized);
    try std.testing.expect(state.initialized.authority.eql(pubkey_mod.Pubkey.init([_]u8{0xAA} ** 32)));
    try std.testing.expect(std.mem.eql(u8, &state.initialized.blockhash.bytes, &([_]u8{0xBB} ** 32)));
}

test "parseNonceAccountData with Versions wrapper" {
    var data: [72]u8 = undefined;
    // Versions::Current = 1
    std.mem.writeInt(u32, data[0..4], 1, .little);
    // State::Initialized discriminant
    std.mem.writeInt(u32, data[4..8], 1, .little);
    @memset(data[8..40], 0xCC);
    @memset(data[40..72], 0xDD);

    const state = try parseNonceAccountData(&data);
    try std.testing.expect(state == .initialized);
    try std.testing.expect(state.initialized.authority.eql(pubkey_mod.Pubkey.init([_]u8{0xCC} ** 32)));
}

test "parseNonceAccountData uninitialized" {
    var data: [4]u8 = undefined;
    std.mem.writeInt(u32, data[0..4], 0, .little);
    const state = try parseNonceAccountData(&data);
    try std.testing.expect(state == .uninitialized);
}

test "parseNonceAccountData rejects truncated" {
    const data = [_]u8{1, 0, 0, 0};
    try std.testing.expectError(error.InvalidNonceAccountData, parseNonceAccountData(&data));
}

test "buildAdvanceNonceAccountInstruction byte layout and accounts" {
    const gpa = std.testing.allocator;

    const nonce_account = pubkey_mod.Pubkey.init([_]u8{1} ** 32);
    const sysvar = pubkey_mod.Pubkey.init([_]u8{2} ** 32);
    const authority = pubkey_mod.Pubkey.init([_]u8{3} ** 32);

    var ix = try buildAdvanceNonceAccountInstruction(gpa, .{
        .nonce_account = nonce_account,
        .recent_blockhashes_sysvar = sysvar,
        .nonce_authority = authority,
    });
    defer gpa.free(ix.data);
    defer gpa.free(ix.accounts);

    try std.testing.expect(ix.program_id.eql(SYSTEM_PROGRAM_ID));
    try std.testing.expectEqual(@as(usize, 4), ix.data.len);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, ix.data[0..4], .little));

    try std.testing.expectEqual(@as(usize, 3), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(nonce_account));
    try std.testing.expectEqual(false, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);

    try std.testing.expect(ix.accounts[1].pubkey.eql(sysvar));
    try std.testing.expectEqual(false, ix.accounts[1].is_signer);
    try std.testing.expectEqual(false, ix.accounts[1].is_writable);

    try std.testing.expect(ix.accounts[2].pubkey.eql(authority));
    try std.testing.expectEqual(true, ix.accounts[2].is_signer);
    try std.testing.expectEqual(false, ix.accounts[2].is_writable);
}

test "nonce workflow minimal compileLegacy" {
    const gpa = std.testing.allocator;
    const message_mod = @import("../tx/message.zig");

    const payer = pubkey_mod.Pubkey.init([_]u8{7} ** 32);
    const nonce_account_key = pubkey_mod.Pubkey.init([_]u8{1} ** 32);
    const sysvar_key = pubkey_mod.Pubkey.init([_]u8{2} ** 32);
    const authority_key = pubkey_mod.Pubkey.init([_]u8{3} ** 32);

    const advance_ix = try buildAdvanceNonceAccountInstruction(gpa, .{
        .nonce_account = nonce_account_key,
        .recent_blockhashes_sysvar = sysvar_key,
        .nonce_authority = authority_key,
    });
    defer gpa.free(advance_ix.data);
    defer gpa.free(advance_ix.accounts);

    const blockhash = hash_mod.Hash.init([_]u8{9} ** 32);
    const ixs = [_]instruction_mod.Instruction{advance_ix};
    var msg = try message_mod.Message.compileLegacy(gpa, payer, &ixs, blockhash);
    defer msg.deinit();
    try std.testing.expectEqual(@as(usize, 1), msg.instructions.len);
}

test "nonce workflow: query -> build advance ix -> compile and sign" {
    const gpa = std.testing.allocator;
    const keypair_mod = @import("../core/keypair.zig");
    const message_mod = @import("../tx/message.zig");
    const transaction_mod = @import("../tx/transaction.zig");

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{7} ** 32);
    const nonce_account_key = pubkey_mod.Pubkey.init([_]u8{1} ** 32);
    const sysvar_key = pubkey_mod.Pubkey.init([_]u8{2} ** 32);

    // Step 1: simulate query nonce account and parse
    var nonce_data: [68]u8 = undefined;
    std.mem.writeInt(u32, nonce_data[0..4], 1, .little);
    @memcpy(nonce_data[4..36], &payer.pubkey().bytes);
    @memset(nonce_data[36..68], 0xAB);
    const nonce_state = try parseNonceAccountData(&nonce_data);
    try std.testing.expect(nonce_state == .initialized);

    // Step 2: build advance nonce instruction
    const advance_ix = try buildAdvanceNonceAccountInstruction(gpa, .{
        .nonce_account = nonce_account_key,
        .recent_blockhashes_sysvar = sysvar_key,
        .nonce_authority = payer.pubkey(),
    });
    defer gpa.free(advance_ix.data);
    defer gpa.free(advance_ix.accounts);

    // Step 3: compile message and sign transaction
    const blockhash = hash_mod.Hash.init([_]u8{9} ** 32);
    const ixs = [_]instruction_mod.Instruction{advance_ix};
    const msg = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    // Note: msg ownership moves into VersionedTransaction; do not deinit msg separately.

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{payer});
    try tx.verifySignatures();

    // Verify serialization roundtrip
    const serialized = try tx.serialize(gpa);
    defer gpa.free(serialized);
    var parsed = try transaction_mod.VersionedTransaction.deserialize(gpa, serialized);
    defer parsed.deinit();
    try parsed.verifySignatures();
}
