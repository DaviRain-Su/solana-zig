# RPC Examples (Phase 2 Extended Methods)

This guide covers the 11 extended RPC methods delivered in Phase 2:

- `getTransaction`
- `getSignaturesForAddress`
- `getSignatureStatuses`
- `getSlot`
- `getEpochInfo`
- `getMinimumBalanceForRentExemption`
- `requestAirdrop`
- `getAddressLookupTable`
- `getTokenAccountsByOwner`
- `getTokenAccountBalance`
- `getTokenSupply`

Each example:

- creates its own `RpcClient`
- constructs the request inputs explicitly
- handles both `.ok` and `.rpc_error`
- releases owned response memory where required

> Notes
>
> - Replace the base58 inputs with values that exist on your target cluster.
> - For Devnet, use `https://api.devnet.solana.com` unless you have a custom endpoint.
> - `requestAirdrop` can be rate-limited on public Devnet, so the `.rpc_error` branch is important in practice.

## Shared helper

```zig
const std = @import("std");
const sol = @import("solana_zig");

fn initClient(allocator: std.mem.Allocator, rpc_url: []const u8) !sol.rpc.RpcClient {
    return sol.rpc.RpcClient.init(allocator, std.io.default, rpc_url);
}

fn printRpcError(allocator: std.mem.Allocator, rpc_err: sol.rpc.types.RpcErrorObject) void {
    defer rpc_err.deinit(allocator);

    std.debug.print("rpc error {d}: {s}\n", .{ rpc_err.code, rpc_err.message });
    if (rpc_err.data_json) |data_json| {
        std.debug.print("rpc error data: {s}\n", .{data_json});
    }
}
```

## 1. `getTransaction`

