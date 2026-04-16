const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const instruction_mod = @import("../tx/instruction.zig");
const hash_mod = @import("../core/hash.zig");
const keypair_mod = @import("../core/keypair.zig");
const message_mod = @import("../tx/message.zig");
const transaction_mod = @import("../tx/transaction.zig");
const rpc_client_mod = @import("../rpc/client.zig");
const rpc_transport_mod = @import("../rpc/transport.zig");

const TOKEN_PROGRAM_ID_STR = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";

const Discriminant = enum(u8) {
    approve = 4,
    mint_to = 7,
    burn = 8,
    close_account = 9,
    transfer_checked = 12,
};

pub const TransferCheckedParams = struct {
    source: pubkey_mod.Pubkey,
    mint: pubkey_mod.Pubkey,
    destination: pubkey_mod.Pubkey,
    owner: pubkey_mod.Pubkey,
    amount: u64,
    decimals: u8,
};

pub const CloseAccountParams = struct {
    account: pubkey_mod.Pubkey,
    destination: pubkey_mod.Pubkey,
    owner: pubkey_mod.Pubkey,
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

/// SPL Token program ID: TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA
pub fn programId() pubkey_mod.Pubkey {
    return pubkey_mod.Pubkey.fromBase58(TOKEN_PROGRAM_ID_STR) catch unreachable;
}

/// Build SPL Token `TransferChecked` instruction.
///
/// Data layout: [0x0C] ++ little-endian u64 amount ++ u8 decimals.
/// Accounts (single-signer owner):
/// 0. source (writable)
/// 1. mint (readonly)
/// 2. destination (writable)
/// 3. owner (readonly signer)
pub fn buildTransferCheckedInstruction(
    allocator: std.mem.Allocator,
    params: TransferCheckedParams,
) !instruction_mod.Instruction {
    const data = try allocator.alloc(u8, 10);
    errdefer allocator.free(data);

    data[0] = @intFromEnum(Discriminant.transfer_checked);
    std.mem.writeInt(u64, data[1..9], params.amount, .little);
    data[9] = params.decimals;

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 4);
    errdefer allocator.free(accounts);

    accounts[0] = .{
        .pubkey = params.source,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.mint,
        .is_signer = false,
        .is_writable = false,
    };
    accounts[2] = .{
        .pubkey = params.destination,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[3] = .{
        .pubkey = params.owner,
        .is_signer = true,
        .is_writable = false,
    };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

/// Build SPL Token `CloseAccount` instruction.
///
/// Data layout: [0x09].
/// Accounts (single-signer owner):
/// 0. account (writable)
/// 1. destination (writable)
/// 2. owner (readonly signer)
pub fn buildCloseAccountInstruction(
    allocator: std.mem.Allocator,
    params: CloseAccountParams,
) !instruction_mod.Instruction {
    const data = try allocator.alloc(u8, 1);
    errdefer allocator.free(data);
    data[0] = @intFromEnum(Discriminant.close_account);

    const accounts = try allocator.alloc(instruction_mod.AccountMeta, 3);
    errdefer allocator.free(accounts);

    accounts[0] = .{
        .pubkey = params.account,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.destination,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[2] = .{
        .pubkey = params.owner,
        .is_signer = true,
        .is_writable = false,
    };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

/// Build SPL Token `MintTo` instruction.
///
/// Data layout: [0x07] ++ little-endian u64 amount.
/// Accounts (single-signer authority):
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
    accounts[0] = .{
        .pubkey = params.mint,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.destination,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[2] = .{
        .pubkey = params.authority,
        .is_signer = true,
        .is_writable = false,
    };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

/// Build SPL Token `Approve` instruction.
///
/// Data layout: [0x04] ++ little-endian u64 amount.
/// Accounts (single-signer owner):
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
    accounts[0] = .{
        .pubkey = params.source,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.delegate,
        .is_signer = false,
        .is_writable = false,
    };
    accounts[2] = .{
        .pubkey = params.owner,
        .is_signer = true,
        .is_writable = false,
    };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

/// Build SPL Token `Burn` instruction.
///
/// Data layout: [0x08] ++ little-endian u64 amount.
/// Accounts (single-signer owner):
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
    accounts[0] = .{
        .pubkey = params.source,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[1] = .{
        .pubkey = params.mint,
        .is_signer = false,
        .is_writable = true,
    };
    accounts[2] = .{
        .pubkey = params.owner,
        .is_signer = true,
        .is_writable = false,
    };

    return .{
        .program_id = programId(),
        .accounts = accounts,
        .data = data,
    };
}

test "programId returns TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" {
    const allocator = std.testing.allocator;
    const id = programId();
    const b58 = try id.toBase58Alloc(allocator);
    defer allocator.free(b58);
    try std.testing.expectEqualStrings(TOKEN_PROGRAM_ID_STR, b58);
}

test "transferChecked byte layout and account metas" {
    const allocator = std.testing.allocator;
    const source = pubkey_mod.Pubkey.init([_]u8{1} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{2} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{3} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{4} ** 32);

    const ix = try buildTransferCheckedInstruction(allocator, .{
        .source = source,
        .mint = mint,
        .destination = destination,
        .owner = owner,
        .amount = 5_000_000,
        .decimals = 6,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(usize, 10), ix.data.len);
    try std.testing.expectEqual(@as(u8, 12), ix.data[0]);
    try std.testing.expectEqual(@as(u64, 5_000_000), std.mem.readInt(u64, ix.data[1..9], .little));
    try std.testing.expectEqual(@as(u8, 6), ix.data[9]);
    try std.testing.expect(ix.program_id.eql(programId()));

    try std.testing.expectEqual(@as(usize, 4), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(source));
    try std.testing.expectEqual(false, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
    try std.testing.expect(ix.accounts[1].pubkey.eql(mint));
    try std.testing.expectEqual(false, ix.accounts[1].is_signer);
    try std.testing.expectEqual(false, ix.accounts[1].is_writable);
    try std.testing.expect(ix.accounts[2].pubkey.eql(destination));
    try std.testing.expectEqual(false, ix.accounts[2].is_signer);
    try std.testing.expectEqual(true, ix.accounts[2].is_writable);
    try std.testing.expect(ix.accounts[3].pubkey.eql(owner));
    try std.testing.expectEqual(true, ix.accounts[3].is_signer);
    try std.testing.expectEqual(false, ix.accounts[3].is_writable);
}

test "transferChecked boundary: zero amount zero decimals" {
    const allocator = std.testing.allocator;
    const key = pubkey_mod.Pubkey.init([_]u8{9} ** 32);

    const ix = try buildTransferCheckedInstruction(allocator, .{
        .source = key,
        .mint = key,
        .destination = key,
        .owner = key,
        .amount = 0,
        .decimals = 0,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(u8, 12), ix.data[0]);
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, ix.data[1..9], .little));
    try std.testing.expectEqual(@as(u8, 0), ix.data[9]);
}

test "transferChecked boundary: max amount max decimals" {
    const allocator = std.testing.allocator;
    const key = pubkey_mod.Pubkey.init([_]u8{8} ** 32);

    const ix = try buildTransferCheckedInstruction(allocator, .{
        .source = key,
        .mint = key,
        .destination = key,
        .owner = key,
        .amount = std.math.maxInt(u64),
        .decimals = std.math.maxInt(u8),
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(std.math.maxInt(u64), std.mem.readInt(u64, ix.data[1..9], .little));
    try std.testing.expectEqual(std.math.maxInt(u8), ix.data[9]);
}

test "closeAccount byte layout and account metas" {
    const allocator = std.testing.allocator;
    const account = pubkey_mod.Pubkey.init([_]u8{5} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{6} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{7} ** 32);

    const ix = try buildCloseAccountInstruction(allocator, .{
        .account = account,
        .destination = destination,
        .owner = owner,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(usize, 1), ix.data.len);
    try std.testing.expectEqual(@as(u8, 9), ix.data[0]);
    try std.testing.expect(ix.program_id.eql(programId()));

    try std.testing.expectEqual(@as(usize, 3), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(account));
    try std.testing.expectEqual(false, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
    try std.testing.expect(ix.accounts[1].pubkey.eql(destination));
    try std.testing.expectEqual(false, ix.accounts[1].is_signer);
    try std.testing.expectEqual(true, ix.accounts[1].is_writable);
    try std.testing.expect(ix.accounts[2].pubkey.eql(owner));
    try std.testing.expectEqual(true, ix.accounts[2].is_signer);
    try std.testing.expectEqual(false, ix.accounts[2].is_writable);
}

test "mint byte layout and account metas" {
    const allocator = std.testing.allocator;
    const mint = pubkey_mod.Pubkey.init([_]u8{0xA1} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{0xA2} ** 32);
    const authority = pubkey_mod.Pubkey.init([_]u8{0xA3} ** 32);

    const ix = try buildMintInstruction(allocator, .{
        .mint = mint,
        .destination = destination,
        .authority = authority,
        .amount = 42,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(usize, 9), ix.data.len);
    try std.testing.expectEqual(@as(u8, 7), ix.data[0]);
    try std.testing.expectEqual(@as(u64, 42), std.mem.readInt(u64, ix.data[1..9], .little));
    try std.testing.expect(ix.program_id.eql(programId()));

    try std.testing.expectEqual(@as(usize, 3), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(mint));
    try std.testing.expectEqual(false, ix.accounts[0].is_signer);
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
    try std.testing.expect(ix.accounts[1].pubkey.eql(destination));
    try std.testing.expectEqual(false, ix.accounts[1].is_signer);
    try std.testing.expectEqual(true, ix.accounts[1].is_writable);
    try std.testing.expect(ix.accounts[2].pubkey.eql(authority));
    try std.testing.expectEqual(true, ix.accounts[2].is_signer);
    try std.testing.expectEqual(false, ix.accounts[2].is_writable);
}

test "approve byte layout and account metas" {
    const allocator = std.testing.allocator;
    const source = pubkey_mod.Pubkey.init([_]u8{0xB1} ** 32);
    const delegate = pubkey_mod.Pubkey.init([_]u8{0xB2} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{0xB3} ** 32);

    const ix = try buildApproveInstruction(allocator, .{
        .source = source,
        .delegate = delegate,
        .owner = owner,
        .amount = 1234,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(usize, 9), ix.data.len);
    try std.testing.expectEqual(@as(u8, 4), ix.data[0]);
    try std.testing.expectEqual(@as(u64, 1234), std.mem.readInt(u64, ix.data[1..9], .little));
    try std.testing.expect(ix.program_id.eql(programId()));

    try std.testing.expectEqual(@as(usize, 3), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(source));
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
    try std.testing.expect(ix.accounts[1].pubkey.eql(delegate));
    try std.testing.expectEqual(false, ix.accounts[1].is_writable);
    try std.testing.expect(ix.accounts[2].pubkey.eql(owner));
    try std.testing.expectEqual(true, ix.accounts[2].is_signer);
}

test "burn byte layout and account metas" {
    const allocator = std.testing.allocator;
    const source = pubkey_mod.Pubkey.init([_]u8{0xC1} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0xC2} ** 32);
    const owner = pubkey_mod.Pubkey.init([_]u8{0xC3} ** 32);

    const ix = try buildBurnInstruction(allocator, .{
        .source = source,
        .mint = mint,
        .owner = owner,
        .amount = 99,
    });
    defer allocator.free(ix.data);
    defer allocator.free(ix.accounts);

    try std.testing.expectEqual(@as(usize, 9), ix.data.len);
    try std.testing.expectEqual(@as(u8, 8), ix.data[0]);
    try std.testing.expectEqual(@as(u64, 99), std.mem.readInt(u64, ix.data[1..9], .little));
    try std.testing.expect(ix.program_id.eql(programId()));

    try std.testing.expectEqual(@as(usize, 3), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.eql(source));
    try std.testing.expectEqual(true, ix.accounts[0].is_writable);
    try std.testing.expect(ix.accounts[1].pubkey.eql(mint));
    try std.testing.expectEqual(true, ix.accounts[1].is_writable);
    try std.testing.expect(ix.accounts[2].pubkey.eql(owner));
    try std.testing.expectEqual(true, ix.accounts[2].is_signer);
}

test "token builders compile into signed legacy transaction" {
    const allocator = std.testing.allocator;

    const owner = try keypair_mod.Keypair.fromSeed([_]u8{0x2A} ** 32);
    const source = pubkey_mod.Pubkey.init([_]u8{0x11} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0x22} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{0x33} ** 32);
    const close_target = pubkey_mod.Pubkey.init([_]u8{0x44} ** 32);

    const transfer_ix = try buildTransferCheckedInstruction(allocator, .{
        .source = source,
        .mint = mint,
        .destination = destination,
        .owner = owner.pubkey(),
        .amount = 1_000,
        .decimals = 6,
    });
    defer allocator.free(transfer_ix.data);
    defer allocator.free(transfer_ix.accounts);

    const close_ix = try buildCloseAccountInstruction(allocator, .{
        .account = source,
        .destination = close_target,
        .owner = owner.pubkey(),
    });
    defer allocator.free(close_ix.data);
    defer allocator.free(close_ix.accounts);

    const ixs = [_]instruction_mod.Instruction{ transfer_ix, close_ix };
    const recent_blockhash = hash_mod.Hash.init([_]u8{0xAB} ** 32);
    const msg = try message_mod.Message.compileLegacy(allocator, owner.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{owner});
    try tx.verifySignatures();
}

const FlowMockTransport = struct {
    mode: enum { ok, fail_mismatch } = .ok,

    fn postJson(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) rpc_transport_mod.PostJsonError![]u8 {
        _ = url;
        const self: *FlowMockTransport = @ptrCast(@alignCast(ctx));

        if (std.mem.indexOf(u8, payload, "\"sendTransaction\"") != null) {
            if (self.mode == .fail_mismatch) {
                return allocator.dupe(
                    u8,
                    "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32002,\"message\":\"Transaction simulation failed: invalid account metas\"}}",
                );
            }
            // 64 bytes of zero encoded in base58.
            const sig = "1111111111111111111111111111111111111111111111111111111111111111";
            return std.fmt.allocPrint(
                allocator,
                "{{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"{s}\"}}",
                .{sig},
            );
        }

        if (std.mem.indexOf(u8, payload, "\"getSignatureStatuses\"") != null) {
            return allocator.dupe(
                u8,
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"context\":{\"slot\":1},\"value\":[{\"slot\":1,\"confirmations\":null,\"err\":null,\"confirmationStatus\":\"confirmed\"}]}}",
            );
        }

        return error.RpcTransport;
    }
};

test "token flow build -> compile/sign -> send/confirm (mock transport)" {
    const allocator = std.testing.allocator;
    var mock = FlowMockTransport{ .mode = .ok };
    const transport = rpc_transport_mod.Transport.init(
        &mock,
        FlowMockTransport.postJson,
        rpc_transport_mod.noopDeinit,
    );
    var client = try rpc_client_mod.RpcClient.initWithTransport(allocator, "http://mock.rpc", transport);
    defer client.deinit();

    const owner = try keypair_mod.Keypair.fromSeed([_]u8{0x2A} ** 32);
    const source = pubkey_mod.Pubkey.init([_]u8{0x11} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0x22} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{0x33} ** 32);
    const close_target = pubkey_mod.Pubkey.init([_]u8{0x44} ** 32);

    const transfer_ix = try buildTransferCheckedInstruction(allocator, .{
        .source = source,
        .mint = mint,
        .destination = destination,
        .owner = owner.pubkey(),
        .amount = 1_000,
        .decimals = 6,
    });
    defer allocator.free(transfer_ix.data);
    defer allocator.free(transfer_ix.accounts);

    const close_ix = try buildCloseAccountInstruction(allocator, .{
        .account = source,
        .destination = close_target,
        .owner = owner.pubkey(),
    });
    defer allocator.free(close_ix.data);
    defer allocator.free(close_ix.accounts);

    const ixs = [_]instruction_mod.Instruction{ transfer_ix, close_ix };
    const recent_blockhash = hash_mod.Hash.init([_]u8{0xAB} ** 32);
    const msg = try message_mod.Message.compileLegacy(allocator, owner.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{owner});

    const send_res = try client.sendTransaction(tx);
    try std.testing.expect(send_res == .ok);

    const status_res = try client.getSignatureStatuses(&[_]@import("../core/signature.zig").Signature{send_res.ok.signature});
    try std.testing.expect(status_res == .ok);
    try std.testing.expect(status_res.ok != null);
    var status = status_res.ok.?;
    defer status.deinit(allocator);
    try std.testing.expect(status.err_json == null);
    try std.testing.expect(status.confirmation_status != null);
    try std.testing.expectEqualStrings("confirmed", status.confirmation_status.?);
}

test "token flow failure-path: account/meta mismatch returns rpc_error" {
    const allocator = std.testing.allocator;
    var mock = FlowMockTransport{ .mode = .fail_mismatch };
    const transport = rpc_transport_mod.Transport.init(
        &mock,
        FlowMockTransport.postJson,
        rpc_transport_mod.noopDeinit,
    );
    var client = try rpc_client_mod.RpcClient.initWithTransport(allocator, "http://mock.rpc", transport);
    defer client.deinit();

    const owner = try keypair_mod.Keypair.fromSeed([_]u8{0x42} ** 32);
    const source = pubkey_mod.Pubkey.init([_]u8{0x55} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0x66} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{0x77} ** 32);
    const close_target = pubkey_mod.Pubkey.init([_]u8{0x88} ** 32);

    const transfer_ix = try buildTransferCheckedInstruction(allocator, .{
        .source = source,
        .mint = mint,
        .destination = destination,
        .owner = owner.pubkey(),
        .amount = 7,
        .decimals = 0,
    });
    defer allocator.free(transfer_ix.data);
    defer allocator.free(transfer_ix.accounts);

    const close_ix = try buildCloseAccountInstruction(allocator, .{
        .account = source,
        .destination = close_target,
        .owner = owner.pubkey(),
    });
    defer allocator.free(close_ix.data);
    defer allocator.free(close_ix.accounts);

    const ixs = [_]instruction_mod.Instruction{ transfer_ix, close_ix };
    const recent_blockhash = hash_mod.Hash.init([_]u8{0xBB} ** 32);
    const msg = try message_mod.Message.compileLegacy(allocator, owner.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{owner});

    const send_res = try client.sendTransaction(tx);
    try std.testing.expect(send_res == .rpc_error);
    send_res.rpc_error.deinit(allocator);
}

test "mint/approve/burn builders compile into signed legacy transaction" {
    const allocator = std.testing.allocator;

    const owner = try keypair_mod.Keypair.fromSeed([_]u8{0x8A} ** 32);
    const source = pubkey_mod.Pubkey.init([_]u8{0x91} ** 32);
    const mint = pubkey_mod.Pubkey.init([_]u8{0x92} ** 32);
    const delegate = pubkey_mod.Pubkey.init([_]u8{0x93} ** 32);
    const destination = pubkey_mod.Pubkey.init([_]u8{0x94} ** 32);

    const mint_ix = try buildMintInstruction(allocator, .{
        .mint = mint,
        .destination = destination,
        .authority = owner.pubkey(),
        .amount = 10,
    });
    defer allocator.free(mint_ix.data);
    defer allocator.free(mint_ix.accounts);

    const approve_ix = try buildApproveInstruction(allocator, .{
        .source = source,
        .delegate = delegate,
        .owner = owner.pubkey(),
        .amount = 5,
    });
    defer allocator.free(approve_ix.data);
    defer allocator.free(approve_ix.accounts);

    const burn_ix = try buildBurnInstruction(allocator, .{
        .source = source,
        .mint = mint,
        .owner = owner.pubkey(),
        .amount = 1,
    });
    defer allocator.free(burn_ix.data);
    defer allocator.free(burn_ix.accounts);

    const ixs = [_]instruction_mod.Instruction{ mint_ix, approve_ix, burn_ix };
    const recent_blockhash = hash_mod.Hash.init([_]u8{0xCD} ** 32);
    const msg = try message_mod.Message.compileLegacy(allocator, owner.pubkey(), &ixs, recent_blockhash);

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(allocator, msg);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{owner});
    try tx.verifySignatures();
}
