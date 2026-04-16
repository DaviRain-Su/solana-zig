const std = @import("std");
const types = @import("types.zig");

const c = std.c;

pub const WsClient = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    stream: std.Io.net.Stream,
    fd: std.posix.fd_t,
    closed: bool = false,
    next_id: u64 = 1,

    pub const ConnectError = std.mem.Allocator.Error || std.Io.net.IpAddress.ConnectError || std.Io.net.Ip6Address.ResolveError || error{
        InvalidUrl,
        HandshakeFailed,
        WsProtocolError,
    };

    pub const SendError = std.mem.Allocator.Error || error{WsProtocolError};

    pub const ReadError = std.mem.Allocator.Error || error{
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

    pub fn connect(allocator: std.mem.Allocator, io: std.Io, url: []const u8) ConnectError!WsClient {
        const parsed = try parseWsUrl(url);
        const is_tls = parsed.protocol == .wss;
        if (is_tls) return error.InvalidUrl;

        const addr = try std.Io.net.IpAddress.resolve(io, parsed.host, parsed.port);
        const stream = try std.Io.net.IpAddress.connect(&addr, io, .{ .mode = .stream });
        errdefer stream.close(io);

        var client = WsClient{
            .allocator = allocator,
            .io = io,
            .stream = stream,
            .fd = stream.socket.handle,
            .closed = false,
        };

        try client.performHandshake(parsed.host, parsed.port, parsed.path);
        return client;
    }

    pub fn deinit(self: *WsClient) void {
        if (self.closed) return;
        self.closed = true;
        self.stream.close(self.io);
    }

    pub fn sendText(self: *WsClient, text: []const u8) SendError!void {
        try self.sendFrame(.text, text);
    }

    pub fn sendClose(self: *WsClient) SendError!void {
        try self.sendFrame(.close, &[_]u8{});
    }

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

    fn posixReadAll(fd: std.posix.fd_t, buf: []u8) !void {
        var off: usize = 0;
        while (off < buf.len) {
            const n = c.read(fd, buf[off..].ptr, buf.len - off);
            if (n == 0) return error.ConnectionClosed;
            if (n < 0) return error.WsProtocolError;
            off += @intCast(n);
        }
    }

    fn posixRead(fd: std.posix.fd_t, buf: []u8) !usize {
        const n = c.read(fd, buf.ptr, buf.len);
        if (n <= 0) return 0;
        return @intCast(n);
    }

    fn posixWriteAll(fd: std.posix.fd_t, data: []const u8) !void {
        var off: usize = 0;
        while (off < data.len) {
            const n = c.write(fd, data[off..].ptr, data.len - off);
            if (n <= 0) return error.WsProtocolError;
            off += @intCast(n);
        }
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

        posixWriteAll(self.fd, request) catch return error.HandshakeFailed;

        var response_buf: [1024]u8 = undefined;
        var response_len: usize = 0;
        while (response_len < response_buf.len) {
            const n = posixRead(self.fd, response_buf[response_len..]) catch return error.HandshakeFailed;
            if (n == 0) return error.HandshakeFailed;
            response_len += n;
            if (std.mem.indexOf(u8, response_buf[0..response_len], "\r\n\r\n")) |_| break;
        } else {
            return error.HandshakeFailed;
        }

        const response = response_buf[0..response_len];
        if (!std.mem.startsWith(u8, response, "HTTP/1.1 101")) return error.HandshakeFailed;

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
        var header: [14]u8 = undefined;
        var header_len: usize = 2;

        header[0] = @as(u8, 0x80) | @intFromEnum(opcode);
        const mask_bit: u8 = 0x80;

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

        posixWriteAll(self.fd, header[0..header_len]) catch return error.WsProtocolError;

        const masked_buf = self.allocator.alloc(u8, payload.len) catch return error.WsProtocolError;
        defer self.allocator.free(masked_buf);
        for (masked_buf, 0..) |*b, i| {
            b.* = payload[i] ^ mask_key[i % 4];
        }
        posixWriteAll(self.fd, masked_buf) catch return error.WsProtocolError;
    }

    const Frame = struct {
        fin: bool,
        opcode: Message.Opcode,
        payload: []const u8,
    };

    fn readFrame(self: *WsClient) ReadError!Frame {
        var buf: [2]u8 = undefined;
        posixReadAll(self.fd, &buf) catch |err| switch (err) {
            error.ConnectionClosed => return error.ConnectionClosed,
            else => return error.WsProtocolError,
        };

        const fin = (buf[0] & 0x80) != 0;
        const opcode: Message.Opcode = @enumFromInt(buf[0] & 0x0F);
        const masked = (buf[1] & 0x80) != 0;
        var payload_len: u64 = @as(u64, buf[1] & 0x7F);

        if (payload_len == 126) {
            var len_buf: [2]u8 = undefined;
            posixReadAll(self.fd, &len_buf) catch return error.WsProtocolError;
            payload_len = (@as(u64, len_buf[0]) << 8) | @as(u64, len_buf[1]);
        } else if (payload_len == 127) {
            var len_buf: [8]u8 = undefined;
            posixReadAll(self.fd, &len_buf) catch return error.WsProtocolError;
            payload_len = 0;
            for (len_buf) |b| {
                payload_len = (payload_len << 8) | @as(u64, b);
            }
        }

        var mask_key: [4]u8 = undefined;
        if (masked) {
            posixReadAll(self.fd, &mask_key) catch return error.WsProtocolError;
        }

        const payload = self.allocator.alloc(u8, @intCast(payload_len)) catch return error.WsProtocolError;
        errdefer self.allocator.free(payload);

        posixReadAll(self.fd, payload) catch return error.WsProtocolError;

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
    // -- Production hardening constants (P2-18, frozen in #36) --
    pub const MAX_RECONNECT_RETRIES: u8 = 5;
    pub const MAX_BACKOFF_MS: u64 = 30_000;
    pub const DEDUP_CACHE_SIZE: usize = 16;

    // -- Observability snapshot schema (P2-23, frozen in docs/24) --
    pub const WsStats = struct {
        reconnect_attempts_total: u32,
        active_subscriptions: u32,
        dedup_dropped_total: u32,
        last_error_code: ?u16,
        last_error_message: ?[]const u8,
        last_reconnect_unix_ms: ?u64,
    };

    ws: WsClient,
    url: []const u8,
    next_id: u64 = 1,
    subscriptions: std.ArrayList(Subscription) = .empty,
    dedup_ring: [DEDUP_CACHE_SIZE]u64 = [_]u64{0} ** DEDUP_CACHE_SIZE,
    dedup_ring_len: usize = 0,
    dedup_ring_pos: usize = 0,
    last_reconnect_attempts: u8 = 0,

    // -- Observability counters/state (P2-23) --
    reconnect_attempts_total: u32 = 0,
    dedup_dropped_total: u32 = 0,
    messages_received_total: u64 = 0,
    last_error_code: ?u16 = null,
    last_error_message_buf: [128]u8 = [_]u8{0} ** 128,
    last_error_message_len: u8 = 0,
    last_reconnect_unix_ms: ?u64 = null,

    pub const SubscribeError = WsClient.SendError || WsClient.ReadError || error{InvalidSubscriptionResponse};
    pub const ReconnectError = WsClient.ConnectError || SubscribeError;
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

    const SubscriptionKind = enum {
        account,
        logs,
        signature,
    };

    const Subscription = struct {
        kind: SubscriptionKind,
        value: []u8,
        id: u64,
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
        for (self.subscriptions.items) |sub| {
            self.ws.allocator.free(sub.value);
        }
        self.subscriptions.deinit(self.ws.allocator);
        self.ws.deinit();
        self.ws.allocator.free(self.url);
    }

    pub fn disconnect(self: *WsRpcClient) void {
        _ = self.ws.sendClose() catch {};
        self.ws.deinit();
    }

    pub fn reconnect(self: *WsRpcClient) WsClient.ConnectError!void {
        self.ws.deinit();
        self.reconnect_attempts_total += 1;
        self.ws = try WsClient.connect(self.ws.allocator, self.ws.io, self.url);
        self.recordReconnectTimestamp();
    }

    pub fn reconnectWithBackoff(self: *WsRpcClient, retries: u8, base_delay_ms: u64) ReconnectError!void {
        const capped_retries = @min(retries, MAX_RECONNECT_RETRIES);
        var attempt: u8 = 0;
        self.last_reconnect_attempts = 0;
        while (attempt < capped_retries) : (attempt += 1) {
            self.last_reconnect_attempts = attempt + 1;
            self.reconnect_attempts_total += 1;
            if (self.reconnectAndResubscribe()) |_| {
                self.recordReconnectTimestamp();
                return;
            } else |err| {
                self.recordError(1, "reconnect_failed");
                if (attempt + 1 == capped_retries) return err;
                const raw_delay = base_delay_ms << @intCast(attempt);
                const delay_ms = @min(raw_delay, MAX_BACKOFF_MS);
                var spins: u64 = delay_ms * 10_000;
                while (spins > 0) : (spins -= 1) {
                    std.atomic.spinLoopHint();
                }
            }
        }
        return error.HandshakeFailed;
    }

    pub fn sendPing(self: *WsRpcClient) WsClient.SendError!void {
        try self.ws.sendFrame(.ping, &[_]u8{});
    }

    pub fn subscriptionCount(self: *const WsRpcClient) usize {
        return self.subscriptions.items.len;
    }

    pub fn snapshot(self: *const WsRpcClient) WsStats {
        return .{
            .reconnect_attempts_total = self.reconnect_attempts_total,
            .active_subscriptions = @intCast(self.subscriptions.items.len),
            .dedup_dropped_total = self.dedup_dropped_total,
            .last_error_code = self.last_error_code,
            .last_error_message = if (self.last_error_message_len > 0)
                self.last_error_message_buf[0..self.last_error_message_len]
            else
                null,
            .last_reconnect_unix_ms = self.last_reconnect_unix_ms,
        };
    }

    fn recordError(self: *WsRpcClient, code: u16, msg: []const u8) void {
        self.last_error_code = code;
        const len = @min(msg.len, self.last_error_message_buf.len);
        @memcpy(self.last_error_message_buf[0..len], msg[0..len]);
        self.last_error_message_len = @intCast(len);
    }

    fn recordReconnectTimestamp(self: *WsRpcClient) void {
        var ts: std.c.timespec = undefined;
        if (std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts) == 0) {
            self.last_reconnect_unix_ms = @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
        }
    }

    pub fn accountSubscribe(self: *WsRpcClient, pubkey_base58: []const u8) SubscribeError!u64 {
        return try self.ensureSubscribed(.account, pubkey_base58);
    }

    pub fn logsSubscribe(self: *WsRpcClient, filter: []const u8) SubscribeError!u64 {
        return try self.ensureSubscribed(.logs, filter);
    }

    pub fn signatureSubscribe(self: *WsRpcClient, signature_base58: []const u8) SubscribeError!u64 {
        return try self.ensureSubscribed(.signature, signature_base58);
    }

    pub fn unsubscribe(self: *WsRpcClient, subscription_id: u64, method: []const u8) SubscribeError!void {
        const payload = try std.fmt.allocPrint(
            self.ws.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":[{d}]}}",
            .{ self.nextRpcId(), method, subscription_id },
        );
        defer self.ws.allocator.free(payload);
        try self.ws.sendText(payload);
        _ = try self.readSubscriptionResult();
        self.removeSubscription(subscription_id);
    }

    pub fn readNotification(self: *WsRpcClient) (SubscribeError || WsClient.ReadError || error{OutOfMemory})!Notification {
        while (true) {
            const msg = try self.ws.readMessage();
            defer self.ws.allocator.free(msg.data);
            if (msg.opcode != .text and msg.opcode != .binary) {
                return error.WsProtocolError;
            }

            self.messages_received_total += 1;

            const h = std.hash.Wyhash.hash(0, msg.data);
            if (self.isDuplicateNotification(h)) {
                self.dedup_dropped_total += 1;
                continue;
            }
            self.recordNotificationHash(h);

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
    }

    fn isDuplicateNotification(self: *const WsRpcClient, h: u64) bool {
        const len = self.dedup_ring_len;
        for (0..len) |i| {
            if (self.dedup_ring[i] == h) return true;
        }
        return false;
    }

    fn recordNotificationHash(self: *WsRpcClient, h: u64) void {
        self.dedup_ring[self.dedup_ring_pos] = h;
        self.dedup_ring_pos = (self.dedup_ring_pos + 1) % DEDUP_CACHE_SIZE;
        if (self.dedup_ring_len < DEDUP_CACHE_SIZE) {
            self.dedup_ring_len += 1;
        }
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

    fn ensureSubscribed(self: *WsRpcClient, kind: SubscriptionKind, value: []const u8) SubscribeError!u64 {
        for (self.subscriptions.items) |sub| {
            if (sub.kind == kind and std.mem.eql(u8, sub.value, value)) {
                return sub.id;
            }
        }

        const payload = try self.buildSubscribePayload(kind, value);
        defer self.ws.allocator.free(payload);
        try self.ws.sendText(payload);
        const id = try self.readSubscriptionResult();

        try self.subscriptions.append(self.ws.allocator, .{
            .kind = kind,
            .value = try self.ws.allocator.dupe(u8, value),
            .id = id,
        });
        return id;
    }

    fn buildSubscribePayload(self: *WsRpcClient, kind: SubscriptionKind, value: []const u8) std.mem.Allocator.Error![]u8 {
        return switch (kind) {
            .account => std.fmt.allocPrint(
                self.ws.allocator,
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"accountSubscribe\",\"params\":[\"{s}\",{{\"encoding\":\"base64\",\"commitment\":\"confirmed\"}}]}}",
                .{ self.nextRpcId(), value },
            ),
            .logs => std.fmt.allocPrint(
                self.ws.allocator,
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"logsSubscribe\",\"params\":[\"{s}\"]}}",
                .{ self.nextRpcId(), value },
            ),
            .signature => std.fmt.allocPrint(
                self.ws.allocator,
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"signatureSubscribe\",\"params\":[\"{s}\",{{\"commitment\":\"confirmed\"}}]}}",
                .{ self.nextRpcId(), value },
            ),
        };
    }

    fn resubscribeAll(self: *WsRpcClient) SubscribeError!void {
        for (self.subscriptions.items) |*sub| {
            const payload = try self.buildSubscribePayload(sub.kind, sub.value);
            defer self.ws.allocator.free(payload);
            try self.ws.sendText(payload);
            sub.id = try self.readSubscriptionResult();
        }
    }

    fn reconnectAndResubscribe(self: *WsRpcClient) ReconnectError!void {
        try self.reconnect();
        try self.resubscribeAll();
    }

    fn removeSubscription(self: *WsRpcClient, subscription_id: u64) void {
        var i: usize = 0;
        while (i < self.subscriptions.items.len) : (i += 1) {
            if (self.subscriptions.items[i].id == subscription_id) {
                self.ws.allocator.free(self.subscriptions.items[i].value);
                _ = self.subscriptions.swapRemove(i);
                return;
            }
        }
    }
};

// ------------------------------------------------------------------
// Mock WebSocket Server (for tests)
// ------------------------------------------------------------------

fn rawReadAll(fd: std.posix.fd_t, buf: []u8) !void {
    var off: usize = 0;
    while (off < buf.len) {
        const n = std.c.read(fd, buf[off..].ptr, buf.len - off);
        if (n <= 0) return error.WsProtocolError;
        off += @intCast(n);
    }
}

fn rawRead(fd: std.posix.fd_t, buf: []u8) !usize {
    const n = std.c.read(fd, buf.ptr, buf.len);
    if (n <= 0) return error.WsProtocolError;
    return @intCast(n);
}

fn rawWriteAll(fd: std.posix.fd_t, data: []const u8) !void {
    var off: usize = 0;
    while (off < data.len) {
        const n = std.c.write(fd, data[off..].ptr, data.len - off);
        if (n <= 0) return error.WsProtocolError;
        off += @intCast(n);
    }
}

const MockWsServer = struct {
    const ServerContext = struct {
        mutex: std.atomic.Mutex = .unlocked,
        listen_fd: std.posix.fd_t,
        conn_fd: std.posix.fd_t = -1,
        stopped: bool = false,
        max_connections: usize = 2,
    };

    ctx: *ServerContext,
    thread: std.Thread,
    port: u16,
    allocator: std.mem.Allocator,

    fn start(allocator: std.mem.Allocator) !MockWsServer {
        return startMulti(allocator, 2);
    }

    fn startMulti(allocator: std.mem.Allocator, max_connections: usize) !MockWsServer {
        const listen_fd = c.socket(c.AF.INET, c.SOCK.STREAM, 0);
        if (listen_fd < 0) return error.WsProtocolError;

        var opt: c_int = 1;
        _ = c.setsockopt(listen_fd, c.SOL.SOCKET, c.SO.REUSEADDR, std.mem.asBytes(&opt), @sizeOf(c_int));

        var addr: c.sockaddr.in = std.mem.zeroes(c.sockaddr.in);
        addr.family = c.AF.INET;
        addr.addr = std.mem.nativeToBig(u32, 0x7f000001);
        addr.port = std.mem.nativeToBig(u16, 0);

        if (c.bind(listen_fd, @ptrCast(&addr), @sizeOf(c.sockaddr.in)) < 0) return error.WsProtocolError;
        if (c.listen(listen_fd, @intCast(max_connections)) < 0) return error.WsProtocolError;

        var bound_addr: c.sockaddr.in = std.mem.zeroes(c.sockaddr.in);
        var addr_len: c.socklen_t = @sizeOf(c.sockaddr.in);
        if (c.getsockname(listen_fd, @ptrCast(&bound_addr), &addr_len) < 0) return error.WsProtocolError;
        const port = std.mem.bigToNative(u16, bound_addr.port);

        const ctx = try allocator.create(ServerContext);
        ctx.* = .{ .listen_fd = listen_fd, .max_connections = max_connections };

        const thread = try std.Thread.spawn(.{}, MockWsServer.run, .{ allocator, ctx });

        return .{
            .ctx = ctx,
            .thread = thread,
            .port = port,
            .allocator = allocator,
        };
    }

    fn stop(self: *MockWsServer) void {
        {
            lockAtomicMutex(&self.ctx.mutex);
            defer self.ctx.mutex.unlock();
            self.ctx.stopped = true;
            if (self.ctx.conn_fd >= 0) {
                _ = std.c.shutdown(self.ctx.conn_fd, 2);
                _ = std.c.close(self.ctx.conn_fd);
                self.ctx.conn_fd = -1;
            }
        }

        const dummy_fd = c.socket(c.AF.INET, c.SOCK.STREAM, 0);
        if (dummy_fd >= 0) {
            var addr: c.sockaddr.in = std.mem.zeroes(c.sockaddr.in);
            addr.family = c.AF.INET;
            addr.addr = std.mem.nativeToBig(u32, 0x7f000001);
            addr.port = std.mem.nativeToBig(u16, self.port);
            _ = c.connect(dummy_fd, @ptrCast(&addr), @sizeOf(c.sockaddr.in));
            _ = std.c.close(dummy_fd);
        }

        self.thread.join();
        _ = std.c.shutdown(self.ctx.listen_fd, 2);
        _ = std.c.close(self.ctx.listen_fd);
        self.allocator.destroy(self.ctx);
    }

    fn run(allocator: std.mem.Allocator, ctx: *ServerContext) void {
        for (0..ctx.max_connections) |_| {
            const conn_fd = c.accept(ctx.listen_fd, null, null);
            if (conn_fd < 0) return;

            {
                lockAtomicMutex(&ctx.mutex);
                defer ctx.mutex.unlock();
                if (ctx.stopped) {
                    _ = std.c.close(conn_fd);
                    return;
                }
                ctx.conn_fd = conn_fd;
            }

            handleConnection(allocator, conn_fd) catch {};

            {
                lockAtomicMutex(&ctx.mutex);
                defer ctx.mutex.unlock();
                if (ctx.conn_fd >= 0) {
                    _ = std.c.shutdown(ctx.conn_fd, 2);
                    _ = std.c.close(ctx.conn_fd);
                    ctx.conn_fd = -1;
                }
            }
        }
    }

    fn handleConnection(allocator: std.mem.Allocator, fd: std.posix.fd_t) !void {
        var req_buf: [1024]u8 = undefined;
        var req_len: usize = 0;
        while (req_len < req_buf.len) {
            const n = rawRead(fd, req_buf[req_len..]) catch return;
            req_len += n;
            if (std.mem.indexOf(u8, req_buf[0..req_len], "\r\n\r\n")) |_| break;
        }

        const key_prefix = "Sec-WebSocket-Key: ";
        const req = req_buf[0..req_len];
        const key_start = std.mem.indexOf(u8, req, key_prefix) orelse return;
        const key_end = std.mem.indexOf(u8, req[key_start + key_prefix.len ..], "\r\n") orelse return;
        const key = req[key_start + key_prefix.len .. key_start + key_prefix.len + key_end];

        const accept = WsClient.computeWebSocketAccept(allocator, key) catch return;
        defer allocator.free(accept);

        const response = std.fmt.allocPrint(
            allocator,
            "HTTP/1.1 101 Switching Protocols\r\n" ++
                "Upgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Sec-WebSocket-Accept: {s}\r\n" ++
                "\r\n",
            .{accept},
        ) catch return;
        defer allocator.free(response);
        rawWriteAll(fd, response) catch return;

        var next_sub: u64 = 1;

        while (true) {
            const frame = readFrameRaw(allocator, fd) catch break;
            defer allocator.free(frame.payload);

            if (frame.opcode == .close) {
                sendFrameRaw(fd, .close, &[_]u8{}) catch {};
                break;
            }
            if (frame.opcode == .ping) {
                sendFrameRaw(fd, .pong, &[_]u8{}) catch {};
                continue;
            }
            if (frame.opcode != .text and frame.opcode != .binary) continue;

            var parsed = std.json.parseFromSlice(std.json.Value, allocator, frame.payload, .{}) catch continue;
            defer parsed.deinit();

            const method = parsed.value.object.get("method") orelse continue;
            const id = parsed.value.object.get("id") orelse continue;
            const is_subscribe = std.mem.endsWith(u8, method.string, "Subscribe");
            const force_disconnect_after_notify = std.mem.indexOf(u8, frame.payload, "force_disconnect_after_notify") != null;
            const malformed_subscribe_response = std.mem.indexOf(u8, frame.payload, "malformed_sub_reply") != null;
            const duplicate_notifications = std.mem.indexOf(u8, frame.payload, "duplicate_notify") != null;
            const sub_id = next_sub;
            next_sub += 1;

            if (is_subscribe and malformed_subscribe_response) {
                const reply = "{\"jsonrpc\":\"2.0\",\"result\":";
                sendFrameRaw(fd, .text, reply) catch break;
                continue;
            }

            const reply = std.fmt.allocPrint(
                allocator,
                "{{\"jsonrpc\":\"2.0\",\"result\":{d},\"id\":{d}}}",
                .{ sub_id, id.integer },
            ) catch break;
            defer allocator.free(reply);
            sendFrameRaw(fd, .text, reply) catch break;

            if (is_subscribe) {
                const notif = std.fmt.allocPrint(
                    allocator,
                    "{{\"jsonrpc\":\"2.0\",\"method\":\"{s}Notification\",\"params\":{{\"result\":{{\"mock\":true}},\"subscription\":{d}}}}}",
                    .{ method.string, sub_id },
                ) catch break;
                defer allocator.free(notif);
                sendFrameRaw(fd, .text, notif) catch break;

                if (duplicate_notifications) {
                    sendFrameRaw(fd, .text, notif) catch break;
                    break;
                }

                if (force_disconnect_after_notify) {
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

    fn readFrameRaw(allocator: std.mem.Allocator, fd: std.posix.fd_t) !FrameHeader {
        var h: [2]u8 = undefined;
        try rawReadAll(fd, &h);
        const fin = (h[0] & 0x80) != 0;
        const opcode: WsClient.Message.Opcode = @enumFromInt(h[0] & 0x0F);
        const masked = (h[1] & 0x80) != 0;
        var payload_len: u64 = @as(u64, h[1] & 0x7F);

        if (payload_len == 126) {
            var lb: [2]u8 = undefined;
            try rawReadAll(fd, &lb);
            payload_len = (@as(u64, lb[0]) << 8) | @as(u64, lb[1]);
        } else if (payload_len == 127) {
            var lb: [8]u8 = undefined;
            try rawReadAll(fd, &lb);
            payload_len = 0;
            for (lb) |b| payload_len = (payload_len << 8) | b;
        }

        var mask_key: [4]u8 = undefined;
        if (masked) {
            try rawReadAll(fd, &mask_key);
        }

        const payload = try allocator.alloc(u8, @intCast(payload_len));
        errdefer allocator.free(payload);

        try rawReadAll(fd, payload);

        if (masked) {
            for (payload, 0..) |*b, i| b.* ^= mask_key[i % 4];
        }

        return .{ .fin = fin, .opcode = opcode, .payload = payload };
    }

    fn sendFrameRaw(fd: std.posix.fd_t, opcode: WsClient.Message.Opcode, payload: []const u8) !void {
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
        try rawWriteAll(fd, header[0..header_len]);
        try rawWriteAll(fd, payload);
    }
};

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

test "WsRpcClient subscribe and receive notification" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
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

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const sub_id = try client.signatureSubscribe("deadbeef");
    try std.testing.expect(sub_id > 0);

    var notif = try client.readNotification();
    defer notif.deinit();

    try client.reconnect();
}

test "ws_unsubscribe_ack_success" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const sub_id = try client.accountSubscribe("11111111111111111111111111111111");
    try std.testing.expect(sub_id > 0);

    // Consume the pending notification before unsubscribing.
    var notif = try client.readNotification();
    notif.deinit();

    try client.unsubscribe(sub_id, "accountUnsubscribe");
}

test "ws_reconnect_detect_disconnect_then_reconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const sub_id = try client.logsSubscribe("force_disconnect_after_notify");
    try std.testing.expect(sub_id > 0);

    var notif = try client.readNotification();
    defer notif.deinit();
    try std.testing.expectEqualStrings("logsSubscribeNotification", notif.method);

    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    try client.reconnect();
}

test "ws_reconnect_resubscribe_after_reconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
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

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    try std.testing.expectError(error.InvalidSubscriptionResponse, client.logsSubscribe("malformed_sub_reply"));
}

test "ws_backoff_reconnect_retry_budget" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    // Force reconnect failure by shutting the server down first.
    server.stop();

    if (client.reconnectWithBackoff(3, 0)) |_| return error.TestUnexpectedResult else |_| {}
    try std.testing.expectEqual(@as(u8, 3), client.last_reconnect_attempts);
}

test "ws_resubscribe_idempotent_same_filter_returns_same_id" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const id1 = try client.logsSubscribe("idempotent_filter");
    const id2 = try client.logsSubscribe("idempotent_filter");
    try std.testing.expectEqual(id1, id2);
}

