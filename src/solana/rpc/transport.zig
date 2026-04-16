const std = @import("std");
const http_transport = @import("http_transport.zig");

pub const PostJsonError = std.mem.Allocator.Error || error{RpcTransport};

pub const PostJsonFn = *const fn (
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    url: []const u8,
    payload: []const u8,
) PostJsonError![]u8;

pub const DeinitFn = *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void;

pub const Transport = struct {
    ctx: *anyopaque,
    post_json_fn: PostJsonFn,
    deinit_fn: DeinitFn,

    pub fn init(ctx: *anyopaque, post_json_fn: PostJsonFn, deinit_fn: DeinitFn) Transport {
        return .{
            .ctx = ctx,
            .post_json_fn = post_json_fn,
            .deinit_fn = deinit_fn,
        };
    }

    pub fn postJson(self: Transport, allocator: std.mem.Allocator, url: []const u8, payload: []const u8) PostJsonError![]u8 {
        return self.post_json_fn(self.ctx, allocator, url, payload);
    }

    pub fn deinit(self: Transport, allocator: std.mem.Allocator) void {
        self.deinit_fn(self.ctx, allocator);
    }
};

pub fn initHttpTransport(allocator: std.mem.Allocator, io: std.Io) !Transport {
    const ptr = try allocator.create(http_transport.HttpTransport);
    ptr.* = http_transport.HttpTransport.init(allocator, io);
    return Transport.init(ptr, postJsonHttp, deinitHttp);
}

fn postJsonHttp(ctx: *anyopaque, allocator: std.mem.Allocator, url: []const u8, payload: []const u8) PostJsonError![]u8 {
    _ = allocator;
    const transport: *http_transport.HttpTransport = @ptrCast(@alignCast(ctx));
    return transport.postJson(url, payload) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.RpcTransport,
    };
}

fn deinitHttp(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    _ = allocator;
    const transport: *http_transport.HttpTransport = @ptrCast(@alignCast(ctx));
    const gpa = transport.allocator;
    transport.deinit();
    gpa.destroy(transport);
}

pub fn noopDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    _ = ctx;
    _ = allocator;
}
