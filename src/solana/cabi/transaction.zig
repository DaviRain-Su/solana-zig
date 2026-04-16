const std = @import("std");
const solana = @import("../mod.zig");
const errors = @import("errors.zig");

export fn solana_instruction_create(
    program_id: *const solana.core.Pubkey,
    accounts: ?[*]const solana.tx.AccountMeta,
    account_count: usize,
    data: [*c]const u8,
    data_len: usize,
    out: **solana.tx.Instruction,
) c_int {
    if (out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;

    const allocator = std.heap.c_allocator;

    const accts = if (account_count > 0 and accounts != null)
        allocator.dupe(solana.tx.AccountMeta, accounts.?[0..account_count]) catch return errors.SOLANA_ERR_INTERNAL
    else
        &[_]solana.tx.AccountMeta{};
    errdefer if (account_count > 0) allocator.free(accts);

    const d = if (data_len > 0 and data != null)
        allocator.dupe(u8, data.?[0..data_len]) catch return errors.SOLANA_ERR_INTERNAL
    else
        &[_]u8{};
    errdefer if (data_len > 0) allocator.free(d);

    const ix = allocator.create(solana.tx.Instruction) catch return errors.SOLANA_ERR_INTERNAL;
    ix.* = .{
        .program_id = program_id.*,
        .accounts = accts,
        .data = d,
    };
    out.* = ix;
    return errors.SOLANA_OK;
}

export fn solana_instruction_destroy(ix: **solana.tx.Instruction) void {
    if (ix == null or ix.* == null) return;
    ix.*.?.deinit(std.heap.c_allocator);
    std.heap.c_allocator.destroy(ix.*.?);
    ix.* = null;
}

export fn solana_message_compile_legacy(
    payer: *const solana.core.Pubkey,
    instructions: ?[*]*const solana.tx.Instruction,
    instruction_count: usize,
    recent_blockhash: *const solana.core.Hash,
    out: **solana.tx.Message,
) c_int {
    if (out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const allocator = std.heap.c_allocator;

    const ixs = allocator.alloc(solana.tx.Instruction, instruction_count) catch return errors.SOLANA_ERR_INTERNAL;
    defer allocator.free(ixs);

    for (0..instruction_count) |i| {
        const src = instructions.?[i];
        ixs[i] = .{
            .program_id = src.program_id,
            .accounts = allocator.dupe(solana.tx.AccountMeta, src.accounts) catch return errors.SOLANA_ERR_INTERNAL,
            .data = allocator.dupe(u8, src.data) catch return errors.SOLANA_ERR_INTERNAL,
        };
    }
    errdefer for (ixs) |ix| {
        allocator.free(ix.accounts);
        allocator.free(ix.data);
    };

    const msg = allocator.create(solana.tx.Message) catch return errors.SOLANA_ERR_INTERNAL;
    msg.* = solana.tx.Message.compileLegacy(allocator, payer.*, &ixs, recent_blockhash.*) catch {
        allocator.destroy(msg);
        return errors.SOLANA_ERR_INTERNAL;
    };
    out.* = msg;
    return errors.SOLANA_OK;
}

export fn solana_message_destroy(msg: **solana.tx.Message) void {
    if (msg == null or msg.* == null) return;
    msg.*.?.deinit();
    std.heap.c_allocator.destroy(msg.*.?);
    msg.* = null;
}

export fn solana_transaction_create_unsigned(msg: *solana.tx.Message, out: **solana.tx.VersionedTransaction) c_int {
    if (out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const allocator = std.heap.c_allocator;
    const tx = allocator.create(solana.tx.VersionedTransaction) catch return errors.SOLANA_ERR_INTERNAL;
    tx.* = solana.tx.VersionedTransaction.initUnsigned(allocator, msg.*) catch {
        allocator.destroy(tx);
        return errors.SOLANA_ERR_INTERNAL;
    };
    out.* = tx;
    return errors.SOLANA_OK;
}

export fn solana_transaction_sign_with_keypair(tx: *solana.tx.VersionedTransaction, secret_key: [*c]const u8) c_int {
    if (secret_key == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const kp = solana.core.Keypair.fromSecretKey(secret_key[0..64].*) catch return errors.SOLANA_ERR_INVALID_ARGUMENT;
    tx.sign(&[_]solana.core.Keypair{kp}) catch |err| switch (err) {
        error.MissingRequiredSignature => return errors.SOLANA_ERR_INVALID_ARGUMENT,
        error.SignatureCountMismatch => return errors.SOLANA_ERR_INVALID_ARGUMENT,
        else => return errors.SOLANA_ERR_INTERNAL,
    };
    return errors.SOLANA_OK;
}

export fn solana_transaction_serialize(tx: *const solana.tx.VersionedTransaction, out_bytes: *[*c]u8, out_len: *usize) c_int {
    const bytes = tx.serialize(std.heap.c_allocator) catch return errors.SOLANA_ERR_INTERNAL;
    out_bytes.* = bytes.ptr;
    out_len.* = bytes.len;
    return errors.SOLANA_OK;
}

export fn solana_transaction_destroy(tx: **solana.tx.VersionedTransaction) void {
    if (tx == null or tx.* == null) return;
    tx.*.?.deinit();
    std.heap.c_allocator.destroy(tx.*.?);
    tx.* = null;
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

    var ix: *solana.tx.Instruction = undefined;
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
    const payer = solana.core.Pubkey.init([_]u8{6} ** 32);
    const blockhash = solana.core.Hash.init([_]u8{5} ** 32);
    const accounts = [_]solana.tx.AccountMeta{
        .{ .pubkey = payer, .is_signer = true, .is_writable = true },
    };
    const data = [_]u8{0x01};

    var ix: *solana.tx.Instruction = undefined;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_instruction_create(
        &program_id,
        &accounts,
        accounts.len,
        &data,
        data.len,
        &ix,
    ));
    defer solana_instruction_destroy(&ix);

    var msg: *solana.tx.Message = undefined;
    const ix_ptrs = [_]*const solana.tx.Instruction{ix};
    try std.testing.expectEqual(errors.SOLANA_OK, solana_message_compile_legacy(
        &payer,
        &ix_ptrs,
        ix_ptrs.len,
        &blockhash,
        &msg,
    ));
    defer solana_message_destroy(&msg);

    var tx: *solana.tx.VersionedTransaction = undefined;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_transaction_create_unsigned(msg, &tx));
    defer solana_transaction_destroy(&tx);

    const seed = [_]u8{3} ** 32;
    const kp = try solana.core.Keypair.fromSeed(seed);
    const secret_bytes = kp.ed25519.secret_key.toBytes();
    try std.testing.expectEqual(errors.SOLANA_OK, solana_transaction_sign_with_keypair(tx, &secret_bytes));

    var serialized: [*c]u8 = undefined;
    var serialized_len: usize = 0;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_transaction_serialize(tx, &serialized, &serialized_len));
    defer solana_bytes_free(serialized, serialized_len);

    try std.testing.expect(serialized_len > 0);
}
