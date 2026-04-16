const std = @import("std");
const pubkey = @import("../core/pubkey.zig").Pubkey;
const instruction = @import("../tx/instruction.zig");
const bincode = @import("../compat/bincode_compat.zig");

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

pub fn buildCreateStakeAccountInstruction(
    allocator: std.mem.Allocator,
    from_pubkey: pubkey,
    stake_pubkey: pubkey,
    authorized: Authorized,
    lockup: Lockup,
    _: u64,
) !instruction.Instruction {
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
    accounts[0] = .{ .pubkey = from_pubkey, .is_signer = true, .is_writable = true };
    accounts[1] = .{ .pubkey = stake_pubkey, .is_signer = true, .is_writable = true };

    return .{
        .program_id = stakeProgramId(),
        .accounts = accounts,
        .data = try data.toOwnedSlice(allocator),
    };
}

pub fn buildDelegateStakeInstruction(
    allocator: std.mem.Allocator,
    stake_pubkey: pubkey,
    vote_pubkey: pubkey,
    authorized_pubkey: pubkey,
) !instruction.Instruction {
    var data = std.ArrayList(u8).empty;
    errdefer data.deinit(allocator);
    try bincode.writeU32(&data, allocator, @intFromEnum(StakeInstruction.delegate_stake));

    const accounts = try allocator.alloc(instruction.AccountMeta, 6);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = stake_pubkey, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = vote_pubkey, .is_signer = false, .is_writable = false };
    accounts[2] = .{ .pubkey = @import("system.zig").SYSTEM_PROGRAM_ID, .is_signer = false, .is_writable = false };
    accounts[3] = .{ .pubkey = @import("../core/pubkey.zig").Pubkey.fromBase58("SysvarC1ock11111111111111111111111111111111") catch unreachable, .is_signer = false, .is_writable = false };
    accounts[4] = .{ .pubkey = @import("../core/pubkey.zig").Pubkey.fromBase58("SysvarStakeHistory1111111111111111111111111") catch unreachable, .is_signer = false, .is_writable = false };
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
    var data = std.ArrayList(u8).empty;
    errdefer data.deinit(allocator);
    try bincode.writeU32(&data, allocator, @intFromEnum(StakeInstruction.deactivate));

    const accounts = try allocator.alloc(instruction.AccountMeta, 3);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = stake_pubkey, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = @import("../core/pubkey.zig").Pubkey.fromBase58("SysvarC1ock11111111111111111111111111111111") catch unreachable, .is_signer = false, .is_writable = false };
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
    var data = std.ArrayList(u8).empty;
    errdefer data.deinit(allocator);
    try bincode.writeU32(&data, allocator, @intFromEnum(StakeInstruction.withdraw));
    try bincode.writeU64(&data, allocator, lamports);

    const accounts = try allocator.alloc(instruction.AccountMeta, 5);
    errdefer allocator.free(accounts);
    accounts[0] = .{ .pubkey = stake_pubkey, .is_signer = false, .is_writable = true };
    accounts[1] = .{ .pubkey = to_pubkey, .is_signer = false, .is_writable = true };
    accounts[2] = .{ .pubkey = @import("../core/pubkey.zig").Pubkey.fromBase58("SysvarC1ock11111111111111111111111111111111") catch unreachable, .is_signer = false, .is_writable = false };
    accounts[3] = .{ .pubkey = @import("../core/pubkey.zig").Pubkey.fromBase58("SysvarStakeHistory1111111111111111111111111") catch unreachable, .is_signer = false, .is_writable = false };
    accounts[4] = .{ .pubkey = authorized_pubkey, .is_signer = true, .is_writable = false };

    return .{
        .program_id = stakeProgramId(),
        .accounts = accounts,
        .data = try data.toOwnedSlice(allocator),
    };
}

test "buildCreateStakeAccountInstruction data layout" {
    const gpa = std.testing.allocator;
    const from = pubkey.init([_]u8{0x11} ** 32);
    const stake = pubkey.init([_]u8{0x22} ** 32);
    const authorized = Authorized{
        .staker = pubkey.init([_]u8{0x33} ** 32),
        .withdrawer = pubkey.init([_]u8{0x44} ** 32),
    };
    const lockup = Lockup{};

    const ix = try buildCreateStakeAccountInstruction(gpa, from, stake, authorized, lockup, 1_000_000);
    defer gpa.free(ix.data);
    defer gpa.free(ix.accounts);

    try std.testing.expect(pubkey.eql(stakeProgramId(), ix.program_id));
    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, ix.data[0..4], .little));
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
    const system_program = @import("system.zig").SYSTEM_PROGRAM_ID;
    const clock_sysvar = pubkey.fromBase58("SysvarC1ock11111111111111111111111111111111") catch unreachable;
    const stake_history_sysvar = pubkey.fromBase58("SysvarStakeHistory1111111111111111111111111") catch unreachable;

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
    try std.testing.expect(pubkey.eql(system_program, ix.accounts[2].pubkey));
    try std.testing.expectEqual(false, ix.accounts[2].is_signer);
    try std.testing.expectEqual(false, ix.accounts[2].is_writable);

    // 3. clock sysvar (readonly, not signer)
    try std.testing.expect(pubkey.eql(clock_sysvar, ix.accounts[3].pubkey));
    try std.testing.expectEqual(false, ix.accounts[3].is_signer);
    try std.testing.expectEqual(false, ix.accounts[3].is_writable);

    // 4. stake history sysvar (readonly, not signer)
    try std.testing.expect(pubkey.eql(stake_history_sysvar, ix.accounts[4].pubkey));
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
