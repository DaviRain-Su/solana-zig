const std = @import("std");
const pubkey = @import("../core/pubkey.zig").Pubkey;
const instruction = @import("../tx/instruction.zig");
const bincode = @import("../compat/bincode_compat.zig");
const system = @import("system.zig");

pub const STAKE_STATE_SPACE: u64 = 200;

pub const StakeBuilderError = error{
    InvalidInstructionParams,
    MissingRequiredAuthority,
};

pub const StakeAuthorize = enum(u32) {
    staker = 0,
    withdrawer = 1,
};

pub const Lockup = struct {
    unix_timestamp: i64 = 0,
    epoch: u64 = 0,
    custodian: pubkey = pubkey.default(),
};

pub const Authorized = struct {
    staker: pubkey,
    withdrawer: pubkey,
};

pub const CreateStakeAccountParams = struct {
    from: pubkey,
    stake_pubkey: pubkey,
    authorized: Authorized,
    lockup: Lockup = .{},
    lamports: u64,
    space: u64 = STAKE_STATE_SPACE,
};

pub const StakeInstruction = enum(u32) {
    initialize = 0,
    authorize = 1,
    delegate_stake = 2,
    split = 3,
    withdraw = 4,
    deactivate = 5,
    set_lockup = 6,
    merge = 7,
    authorize_with_seed = 8,
    initialize_checked = 9,
    authorize_checked = 10,
    authorize_checked_with_seed = 11,
    set_lockup_checked = 12,
    get_minimum_delegation = 13,
    deactivate_delinquent = 14,
    move_stake = 15,
    move_lamports = 16,
};

pub fn stakeProgramId() pubkey {
    return pubkey.fromBase58("Stake11111111111111111111111111111111111111") catch unreachable;
}

fn clockSysvar() pubkey {
    return pubkey.fromBase58("SysvarC1ock11111111111111111111111111111111") catch unreachable;
}

fn stakeHistorySysvar() pubkey {
    return pubkey.fromBase58("SysvarStakeHistory1111111111111111111111111") catch unreachable;
}

fn rentSysvar() pubkey {
    return pubkey.fromBase58("SysvarRent111111111111111111111111111111111") catch unreachable;
}

fn freeInstruction(allocator: std.mem.Allocator, ix: instruction.Instruction) void {
    if (ix.data.len > 0) allocator.free(ix.data);
    if (ix.accounts.len > 0) allocator.free(ix.accounts);
}

pub fn deinitInstructions(allocator: std.mem.Allocator, instructions: []instruction.Instruction) void {
    for (instructions) |ix| freeInstruction(allocator, ix);
    allocator.free(instructions);
}

fn validateAuthority(authority: pubkey) StakeBuilderError!void {
    if (authority.eql(pubkey.default())) return error.MissingRequiredAuthority;
}

fn validateStakeAccount(stake_pubkey: pubkey) StakeBuilderError!void {
    if (stake_pubkey.eql(pubkey.default())) return error.InvalidInstructionParams;
}

fn validateAuthorized(authorized: Authorized) StakeBuilderError!void {
    try validateAuthority(authorized.staker);
    try validateAuthority(authorized.withdrawer);
}

pub fn buildInitializeStakeInstruction(
    allocator: std.mem.Allocator,
    stake_pubkey: pubkey,
    authorized: Authorized,
    lockup: Lockup,
) !instruction.Instruction {
    try validateStakeAccount(stake_pubkey);
    try validateAuthorized(authorized);

    var data = std.ArrayList(u8).empty;
    errdefer data.deinit(allocator);

    try bincode.writeU32(&data, allocator, @intFromEnum(StakeInstruction.initialize));
    try bincode.writePubkey(&data, allocator, authorized.staker);
    try bincode.writePubkey(&data, allocator, authorized.withdrawer);
    try bincode.writeI64(&data, allocator, lockup.unix_timestamp);
    try bincode.writeU64(&data, allocator, lockup.epoch);
    try bincode.writePubkey(&data, allocator, lockup.custodian);

    const accounts = try allocator.alloc(instruction.AccountMeta, 2);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = stake_pubkey, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = rentSysvar(), .is_signer = false, .is_writable = false };

    return .{
        .program_id = stakeProgramId(),
        .accounts = accounts,
        .data = try data.toOwnedSlice(allocator),
    };
}

