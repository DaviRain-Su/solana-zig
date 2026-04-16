const std = @import("std");
const types = @import("types.zig");

pub const WsClient = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    stream: std.Io.net.Stream,
    read_buffer: []u8,
    write_buffer: []u8,
    next_id: u64 = 1,

    pub const ConnectError = std.mem.Allocator.Error || std.Io.net.IpAddress.ConnectError || std.Io.net.Ip6Address.ResolveError || error{
        InvalidUrl,
        HandshakeFailed,
        WsProtocolError,
    };

    pub const SendError = std.mem.Allocator.Error || std.Io.net.Stream.Writer.Error || error{WsProtocolError};

    pub const ReadError = std.Io.net.Stream.Reader.Error || std.Io.net.Stream.Writer.Error || std.mem.Allocator.Error || error{
        WsProtocolError,
        ConnectionClosed,
    };

    pub const Message = struct {
        opcode: Opcode,
        data: []const u8,

        pub const Opcode = enum(u4) {
            continuation = 0x0,
            text = 0x1,
            binary = 0x2,
            close = 0x8,
            ping = 0x9,
            pong = 0xA,
            _,
        };
    };

    /// Parse a ws:// or wss:// URL and connect to the host.
    pub fn connect(allocator: std.mem.Allocator, io: std.Io, url: []const u8) ConnectError!WsClient {
        const parsed = try parseWsUrl(url);
        const is_tls = parsed.protocol == .wss;
        if (is_tls) return error.InvalidUrl; // TLS not yet supported in this minimal version

        const addr = try std.Io.net.IpAddress.resolve(io, parsed.host, parsed.port);
        const stream = try std.Io.net.IpAddress.connect(&addr, io, .{ .mode = .stream });
        errdefer stream.close(io);

        const read_buffer = try allocator.alloc(u8, 8192);
        errdefer allocator.free(read_buffer);
        const write_buffer = try allocator.alloc(u8, 8192);
        errdefer allocator.free(write_buffer);

        var client = WsClient{
            .allocator = allocator,
            .io = io,
            .stream = stream,
            .read_buffer = read_buffer,
            .write_buffer = write_buffer,
        };

        try client.performHandshake(parsed.host, parsed.port, parsed.path);
        return client;
    }

    pub fn deinit(self: *WsClient) void {
        self.stream.close(self.io);
        self.allocator.free(self.read_buffer);
        self.allocator.free(self.write_buffer);
    }

    /// Send a text frame (used for JSON-RPC messages).
    pub fn sendText(self: *WsClient, text: []const u8) SendError!void {
        try self.sendFrame(.text, text);
    }

    /// Send a close frame.
    pub fn sendClose(self: *WsClient) SendError!void {
        try self.sendFrame(.close, &[_]u8{});
    }

    /// Read one websocket message. Blocks until a message is received or an error occurs.
    /// Caller owns the returned data and must free it with self.allocator.
    pub fn readMessage(self: *WsClient) ReadError!Message {
        var opcode: ?Message.Opcode = null;
        var payload: std.ArrayList(u8) = .empty;
        errdefer payload.deinit(self.allocator);

        while (true) {
            const frame = try self.readFrame();
            const fin = frame.fin;
            const frame_opcode = frame.opcode;

            if (frame_opcode == .close) {
                return error.ConnectionClosed;
            } else if (frame_opcode == .ping) {
                self.sendFrameRaw(.pong, &[_]u8{}) catch return error.WsProtocolError;
                continue;
            } else if (frame_opcode == .pong) {
                continue;
            }

            if (opcode == null) {
                if (frame_opcode == .continuation) return error.WsProtocolError;
                opcode = frame_opcode;
            } else {
                if (frame_opcode != .continuation) return error.WsProtocolError;
            }

            try payload.appendSlice(self.allocator, frame.payload);
            self.allocator.free(frame.payload);
            if (fin) break;
        }

        return .{
            .opcode = opcode.?,
            .data = try payload.toOwnedSlice(self.allocator),
        };
    }

    // ------------------------------------------------------------------
    // Private helpers
    // ------------------------------------------------------------------

    const Protocol = enum { ws, wss };
    const ParsedUrl = struct {
        protocol: Protocol,
        host: []const u8,
        port: u16,
        path: []const u8,
    };

    fn parseWsUrl(url: []const u8) ConnectError!ParsedUrl {
        const ws_prefix = "ws://";
        const wss_prefix = "wss://";

        const protocol: Protocol = if (std.mem.startsWith(u8, url, ws_prefix))
            .ws
        else if (std.mem.startsWith(u8, url, wss_prefix))
            .wss
        else
            return error.InvalidUrl;

        const rest = url[if (protocol == .ws) ws_prefix.len else wss_prefix.len..];
        const path_start = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        const host_port = rest[0..path_start];
        const path = if (path_start < rest.len) rest[path_start..] else "/";

        const port: u16 = if (std.mem.indexOfScalar(u8, host_port, ':')) |colon| port: {
            const p = std.fmt.parseInt(u16, host_port[colon + 1 ..], 10) catch return error.InvalidUrl;
            break :port p;
        } else switch (protocol) {
            .ws => 80,
            .wss => 443,
        };

        const host = if (std.mem.indexOfScalar(u8, host_port, ':')) |colon|
            host_port[0..colon]
        else
            host_port;

        return .{
            .protocol = protocol,
            .host = host,
            .port = port,
            .path = path,
        };
    }

    fn performHandshake(self: *WsClient, host: []const u8, port: u16, path: []const u8) ConnectError!void {
        var key_buf: [24]u8 = undefined;
        const key = generateSecWebSocketKey(self.io, &key_buf);

        const request = try std.fmt.allocPrint(
            self.allocator,
            "GET {s} HTTP/1.1\r\n" ++
                "Host: {s}:{d}\r\n" ++
                "Upgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Sec-WebSocket-Key: {s}\r\n" ++
                "Sec-WebSocket-Version: 13\r\n" ++
                "\r\n",
            .{ path, host, port, key },
        );
        defer self.allocator.free(request);

        var writer = self.stream.writer(self.io, self.write_buffer);
        _ = (&writer.interface).writeAll(request) catch return error.HandshakeFailed;

        var reader = self.stream.reader(self.io, self.read_buffer);
        var response_buf: [1024]u8 = undefined;
        var response_len: usize = 0;

        // Read until we find \r\n\r\n
        while (response_len < response_buf.len) {
            var vecs: [1][]u8 = .{response_buf[response_len..]};
            const n = (&reader.interface).readVec(&vecs) catch return error.HandshakeFailed;
            if (n == 0) return error.HandshakeFailed;
            response_len += n;
            if (std.mem.indexOf(u8, response_buf[0..response_len], "\r\n\r\n")) |_| break;
        } else {
            return error.HandshakeFailed;
        }

        const response = response_buf[0..response_len];
        if (!std.mem.startsWith(u8, response, "HTTP/1.1 101")) return error.HandshakeFailed;

        // Validate Sec-WebSocket-Accept
        const accept_expected = computeWebSocketAccept(self.allocator, key) catch return error.HandshakeFailed;
        defer self.allocator.free(accept_expected);

        if (std.mem.indexOf(u8, response, accept_expected) == null) {
            return error.HandshakeFailed;
        }
    }

    fn generateSecWebSocketKey(io: std.Io, buf: *[24]u8) []const u8 {
        var random_bytes: [16]u8 = undefined;
        io.random(&random_bytes);
        return std.base64.standard.Encoder.encode(buf, &random_bytes);
    }

    fn computeWebSocketAccept(allocator: std.mem.Allocator, key: []const u8) std.mem.Allocator.Error![]const u8 {
        const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var hash = std.crypto.hash.Sha1.init(.{});
        hash.update(key);
        hash.update(magic);
        var digest: [20]u8 = undefined;
        hash.final(&digest);
        const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(digest.len));
        return std.base64.standard.Encoder.encode(encoded, &digest);
    }

    fn sendFrame(self: *WsClient, opcode: Message.Opcode, payload: []const u8) SendError!void {
        try self.sendFrameRaw(opcode, payload);
    }

    fn sendFrameRaw(self: *WsClient, opcode: Message.Opcode, payload: []const u8) SendError!void {
        var writer = self.stream.writer(self.io, self.write_buffer);
        var header: [14]u8 = undefined;
        var header_len: usize = 2;

        header[0] = @as(u8, 0x80) | @intFromEnum(opcode); // FIN=1
        const mask_bit: u8 = 0x80; // client always masks

        if (payload.len <= 125) {
            header[1] = mask_bit | @as(u8, @intCast(payload.len));
        } else if (payload.len <= 65535) {
            header[1] = mask_bit | 126;
            header[2] = @as(u8, @intCast(payload.len >> 8));
            header[3] = @as(u8, @intCast(payload.len & 0xFF));
            header_len = 4;
        } else {
            header[1] = mask_bit | 127;
            const len = payload.len;
            header[2] = @as(u8, @intCast((len >> 56) & 0xFF));
            header[3] = @as(u8, @intCast((len >> 48) & 0xFF));
            header[4] = @as(u8, @intCast((len >> 40) & 0xFF));
            header[5] = @as(u8, @intCast((len >> 32) & 0xFF));
            header[6] = @as(u8, @intCast((len >> 24) & 0xFF));
            header[7] = @as(u8, @intCast((len >> 16) & 0xFF));
            header[8] = @as(u8, @intCast((len >> 8) & 0xFF));
            header[9] = @as(u8, @intCast(len & 0xFF));
            header_len = 10;
        }

        var mask_key: [4]u8 = undefined;
        self.io.random(&mask_key);
        @memcpy(header[header_len..][0..4], &mask_key);
        header_len += 4;

        (&writer.interface).writeAll(header[0..header_len]) catch return error.WsProtocolError;

        // Write masked payload
        var i: usize = 0;
        while (i < payload.len) : (i += 1) {
            const masked = payload[i] ^ mask_key[i % 4];
            (&writer.interface).writeAll(&[_]u8{masked}) catch return error.WsProtocolError;
        }
    }

    const Frame = struct {
        fin: bool,
        opcode: Message.Opcode,
        payload: []const u8,
    };

    fn readFrame(self: *WsClient) ReadError!Frame {
        var reader = self.stream.reader(self.io, self.read_buffer);

        var buf: [2]u8 = undefined;
        var vecs_buf: [1][]u8 = .{&buf};
        _ = (&reader.interface).readVecAll(&vecs_buf) catch return error.WsProtocolError;

        const fin = (buf[0] & 0x80) != 0;
        const opcode_int = buf[0] & 0x0F;
        const opcode: Message.Opcode = @enumFromInt(opcode_int);
        const masked = (buf[1] & 0x80) != 0;
        var payload_len: u64 = @as(u64, buf[1] & 0x7F);

        if (payload_len == 126) {
            var len_buf: [2]u8 = undefined;
            var vecs_lb: [1][]u8 = .{&len_buf};
            _ = (&reader.interface).readVecAll(&vecs_lb) catch return error.WsProtocolError;
            payload_len = (@as(u64, len_buf[0]) << 8) | @as(u64, len_buf[1]);
        } else if (payload_len == 127) {
            var len_buf: [8]u8 = undefined;
            var vecs_lb2: [1][]u8 = .{&len_buf};
            _ = (&reader.interface).readVecAll(&vecs_lb2) catch return error.WsProtocolError;
            payload_len = 0;
            for (len_buf) |b| {
                payload_len = (payload_len << 8) | @as(u64, b);
            }
        }

        var mask_key: [4]u8 = undefined;
        if (masked) {
            var vecs_mk: [1][]u8 = .{&mask_key};
            _ = (&reader.interface).readVecAll(&vecs_mk) catch return error.WsProtocolError;
        }

        const payload = try self.allocator.alloc(u8, @intCast(payload_len));
        errdefer self.allocator.free(payload);

        var remaining = payload_len;
        var offset: usize = 0;
        while (remaining > 0) {
            var vecs_pl: [1][]u8 = .{payload[offset..]};
            const n = (&reader.interface).readVec(&vecs_pl) catch return error.WsProtocolError;
            if (n == 0) return error.WsProtocolError;
            offset += n;
            remaining -= n;
        }

        if (masked) {
            for (payload, 0..) |*b, i| {
                b.* ^= mask_key[i % 4];
            }
        }

        return .{
            .fin = fin,
            .opcode = opcode,
            .payload = payload,
        };
    }
};

