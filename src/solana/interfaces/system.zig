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

pub const TransferParams = struct {
    from: pubkey_mod.Pubkey,
    to: pubkey_mod.Pubkey,
    lamports: u64,
};

pub const CreateAccountParams = struct {
    from: pubkey_mod.Pubkey,
    new_account: pubkey_mod.Pubkey,
    lamports: u64,
    space: u64,
    program_id: pubkey_mod.Pubkey,
};

pub const AssignParams = struct {
    account: pubkey_mod.Pubkey,
    program_id: pubkey_mod.Pubkey,
};

pub const AdvanceNonceAccountParams = struct {
    nonce_account: pubkey_mod.Pubkey,
    recent_blockhashes_sysvar: pubkey_mod.Pubkey,
    nonce_authority: pubkey_mod.Pubkey,
};

/// Build System Program `Transfer` instruction.
///
/// Data layout: [u32=2] ++ little-endian u64 lamports.
/// Accounts:
/// 0. from (signer, writable)
/// 1. to (writable)
pub fn buildTransferInstruction(
    allocator: std.mem.Allocator,
    params: TransferParams,
) !instruction_mod.Instruction {
    var data = try allocator.alloc(u8, 12);
    errdefer allocator.free(data);
    std.mem.writeInt(u32, data[0..4], 2, .little);
    std.mem.writeInt(u64, data[4..12], params.lamports, .little);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 2);
    errdefer allocator.free(accounts);
    accounts[0] = .{
        .pubkey = params.from,
        .is_signer = true,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.to,
        .is_signer = false,
        .is_writable = true,
    };

    return .{
        .program_id = SYSTEM_PROGRAM_ID,
        .accounts = accounts,
        .data = data,
    };
}

/// Build System Program `CreateAccount` instruction.
///
/// Data layout: [u32=0] ++ little-endian u64 lamports ++ little-endian u64 space ++ Pubkey owner.
/// Accounts:
/// 0. from (signer, writable)
/// 1. new_account (signer, writable)
pub fn buildCreateAccountInstruction(
    allocator: std.mem.Allocator,
    params: CreateAccountParams,
) !instruction_mod.Instruction {
    var data = try allocator.alloc(u8, 52);
    errdefer allocator.free(data);
    std.mem.writeInt(u32, data[0..4], 0, .little);
    std.mem.writeInt(u64, data[4..12], params.lamports, .little);
    std.mem.writeInt(u64, data[12..20], params.space, .little);
    @memcpy(data[20..52], &params.program_id.bytes);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 2);
    errdefer allocator.free(accounts);
    accounts[0] = .{
        .pubkey = params.from,
        .is_signer = true,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.new_account,
        .is_signer = true,
        .is_writable = true,
    };

    return .{
        .program_id = SYSTEM_PROGRAM_ID,
        .accounts = accounts,
        .data = data,
    };
}

/// Build System Program `Assign` instruction.
///
/// Data layout: [u32=1] ++ Pubkey owner.
/// Accounts:
/// 0. account (signer, writable)
pub fn buildAssignInstruction(
    allocator: std.mem.Allocator,
    params: AssignParams,
) !instruction_mod.Instruction {
    var data = try allocator.alloc(u8, 36);
    errdefer allocator.free(data);
    std.mem.writeInt(u32, data[0..4], 1, .little);
    @memcpy(data[4..36], &params.program_id.bytes);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 1);
    errdefer allocator.free(accounts);
    accounts[0] = .{
        .pubkey = params.account,
        .is_signer = true,
        .is_writable = true,
    };

    return .{
        .program_id = SYSTEM_PROGRAM_ID,
        .accounts = accounts,
        .data = data,
    };
}

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

test "transfer byte layout and account metas" {
    const allocator = std.testing.allocator;
    const from = pubkey_mod.Pubkey.init([_]u8{0x11} ** 32);
    const to = pubkey_mod.Pubkey.init([_]u8{0x22} ** 32);

    const ix = try buildTransferInstruction(allocator, .{
        .from = from,
        .to = to,
        .lamports = 1_000_000,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expect(ix.program_id.eql(SYSTEM_PROGRAM_ID));
    try std.testing.expectEqual(@as(usize, 12), ix.data.len);
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, ix.data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 1_000_000), std.mem.readInt(u64, ix.data[4..12], .little));

    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(from));
    try std.testing.expectEqual(true, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
    try std.testing.expect(ix.accounts[1].pubkey.eql(to));
    try std.testing.expectEqual(false, ix.accounts[1].is_signer);
    try std.testing.expectEqual(true, ix.accounts[1].is_writable);
}

test "transfer boundary: zero lamports" {
    const allocator = std.testing.allocator;
    const key = pubkey_mod.Pubkey.init([_]u8{0x33} ** 32);

    const ix = try buildTransferInstruction(allocator, .{
        .from = key,
        .to = key,
        .lamports = 0,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, ix.data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, ix.data[4..12], .little));
}