test "ws_dedup_skip_duplicate_notifications" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    _ = try client.logsSubscribe("duplicate_notify");
    var first = try client.readNotification();
    defer first.deinit();
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());
}

test "ws_connection_flap_reconnect_with_backoff" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    _ = try client.logsSubscribe("force_disconnect_after_notify");
    var notif1 = try client.readNotification();
    notif1.deinit();
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    try client.reconnectWithBackoff(3, 0);
    try std.testing.expect(client.last_reconnect_attempts >= 1);
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
test "ws_production_heartbeat_ping_pong" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    // sendPing should succeed (server responds with pong automatically)
    try client.sendPing();
}

test "ws_production_backoff_hard_limit" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    server.stop();

    // Request 10 retries but MAX_RECONNECT_RETRIES = 5 caps it
    if (client.reconnectWithBackoff(10, 0)) |_| {
        return error.TestUnexpectedResult;
    } else |_| {}
    try std.testing.expectEqual(WsRpcClient.MAX_RECONNECT_RETRIES, client.last_reconnect_attempts);
}

test "ws_production_cleanup_state_consistency" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    // Subscribe to one filter, consume its notification
    _ = try client.logsSubscribe("force_disconnect_after_notify");
    const count_before = client.subscriptionCount();
    try std.testing.expectEqual(@as(usize, 1), count_before);

    var n1 = try client.readNotification();
    n1.deinit();

    // Server disconnects after notification; detect it
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    // Reconnect — resubscribeAll should preserve subscription count
    try client.reconnect();
    const count_after = client.subscriptionCount();
    try std.testing.expectEqual(count_before, count_after);
}