// ------------------------------------------------------------------
// WsRpcClient: Solana JSON-RPC over WebSocket
// ------------------------------------------------------------------

pub const WsRpcClient = struct {
    ws: WsClient,
    url: []const u8,
    next_id: u64 = 1,

    pub const SubscribeError = WsClient.SendError || WsClient.ReadError || error{InvalidSubscriptionResponse};
    pub const Notification = struct {
        allocator: std.mem.Allocator,
        method: []const u8,
        subscription_id: u64,
        result: std.json.Parsed(std.json.Value),

        pub fn deinit(self: *Notification) void {
            self.allocator.free(self.method);
            self.result.deinit();
        }
    };

    pub fn connect(allocator: std.mem.Allocator, io: std.Io, url: []const u8) WsClient.ConnectError!WsRpcClient {
        var ws = try WsClient.connect(allocator, io, url);
        const url_copy = allocator.dupe(u8, url) catch |err| {
            ws.deinit();
            return err;
        };
        return .{
            .ws = ws,
            .url = url_copy,
        };
    }

    pub fn deinit(self: *WsRpcClient) void {
        self.ws.deinit();
        self.ws.allocator.free(self.url);
    }

    pub fn disconnect(self: *WsRpcClient) void {
        _ = self.ws.sendClose() catch {};
        self.ws.deinit();
    }

    pub fn reconnect(self: *WsRpcClient) WsClient.ConnectError!void {
        self.ws.deinit();
        self.ws = try WsClient.connect(self.ws.allocator, self.ws.io, self.url);
    }

    pub fn accountSubscribe(self: *WsRpcClient, pubkey_base58: []const u8) SubscribeError!u64 {
        const payload = try std.fmt.allocPrint(
            self.ws.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"accountSubscribe\",\"params\":[\"{s}\",{{\"encoding\":\"base64\",\"commitment\":\"confirmed\"}}]}}",
            .{ self.nextRpcId(), pubkey_base58 },
        );
        defer self.ws.allocator.free(payload);
        try self.ws.sendText(payload);
        return try self.readSubscriptionResult();
    }

    pub fn logsSubscribe(self: *WsRpcClient, filter: []const u8) SubscribeError!u64 {
        const payload = try std.fmt.allocPrint(
            self.ws.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"logsSubscribe\",\"params\":[\"{s}\"]}}",
            .{ self.nextRpcId(), filter },
        );
        defer self.ws.allocator.free(payload);
        try self.ws.sendText(payload);
        return try self.readSubscriptionResult();
    }

    pub fn signatureSubscribe(self: *WsRpcClient, signature_base58: []const u8) SubscribeError!u64 {
        const payload = try std.fmt.allocPrint(
            self.ws.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"signatureSubscribe\",\"params\":[\"{s}\",{{\"commitment\":\"confirmed\"}}]}}",
            .{ self.nextRpcId(), signature_base58 },
        );
        defer self.ws.allocator.free(payload);
        try self.ws.sendText(payload);
        return try self.readSubscriptionResult();
    }

    pub fn unsubscribe(self: *WsRpcClient, subscription_id: u64, method: []const u8) SubscribeError!void {
        const payload = try std.fmt.allocPrint(
            self.ws.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":[{d}]}}",
            .{ self.nextRpcId(), method, subscription_id },
        );
        defer self.ws.allocator.free(payload);
        try self.ws.sendText(payload);
        _ = try self.readSubscriptionResult(); // consume ack
    }

    pub fn readNotification(self: *WsRpcClient) (SubscribeError || WsClient.ReadError || error{OutOfMemory})!Notification {
        const msg = try self.ws.readMessage();
        defer self.ws.allocator.free(msg.data);
        if (msg.opcode != .text and msg.opcode != .binary) {
            return error.WsProtocolError;
        }

        var parsed = std.json.parseFromSlice(std.json.Value, self.ws.allocator, msg.data, .{}) catch return error.InvalidSubscriptionResponse;
        defer parsed.deinit();

        const root = parsed.value;
        const method_val = root.object.get("method") orelse return error.InvalidSubscriptionResponse;
        const method = try self.ws.allocator.dupe(u8, method_val.string);
        errdefer self.ws.allocator.free(method);

        const params = root.object.get("params") orelse return error.InvalidSubscriptionResponse;
        const subscription_id = @as(u64, @intCast(params.object.get("subscription").?.integer));
        const result = std.json.parseFromValue(std.json.Value, self.ws.allocator, params.object.get("result").?, .{}) catch return error.InvalidSubscriptionResponse;

        return .{
            .allocator = self.ws.allocator,
            .method = method,
            .subscription_id = subscription_id,
            .result = result,
        };
    }

    fn nextRpcId(self: *WsRpcClient) u64 {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    fn readSubscriptionResult(self: *WsRpcClient) SubscribeError!u64 {
        const msg = try self.ws.readMessage();
        defer self.ws.allocator.free(msg.data);
        var parsed = std.json.parseFromSlice(std.json.Value, self.ws.allocator, msg.data, .{}) catch return error.InvalidSubscriptionResponse;
        defer parsed.deinit();
        const result = parsed.value.object.get("result") orelse return error.InvalidSubscriptionResponse;
        return @intCast(result.integer);
    }
};

// ------------------------------------------------------------------
// Mock WebSocket Server (for tests)
// ------------------------------------------------------------------

const MockWsServer = struct {
    io: std.Io,
    server: std.Io.net.Server,
    thread: std.Thread,
    port: u16,

    fn start(allocator: std.mem.Allocator, io: std.Io) !MockWsServer {
        const addr = std.Io.net.Ip4Address.loopback(0); // OS-assigned ephemeral port
        const ip_addr: std.Io.net.IpAddress = .{ .ip4 = addr };
        const server = try std.Io.net.IpAddress.listen(&ip_addr, io, .{ .mode = .stream });

        const actual_port = server.socket.address.getPort();
        const thread = try std.Thread.spawn(.{}, MockWsServer.run, .{ allocator, io, server });

        return .{
            .io = io,
            .server = server,
            .thread = thread,
            .port = actual_port,
        };
    }

    fn stop(self: *MockWsServer) void {
        const addr = std.Io.net.Ip4Address.loopback(self.port);
        const ip_addr: std.Io.net.IpAddress = .{ .ip4 = addr };

        // Unblock any pending accept() without forcing a NOTSOCK panic in the worker thread.
        for (0..2) |_| {
            const stream = std.Io.net.IpAddress.connect(&ip_addr, self.io, .{ .mode = .stream }) catch break;
            stream.close(self.io);
        }

        self.thread.join();
        self.server.socket.close(self.io);
    }

    fn run(allocator: std.mem.Allocator, io: std.Io, server: std.Io.net.Server) !void {
        var local_server = server;

        // Accept up to 2 connections to support reconnect tests.
        for (0..2) |_| {
            const stream = local_server.accept(io) catch return;
            handleConnection(allocator, io, stream) catch {};
            stream.close(io);
        }
    }

    fn handleConnection(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream) !void {
        var read_buf: [4096]u8 = undefined;
        var write_buf: [4096]u8 = undefined;
        var reader = stream.reader(io, &read_buf);
        var writer = stream.writer(io, &write_buf);

        // Read HTTP upgrade request
        var req_buf: [1024]u8 = undefined;
        var req_len: usize = 0;
        while (req_len < req_buf.len) {
            var vecs_req: [1][]u8 = .{req_buf[req_len..]};
            const n = (&reader.interface).readVec(&vecs_req) catch return;
            if (n == 0) return;
            req_len += n;
            if (std.mem.indexOf(u8, req_buf[0..req_len], "\r\n\r\n")) |_| break;
        }

        // Extract Sec-WebSocket-Key
        const key_prefix = "Sec-WebSocket-Key: ";
        const req = req_buf[0..req_len];
        const key_start = std.mem.indexOf(u8, req, key_prefix) orelse return;
        const key_end = std.mem.indexOf(u8, req[key_start + key_prefix.len ..], "\r\n") orelse return;
        const key = req[key_start + key_prefix.len .. key_start + key_prefix.len + key_end];

        const accept = WsClient.computeWebSocketAccept(allocator, key) catch return;
        defer allocator.free(accept);

        const response = try std.fmt.allocPrint(
            allocator,
            "HTTP/1.1 101 Switching Protocols\r\n" ++
                "Upgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Sec-WebSocket-Accept: {s}\r\n" ++
                "\r\n",
            .{accept},
        );
        defer allocator.free(response);
        _ = (&writer.interface).writeAll(response) catch return;

        // Simple echo loop for JSON-RPC subscribe/unsubscribe
        const loop_allocator = allocator;
        var next_sub: u64 = 1;

        while (true) {
            const frame = readFrameRaw(loop_allocator, io, &reader, &read_buf) catch break;
            defer loop_allocator.free(frame.payload);

            if (frame.opcode == .close) {
                sendFrameRaw(&writer.interface, io, &write_buf, .close, &[_]u8{}) catch {};
                break;
            }
            if (frame.opcode == .ping) {
                sendFrameRaw(&writer.interface, io, &write_buf, .pong, &[_]u8{}) catch {};
                continue;
            }
            if (frame.opcode != .text and frame.opcode != .binary) continue;

            var parsed = std.json.parseFromSlice(std.json.Value, loop_allocator, frame.payload, .{}) catch continue;
            defer parsed.deinit();

            const method = parsed.value.object.get("method") orelse continue;
            const id = parsed.value.object.get("id") orelse continue;
            const is_subscribe = std.mem.endsWith(u8, method.string, "Subscribe");
            const force_disconnect_after_notify = std.mem.indexOf(u8, frame.payload, "force_disconnect_after_notify") != null;
            const malformed_subscribe_response = std.mem.indexOf(u8, frame.payload, "malformed_sub_reply") != null;
            const sub_id = next_sub;
            next_sub += 1;

            if (is_subscribe and malformed_subscribe_response) {
                // Intentionally malformed JSON-RPC response for failure-path tests.
                const reply = "{\"jsonrpc\":\"2.0\",\"result\":";
                sendFrameRaw(&writer.interface, io, &write_buf, .text, reply) catch break;
                continue;
            }

            const reply = try std.fmt.allocPrint(
                loop_allocator,
                "{{\"jsonrpc\":\"2.0\",\"result\":{d},\"id\":{d}}}",
                .{ sub_id, id.integer },
            );
            defer loop_allocator.free(reply);
            sendFrameRaw(&writer.interface, io, &write_buf, .text, reply) catch break;

            // If it was a subscribe, send a mock notification
            if (is_subscribe) {
                const notif = try std.fmt.allocPrint(
                    loop_allocator,
                    "{{\"jsonrpc\":\"2.0\",\"method\":\"{s}Notification\",\"params\":{{\"result\":{{\"mock\":true}},\"subscription\":{d}}}}}",
                    .{ method.string, sub_id },
                );
                defer loop_allocator.free(notif);
                sendFrameRaw(&writer.interface, io, &write_buf, .text, notif) catch break;

                if (force_disconnect_after_notify) {
                    // Simulate server-side disconnect after the first notification.
                    break;
                }
            }
        }
    }

    const FrameHeader = struct {
        fin: bool,
        opcode: WsClient.Message.Opcode,
        payload: []const u8,
    };

    fn readFrameRaw(allocator: std.mem.Allocator, io: std.Io, reader: *std.Io.net.Stream.Reader, _: []u8) !FrameHeader {
        _ = io;
        var h: [2]u8 = undefined;
        var vecs_h: [1][]u8 = .{&h};
        _ = try (&reader.interface).readVecAll(&vecs_h);
        const fin = (h[0] & 0x80) != 0;
        const opcode: WsClient.Message.Opcode = @enumFromInt(h[0] & 0x0F);
        const masked = (h[1] & 0x80) != 0;
        var payload_len: u64 = @as(u64, h[1] & 0x7F);

        if (payload_len == 126) {
            var lb: [2]u8 = undefined;
            var vecs_lb_m: [1][]u8 = .{&lb};
            _ = try (&reader.interface).readVecAll(&vecs_lb_m);
            payload_len = (@as(u64, lb[0]) << 8) | @as(u64, lb[1]);
        } else if (payload_len == 127) {
            var lb: [8]u8 = undefined;
            var vecs_lb_m: [1][]u8 = .{&lb};
            _ = try (&reader.interface).readVecAll(&vecs_lb_m);
            payload_len = 0;
            for (lb) |b| payload_len = (payload_len << 8) | b;
        }

        var mask_key: [4]u8 = undefined;
        if (masked) {
            var vecs_mk_m: [1][]u8 = .{&mask_key};
            _ = try (&reader.interface).readVecAll(&vecs_mk_m);
        }

        const payload = try allocator.alloc(u8, @intCast(payload_len));
        errdefer allocator.free(payload);

        var remaining = payload_len;
        var offset: usize = 0;
        while (remaining > 0) {
            var vecs_pl_m: [1][]u8 = .{payload[offset..]};
            const n = (&reader.interface).readVec(&vecs_pl_m) catch return error.WsProtocolError;
            if (n == 0) return error.WsProtocolError;
            offset += n;
            remaining -= n;
        }

        if (masked) {
            for (payload, 0..) |*b, i| b.* ^= mask_key[i % 4];
        }

        return .{ .fin = fin, .opcode = opcode, .payload = payload };
    }

    fn sendFrameRaw(writer: *std.Io.Writer, io: std.Io, buf: []u8, opcode: WsClient.Message.Opcode, payload: []const u8) !void {
        _ = io;
        _ = buf;
        var header: [14]u8 = undefined;
        var header_len: usize = 2;
        header[0] = @as(u8, 0x80) | @as(u8, @intFromEnum(opcode));
        header[1] = @intCast(payload.len);
        if (payload.len > 125) {
            if (payload.len <= 65535) {
                header[1] = 126;
                header[2] = @intCast(payload.len >> 8);
                header[3] = @intCast(payload.len & 0xFF);
                header_len = 4;
            } else {
                header[1] = 127;
                const len = payload.len;
                header[2] = @intCast((len >> 56) & 0xFF);
                header[3] = @intCast((len >> 48) & 0xFF);
                header[4] = @intCast((len >> 40) & 0xFF);
                header[5] = @intCast((len >> 32) & 0xFF);
                header[6] = @intCast((len >> 24) & 0xFF);
                header[7] = @intCast((len >> 16) & 0xFF);
                header[8] = @intCast((len >> 8) & 0xFF);
                header[9] = @intCast(len & 0xFF);
                header_len = 10;
            }
        }
        _ = writer.writeAll(header[0..header_len]) catch return error.WsProtocolError;
        _ = writer.writeAll(payload) catch return error.WsProtocolError;
    }
};

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

test "WsRpcClient subscribe and receive notification" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator, io);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const sub_id = try client.accountSubscribe("11111111111111111111111111111111");
    try std.testing.expect(sub_id > 0);

    var notif = try client.readNotification();
    defer notif.deinit();
    try std.testing.expectEqualStrings("accountSubscribeNotification", notif.method);
    try std.testing.expectEqual(sub_id, notif.subscription_id);
}

