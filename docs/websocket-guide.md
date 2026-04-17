# Websocket Guide

This guide shows how to use the Phase 2 websocket client in `solana_zig` for:

- connecting to a Solana JSON-RPC websocket endpoint
- subscribing to notifications
- reading and handling notifications
- unsubscribing cleanly
- handling reconnects and failures

## Current API surface

`sol.rpc.WsRpcClient` supports these subscription families:

| Subscribe | Unsubscribe | Typed reader | Input |
| --- | --- | --- | --- |
| `accountSubscribe` | `accountUnsubscribe` | `readAccountNotification` | base58 account pubkey + commitment |
| `programSubscribe` | `programUnsubscribe` | `readProgramNotification` | base58 program id + commitment |
| `signatureSubscribe` | `signatureUnsubscribe` | `readSignatureNotification` | base58 signature + commitment |
| `slotSubscribe` | `slotUnsubscribe` | `readSlotNotification` | none |
| `rootSubscribe` | `rootUnsubscribe` | `readRootNotification` | none |
| `logsSubscribe` | `logsUnsubscribe` | `readLogsNotification` | raw Solana logs filter string |
| `blockSubscribe` | `blockUnsubscribe` | `readBlockNotification` | raw Solana block filter string + commitment |

Also available:

- `readNotification()` for generic method-based dispatch
- `setReconnectConfig(...)` to configure automatic reconnect backoff
- `snapshot()` and `connectionState()` for runtime health/metrics
- `subscriptionCount()` to inspect active subscriptions
- `reconnect()` / `reconnectWithBackoff(...)` for explicit reconnect attempts
- `sendPing()` and `disconnect()` for connection control

## Important behavior and limitations

- The current transport only supports `ws://` endpoints. `wss://` will return `error.InvalidUrl`.
- `accountSubscribe`, `programSubscribe`, `signatureSubscribe`, and `blockSubscribe` accept a `Commitment` parameter (default: `.confirmed`).
- `accountSubscribe` and `programSubscribe` currently send `encoding = "base64"` and `commitment = "confirmed"`.
- `signatureSubscribe` and `blockSubscribe` currently send `commitment = "confirmed"`.
- Re-subscribing with the same subscription kind and same input value is deduplicated: the client returns the existing subscription id instead of sending another request.
- Read APIs are pull-based: your code owns the loop and calls `read*Notification()` or `readNotification()`.

## Shared helper

```zig
const std = @import("std");
const sol = @import("solana_zig");

fn connectWs(allocator: std.mem.Allocator, ws_url: []const u8) !sol.rpc.WsRpcClient {
    var client = try sol.rpc.WsRpcClient.connect(allocator, std.io.default, ws_url);
    client.setReconnectConfig(.{
        .max_retries = 5,
        .base_delay_ms = 200,
        .max_delay_ms = 2_000,
    });
    return client;
}

fn reportWsError(client: *const sol.rpc.WsRpcClient, err: anyerror) void {
    const stats = client.snapshot();
    std.debug.print(
        "ws error={s} state={s} active={d} reconnects={d} sent={d} recv={d}\n",
        .{
            @errorName(err),
            @tagName(stats.connection_state),
            stats.active_subscriptions,
            stats.reconnect_attempts_total,
            stats.messages_sent_total,
            stats.messages_received_total,
        },
    );

    if (stats.last_error_message) |msg| {
        std.debug.print("last ws error detail: {s}\n", .{msg});
    }
}
```

## Full lifecycle example: connect → subscribe → read → unsubscribe

`slotSubscribe` is the simplest end-to-end example because it does not need extra inputs and works well with reconnect testing.

```zig
pub fn exampleSlotSubscription(ws_url: []const u8) !void {
    const allocator = std.heap.page_allocator;

    var client = try connectWs(allocator, ws_url);
    defer client.deinit();

    const subscription_id = try client.slotSubscribe();

    std.debug.print("slot subscription id={d}\n", .{subscription_id});

    const notification = client.readSlotNotification() catch |err| {
        reportWsError(&client, err);
        return err;
    };
    defer notification.deinit(allocator);

    std.debug.print(
        "slot={d} parent={d} root={d}\n",
        .{ notification.slot, notification.parent, notification.root },
    );

    const stats = client.snapshot();
    std.debug.print(
        "state={s} active={d} reconnects={d}\n",
        .{
            @tagName(stats.connection_state),
            stats.active_subscriptions,
            stats.reconnect_attempts_total,
        },
    );

    try client.slotUnsubscribe(subscription_id);
}
```

What this flow demonstrates:

1. `WsRpcClient.connect(...)` opens the websocket session.
2. `setReconnectConfig(...)` enables automatic reconnect with bounded exponential backoff.
3. `slotSubscribe()` returns the server subscription id.
4. `readSlotNotification()` blocks until a typed `slotNotification` arrives.
5. `slotUnsubscribe(...)` removes the remote subscription and the local active-subscription record.

## Example: account notifications

Use `accountSubscribe` when you want structured account state-change notifications.

