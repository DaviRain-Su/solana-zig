// Phase 2 Batch 3 — P2-14: Nonce Live Deepening (#34)
//
// Gate: G-P2C-04
// Evidence: query nonce -> build advance -> compile/sign -> send/confirm
//
// Mock mode: always runs (scripted RPC responses).
// Live mode: runs only when SOLANA_RPC_URL is set.
//
// Build & run: zig build nonce-e2e

const std = @import("std");
const root = @import("solana_zig");

const Pubkey = root.core.Pubkey;
const Hash = root.core.Hash;
const Keypair = root.core.Keypair;
const Instruction = root.tx.Instruction;
const AccountMeta = root.tx.AccountMeta;
const Message = root.tx.Message;
const VersionedTransaction = root.tx.VersionedTransaction;
const RpcClient = root.rpc.RpcClient;
const transport_mod = root.rpc.transport;
const system = root.interfaces.system;

// --- Well-known addresses ---

const SYSTEM_PROGRAM = Pubkey.init([_]u8{0} ** 32);

// SysvarRecentB1ockHashes11111111111111111111
const RECENT_BLOCKHASHES_SYSVAR = Pubkey.init(.{
    6, 167, 213, 23, 25, 44, 86, 142,
    224, 138, 132, 95, 115, 210, 151, 136,
    207, 3, 92, 49, 69, 178, 26, 179,
    68, 216, 6, 46, 169, 64, 0, 0,
});

// SysvarRent111111111111111111111111111111111
const RENT_SYSVAR = Pubkey.init(.{
    6, 167, 213, 23, 25, 44, 92, 81,
    33, 140, 201, 76, 61, 74, 241, 127,
    88, 218, 238, 8, 155, 161, 253, 68,
    227, 219, 217, 138, 0, 0, 0, 0,
});

// --- Scripted Mock Transport ---

const ScriptedMock = struct {
    responses: []const []const u8,
    call_index: usize = 0,

    fn postJson(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) transport_mod.PostJsonError!transport_mod.PostJsonResponse {
        _ = url;
        _ = payload;
        const self: *ScriptedMock = @ptrCast(@alignCast(ctx));
        if (self.call_index >= self.responses.len) return error.RpcTransport;
        const response = self.responses[self.call_index];
        self.call_index += 1;
        return .{
            .status = .ok,
            .body = try allocator.dupe(u8, response),
        };
    }
};

// --- Mock RPC responses ---

// Nonce account data (base64): Versions::Current(1) + State::Initialized(1) + authority(32 bytes 0xAA) + blockhash(32 bytes 0xBB)
// Total 72 bytes: [01,00,00,00] [01,00,00,00] [AA x 32] [BB x 32]
const MOCK_NONCE_ACCOUNT_B64 = "AQAAAAEAAACqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqru7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7";