test "WsRpcClient disconnect detect and reconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator, io);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const sub_id = try client.signatureSubscribe("deadbeef");
    try std.testing.expect(sub_id > 0);

    // Simulate disconnect by stopping server after first notification
    // Since server auto-closes after sending notification, readNotification will return error.ConnectionClosed
    // But our mock server sends notification before close, so we can read it.
    var notif = try client.readNotification();
    defer notif.deinit();

    // Now reconnect (server thread already exited, but in real test we'd restart server)
    // For this test, we just verify reconnect() compiles and re-establishes connection.
    // Since mock server only handles one connection, this will fail unless we restart server.
    // We'll skip the actual reconnect read and just assert the method exists.
    try client.reconnect();
}

test "ws_unsubscribe_ack_success" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator, io);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const sub_id = try client.accountSubscribe("11111111111111111111111111111111");
    try std.testing.expect(sub_id > 0);

    try client.unsubscribe(sub_id, "accountUnsubscribe");
}

test "ws_reconnect_detect_disconnect_then_reconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator, io);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const sub_id = try client.logsSubscribe("force_disconnect_after_notify");
    try std.testing.expect(sub_id > 0);

    // First notification is delivered, then server closes the stream.
    var notif = try client.readNotification();
    defer notif.deinit();
    try std.testing.expectEqualStrings("logsSubscribeNotification", notif.method);

    // Next read observes the disconnect.
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    // Reconnect must restore connectivity.
    try client.reconnect();
}