test "transfer boundary: max lamports" {
    const allocator = std.testing.allocator;
    const key = pubkey_mod.Pubkey.init([_]u8{0x44} ** 32);

    const ix = try buildTransferInstruction(allocator, .{
        .from = key,
        .to = key,
        .lamports = std.math.maxInt(u64),
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(std.math.maxInt(u64), std.mem.readInt(u64, ix.data[4..12], .little));
}

test "createAccount byte layout and account metas" {
    const allocator = std.testing.allocator;
    const from = pubkey_mod.Pubkey.init([_]u8{0x55} ** 32);
    const new_account = pubkey_mod.Pubkey.init([_]u8{0x66} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{0x77} ** 32);

    const ix = try buildCreateAccountInstruction(allocator, .{
        .from = from,
        .new_account = new_account,
        .lamports = 5_000,
        .space = 128,
        .program_id = owner,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expect(ix.program_id.eql(SYSTEM_PROGRAM_ID));
    try std.testing.expectEqual(@as(usize, 52), ix.data.len);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, ix.data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 5_000), std.mem.readInt(u64, ix.data[4..12], .little));
    try std.testing.expectEqual(@as(u64, 128), std.mem.readInt(u64, ix.data[12..20], .little));
    try std.testing.expect(std.mem.eql(u8, ix.data[20..52], &owner.bytes));

    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(from));
    try std.testing.expectEqual(true, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
    try std.testing.expect(ix.accounts[1].pubkey.eql(new_account));
    try std.testing.expectEqual(true, ix.accounts[1].is_signer);
    try std.testing.expectEqual(true, ix.accounts[1].is_writable);
}

test "createAccount boundary: zero lamports and zero space" {
    const allocator = std.testing.allocator;
    const from = pubkey_mod.Pubkey.init([_]u8{0x88} ** 32);
    const new_account = pubkey_mod.Pubkey.init([_]u8{0x99} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{0xAA} ** 32);

    const ix = try buildCreateAccountInstruction(allocator, .{
        .from = from,
        .new_account = new_account,
        .lamports = 0,
        .space = 0,
        .program_id = owner,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, ix.data[4..12], .little));
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, ix.data[12..20], .little));
}

test "assign byte layout and account metas" {
    const allocator = std.testing.allocator;
    const account = pubkey_mod.Pubkey.init([_]u8{0xAB} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{0xBC} ** 32);

    const ix = try buildAssignInstruction(allocator, .{
        .account = account,
        .program_id = owner,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expect(ix.program_id.eql(SYSTEM_PROGRAM_ID));
    try std.testing.expectEqual(@as(usize, 36), ix.data.len);
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, ix.data[0..4], .little));
    try std.testing.expect(std.mem.eql(u8, ix.data[4..36], &owner.bytes));

    try std.testing.expectEqual(@as(usize, 1), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(account));
    try std.testing.expectEqual(true, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
}

test "system builders compile into signed legacy transaction" {
    const allocator = std.testing.allocator;
    const keypair_mod = @import("../core/keypair.zig");
    const message_mod = @import("../tx/message.zig");
    const transaction_mod = @import("../tx/transaction.zig");

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{0x2A} ** 32);
    const new_account_keypair = try keypair_mod.Keypair.fromSeed([_]u8{0x2B} ** 32);
    const recipient = pubkey_mod.Pubkey.init([_]u8{0xBB} ** 32);
    const program_owner = pubkey_mod.Pubkey.init([_]u8{0xDD} ** 32);

    const transfer_ix = try buildTransferInstruction(allocator, .{
        .from = payer.pubkey(),
        .to = recipient,
        .lamports = 1_000,
    });
    defer allocator.free(transfer_ix.data);
    defer allocator.free(transfer_ix.accounts);

    const create_ix = try buildCreateAccountInstruction(allocator, .{
        .from = payer.pubkey(),
        .new_account = new_account_keypair.pubkey(),
        .lamports = 2_000,
        .space = 64,
        .program_id = program_owner,
    });
    defer allocator.free(create_ix.data);
    defer allocator.free(create_ix.accounts);

    const assign_ix = try buildAssignInstruction(allocator, .{
        .account = new_account_keypair.pubkey(),
        .program_id = program_owner,
    });
    defer allocator.free(assign_ix.data);
    defer allocator.free(assign_ix.accounts);

    const ixs = [_]instruction_mod.Instruction{ transfer_ix, create_ix, assign_ix };
    const recent_blockhash = hash_mod.Hash.init([_]u8{0xAB} ** 32);
    const msg = try message_mod.Message.compileLegacy(allocator, payer.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{ payer, new_account_keypair });
    try tx.verifySignatures();
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