```zig
pub fn exampleGetTransaction(rpc_url: []const u8, signature_b58: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const signature = try sol.core.Signature.fromBase58(signature_b58);

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getTransactionWithOptions(signature, .{
        .commitment = .confirmed,
        .max_supported_transaction_version = 0,
    });

    switch (result) {
        .ok => |maybe_transaction| {
            if (maybe_transaction) |owned_transaction| {
                var transaction = owned_transaction;
                defer transaction.deinit(allocator);

                std.debug.print("slot={d}\n", .{transaction.slot});
                if (transaction.block_time) |block_time| {
                    std.debug.print("blockTime={d}\n", .{block_time});
                }

                if (transaction.meta) |meta| {
                    if (meta.fee) |fee| {
                        std.debug.print("fee={d}\n", .{fee});
                    }
                    if (meta.err_json) |err_json| {
                        std.debug.print("meta.err={s}\n", .{err_json});
                    }
                    if (meta.log_messages) |logs| {
                        std.debug.print("logMessages={d}\n", .{logs.len});
                    }
                }
            } else {
                std.debug.print("transaction not found\n", .{});
            }
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 2. `getSignaturesForAddress`

```zig
pub fn exampleGetSignaturesForAddress(
    rpc_url: []const u8,
    address_b58: []const u8,
    before_b58: ?[]const u8,
    until_b58: ?[]const u8,
    limit: ?u32,
) !void {
    const allocator = std.heap.page_allocator;
    const address = try sol.core.Pubkey.fromBase58(address_b58);

    var before: ?sol.core.Signature = null;
    if (before_b58) |text| {
        before = try sol.core.Signature.fromBase58(text);
    }

    var until: ?sol.core.Signature = null;
    if (until_b58) |text| {
        until = try sol.core.Signature.fromBase58(text);
    }

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getSignaturesForAddressWithOptions(address, .{
        .before = before,
        .until = until,
        .limit = limit,
    });

    switch (result) {
        .ok => |owned_history| {
            var history = owned_history;
            defer history.deinit(allocator);

            std.debug.print("signatures={d}\n", .{history.items.len});
            for (history.items) |item| {
                const signature_text = try item.signature.toBase58Alloc(allocator);
                defer allocator.free(signature_text);

                std.debug.print("signature={s} slot={d}\n", .{ signature_text, item.slot });
                if (item.memo) |memo| {
                    std.debug.print("memo={s}\n", .{memo});
                }
                if (item.err_json) |err_json| {
                    std.debug.print("err={s}\n", .{err_json});
                }
            }
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 3. `getSignatureStatuses`

```zig
pub fn exampleGetSignatureStatuses(
    rpc_url: []const u8,
    signature_b58_list: []const []const u8,
) !void {
    const allocator = std.heap.page_allocator;

    const signatures = try allocator.alloc(sol.core.Signature, signature_b58_list.len);
    defer allocator.free(signatures);

    for (signature_b58_list, 0..) |signature_b58, i| {
        signatures[i] = try sol.core.Signature.fromBase58(signature_b58);
    }

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getSignatureStatusesWithOptions(signatures, .{
        .search_transaction_history = true,
    });

    switch (result) {
        .ok => |owned_statuses| {
            var statuses = owned_statuses;
            defer statuses.deinit(allocator);

            for (statuses.items, 0..) |maybe_status, i| {
                if (maybe_status) |status| {
                    std.debug.print("index={d} slot={d}\n", .{ i, status.slot });
                    if (status.confirmations) |confirmations| {
                        std.debug.print("confirmations={d}\n", .{confirmations});
                    }
                    if (status.confirmation_status) |confirmation_status| {
                        std.debug.print("confirmationStatus={s}\n", .{confirmation_status});
                    }
                    if (status.err_json) |err_json| {
                        std.debug.print("err={s}\n", .{err_json});
                    }
                } else {
                    std.debug.print("index={d} status not found\n", .{i});
                }
            }
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 4. `getSlot`

```zig
pub fn exampleGetSlot(rpc_url: []const u8) !void {
    const allocator = std.heap.page_allocator;

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getSlotWithOptions(.{
        .commitment = .finalized,
    });

    switch (result) {
        .ok => |slot| std.debug.print("slot={d}\n", .{slot}),
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 5. `getEpochInfo`

```zig
pub fn exampleGetEpochInfo(rpc_url: []const u8) !void {
    const allocator = std.heap.page_allocator;

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getEpochInfoWithOptions(.{
        .commitment = .confirmed,
    });

    switch (result) {
        .ok => |owned_epoch_info| {
            var epoch_info = owned_epoch_info;
            defer epoch_info.deinit(allocator);

            std.debug.print("epoch={d}\n", .{epoch_info.epoch});
            std.debug.print("slotIndex={d}/{d}\n", .{
                epoch_info.slot_index,
                epoch_info.slots_in_epoch,
            });
            std.debug.print("absoluteSlot={d}\n", .{epoch_info.absolute_slot});
            if (epoch_info.block_height) |block_height| {
                std.debug.print("blockHeight={d}\n", .{block_height});
            }
            if (epoch_info.transaction_count) |transaction_count| {
                std.debug.print("transactionCount={d}\n", .{transaction_count});
            }
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 6. `getMinimumBalanceForRentExemption`

```zig
pub fn exampleGetMinimumBalanceForRentExemption(
    rpc_url: []const u8,
    data_len: usize,
) !void {
    const allocator = std.heap.page_allocator;

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getMinimumBalanceForRentExemption(data_len);

    switch (result) {
        .ok => |lamports| {
            std.debug.print("data_len={d} rent_exempt_lamports={d}\n", .{
                data_len,
                lamports,
            });
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 7. `requestAirdrop`

```zig
pub fn exampleRequestAirdrop(
    rpc_url: []const u8,
    recipient_b58: []const u8,
    lamports: u64,
) !void {
    const allocator = std.heap.page_allocator;
    const recipient = try sol.core.Pubkey.fromBase58(recipient_b58);

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.requestAirdrop(recipient, lamports);

    switch (result) {
        .ok => |airdrop| {
            const signature_text = try airdrop.signature.toBase58Alloc(allocator);
            defer allocator.free(signature_text);

            std.debug.print("airdrop signature={s}\n", .{signature_text});
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 8. `getAddressLookupTable`

```zig
pub fn exampleGetAddressLookupTable(
    rpc_url: []const u8,
    table_address_b58: []const u8,
) !void {
    const allocator = std.heap.page_allocator;
    const table_address = try sol.core.Pubkey.fromBase58(table_address_b58);

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getAddressLookupTable(table_address);

    switch (result) {
        .ok => |owned_table_result| {
            var table_result = owned_table_result;
            defer table_result.deinit(allocator);

            std.debug.print("context.slot={d}\n", .{table_result.context_slot});
            if (table_result.value) |table| {
                std.debug.print("addresses={d}\n", .{table.state.addresses.len});
                if (table.state.authority) |authority| {
                    const authority_text = try authority.toBase58Alloc(allocator);
                    defer allocator.free(authority_text);
                    std.debug.print("authority={s}\n", .{authority_text});
                }
            } else {
                std.debug.print("lookup table not found\n", .{});
            }
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 9. `getTokenAccountsByOwner`

### 9.1 Filter by mint

```zig
pub fn exampleGetTokenAccountsByOwnerByMint(
    rpc_url: []const u8,
    owner_b58: []const u8,
    mint_b58: []const u8,
) !void {
    const allocator = std.heap.page_allocator;
    const owner = try sol.core.Pubkey.fromBase58(owner_b58);
    const mint = try sol.core.Pubkey.fromBase58(mint_b58);

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getTokenAccountsByOwnerWithOptions(owner, .{
        .filter = .{ .mint = mint },
        .encoding = .base64,
        .commitment = .confirmed,
    });

    switch (result) {
        .ok => |owned_accounts| {
            var accounts = owned_accounts;
            defer accounts.deinit(allocator);

            std.debug.print("token accounts={d}\n", .{accounts.items.len});
            for (accounts.items) |account| {
                const account_text = try account.pubkey.toBase58Alloc(allocator);
                defer allocator.free(account_text);

                std.debug.print("pubkey={s} lamports={d} data_len={d}\n", .{
                    account_text,
                    account.account_info.lamports,
                    account.account_info.data.len,
                });
            }
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

### 9.2 Filter by program ID

```zig
pub fn exampleGetTokenAccountsByOwnerByProgram(
    rpc_url: []const u8,
    owner_b58: []const u8,
) !void {
    const allocator = std.heap.page_allocator;
    const owner = try sol.core.Pubkey.fromBase58(owner_b58);
    const token_program = try sol.core.Pubkey.fromBase58(
        "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
    );

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getTokenAccountsByOwnerWithOptions(owner, .{
        .filter = .{ .program_id = token_program },
        .encoding = .base64,
        .commitment = .confirmed,
    });

    switch (result) {
        .ok => |owned_accounts| {
            var accounts = owned_accounts;
            defer accounts.deinit(allocator);

            std.debug.print("token accounts={d}\n", .{accounts.items.len});
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 10. `getTokenAccountBalance`

```zig
pub fn exampleGetTokenAccountBalance(
    rpc_url: []const u8,
    token_account_b58: []const u8,
) !void {
    const allocator = std.heap.page_allocator;
    const token_account = try sol.core.Pubkey.fromBase58(token_account_b58);

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getTokenAccountBalance(token_account);

    switch (result) {
        .ok => |owned_amount| {
            var amount = owned_amount;
            defer amount.deinit(allocator);

            std.debug.print("amount={d}\n", .{amount.amount});
            std.debug.print("decimals={d}\n", .{amount.decimals});
            std.debug.print("uiAmountString={s}\n", .{amount.ui_amount_string});
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## 11. `getTokenSupply`

```zig
pub fn exampleGetTokenSupply(rpc_url: []const u8, mint_b58: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const mint = try sol.core.Pubkey.fromBase58(mint_b58);

    var client = try initClient(allocator, rpc_url);
    defer client.deinit();

    const result = try client.getTokenSupply(mint);

    switch (result) {
        .ok => |owned_amount| {
            var amount = owned_amount;
            defer amount.deinit(allocator);

            std.debug.print("amount={d}\n", .{amount.amount});
            std.debug.print("decimals={d}\n", .{amount.decimals});
            std.debug.print("uiAmountString={s}\n", .{amount.ui_amount_string});
        },
        .rpc_error => |rpc_err| printRpcError(allocator, rpc_err),
    }
}
```

## Suggested live inputs

- `rpc_url`: `https://api.devnet.solana.com`
- `owner_b58`: a wallet that currently holds SPL token accounts on Devnet
- `mint_b58`: wrapped SOL mint `So11111111111111111111111111111111111111112`
- `token_program`: `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`
- `token_account_b58`: any live SPL token account for the chosen mint
- `recipient_b58`: a Devnet wallet you control for airdrops
- `signature_b58` / pagination signatures: any confirmed Devnet transaction signatures