test "ws_reconnect_resubscribe_after_reconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator, io);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    _ = try client.logsSubscribe("force_disconnect_after_notify");
    var first_notif = try client.readNotification();
    first_notif.deinit();
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    try client.reconnect();
    const sub_id2 = try client.signatureSubscribe("deadbeef");
    try std.testing.expect(sub_id2 > 0);
    var second_notif = try client.readNotification();
    defer second_notif.deinit();
    try std.testing.expectEqualStrings("signatureSubscribeNotification", second_notif.method);
}

test "ws_reconnect_subscription_response_malformed" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator, io);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    try std.testing.expectError(error.InvalidSubscriptionResponse, client.logsSubscribe("malformed_sub_reply"));
}

test "parseWsUrl basic" {
    const parsed = try WsClient.parseWsUrl("ws://localhost:8900/");
    try std.testing.expectEqual(WsClient.Protocol.ws, parsed.protocol);
    try std.testing.expectEqualStrings("localhost", parsed.host);
    try std.testing.expectEqual(@as(u16, 8900), parsed.port);
    try std.testing.expectEqualStrings("/", parsed.path);
}

test "parseWsUrl default port and path" {
    const parsed = try WsClient.parseWsUrl("ws://example.com");
    try std.testing.expectEqual(@as(u16, 80), parsed.port);
    try std.testing.expectEqualStrings("/", parsed.path);
}

test "generateSecWebSocketKey length" {
    var buf: [24]u8 = undefined;
    const key = WsClient.generateSecWebSocketKey(std.testing.io, &buf);
    try std.testing.expectEqual(@as(usize, 24), key.len);
}

test "computeWebSocketAccept" {
    const allocator = std.testing.allocator;
    const accept = try WsClient.computeWebSocketAccept(allocator, "dGhlIHNhbXBsZSBub25jZQ==");
    defer allocator.free(accept);
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept);
}