pub fn buildCreateStakeAccountInstructions(
    allocator: std.mem.Allocator,
    params: CreateStakeAccountParams,
) ![]instruction.Instruction {
    try validateStakeAccount(params.stake_pubkey);
    try validateAuthorized(params.authorized);
    if (params.lamports == 0 or params.space == 0) return error.InvalidInstructionParams;

    const create_ix = try system.buildCreateAccountInstruction(allocator, .{
        .from = params.from,
        .new_account = params.stake_pubkey,
        .lamports = params.lamports,
        .space = params.space,
        .program_id = stakeProgramId(),
    });
    errdefer freeInstruction(allocator, create_ix);

    const initialize_ix = try buildInitializeStakeInstruction(
        allocator,
        params.stake_pubkey,
        params.authorized,
        params.lockup,
    );
    errdefer freeInstruction(allocator, initialize_ix);

    const instructions = try allocator.alloc(instruction.Instruction, 2);
    instructions[0] = create_ix;
    instructions[1] = initialize_ix;
    return instructions;
}

pub fn buildDelegateStakeInstruction(
    allocator: std.mem.Allocator,
    stake_pubkey: pubkey,
    vote_pubkey: pubkey,
    authorized_pubkey: pubkey,
) !instruction.Instruction {
    try validateStakeAccount(stake_pubkey);
    try validateAuthority(authorized_pubkey);

    var data = std.ArrayList(u8).empty;
    errdefer data.deinit(allocator);
    try bincode.writeU32(&data, allocator, @intFromEnum(StakeInstruction.delegate_stake));

    const accounts = try allocator.alloc(instruction.AccountMeta, 6);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = stake_pubkey, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = vote_pubkey, .is_signer = false, .is_writable = false };
    accounts[2] = .{ .pubkey = system.SYSTEM_PROGRAM_ID, .is_signer = false, .is_writable = false };
    accounts[3] = .{ .pubkey = clockSysvar(), .is_signer = false, .is_writable = false };
    accounts[4] = .{ .pubkey = stakeHistorySysvar(), .is_signer = false, .is_writable = false };
    accounts[5] = .{ .pubkey = authorized_pubkey, .is_signer = true, .is_writable = false };

    return .{
        .program_id = stakeProgramId(),
        .accounts = accounts,
        .data = try data.toOwnedSlice(allocator),
    };
}

pub fn buildDeactivateStakeInstruction(
    allocator: std.mem.Allocator,
    stake_pubkey: pubkey,
    authorized_pubkey: pubkey,
) !instruction.Instruction {
    try validateStakeAccount(stake_pubkey);
    try validateAuthority(authorized_pubkey);

    var data = std.ArrayList(u8).empty;
    errdefer data.deinit(allocator);
    try bincode.writeU32(&data, allocator, @intFromEnum(StakeInstruction.deactivate));

    const accounts = try allocator.alloc(instruction.AccountMeta, 3);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = stake_pubkey, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = clockSysvar(), .is_signer = false, .is_writable = false };
    accounts[2] = .{ .pubkey = authorized_pubkey, .is_signer = true, .is_writable = false };

    return .{
        .program_id = stakeProgramId(),
        .accounts = accounts,
        .data = try data.toOwnedSlice(allocator),
    };
}

pub fn buildWithdrawStakeInstruction(
    allocator: std.mem.Allocator,
    stake_pubkey: pubkey,
    to_pubkey: pubkey,
    authorized_pubkey: pubkey,
    lamports: u64,
) !instruction.Instruction {
    try validateStakeAccount(stake_pubkey);
    try validateAuthority(authorized_pubkey);
    if (lamports == 0) return error.InvalidInstructionParams;

    var data = std.ArrayList(u8).empty;
    errdefer data.deinit(allocator);
    try bincode.writeU32(&data, allocator, @intFromEnum(StakeInstruction.withdraw));
    try bincode.writeU64(&data, allocator, lamports);

    const accounts = try allocator.alloc(instruction.AccountMeta, 5);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = stake_pubkey, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = to_pubkey, .is_signer = false, .is_writable = true };
    accounts[2] = .{ .pubkey = clockSysvar(), .is_signer = false, .is_writable = false };
    accounts[3] = .{ .pubkey = stakeHistorySysvar(), .is_signer = false, .is_writable = false };
    accounts[4] = .{ .pubkey = authorized_pubkey, .is_signer = true, .is_writable = false };

    return .{
        .program_id = stakeProgramId(),
        .accounts = accounts,
        .data = try data.toOwnedSlice(allocator),
    };
}