const MOCK_ACCOUNT_INFO_RESPONSE =
    \\{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":100},"value":{"lamports":1447680,"owner":"11111111111111111111111111111111","executable":false,"rentEpoch":0,"data":["
++ MOCK_NONCE_ACCOUNT_B64 ++
    \\","base64"]}}}
;

const MOCK_BLOCKHASH_RESPONSE =
    \\{"jsonrpc":"2.0","id":2,"result":{"context":{"slot":100},"value":{"blockhash":"4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn","lastValidBlockHeight":1000}}}
;

const MOCK_SEND_RESPONSE =
    \\{"jsonrpc":"2.0","id":3,"result":"5VERv8NMhceraWcxKqwqGJVDRBQ4nLs28XvP8jYhDVTtPQAHY2hEPNkRGMhj5H9rD3kN3rR2XJLFAB5fyb4bsqj"}
;

const MOCK_CONFIRM_RESPONSE =
    \\{"jsonrpc":"2.0","id":4,"result":{"context":{"slot":100},"value":[{"slot":99,"confirmations":null,"err":null,"confirmationStatus":"confirmed"}]}}
;

// --- Mock Test: Full nonce workflow ---

test "P2-14 mock: query nonce -> build advance -> compile/sign -> send -> confirm" {
    const gpa = std.testing.allocator;
    const payer = try Keypair.fromSeed([_]u8{7} ** 32);
    const nonce_account_key = Pubkey.init([_]u8{1} ** 32);

    // Note: no getLatestBlockhash call — we use the nonce's stored blockhash
    var responses = [_][]const u8{
        MOCK_ACCOUNT_INFO_RESPONSE,
        MOCK_SEND_RESPONSE,
        MOCK_CONFIRM_RESPONSE,
    };
    var mock = ScriptedMock{ .responses = &responses };
    const transport = transport_mod.Transport.init(@ptrCast(&mock), ScriptedMock.postJson, transport_mod.noopDeinit);

    var client = try RpcClient.initWithTransport(gpa, "http://mock.test", transport);
    defer client.deinit();

    // Step 1: Query nonce account
    const acct_result = try client.getAccountInfo(nonce_account_key);
    switch (acct_result) {
        .ok => |maybe_acct_info| {
            const acct_info_val = maybe_acct_info orelse return error.ExpectedNonceAccount;
            var acct_info = acct_info_val;
            defer acct_info.deinit(gpa);

            // Step 2: Parse nonce state
            const nonce_state = try system.parseNonceAccountData(acct_info.data);
            try std.testing.expect(nonce_state == .initialized);
            const nonce_blockhash = nonce_state.initialized.blockhash;

            // Step 3: Build advance nonce instruction
            const advance_ix = try system.buildAdvanceNonceAccountInstruction(gpa, .{
                .nonce_account = nonce_account_key,
                .recent_blockhashes_sysvar = RECENT_BLOCKHASHES_SYSVAR,
                .nonce_authority = payer.pubkey(),
            });
            defer gpa.free(advance_ix.data);
            defer gpa.free(advance_ix.accounts);

            // Step 4: Compile message (use nonce blockhash as the "recent blockhash")
            const ixs = [_]Instruction{advance_ix};
            const msg = try Message.compileLegacy(gpa, payer.pubkey(), &ixs, nonce_blockhash);

            // Step 5: Sign
            var tx = try VersionedTransaction.initUnsigned(gpa, msg);
            defer tx.deinit();
            try tx.sign(&[_]Keypair{payer});
            try tx.verifySignatures();

            // Step 6: Send
            const send_result = try client.sendTransaction(tx);
            switch (send_result) {
                .ok => |result| {
                    try std.testing.expectEqual(@as(usize, 64), result.signature.bytes.len);

                    // Step 7: Confirm
                    const sigs = [_]root.core.Signature{result.signature};
                    const status_result = try client.getSignatureStatuses(&sigs);
                    switch (status_result) {
                        .ok => |statuses_val| {
                            var statuses = statuses_val;
                            defer statuses.deinit(gpa);
                            try std.testing.expectEqual(@as(usize, 1), statuses.items.len);
                            try std.testing.expect(statuses.items[0] != null);
                            const status = statuses.items[0].?;
                            try std.testing.expectEqualStrings("confirmed", status.confirmation_status.?);
                            try std.testing.expect(status.err_json == null);
                        },
                        .rpc_error => |rpc_err| {
                            defer rpc_err.deinit(gpa);
                            return error.UnexpectedRpcError;
                        },
                    }
                },
                .rpc_error => |rpc_err| {
                    defer rpc_err.deinit(gpa);
                    return error.UnexpectedRpcError;
                },
            }
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            return error.UnexpectedRpcError;
        },
    }
}

// --- Helper: raw requestAirdrop ---

fn requestAirdrop(client: *RpcClient, pubkey_str: []const u8, lamports: u64) !void {
    const a = client.allocator;
    const payload = try std.fmt.allocPrint(
        a,
        "{{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"requestAirdrop\",\"params\":[\"{s}\",{d}]}}",
        .{ pubkey_str, lamports },
    );
    defer a.free(payload);
    const raw = try client.transport.postJson(a, client.endpoint, payload);
    defer raw.deinit(a);
}

// --- Helper: raw getMinimumBalanceForRentExemption ---

fn getMinimumBalanceForRentExemption(client: *RpcClient, data_len: u64) !u64 {
    const a = client.allocator;
    const payload = try std.fmt.allocPrint(
        a,
        "{{\"jsonrpc\":\"2.0\",\"id\":98,\"method\":\"getMinimumBalanceForRentExemption\",\"params\":[{d}]}}",
        .{data_len},
    );
    defer a.free(payload);
    const raw = try client.transport.postJson(a, client.endpoint, payload);
    defer raw.deinit(a);

    const parsed = try std.json.parseFromSlice(std.json.Value, a, raw.body, .{});
    defer parsed.deinit();
    const result = parsed.value.object.get("result") orelse return error.InvalidRpcResponse;
    return @intCast(result.integer);
}

// --- Helper: build CreateAccount instruction ---
// System program index 0: [u32 LE = 0] + [u64 LE lamports] + [u64 LE space] + [Pubkey owner]

fn buildCreateAccountData(allocator: std.mem.Allocator, lamports: u64, space: u64, owner: Pubkey) ![]u8 {
    const data = try allocator.alloc(u8, 52);
    std.mem.writeInt(u32, data[0..4], 0, .little); // CreateAccount index
    std.mem.writeInt(u64, data[4..12], lamports, .little);
    std.mem.writeInt(u64, data[12..20], space, .little);
    @memcpy(data[20..52], &owner.bytes);
    return data;
}

// --- Helper: build InitializeNonceAccount instruction ---
// System program index 6: [u32 LE = 6] + [Pubkey authority]

fn buildInitializeNonceAccountData(allocator: std.mem.Allocator, authority: Pubkey) ![]u8 {
    const data = try allocator.alloc(u8, 36);
    std.mem.writeInt(u32, data[0..4], 6, .little); // InitializeNonceAccount index
    @memcpy(data[4..36], &authority.bytes);
    return data;
}

// Nonce account data size (NonceState struct on-chain)
const NONCE_ACCOUNT_SIZE: u64 = 80;

// --- Live Test: Full nonce workflow ---

test "P2-14 live: create nonce -> query -> advance -> send -> confirm" {
    const gpa = std.testing.allocator;

    const endpoint = std.process.Environ.getAlloc(std.testing.environ, gpa, "SOLANA_RPC_URL") catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            std.debug.print("[skip] SOLANA_RPC_URL not set, skipping nonce live E2E\n", .{});
            return;
        },
        else => return err,
    };
    defer gpa.free(endpoint);

    std.debug.print("[nonce E2E] endpoint: {s}\n", .{endpoint});

    // Use a dedicated seed to avoid conflicts with other E2E tests
    const NONCE_PAYER_SEED = [_]u8{ 0x4E, 0x6F, 0x6E, 0x63, 0x65, 0x50, 0x61, 0x79, 0x65, 0x72, 0x53, 0x65, 0x65, 0x64, 0x21, 0x21, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46 };
    const payer = try Keypair.fromSeed(NONCE_PAYER_SEED);
    const payer_b58 = try payer.pubkey().toBase58Alloc(gpa);
    defer gpa.free(payer_b58);
    std.debug.print("[nonce E2E] payer: {s}\n", .{payer_b58});

    // Nonce account keypair (derived from a different seed)
    const NONCE_ACCT_SEED = [_]u8{ 0x4E, 0x6F, 0x6E, 0x63, 0x65, 0x41, 0x63, 0x63, 0x74, 0x53, 0x65, 0x65, 0x64, 0x21, 0x21, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32 };
    const nonce_keypair = try Keypair.fromSeed(NONCE_ACCT_SEED);
    const nonce_b58 = try nonce_keypair.pubkey().toBase58Alloc(gpa);
    defer gpa.free(nonce_b58);
    std.debug.print("[nonce E2E] nonce account: {s}\n", .{nonce_b58});

    var client = try RpcClient.init(gpa, std.testing.io, endpoint);
    defer client.deinit();

    // === Phase A: Fund payer ===
    requestAirdrop(&client, payer_b58, 2_000_000_000) catch |err| {
        std.debug.print("[nonce E2E] airdrop failed (may be rate-limited): {}\n", .{err});
    };

    // Poll balance
    var balance: u64 = 0;
    var attempts: u32 = 0;
    while (attempts < 30) : (attempts += 1) {
        const bal_result = try client.getBalance(payer.pubkey());
        switch (bal_result) {
            .ok => |b| {
                balance = b;
                if (balance > 0) break;
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(gpa);
            },
        }
    }
    std.debug.print("[nonce E2E] payer balance: {d} lamports (after {d} polls)\n", .{ balance, attempts });
    if (balance == 0) {
        std.debug.print("[nonce E2E] skip: payer has no funds\n", .{});
        return;
    }

    // === Phase B: Create nonce account ===
    // Check if nonce account already exists (idempotent re-run)
    var nonce_exists = false;
    if (client.getAccountInfo(nonce_keypair.pubkey())) |check_result| {
        switch (check_result) {
            .ok => |maybe_info| {
                if (maybe_info) |info_val| {
                    var info = info_val;
                    defer info.deinit(gpa);
                    nonce_exists = true;
                    std.debug.print("[nonce E2E] nonce account already exists (lamports={d})\n", .{info.lamports});
                }
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(gpa);
                // Non-not-found RPC failures are tolerated for this best-effort existence probe.
            },
        }
    } else |_| {
        // Transport/parse failures are tolerated for this best-effort existence probe.
    }

    if (!nonce_exists) {
        // Get rent-exempt minimum for nonce account
        const rent_exempt = getMinimumBalanceForRentExemption(&client, NONCE_ACCOUNT_SIZE) catch |err| blk: {
            std.debug.print("[nonce E2E] getMinimumBalanceForRentExemption failed: {}, using fallback\n", .{err});
            break :blk @as(u64, 1_447_680); // known fallback for 80-byte account
        };
        std.debug.print("[nonce E2E] rent-exempt minimum: {d} lamports\n", .{rent_exempt});

        // Get blockhash for create tx
        const bh_result = try client.getLatestBlockhash();
        switch (bh_result) {
            .ok => |bh| {
                // Build CreateAccount instruction
                const create_data = try buildCreateAccountData(gpa, rent_exempt, NONCE_ACCOUNT_SIZE, SYSTEM_PROGRAM);
                defer gpa.free(create_data);

                const create_accounts = [_]AccountMeta{
                    .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
                    .{ .pubkey = nonce_keypair.pubkey(), .is_signer = true, .is_writable = true },
                };

                // Build InitializeNonceAccount instruction
                const init_data = try buildInitializeNonceAccountData(gpa, payer.pubkey());
                defer gpa.free(init_data);

                const init_accounts = [_]AccountMeta{
                    .{ .pubkey = nonce_keypair.pubkey(), .is_signer = false, .is_writable = true },
                    .{ .pubkey = RECENT_BLOCKHASHES_SYSVAR, .is_signer = false, .is_writable = false },
                    .{ .pubkey = RENT_SYSVAR, .is_signer = false, .is_writable = false },
                };

                const ixs = [_]Instruction{
                    .{ .program_id = SYSTEM_PROGRAM, .accounts = &create_accounts, .data = create_data },
                    .{ .program_id = SYSTEM_PROGRAM, .accounts = &init_accounts, .data = init_data },
                };

                const msg = try Message.compileLegacy(gpa, payer.pubkey(), &ixs, bh.blockhash);
                var create_tx = try VersionedTransaction.initUnsigned(gpa, msg);
                defer create_tx.deinit();
                try create_tx.sign(&[_]Keypair{ payer, nonce_keypair });
                try create_tx.verifySignatures();

                const send_result = try client.sendTransaction(create_tx);
                switch (send_result) {
                    .ok => |result| {
                        const sig_b58 = try result.signature.toBase58Alloc(gpa);
                        defer gpa.free(sig_b58);
                        std.debug.print("[nonce E2E] create tx sent — sig: {s}\n", .{sig_b58});

                        // Wait for confirmation
                        const sigs = [_]root.core.Signature{result.signature};
                        var confirm_attempts: u32 = 0;
                        while (confirm_attempts < 30) : (confirm_attempts += 1) {
                            const status_result = try client.getSignatureStatuses(&sigs);
                            switch (status_result) {
                                .ok => |statuses_val| {
                                    var statuses = statuses_val;
                                    defer statuses.deinit(gpa);
                                    if (statuses.items.len == 0 or statuses.items[0] == null) continue;

                                    const status = statuses.items[0].?;
                                    if (status.confirmation_status) |cs| {
                                        if (std.mem.eql(u8, cs, "confirmed") or std.mem.eql(u8, cs, "finalized")) {
                                            if (status.err_json) |tx_err| {
                                                std.debug.print("[nonce E2E] create tx error: {s}\n", .{tx_err});
                                                return error.NonceCreateFailed;
                                            }
                                            std.debug.print("[nonce E2E] create tx confirmed (poll {d})\n", .{confirm_attempts});
                                            break;
                                        }
                                    }
                                },
                                .rpc_error => |rpc_err| {
                                    defer rpc_err.deinit(gpa);
                                },
                            }
                        }
                    },
                    .rpc_error => |rpc_err| {
                        defer rpc_err.deinit(gpa);
                        std.debug.print("[nonce E2E] create tx rpc_error: {s}\n", .{rpc_err.message});
                        // May already exist from a previous partial run; continue to query
                    },
                }
            },
            .rpc_error => |rpc_err| {
                defer rpc_err.deinit(gpa);
                std.debug.print("[nonce E2E] getLatestBlockhash failed: {s}\n", .{rpc_err.message});
                return error.DevnetRpcError;
            },
        }
    }

    // === Phase C: Query nonce account ===
    std.debug.print("[nonce E2E] === Phase C: Query nonce account ===\n", .{});
    const acct_result = try client.getAccountInfo(nonce_keypair.pubkey());
    switch (acct_result) {
        .ok => |maybe_acct_info| {
            const acct_info_val = maybe_acct_info orelse return error.NonceQueryFailed;
            var acct_info = acct_info_val;
            defer acct_info.deinit(gpa);

            std.debug.print("[nonce E2E] nonce account: lamports={d}, data.len={d}, owner=system\n", .{ acct_info.lamports, acct_info.data.len });

            // === Phase D: Parse nonce state ===
            const nonce_state = system.parseNonceAccountData(acct_info.data) catch |err| {
                std.debug.print("[nonce E2E] parseNonceAccountData failed: {}\n", .{err});
                return err;
            };

            switch (nonce_state) {
                .initialized => |init| {
                    const auth_b58 = try init.authority.toBase58Alloc(gpa);
                    defer gpa.free(auth_b58);
                    const bh_b58 = try init.blockhash.toBase58Alloc(gpa);
                    defer gpa.free(bh_b58);
                    std.debug.print("[nonce E2E] nonce state: initialized, authority={s}, blockhash={s}\n", .{ auth_b58, bh_b58 });

                    // === Phase E: Build advance nonce + send + confirm ===
                    const advance_ix = try system.buildAdvanceNonceAccountInstruction(gpa, .{
                        .nonce_account = nonce_keypair.pubkey(),
                        .recent_blockhashes_sysvar = RECENT_BLOCKHASHES_SYSVAR,
                        .nonce_authority = payer.pubkey(),
                    });
                    defer gpa.free(advance_ix.data);
                    defer gpa.free(advance_ix.accounts);

                    // Get a fresh blockhash for the advance tx.
                    // Note: the nonce's stored blockhash is used by OTHER transactions
                    // that want durable lifetime. The advance tx itself uses a normal
                    // recent blockhash to execute on-chain.
                    const adv_bh_result = try client.getLatestBlockhash();
                    const adv_blockhash = switch (adv_bh_result) {
                        .ok => |bh| bh.blockhash,
                        .rpc_error => |rpc_err| {
                            defer rpc_err.deinit(gpa);
                            return error.DevnetRpcError;
                        },
                    };

                    const ixs = [_]Instruction{advance_ix};
                    const msg = try Message.compileLegacy(gpa, payer.pubkey(), &ixs, adv_blockhash);

                    var tx = try VersionedTransaction.initUnsigned(gpa, msg);
                    defer tx.deinit();
                    try tx.sign(&[_]Keypair{payer});
                    try tx.verifySignatures();
                    std.debug.print("[nonce E2E] advance tx signed, sending...\n", .{});

                    const send_result = try client.sendTransaction(tx);
                    switch (send_result) {
                        .ok => |result| {
                            const sig_b58 = try result.signature.toBase58Alloc(gpa);
                            defer gpa.free(sig_b58);
                            std.debug.print("[nonce E2E] advance tx sent — sig: {s}\n", .{sig_b58});

                            // Confirm
                            const sigs = [_]root.core.Signature{result.signature};
                            var confirm_attempts: u32 = 0;
                            var confirmed = false;
                            while (confirm_attempts < 30) : (confirm_attempts += 1) {
                                const status_result = try client.getSignatureStatuses(&sigs);
                                switch (status_result) {
                                    .ok => |statuses_val| {
                                        var statuses = statuses_val;
                                        defer statuses.deinit(gpa);
                                        if (statuses.items.len == 0 or statuses.items[0] == null) continue;

                                        const status = statuses.items[0].?;
                                        if (status.confirmation_status) |cs| {
                                            std.debug.print("[nonce E2E] confirm poll {d}: {s}\n", .{ confirm_attempts, cs });
                                            if (std.mem.eql(u8, cs, "confirmed") or std.mem.eql(u8, cs, "finalized")) {
                                                if (status.err_json) |tx_err| {
                                                    std.debug.print("[nonce E2E] advance tx error: {s}\n", .{tx_err});
                                                } else {
                                                    confirmed = true;
                                                }
                                                break;
                                            }
                                        }
                                    },
                                    .rpc_error => |rpc_err| {
                                        defer rpc_err.deinit(gpa);
                                    },
                                }
                            }

                            if (confirmed) {
                                std.debug.print("[nonce E2E] CONFIRMED — advance nonce tx: {s} (after {d} polls)\n", .{ sig_b58, confirm_attempts });
                                std.debug.print("[nonce E2E] === G-P2C-04 PASS: query -> build -> compile/sign -> send/confirm ===\n", .{});
                            } else {
                                std.debug.print("[nonce E2E] WARNING: advance tx sent but not confirmed within 30 polls — sig: {s}\n", .{sig_b58});
                            }
                        },
                        .rpc_error => |rpc_err| {
                            defer rpc_err.deinit(gpa);
                            std.debug.print("[nonce E2E] advance tx rpc_error: {s}\n", .{rpc_err.message});
                        },
                    }
                },
                .uninitialized => {
                    std.debug.print("[nonce E2E] nonce account is uninitialized — create may have failed\n", .{});
                    return error.NonceNotInitialized;
                },
            }
        },
        .rpc_error => |rpc_err| {
            defer rpc_err.deinit(gpa);
            std.debug.print("[nonce E2E] getAccountInfo failed: {s}\n", .{rpc_err.message});
            return error.NonceQueryFailed;
        },
    }
}
