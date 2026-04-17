const std = @import("std");
const solana = @import("../mod.zig");
const errors = @import("errors.zig");

const RpcClientHandle = opaque {};

export fn solana_rpc_client_init(endpoint: [*c]const u8, endpoint_len: usize, out: [*c]?*RpcClientHandle) c_int {
    if (endpoint == null or out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const allocator = std.heap.c_allocator;
    const endpoint_slice = endpoint[0..endpoint_len];

    const client = allocator.create(solana.rpc.RpcClient) catch return errors.SOLANA_ERR_INTERNAL;
    errdefer allocator.destroy(client);

    const transport_ctx = allocator.create(DummyTransportCtx) catch return errors.SOLANA_ERR_INTERNAL;
    transport_ctx.* = .{};

    const transport = solana.rpc.Transport.init(transport_ctx, dummyPostJson, dummyDeinit);
    errdefer transport.deinit(allocator);

    client.* = solana.rpc.RpcClient.initWithTransport(allocator, endpoint_slice, transport) catch {
        return errors.SOLANA_ERR_INTERNAL;
    };

    out[0] = @ptrCast(client);
    return errors.SOLANA_OK;
}

export fn solana_rpc_client_deinit(handle: [*c]?*RpcClientHandle) void {
    if (handle == null or handle[0] == null) return;
    const client: *solana.rpc.RpcClient = @ptrCast(@alignCast(handle[0]));
    client.deinit();
    std.heap.c_allocator.destroy(client);
    handle[0] = null;
}

export fn solana_rpc_client_get_latest_blockhash(handle: *RpcClientHandle, out_blockhash: *solana.core.Hash) c_int {
    const client: *solana.rpc.RpcClient = @ptrCast(@alignCast(handle));
    const result = client.getLatestBlockhash() catch |err| return mapRpcErr(err);
    switch (result) {
        .ok => |v| {
            out_blockhash.* = v.blockhash;
            return errors.SOLANA_OK;
        },
        .rpc_error => return errors.SOLANA_ERR_BACKEND_FAILURE,
    }
}

export fn solana_rpc_client_get_balance(handle: *RpcClientHandle, pubkey: *const solana.core.Pubkey, out_lamports: *u64) c_int {
    const client: *solana.rpc.RpcClient = @ptrCast(@alignCast(handle));
    const result = client.getBalance(pubkey.*) catch |err| return mapRpcErr(err);
    switch (result) {
        .ok => |v| {
            out_lamports.* = v;
            return errors.SOLANA_OK;
        },
        .rpc_error => return errors.SOLANA_ERR_BACKEND_FAILURE,
    }
}

fn mapRpcErr(err: anyerror) c_int {
    return switch (err) {
        error.InvalidRpcResponse => errors.SOLANA_ERR_RPC_PARSE,
        error.RpcTransport => errors.SOLANA_ERR_RPC_TRANSPORT,
        error.RpcTimeout => errors.SOLANA_ERR_RPC_TRANSPORT,
        else => errors.SOLANA_ERR_INTERNAL,
    };
}

const DummyTransportCtx = struct {};

fn dummyPostJson(_: *anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) !@import("../rpc/transport.zig").PostJsonResponse {
    return error.RpcTransport;
}

fn dummyDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const transport_ctx: *DummyTransportCtx = @ptrCast(@alignCast(ctx));
    allocator.destroy(transport_ctx);
}

test "cabi rpc client uses dummy transport scaffold" {
    var handle: ?*RpcClientHandle = null;
    try std.testing.expectEqual(
        errors.SOLANA_OK,
        solana_rpc_client_init("http://example.invalid".ptr, "http://example.invalid".len, &handle),
    );
    defer solana_rpc_client_deinit(&handle);

    var blockhash: solana.core.Hash = undefined;
    try std.testing.expectEqual(
        errors.SOLANA_ERR_RPC_TRANSPORT,
        solana_rpc_client_get_latest_blockhash(handle.?, &blockhash),
    );

    const pk = solana.core.Pubkey.init([_]u8{1} ** 32);
    var lamports: u64 = 0;
    try std.testing.expectEqual(
        errors.SOLANA_ERR_RPC_TRANSPORT,
        solana_rpc_client_get_balance(handle.?, &pk, &lamports),
    );
}
