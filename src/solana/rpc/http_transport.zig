const std = @import("std");

pub const HttpTransport = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) HttpTransport {
        return .{
            .allocator = allocator,
            .io = io,
            .client = .{
                .allocator = allocator,
                .io = io,
            },
        };
    }

    pub fn deinit(self: *HttpTransport) void {
        self.client.deinit();
    }

    pub fn postJson(self: *HttpTransport, url: []const u8, payload: []const u8) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();

        const headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Accept", .value = "application/json" },
        };

        const result = self.client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .extra_headers = &headers,
            .response_writer = &out.writer,
        }) catch return error.RpcTransport;

        if (result.status != .ok) return error.RpcTransport;

        return self.allocator.dupe(u8, out.written());
    }
};