test "buildInitializeStakeInstruction data layout" {
    const gpa = std.testing.allocator;
    const stake = pubkey.init([_]u8{0x22} ** 32);
    const authorized = Authorized{
        .staker = pubkey.init([_]u8{0x33} ** 32),
        .withdrawer = pubkey.init([_]u8{0x44} ** 32),
    };
    const lockup = Lockup{};

    const ix = try buildInitializeStakeInstruction(gpa, stake, authorized, lockup);
    defer gpa.free(ix.data);
    defer gpa.free(ix.accounts);

    try std.testing.expect(pubkey.eql(stakeProgramId(), ix.program_id));
    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, ix.data[0..4], .little));
    try std.testing.expect(pubkey.eql(stake, ix.accounts[0].pubkey));
    try std.testing.expectEqual(false, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
    try std.testing.expect(pubkey.eql(rentSysvar(), ix.accounts[1].pubkey));
}

test "buildCreateStakeAccountInstructions returns create-account plus initialize pair" {
    const gpa = std.testing.allocator;
    const payer = pubkey.init([_]u8{0x11} ** 32);
    const stake = pubkey.init([_]u8{0x12} ** 32);
    const authorized = Authorized{
        .staker = pubkey.init([_]u8{0x13} ** 32),
        .withdrawer = pubkey.init([_]u8{0x14} ** 32),
    };

    const ixs = try buildCreateStakeAccountInstructions(gpa, .{
        .from = payer,
        .stake_pubkey = stake,
        .authorized = authorized,
        .lamports = 1_000_000,
    });
    defer deinitInstructions(gpa, ixs);

    try std.testing.expectEqual(@as(usize, 2), ixs.len);

    try std.testing.expect(pubkey.eql(system.SYSTEM_PROGRAM_ID, ixs[0].program_id));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, ixs[0].data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 1_000_000), std.mem.readInt(u64, ixs[0].data[4..12], .little));
    try std.testing.expectEqual(STAKE_STATE_SPACE, std.mem.readInt(u64, ixs[0].data[12..20], .little));
    try std.testing.expectEqualSlices(u8, &stakeProgramId().bytes, ixs[0].data[20..52]);

    try std.testing.expect(pubkey.eql(stakeProgramId(), ixs[1].program_id));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, ixs[1].data[0..4], .little));
}

test "buildDelegateStakeInstruction data layout" {
    const gpa = std.testing.allocator;
    const stake = pubkey.init([_]u8{0x11} ** 32);
    const vote = pubkey.init([_]u8{0x22} ** 32);
    const auth = pubkey.init([_]u8{0x33} ** 32);

    const ix = try buildDelegateStakeInstruction(gpa, stake, vote, auth);
    defer gpa.free(ix.data);
    defer gpa.free(ix.accounts);

    try std.testing.expect(pubkey.eql(stakeProgramId(), ix.program_id));
    try std.testing.expectEqual(@as(usize, 6), ix.accounts.len);
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, ix.data[0..4], .little));
}

