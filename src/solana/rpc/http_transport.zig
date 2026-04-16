const std = @import("std");

pub const PostJsonResponse = struct {
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: PostJsonResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

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

    pub fn postJson(self: *HttpTransport, allocator: std.mem.Allocator, url: []const u8, payload: []const u8) !PostJsonResponse {
        var out: std.Io.Writer.Allocating = .init(allocator);
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

        return .{
            .status = result.status,
            .body = try allocator.dupe(u8, out.written()),
        };
    }
};