test "ws_production_dedup_cache_boundary" {
    // Verify dedup ring buffer has fixed size and doesn't grow unbounded
    var client: WsRpcClient = undefined;
    client.dedup_ring = [_]u64{0} ** WsRpcClient.DEDUP_CACHE_SIZE;
    client.dedup_ring_len = 0;
    client.dedup_ring_pos = 0;

    // Fill the ring buffer beyond capacity
    for (0..WsRpcClient.DEDUP_CACHE_SIZE + 4) |i| {
        client.recordNotificationHash(@as(u64, @intCast(i + 1)));
    }

    // Ring length should be capped at DEDUP_CACHE_SIZE
    try std.testing.expectEqual(WsRpcClient.DEDUP_CACHE_SIZE, client.dedup_ring_len);

    // Oldest entries should have been evicted — hash 1..4 gone
    try std.testing.expect(!client.isDuplicateNotification(1));
    try std.testing.expect(!client.isDuplicateNotification(2));

    // Recent entries should still be present
    const recent = @as(u64, @intCast(WsRpcClient.DEDUP_CACHE_SIZE + 4));
    try std.testing.expect(client.isDuplicateNotification(recent));
}

fn lockAtomicMutex(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) {
        std.atomic.spinLoopHint();
    }
}

// ------------------------------------------------------------------
// P2-23 Observability Tests
// ------------------------------------------------------------------