test "buildDelegateStakeInstruction account metas" {
    const gpa = std.testing.allocator;
    const stake = pubkey.init([_]u8{0x11} ** 32);
    const vote = pubkey.init([_]u8{0x22} ** 32);
    const auth = pubkey.init([_]u8{0x33} ** 32);
    const ix = try buildDelegateStakeInstruction(gpa, stake, vote, auth);
    defer gpa.free(ix.data);
    defer gpa.free(ix.accounts);

    try std.testing.expectEqual(@as(usize, 6), ix.accounts.len);

    // 0. stake account (writable, not signer)
    try std.testing.expect(pubkey.eql(stake, ix.accounts[0].pubkey));
    try std.testing.expectEqual(false, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);

    // 1. vote account (readonly, not signer)
    try std.testing.expect(pubkey.eql(vote, ix.accounts[1].pubkey));
    try std.testing.expectEqual(false, ix.accounts[1].is_signer);
    try std.testing.expectEqual(false, ix.accounts[1].is_writable);

    // 2. system program (readonly, not signer)
    try std.testing.expect(pubkey.eql(system.SYSTEM_PROGRAM_ID, ix.accounts[2].pubkey));
    try std.testing.expectEqual(false, ix.accounts[2].is_signer);
    try std.testing.expectEqual(false, ix.accounts[2].is_writable);

    // 3. clock sysvar (readonly, not signer)
    try std.testing.expect(pubkey.eql(clockSysvar(), ix.accounts[3].pubkey));
    try std.testing.expectEqual(false, ix.accounts[3].is_signer);
    try std.testing.expectEqual(false, ix.accounts[3].is_writable);

    // 4. stake history sysvar (readonly, not signer)
    try std.testing.expect(pubkey.eql(stakeHistorySysvar(), ix.accounts[4].pubkey));
    try std.testing.expectEqual(false, ix.accounts[4].is_signer);
    try std.testing.expectEqual(false, ix.accounts[4].is_writable);

    // 5. authorized pubkey (signer, readonly)
    try std.testing.expect(pubkey.eql(auth, ix.accounts[5].pubkey));
    try std.testing.expectEqual(true, ix.accounts[5].is_signer);
    try std.testing.expectEqual(false, ix.accounts[5].is_writable);
}

test "stake delegate builder compile into signed legacy transaction" {
    const gpa = std.testing.allocator;
    const keypair_mod = @import("../core/keypair.zig");
    const message_mod = @import("../tx/message.zig");
    const transaction_mod = @import("../tx/transaction.zig");
    const hash_mod = @import("../core/hash.zig");

    const authorized = try keypair_mod.Keypair.fromSeed([_]u8{0x2A} ** 32);
    const stake = pubkey.init([_]u8{0x11} ** 32);
    const vote = pubkey.init([_]u8{0x22} ** 32);

    const delegate_ix = try buildDelegateStakeInstruction(gpa, stake, vote, authorized.pubkey());
    defer gpa.free(delegate_ix.data);
    defer gpa.free(delegate_ix.accounts);

    const ixs = [_]instruction.Instruction{delegate_ix};
    const recent_blockhash = hash_mod.Hash.init([_]u8{0xAB} ** 32);
    const msg = try message_mod.Message.compileLegacy(gpa, authorized.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{authorized});
    try tx.verifySignatures();
}

test "buildDeactivateStakeInstruction data layout" {
    const gpa = std.testing.allocator;
    const stake = pubkey.init([_]u8{0x11} ** 32);
    const auth = pubkey.init([_]u8{0x33} ** 32);

    const ix = try buildDeactivateStakeInstruction(gpa, stake, auth);
    defer gpa.free(ix.data);
    defer gpa.free(ix.accounts);

    try std.testing.expect(pubkey.eql(stakeProgramId(), ix.program_id));
    try std.testing.expectEqual(@as(usize, 3), ix.accounts.len);
    try std.testing.expectEqual(@as(u32, 5), std.mem.readInt(u32, ix.data[0..4], .little));
}

test "buildWithdrawStakeInstruction data layout" {
    const gpa = std.testing.allocator;
    const stake = pubkey.init([_]u8{0x11} ** 32);
    const to = pubkey.init([_]u8{0x22} ** 32);
    const auth = pubkey.init([_]u8{0x33} ** 32);

    const ix = try buildWithdrawStakeInstruction(gpa, stake, to, auth, 500_000);
    defer gpa.free(ix.data);
    defer gpa.free(ix.accounts);

    try std.testing.expect(pubkey.eql(stakeProgramId(), ix.program_id));
    try std.testing.expectEqual(@as(usize, 5), ix.accounts.len);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, ix.data[0..4], .little));
    try std.testing.expectEqual(@as(u64, 500_000), std.mem.readInt(u64, ix.data[4..12], .little));
}

