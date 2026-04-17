const std = @import("std");
const solana = @import("../mod.zig");
const errors = @import("errors.zig");

fn freeInstruction(allocator: std.mem.Allocator, ix: *solana.tx.Instruction) void {
    if (ix.accounts.len > 0) allocator.free(ix.accounts);
    if (ix.data.len > 0) allocator.free(ix.data);
}

export fn solana_instruction_create(
    program_id: ?*const solana.core.Pubkey,
    accounts: ?[*]const solana.tx.AccountMeta,
    account_count: usize,
    data: [*c]const u8,
    data_len: usize,
    out: [*c]?*solana.tx.Instruction,
) c_int {
    if (program_id == null or out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;

    const allocator = std.heap.c_allocator;

    const accts = if (account_count > 0 and accounts != null)
        allocator.dupe(solana.tx.AccountMeta, accounts.?[0..account_count]) catch return errors.SOLANA_ERR_INTERNAL
    else
        &[_]solana.tx.AccountMeta{};

    const d = if (data_len > 0 and data != null)
        allocator.dupe(u8, data[0..data_len]) catch {
            if (account_count > 0) allocator.free(accts);
            return errors.SOLANA_ERR_INTERNAL;
        }
    else
        &[_]u8{};

    const ix = allocator.create(solana.tx.Instruction) catch {
        if (data_len > 0) allocator.free(d);
        if (account_count > 0) allocator.free(accts);
        return errors.SOLANA_ERR_INTERNAL;
    };
    ix.* = .{
        .program_id = program_id.?.*,
        .accounts = accts,
        .data = d,
    };
    out[0] = ix;
    return errors.SOLANA_OK;
}

export fn solana_instruction_destroy(ix: [*c]?*solana.tx.Instruction) void {
    if (ix == null or ix[0] == null) return;
    freeInstruction(std.heap.c_allocator, ix[0].?);
    std.heap.c_allocator.destroy(ix[0].?);
    ix[0] = null;
}

export fn solana_message_compile_legacy(
    payer: ?*const solana.core.Pubkey,
    instructions: ?[*]const *const solana.tx.Instruction,
    instruction_count: usize,
    recent_blockhash: ?*const solana.core.Hash,
    out: [*c]?*solana.tx.Message,
) c_int {
    if (payer == null or recent_blockhash == null or out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const allocator = std.heap.c_allocator;

    const ixs = allocator.alloc(solana.tx.Instruction, instruction_count) catch return errors.SOLANA_ERR_INTERNAL;
    defer allocator.free(ixs);

    var initialized_ix_count: usize = 0;
    for (0..instruction_count) |i| {
        const src = instructions.?[i];
        const accounts = allocator.dupe(solana.tx.AccountMeta, src.accounts) catch {
            for (0..initialized_ix_count) |j| {
                allocator.free(ixs[j].accounts);
                allocator.free(ixs[j].data);
            }
            return errors.SOLANA_ERR_INTERNAL;
        };
        const d = allocator.dupe(u8, src.data) catch {
            allocator.free(accounts);
            for (0..initialized_ix_count) |j| {
                allocator.free(ixs[j].accounts);
                allocator.free(ixs[j].data);
            }
            return errors.SOLANA_ERR_INTERNAL;
        };
        ixs[i] = .{
            .program_id = src.program_id,
            .accounts = accounts,
            .data = d,
        };
        initialized_ix_count += 1;
    }

    const msg = allocator.create(solana.tx.Message) catch {
        for (0..initialized_ix_count) |j| {
            allocator.free(ixs[j].accounts);
            allocator.free(ixs[j].data);
        }
        return errors.SOLANA_ERR_INTERNAL;
    };
    msg.* = solana.tx.Message.compileLegacy(allocator, payer.?.*, ixs, recent_blockhash.?.*) catch {
        allocator.destroy(msg);
        for (0..initialized_ix_count) |j| {
            allocator.free(ixs[j].accounts);
            allocator.free(ixs[j].data);
        }
        return errors.SOLANA_ERR_INTERNAL;
    };
    out[0] = msg;
    return errors.SOLANA_OK;
}

export fn solana_message_destroy(msg: [*c]?*solana.tx.Message) void {
    if (msg == null or msg[0] == null) return;
    msg[0].?.deinit();
    std.heap.c_allocator.destroy(msg[0].?);
    msg[0] = null;
}

export fn solana_transaction_create_unsigned(msg: [*c]?*solana.tx.Message, out: [*c]?*solana.tx.VersionedTransaction) c_int {
    if (msg == null or msg[0] == null or out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const allocator = std.heap.c_allocator;
    const tx = allocator.create(solana.tx.VersionedTransaction) catch return errors.SOLANA_ERR_INTERNAL;
    tx.* = solana.tx.VersionedTransaction.initUnsigned(allocator, msg[0].?.*) catch {
        allocator.destroy(tx);
        return errors.SOLANA_ERR_INTERNAL;
    };
    // Transfer ownership: destroy the message wrapper and null out the handle.
    allocator.destroy(msg[0].?);
    msg[0] = null;
    out[0] = tx;
    return errors.SOLANA_OK;
}

export fn solana_transaction_sign_with_keypair(tx: ?*solana.tx.VersionedTransaction, secret_key: [*c]const u8, secret_key_len: usize) c_int {
    if (tx == null or secret_key == null or secret_key_len != 64) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const kp = solana.core.Keypair.fromSecretKey(secret_key[0..64].*) catch return errors.SOLANA_ERR_INVALID_ARGUMENT;
    tx.?.sign(&[_]solana.core.Keypair{kp}) catch |err| switch (err) {
        error.MissingRequiredSignature => return errors.SOLANA_ERR_INVALID_ARGUMENT,
        error.SignatureCountMismatch => return errors.SOLANA_ERR_INVALID_ARGUMENT,
        else => return errors.SOLANA_ERR_INTERNAL,
    };
    return errors.SOLANA_OK;
}

export fn solana_transaction_serialize(tx: ?*const solana.tx.VersionedTransaction, out_bytes: *[*c]u8, out_len: *usize) c_int {
    if (tx == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const bytes = tx.?.serialize(std.heap.c_allocator) catch return errors.SOLANA_ERR_INTERNAL;
    out_bytes.* = bytes.ptr;
    out_len.* = bytes.len;
    return errors.SOLANA_OK;
}

export fn solana_transaction_destroy(tx: [*c]?*solana.tx.VersionedTransaction) void {
    if (tx == null or tx[0] == null) return;
    tx[0].?.deinit();
    std.heap.c_allocator.destroy(tx[0].?);
    tx[0] = null;
}

export fn solana_bytes_free(bytes: [*c]u8, len: usize) void {
    if (bytes == null) return;
    std.heap.c_allocator.free(bytes[0..len]);
}

test "cabi instruction create/destroy" {
    const program_id = solana.core.Pubkey.init([_]u8{9} ** 32);
    const accounts = [_]solana.tx.AccountMeta{
        .{ .pubkey = solana.core.Pubkey.init([_]u8{8} ** 32), .is_signer = true, .is_writable = true },
    };
    const data = [_]u8{ 0xAB, 0xCD };

    var ix: ?*solana.tx.Instruction = null;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_instruction_create(
        &program_id,
        &accounts,
        accounts.len,
        &data,
        data.len,
        &ix,
    ));
    solana_instruction_destroy(&ix);
    try std.testing.expect(ix == null);
}

test "cabi transaction build serialize destroy" {
    const program_id = solana.core.Pubkey.init([_]u8{7} ** 32);
    const seed = [_]u8{3} ** 32;
    const kp = try solana.core.Keypair.fromSeed(seed);
    const payer = kp.pubkey();
    const blockhash = solana.core.Hash.init([_]u8{5} ** 32);
    const accounts = [_]solana.tx.AccountMeta{
        .{ .pubkey = payer, .is_signer = true, .is_writable = true },
    };
    const data = [_]u8{0x01};

    var ix: ?*solana.tx.Instruction = null;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_instruction_create(
        &program_id,
        &accounts,
        accounts.len,
        &data,
        data.len,
        &ix,
    ));
    defer solana_instruction_destroy(&ix);

    var msg: ?*solana.tx.Message = null;
    const ix_ptrs = [_]*const solana.tx.Instruction{ix.?};
    try std.testing.expectEqual(errors.SOLANA_OK, solana_message_compile_legacy(
        &payer,
        @ptrCast(&ix_ptrs),
        ix_ptrs.len,
        &blockhash,
        &msg,
    ));
    defer solana_message_destroy(&msg);

    var tx: ?*solana.tx.VersionedTransaction = null;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_transaction_create_unsigned(&msg, &tx));
    defer solana_transaction_destroy(&tx);

    const secret_bytes = kp.ed25519.secret_key.toBytes();
    try std.testing.expectEqual(errors.SOLANA_OK, solana_transaction_sign_with_keypair(tx.?, &secret_bytes, secret_bytes.len));

    var serialized: [*c]u8 = undefined;
    var serialized_len: usize = 0;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_transaction_serialize(tx.?, &serialized, &serialized_len));
    defer solana_bytes_free(serialized, serialized_len);

    try std.testing.expect(serialized_len > 0);
}