```zig
pub fn exampleAccountSubscription(ws_url: []const u8, account_pubkey_b58: []const u8) !void {
    const allocator = std.heap.page_allocator;

    var client = try connectWs(allocator, ws_url);
    defer client.deinit();

    const subscription_id = try client.accountSubscribe(account_pubkey_b58, .confirmed);
    defer client.accountUnsubscribe(subscription_id) catch {};

    const notification = client.readAccountNotification() catch |err| {
        reportWsError(&client, err);
        return err;
    };
    defer notification.deinit(allocator);

    std.debug.print("account subscription id={d}\n", .{notification.subscription_id});
    std.debug.print("context.slot={d}\n", .{notification.context_slot});
    std.debug.print("lamports={d}\n", .{notification.account.lamports});
    std.debug.print("owner={s}\n", .{notification.account.owner});
    std.debug.print("executable={any}\n", .{notification.account.executable});
}
```

## Generic notification dispatch for mixed subscription types

If you are watching more than one notification method at the same time, prefer `readNotification()` and dispatch on `notification.method`.

```zig
pub fn exampleMixedDispatch(ws_url: []const u8, account_pubkey_b58: []const u8) !void {
    const allocator = std.heap.page_allocator;

    var client = try connectWs(allocator, ws_url);
    defer client.deinit();

    const account_sub_id = try client.accountSubscribe(account_pubkey_b58, .confirmed);
    defer client.accountUnsubscribe(account_sub_id) catch {};

    const slot_sub_id = try client.slotSubscribe();
    defer client.slotUnsubscribe(slot_sub_id) catch {};

    while (true) {
        var notification = client.readNotification() catch |err| {
            reportWsError(&client, err);
            return err;
        };
        defer notification.deinit();

        if (std.mem.eql(u8, notification.method, "accountNotification")) {
            var account = try sol.rpc.ws_client.parseAccountNotificationMessage(
                allocator,
                notification.raw_message,
            );
            defer account.deinit(allocator);

            std.debug.print("account change at slot={d}\n", .{account.context_slot});
            break;
        }

        if (std.mem.eql(u8, notification.method, "slotNotification")) {
            std.debug.print("received slot notification envelope\n", .{});
            continue;
        }
    }
}
```

This pattern matters because Solana can interleave notifications from different subscriptions between subscribe/unsubscribe acknowledgements.

## Error handling

All read methods can fail with websocket I/O errors, malformed-response errors, or reconnect failures. A practical pattern is:

1. catch the error
2. inspect `client.snapshot()`
3. decide whether to return, reconnect explicitly, or recreate the client

```zig
const notification = client.readLogsNotification() catch |err| {
    reportWsError(&client, err);

    if (client.connectionState() == .disconnected) {
        // Retry budget was likely exhausted or reconnect was disabled.
        // At this point you can rebuild the client, back off externally,
        // or surface the error to your caller.
    }
    return err;
};
defer notification.deinit(allocator);
```

## Reconnect behavior

`WsRpcClient` automatically reconnects when a read hits `error.ConnectionClosed`:

1. state changes to `.reconnecting`
2. the client retries the websocket handshake with exponential backoff
3. all active subscriptions are resubscribed automatically
4. state returns to `.connected` if recovery succeeds
5. the read loop resumes and later notifications continue to flow

If recovery fails after the retry budget is exhausted:

- the read call returns an error
- `snapshot().connection_state` becomes `.disconnected`
- `snapshot().last_error_message` is updated

You can also force reconnects yourself:

```zig
try client.reconnect();                  // single reconnect attempt
try client.reconnectWithBackoff(5, 200); // explicit retry budget + base delay
```

## Reconnect configuration

`setReconnectConfig(...)` accepts `sol.rpc.types.WsReconnectConfig`:

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `max_retries` | `u8` | `3` | Maximum reconnect attempts before giving up |
| `base_delay_ms` | `u64` | `100` | Initial backoff delay in milliseconds |
| `max_delay_ms` | `u64` | `1_000` | Upper cap for exponential backoff |

Notes:

- `max_retries = 0` disables automatic reconnect.
- The client also applies internal caps: `MAX_RECONNECT_RETRIES = 5` and `MAX_BACKOFF_MS = 30_000`.

## Observability and health checks

Use `snapshot()` to expose websocket runtime health to your app:

```zig
const stats = client.snapshot();
std.debug.print(
    "state={s} active={d} reconnects={d} dedup_dropped={d} sent={d} recv={d}\n",
    .{
        @tagName(stats.connection_state),
        stats.active_subscriptions,
        stats.reconnect_attempts_total,
        stats.dedup_dropped_total,
        stats.messages_sent_total,
        stats.messages_received_total,
    },
);
```

`snapshot()` includes:

- `connection_state`
- `active_subscriptions`
- `messages_sent_total`
- `messages_received_total`
- `reconnect_attempts_total`
- `dedup_dropped_total`
- `last_error_code`
- `last_error_message`
- `last_reconnect_unix_ms`

## Recommended integration checklist

- Use a `ws://` endpoint, not `wss://`.
- Set reconnect policy immediately after `connect(...)`.
- Unsubscribe explicitly before tearing the client down when possible.
- Use typed `read*Notification()` helpers for single-subscription or single-method loops.
- Use `readNotification()` plus method dispatch when multiple subscription types may interleave.
- Inspect `snapshot()` in error paths and export it to your own metrics/logging system.