test "stake create helper compiles into signed legacy transaction" {
    const gpa = std.testing.allocator;
    const keypair_mod = @import("../core/keypair.zig");
    const message_mod = @import("../tx/message.zig");
    const transaction_mod = @import("../tx/transaction.zig");
    const hash_mod = @import("../core/hash.zig");

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{0x31} ** 32);
    const stake_account = try keypair_mod.Keypair.fromSeed([_]u8{0x32} ** 32);

    const ixs = try buildCreateStakeAccountInstructions(gpa, .{
        .from = payer.pubkey(),
        .stake_pubkey = stake_account.pubkey(),
        .authorized = .{
            .staker = payer.pubkey(),
            .withdrawer = payer.pubkey(),
        },
        .lamports = 1_500_000,
    });
    defer deinitInstructions(gpa, ixs);

    const recent_blockhash = hash_mod.Hash.init([_]u8{0x33} ** 32);
    var msg = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), ixs, recent_blockhash);
    errdefer msg.deinit();

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{ payer, stake_account });
    try tx.verifySignatures();
}

test "buildCreateStakeAccountInstructions rejects zero lamports" {
    const gpa = std.testing.allocator;
    const stake = pubkey.init([_]u8{0x41} ** 32);

    try std.testing.expectError(error.InvalidInstructionParams, buildCreateStakeAccountInstructions(gpa, .{
        .from = pubkey.init([_]u8{0x42} ** 32),
        .stake_pubkey = stake,
        .authorized = .{
            .staker = pubkey.init([_]u8{0x43} ** 32),
            .withdrawer = pubkey.init([_]u8{0x44} ** 32),
        },
        .lamports = 0,
    }));
}

test "stake builders reject missing authority" {
    const gpa = std.testing.allocator;
    const stake = pubkey.init([_]u8{0x51} ** 32);
    const vote = pubkey.init([_]u8{0x52} ** 32);
    const to = pubkey.init([_]u8{0x53} ** 32);

    try std.testing.expectError(
        error.MissingRequiredAuthority,
        buildDelegateStakeInstruction(gpa, stake, vote, pubkey.default()),
    );
    try std.testing.expectError(
        error.MissingRequiredAuthority,
        buildDeactivateStakeInstruction(gpa, stake, pubkey.default()),
    );
    try std.testing.expectError(
        error.MissingRequiredAuthority,
        buildWithdrawStakeInstruction(gpa, stake, to, pubkey.default(), 1),
    );
}

test "buildWithdrawStakeInstruction rejects zero lamports" {
    const gpa = std.testing.allocator;
    const stake = pubkey.init([_]u8{0x61} ** 32);
    const to = pubkey.init([_]u8{0x62} ** 32);
    const auth = pubkey.init([_]u8{0x63} ** 32);

    try std.testing.expectError(
        error.InvalidInstructionParams,
        buildWithdrawStakeInstruction(gpa, stake, to, auth, 0),
    );
}

test "buildCreateStakeAccountInstructions rejects default stake pubkey" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(
        error.InvalidInstructionParams,
        buildCreateStakeAccountInstructions(gpa, .{
            .from = pubkey.init([_]u8{0x71} ** 32),
            .stake_pubkey = pubkey.default(),
            .authorized = .{
                .staker = pubkey.init([_]u8{0x72} ** 32),
                .withdrawer = pubkey.init([_]u8{0x73} ** 32),
            },
            .lamports = 1_000_000,
        }),
    );
}

test "buildCreateStakeAccountInstructions rejects default authority" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(
        error.MissingRequiredAuthority,
        buildCreateStakeAccountInstructions(gpa, .{
            .from = pubkey.init([_]u8{0x81} ** 32),
            .stake_pubkey = pubkey.init([_]u8{0x82} ** 32),
            .authorized = .{
                .staker = pubkey.default(),
                .withdrawer = pubkey.init([_]u8{0x83} ** 32),
            },
            .lamports = 1_000_000,
        }),
    );
}

test "buildInitializeStakeInstruction rejects default stake pubkey" {
    const gpa = std.testing.allocator;
    const authorized = Authorized{
        .staker = pubkey.init([_]u8{0x91} ** 32),
        .withdrawer = pubkey.init([_]u8{0x92} ** 32),
    };

    try std.testing.expectError(
        error.InvalidInstructionParams,
        buildInitializeStakeInstruction(gpa, pubkey.default(), authorized, .{}),
    );
}