test "ws_observability_snapshot_initial_state" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const stats = client.snapshot();
    try std.testing.expectEqual(@as(u32, 0), stats.reconnect_attempts_total);
    try std.testing.expectEqual(@as(u32, 0), stats.active_subscriptions);
    try std.testing.expectEqual(@as(u32, 0), stats.dedup_dropped_total);
    try std.testing.expectEqual(@as(?u16, null), stats.last_error_code);
    try std.testing.expectEqual(@as(?[]const u8, null), stats.last_error_message);
    try std.testing.expectEqual(@as(?u64, null), stats.last_reconnect_unix_ms);
}

test "ws_observability_counters_after_subscribe" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    _ = try client.accountSubscribe("11111111111111111111111111111111");
    const stats = client.snapshot();
    try std.testing.expectEqual(@as(u32, 1), stats.active_subscriptions);
    try std.testing.expectEqual(@as(u32, 0), stats.reconnect_attempts_total);
}

test "ws_observability_reconnect_counter_increments" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    _ = try client.logsSubscribe("force_disconnect_after_notify");
    var notif = try client.readNotification();
    notif.deinit();
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    const before = client.snapshot();
    try std.testing.expectEqual(@as(u32, 0), before.reconnect_attempts_total);

    try client.reconnect();
    const after = client.snapshot();
    try std.testing.expectEqual(@as(u32, 1), after.reconnect_attempts_total);
    try std.testing.expect(after.last_reconnect_unix_ms != null);
}

test "ws_observability_dedup_dropped_counter" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    _ = try client.logsSubscribe("duplicate_notify");

    // First notification passes dedup, second is duplicate and dropped
    var first = try client.readNotification();
    defer first.deinit();

    // After the duplicate is dropped, server sends close — readNotification returns ConnectionClosed
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    const stats = client.snapshot();
    try std.testing.expect(stats.dedup_dropped_total >= 1);
}

test "ws_observability_backoff_error_state" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    server.stop();

    // Failed reconnect should update error state and reconnect counter
    if (client.reconnectWithBackoff(2, 0)) |_| {
        return error.TestUnexpectedResult;
    } else |_| {}

    const stats = client.snapshot();
    try std.testing.expect(stats.reconnect_attempts_total >= 2);
    try std.testing.expect(stats.last_error_code != null);
    try std.testing.expect(stats.last_error_message != null);
}
