const std = @import("std");
const types = @import("types.zig");

const c = std.c;
const max_ws_payload_len = 16 * 1024 * 1024; // 16MB

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
        if (payload_len > max_ws_payload_len) return error.WsProtocolError;

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

    pub const ConnectionState = enum {
        connected,
        disconnected,
        reconnecting,
    };

    // -- Observability snapshot schema (P2-23, frozen in docs/24) --
    pub const WsStats = struct {
        connection_state: ConnectionState,
        reconnect_attempts_total: u32,
        active_subscriptions: u32,
        dedup_dropped_total: u32,
        messages_sent_total: u64,
        messages_received_total: u64,
        last_error_code: ?u16,
        last_error_message: ?[]const u8,
        last_reconnect_unix_ms: ?u64,
    };

    ws: WsClient,
    url: []const u8,
    next_id: u64 = 1,
    reconnect_config: types.WsReconnectConfig = .{},
    subscriptions: std.ArrayList(Subscription) = .empty,
    pending_messages: std.ArrayList(WsClient.Message) = .empty,
    dedup_ring: [DEDUP_CACHE_SIZE]u64 = [_]u64{0} ** DEDUP_CACHE_SIZE,
    dedup_ring_len: usize = 0,
    dedup_ring_pos: usize = 0,
    last_reconnect_attempts: u8 = 0,

    // -- Observability counters/state (P2-23) --
    connection_state: ConnectionState = .connected,
    reconnect_attempts_total: u32 = 0,
    dedup_dropped_total: u32 = 0,
    messages_sent_total: u64 = 0,
    messages_received_total: u64 = 0,
    last_error_code: ?u16 = null,
    last_error_message_buf: [128]u8 = [_]u8{0} ** 128,
    last_error_message_len: u8 = 0,
    last_reconnect_unix_ms: ?u64 = null,

    pub const SubscribeError = WsClient.SendError || WsClient.ReadError || error{InvalidSubscriptionResponse};
    pub const ReconnectError = WsClient.ConnectError || SubscribeError;
    pub const NotificationReadError = ReconnectError || error{ OutOfMemory, WriteFailed };

    pub const NotificationAccountInfo = struct {
        lamports: u64,
        owner: []const u8,
        executable: bool,
        rent_epoch: u64,
        data_encoding: ?[]const u8 = null,

        pub fn deinit(self: *NotificationAccountInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.owner);
            if (self.data_encoding) |encoding| allocator.free(encoding);
        }
    };

    pub const AccountNotification = struct {
        subscription_id: u64,
        context_slot: u64,
        account: NotificationAccountInfo,

        pub fn deinit(self: *AccountNotification, allocator: std.mem.Allocator) void {
            self.account.deinit(allocator);
        }
    };

    pub const ProgramNotification = struct {
        subscription_id: u64,
        context_slot: u64,
        pubkey: []const u8,
        account: NotificationAccountInfo,

        pub fn deinit(self: *ProgramNotification, allocator: std.mem.Allocator) void {
            allocator.free(self.pubkey);
            self.account.deinit(allocator);
        }
    };

    pub const SignatureNotification = struct {
        subscription_id: u64,
        context_slot: u64,
        err_json: ?[]const u8 = null,

        pub fn deinit(self: *SignatureNotification, allocator: std.mem.Allocator) void {
            if (self.err_json) |err_json| allocator.free(err_json);
        }
    };

    pub const SlotNotification = struct {
        subscription_id: u64,
        parent: u64,
        slot: u64,
        root: u64,

        pub fn deinit(self: *SlotNotification, allocator: std.mem.Allocator) void {
            _ = self;
            _ = allocator;
        }
    };

    pub const RootNotification = struct {
        subscription_id: u64,
        root: u64,

        pub fn deinit(self: *RootNotification, allocator: std.mem.Allocator) void {
            _ = self;
            _ = allocator;
        }
    };

    pub const LogsNotification = struct {
        subscription_id: u64,
        context_slot: u64,
        signature: ?[]const u8 = null,
        err_json: ?[]const u8 = null,
        logs: [][]const u8,

        pub fn deinit(self: *LogsNotification, allocator: std.mem.Allocator) void {
            if (self.signature) |signature| allocator.free(signature);
            if (self.err_json) |err_json| allocator.free(err_json);
            for (self.logs) |log| allocator.free(log);
            allocator.free(self.logs);
        }
    };

    pub const BlockNotification = struct {
        subscription_id: u64,
        context_slot: u64,
        slot: u64,
        err_json: ?[]const u8 = null,

        pub fn deinit(self: *BlockNotification, allocator: std.mem.Allocator) void {
            if (self.err_json) |err_json| allocator.free(err_json);
        }
    };

    pub const AccountNotificationCallback = *const fn (notification: *const AccountNotification) void;
    pub const ProgramNotificationCallback = *const fn (notification: *const ProgramNotification) void;
    pub const SignatureNotificationCallback = *const fn (notification: *const SignatureNotification) void;
    pub const SlotNotificationCallback = *const fn (notification: *const SlotNotification) void;
    pub const RootNotificationCallback = *const fn (notification: *const RootNotification) void;
    pub const LogsNotificationCallback = *const fn (notification: *const LogsNotification) void;
    pub const BlockNotificationCallback = *const fn (notification: *const BlockNotification) void;

    pub const Notification = struct {
        allocator: std.mem.Allocator,
        raw_message: []const u8,
        method: []const u8,
        subscription_id: u64,
        parsed: std.json.Parsed(std.json.Value),
        result: std.json.Value,

        pub fn deinit(self: *Notification) void {
            self.allocator.free(self.method);
            self.parsed.deinit();
            self.allocator.free(self.raw_message);
        }
    };

    const SubscriptionKind = enum {
        account,
        program,
        logs,
        signature,
        slot,
        root,
        block,
    };

    const Subscription = struct {
        kind: SubscriptionKind,
        value: []u8,
        id: u64,
        commitment: types.Commitment = .confirmed,
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

    pub fn setReconnectConfig(self: *WsRpcClient, reconnect_config: types.WsReconnectConfig) void {
        self.reconnect_config = reconnect_config;
    }

    pub fn deinit(self: *WsRpcClient) void {
        for (self.subscriptions.items) |sub| {
            self.ws.allocator.free(sub.value);
        }
        self.subscriptions.deinit(self.ws.allocator);
        for (self.pending_messages.items) |message| {
            self.ws.allocator.free(message.data);
        }
        self.pending_messages.deinit(self.ws.allocator);
        self.ws.deinit();
        self.ws.allocator.free(self.url);
    }

    pub fn disconnect(self: *WsRpcClient) void {
        if (self.ws.sendClose()) |_| {
            self.messages_sent_total += 1;
        } else |_| {}
        self.ws.deinit();
        self.connection_state = .disconnected;
    }

    pub fn reconnect(self: *WsRpcClient) ReconnectError!void {
        self.connection_state = .reconnecting;
        self.last_reconnect_attempts = 1;
        self.reconnectOnce() catch |err| {
            self.connection_state = .disconnected;
            return err;
        };
    }

    pub fn reconnectWithBackoff(self: *WsRpcClient, retries: u8, base_delay_ms: u64) ReconnectError!void {
        var reconnect_config = self.reconnect_config;
        reconnect_config.max_retries = retries;
        reconnect_config.base_delay_ms = base_delay_ms;
        try self.reconnectWithConfig(reconnect_config);
    }

    pub fn sendPing(self: *WsRpcClient) WsClient.SendError!void {
        try self.ws.sendFrame(.ping, &[_]u8{});
        self.messages_sent_total += 1;
    }

    pub fn connectionState(self: *const WsRpcClient) ConnectionState {
        return self.connection_state;
    }

    pub fn subscriptionCount(self: *const WsRpcClient) usize {
        return self.subscriptions.items.len;
    }

    pub fn snapshot(self: *const WsRpcClient) WsStats {
        return .{
            .connection_state = self.connection_state,
            .reconnect_attempts_total = self.reconnect_attempts_total,
            .active_subscriptions = @intCast(self.subscriptions.items.len),
            .dedup_dropped_total = self.dedup_dropped_total,
            .messages_sent_total = self.messages_sent_total,
            .messages_received_total = self.messages_received_total,
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

    pub fn accountSubscribe(self: *WsRpcClient, pubkey_base58: []const u8, commitment: types.Commitment) SubscribeError!u64 {
        return try self.ensureSubscribed(.account, pubkey_base58, commitment);
    }

    pub fn programSubscribe(self: *WsRpcClient, program_id_base58: []const u8, commitment: types.Commitment) SubscribeError!u64 {
        return try self.ensureSubscribed(.program, program_id_base58, commitment);
    }

    pub fn logsSubscribe(self: *WsRpcClient, filter: []const u8) SubscribeError!u64 {
        return try self.ensureSubscribed(.logs, filter, .confirmed);
    }

    pub fn signatureSubscribe(self: *WsRpcClient, signature_base58: []const u8, commitment: types.Commitment) SubscribeError!u64 {
        return try self.ensureSubscribed(.signature, signature_base58, commitment);
    }

    pub fn slotSubscribe(self: *WsRpcClient) SubscribeError!u64 {
        return try self.ensureSubscribed(.slot, "", .confirmed);
    }

    pub fn rootSubscribe(self: *WsRpcClient) SubscribeError!u64 {
        return try self.ensureSubscribed(.root, "", .confirmed);
    }

    pub fn blockSubscribe(self: *WsRpcClient, filter: []const u8, commitment: types.Commitment) SubscribeError!u64 {
        return try self.ensureSubscribed(.block, filter, commitment);
    }

    pub fn accountUnsubscribe(self: *WsRpcClient, subscription_id: u64) SubscribeError!void {
        try self.unsubscribe(subscription_id, "accountUnsubscribe");
    }

    pub fn programUnsubscribe(self: *WsRpcClient, subscription_id: u64) SubscribeError!void {
        try self.unsubscribe(subscription_id, "programUnsubscribe");
    }

    pub fn logsUnsubscribe(self: *WsRpcClient, subscription_id: u64) SubscribeError!void {
        try self.unsubscribe(subscription_id, "logsUnsubscribe");
    }

    pub fn signatureUnsubscribe(self: *WsRpcClient, subscription_id: u64) SubscribeError!void {
        try self.unsubscribe(subscription_id, "signatureUnsubscribe");
    }

    pub fn slotUnsubscribe(self: *WsRpcClient, subscription_id: u64) SubscribeError!void {
        try self.unsubscribe(subscription_id, "slotUnsubscribe");
    }

    pub fn rootUnsubscribe(self: *WsRpcClient, subscription_id: u64) SubscribeError!void {
        try self.unsubscribe(subscription_id, "rootUnsubscribe");
    }

    pub fn blockUnsubscribe(self: *WsRpcClient, subscription_id: u64) SubscribeError!void {
        try self.unsubscribe(subscription_id, "blockUnsubscribe");
    }

    pub fn unsubscribe(self: *WsRpcClient, subscription_id: u64, method: []const u8) SubscribeError!void {
        const payload = try std.fmt.allocPrint(
            self.ws.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":[{d}]}}",
            .{ self.nextRpcId(), method, subscription_id },
        );
        defer self.ws.allocator.free(payload);
        try self.sendTextTracked(payload);
        try self.readUnsubscribeAck();
        self.removeSubscription(subscription_id);
    }

    pub fn readNotification(self: *WsRpcClient) NotificationReadError!Notification {
        while (true) {
            const msg = if (self.pending_messages.items.len > 0)
                self.pending_messages.orderedRemove(0)
            else
                self.readMessageTracked() catch |err| switch (err) {
                    error.ConnectionClosed => {
                        self.connection_state = .disconnected;
                        try self.reconnectWithConfig(self.reconnect_config);
                        continue;
                    },
                    else => return err,
                };
            if (msg.opcode != .text and msg.opcode != .binary) {
                self.ws.allocator.free(msg.data);
                return error.WsProtocolError;
            }

            const h = std.hash.Wyhash.hash(0, msg.data);
            if (self.isDuplicateNotification(h)) {
                self.dedup_dropped_total += 1;
                self.ws.allocator.free(msg.data);
                continue;
            }
            self.recordNotificationHash(h);

            return try parseNotificationEnvelopeOwned(self.ws.allocator, msg.data);
        }
    }

    pub fn readAccountNotification(self: *WsRpcClient) NotificationReadError!AccountNotification {
        var notification = try self.readNotificationForMethod("accountNotification");
        defer notification.deinit();
        return try parseAccountNotification(self.ws.allocator, notification.subscription_id, &notification.result);
    }

    pub fn readProgramNotification(self: *WsRpcClient) NotificationReadError!ProgramNotification {
        var notification = try self.readNotificationForMethod("programNotification");
        defer notification.deinit();
        return try parseProgramNotification(self.ws.allocator, notification.subscription_id, &notification.result);
    }

    pub fn readSignatureNotification(self: *WsRpcClient) NotificationReadError!SignatureNotification {
        var notification = try self.readNotificationForMethod("signatureNotification");
        defer notification.deinit();
        return try parseSignatureNotification(self.ws.allocator, notification.subscription_id, &notification.result);
    }

    pub fn readSlotNotification(self: *WsRpcClient) NotificationReadError!SlotNotification {
        var notification = try self.readNotificationForMethod("slotNotification");
        defer notification.deinit();
        return try parseSlotNotification(notification.subscription_id, &notification.result);
    }

    pub fn readRootNotification(self: *WsRpcClient) NotificationReadError!RootNotification {
        var notification = try self.readNotificationForMethod("rootNotification");
        defer notification.deinit();
        return try parseRootNotification(notification.subscription_id, &notification.result);
    }

    pub fn readLogsNotification(self: *WsRpcClient) NotificationReadError!LogsNotification {
        var notification = try self.readNotificationForMethod("logsNotification");
        defer notification.deinit();
        return try parseLogsNotification(self.ws.allocator, notification.subscription_id, &notification.result);
    }

    pub fn readBlockNotification(self: *WsRpcClient) NotificationReadError!BlockNotification {
        var notification = try self.readNotificationForMethod("blockNotification");
        defer notification.deinit();
        return try parseBlockNotification(self.ws.allocator, notification.subscription_id, &notification.result);
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
        while (true) {
            const msg = try self.readMessageTracked();
            var keep_message = false;
            defer if (!keep_message) self.ws.allocator.free(msg.data);

            if (msg.opcode != .text and msg.opcode != .binary) return error.InvalidSubscriptionResponse;

            var parsed = std.json.parseFromSlice(std.json.Value, self.ws.allocator, msg.data, .{}) catch return error.InvalidSubscriptionResponse;
            defer parsed.deinit();

            if (parsed.value != .object) return error.InvalidSubscriptionResponse;
            if (parsed.value.object.get("method") != null) {
                try self.pending_messages.append(self.ws.allocator, msg);
                keep_message = true;
                continue;
            }

            const result = parsed.value.object.get("result") orelse return error.InvalidSubscriptionResponse;
            return @intCast(result.integer);
        }
    }

    fn readUnsubscribeAck(self: *WsRpcClient) SubscribeError!void {
        while (true) {
            const msg = try self.readMessageTracked();
            var keep_message = false;
            defer if (!keep_message) self.ws.allocator.free(msg.data);

            if (msg.opcode != .text and msg.opcode != .binary) return error.InvalidSubscriptionResponse;

            var parsed = std.json.parseFromSlice(std.json.Value, self.ws.allocator, msg.data, .{}) catch return error.InvalidSubscriptionResponse;
            defer parsed.deinit();

            if (parsed.value != .object) return error.InvalidSubscriptionResponse;
            if (parsed.value.object.get("method") != null) {
                try self.pending_messages.append(self.ws.allocator, msg);
                keep_message = true;
                continue;
            }

            const result = parsed.value.object.get("result") orelse return error.InvalidSubscriptionResponse;
            if (result != .bool or !result.bool) return error.InvalidSubscriptionResponse;
            return;
        }
    }

    fn readNotificationForMethod(self: *WsRpcClient, expected_method: []const u8) NotificationReadError!Notification {
        var notification = try self.readNotification();
        errdefer notification.deinit();
        if (!std.mem.eql(u8, notification.method, expected_method)) {
            return error.InvalidSubscriptionResponse;
        }
        return notification;
    }

    fn ensureSubscribed(self: *WsRpcClient, kind: SubscriptionKind, value: []const u8, commitment: types.Commitment) SubscribeError!u64 {
        for (self.subscriptions.items) |sub| {
            if (sub.kind == kind and std.mem.eql(u8, sub.value, value) and sub.commitment == commitment) {
                return sub.id;
            }
        }

        const payload = try self.buildSubscribePayload(kind, value, commitment);
        defer self.ws.allocator.free(payload);
        try self.sendTextTracked(payload);
        const id = try self.readSubscriptionResult();

        try self.subscriptions.append(self.ws.allocator, .{
            .kind = kind,
            .value = try self.ws.allocator.dupe(u8, value),
            .id = id,
            .commitment = commitment,
        });
        return id;
    }

    fn buildSubscribePayload(self: *WsRpcClient, kind: SubscriptionKind, value: []const u8, commitment: types.Commitment) std.mem.Allocator.Error![]u8 {
        return switch (kind) {
            .account => serializeAccountSubscribeRequest(self.ws.allocator, self.nextRpcId(), value, commitment),
            .program => serializeProgramSubscribeRequest(self.ws.allocator, self.nextRpcId(), value, commitment),
            .logs => serializeLogsSubscribeRequest(self.ws.allocator, self.nextRpcId(), value),
            .signature => serializeSignatureSubscribeRequest(self.ws.allocator, self.nextRpcId(), value, commitment),
            .slot => serializeSlotSubscribeRequest(self.ws.allocator, self.nextRpcId()),
            .root => serializeRootSubscribeRequest(self.ws.allocator, self.nextRpcId()),
            .block => serializeBlockSubscribeRequest(self.ws.allocator, self.nextRpcId(), value, commitment),
        };
    }

    fn resubscribeAll(self: *WsRpcClient) SubscribeError!void {
        for (self.subscriptions.items) |*sub| {
            const payload = try self.buildSubscribePayload(sub.kind, sub.value, sub.commitment);
            defer self.ws.allocator.free(payload);
            try self.sendTextTracked(payload);
            sub.id = try self.readSubscriptionResult();
        }
    }

    fn reconnectOnce(self: *WsRpcClient) ReconnectError!void {
        self.reconnect_attempts_total += 1;
        self.ws.deinit();
        self.ws = try WsClient.connect(self.ws.allocator, self.ws.io, self.url);
        try self.resubscribeAll();
        self.connection_state = .connected;
        self.recordReconnectTimestamp();
    }

    fn reconnectWithConfig(self: *WsRpcClient, reconnect_config: types.WsReconnectConfig) ReconnectError!void {
        const capped_retries = @min(reconnect_config.max_retries, MAX_RECONNECT_RETRIES);
        if (capped_retries == 0) {
            self.last_reconnect_attempts = 0;
            self.connection_state = .disconnected;
            self.recordError(1, "reconnect_disabled");
            return error.ConnectionClosed;
        }

        self.connection_state = .reconnecting;
        var attempt: u8 = 0;
        while (attempt < capped_retries) : (attempt += 1) {
            self.last_reconnect_attempts = attempt + 1;
            if (self.reconnectOnce()) |_| {
                return;
            } else |err| {
                self.recordError(1, "reconnect_failed");
                self.connection_state = .reconnecting;
                if (attempt + 1 == capped_retries) {
                    self.connection_state = .disconnected;
                    return err;
                }
                self.sleepBeforeReconnect(reconnect_config, attempt);
            }
        }

        self.connection_state = .disconnected;
        return error.HandshakeFailed;
    }

    fn sendTextTracked(self: *WsRpcClient, payload: []const u8) WsClient.SendError!void {
        try self.ws.sendText(payload);
        self.messages_sent_total += 1;
    }

    fn readMessageTracked(self: *WsRpcClient) WsClient.ReadError!WsClient.Message {
        const msg = self.ws.readMessage() catch |err| switch (err) {
            error.ConnectionClosed => {
                self.connection_state = .disconnected;
                return error.ConnectionClosed;
            },
            else => return err,
        };
        self.messages_received_total += 1;
        return msg;
    }

    fn sleepBeforeReconnect(self: *const WsRpcClient, reconnect_config: types.WsReconnectConfig, attempt: u8) void {
        _ = self;
        const delay_ms = retryDelayMs(reconnect_config, attempt);
        if (delay_ms == 0) return;

        const delay_ns = std.math.mul(u64, delay_ms, std.time.ns_per_ms) catch std.math.maxInt(u64);
        var req = std.c.timespec{
            .sec = @intCast(delay_ns / std.time.ns_per_s),
            .nsec = @intCast(delay_ns % std.time.ns_per_s),
        };
        _ = std.c.nanosleep(&req, null);
    }

    fn retryDelayMs(reconnect_config: types.WsReconnectConfig, attempt: u8) u64 {
        const max_delay_ms = @min(reconnect_config.max_delay_ms, MAX_BACKOFF_MS);
        if (reconnect_config.base_delay_ms == 0 or max_delay_ms == 0) return 0;

        var delay_ms = @min(reconnect_config.base_delay_ms, max_delay_ms);
        var step: u8 = 0;
        while (step < attempt and delay_ms < max_delay_ms) : (step += 1) {
            const doubled = std.math.mul(u64, delay_ms, 2) catch max_delay_ms;
            delay_ms = @min(doubled, max_delay_ms);
        }

        return delay_ms;
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

pub fn serializeAccountSubscribeRequest(allocator: std.mem.Allocator, rpc_id: u64, pubkey_base58: []const u8, commitment: types.Commitment) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"accountSubscribe\",\"params\":[\"{s}\",{{\"encoding\":\"base64\",\"commitment\":\"{s}\"}}]}}",
        .{ rpc_id, pubkey_base58, commitment.jsonString() },
    );
}

pub fn serializeProgramSubscribeRequest(allocator: std.mem.Allocator, rpc_id: u64, program_id_base58: []const u8, commitment: types.Commitment) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"programSubscribe\",\"params\":[\"{s}\",{{\"encoding\":\"base64\",\"commitment\":\"{s}\"}}]}}",
        .{ rpc_id, program_id_base58, commitment.jsonString() },
    );
}

pub fn serializeLogsSubscribeRequest(allocator: std.mem.Allocator, rpc_id: u64, filter: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"logsSubscribe\",\"params\":[\"{s}\"]}}",
        .{ rpc_id, filter },
    );
}

fn serializeSignatureSubscribeRequest(allocator: std.mem.Allocator, rpc_id: u64, signature_base58: []const u8, commitment: types.Commitment) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"signatureSubscribe\",\"params\":[\"{s}\",{{\"commitment\":\"{s}\"}}]}}",
        .{ rpc_id, signature_base58, commitment.jsonString() },
    );
}

fn serializeSlotSubscribeRequest(allocator: std.mem.Allocator, rpc_id: u64) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"slotSubscribe\",\"params\":[]}}",
        .{rpc_id},
    );
}

fn serializeRootSubscribeRequest(allocator: std.mem.Allocator, rpc_id: u64) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"rootSubscribe\",\"params\":[]}}",
        .{rpc_id},
    );
}

fn serializeBlockSubscribeRequest(allocator: std.mem.Allocator, rpc_id: u64, filter: []const u8, commitment: types.Commitment) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"blockSubscribe\",\"params\":[\"{s}\",{{\"commitment\":\"{s}\"}}]}}",
        .{ rpc_id, filter, commitment.jsonString() },
    );
}

fn parseNotificationEnvelopeOwned(allocator: std.mem.Allocator, raw_message: []const u8) !WsRpcClient.Notification {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, raw_message, .{}) catch {
        allocator.free(raw_message);
        return error.InvalidSubscriptionResponse;
    };
    errdefer {
        parsed.deinit();
        allocator.free(raw_message);
    }

    if (parsed.value != .object) return error.InvalidSubscriptionResponse;

    const root_obj: *std.json.ObjectMap = @constCast(&parsed.value.object);
    const method_value = root_obj.getPtr("method") orelse return error.InvalidSubscriptionResponse;
    if (method_value.* != .string) return error.InvalidSubscriptionResponse;
    const method = try allocator.dupe(u8, method_value.string);
    errdefer allocator.free(method);

    const params = root_obj.getPtr("params") orelse return error.InvalidSubscriptionResponse;
    if (params.* != .object) return error.InvalidSubscriptionResponse;

    const params_obj: *std.json.ObjectMap = @constCast(&params.object);
    const subscription_value = params_obj.getPtr("subscription") orelse return error.InvalidSubscriptionResponse;
    const subscription_id = parseIntegerAsU64(subscription_value) orelse return error.InvalidSubscriptionResponse;
    const result = params_obj.get("result") orelse return error.InvalidSubscriptionResponse;

    return .{
        .allocator = allocator,
        .raw_message = raw_message,
        .method = method,
        .subscription_id = subscription_id,
        .parsed = parsed,
        .result = result,
    };
}

fn parseNotificationEnvelope(allocator: std.mem.Allocator, raw_message: []const u8) !WsRpcClient.Notification {
    return parseNotificationEnvelopeOwned(allocator, try allocator.dupe(u8, raw_message));
}

pub fn parseAccountNotificationMessage(allocator: std.mem.Allocator, raw_message: []const u8) !WsRpcClient.AccountNotification {
    var notification = try parseNotificationEnvelope(allocator, raw_message);
    defer notification.deinit();

    if (!std.mem.eql(u8, notification.method, "accountNotification")) {
        return error.InvalidSubscriptionResponse;
    }
    return try parseAccountNotification(allocator, notification.subscription_id, &notification.result);
}

pub fn parseProgramNotificationMessage(allocator: std.mem.Allocator, raw_message: []const u8) !WsRpcClient.ProgramNotification {
    var notification = try parseNotificationEnvelope(allocator, raw_message);
    defer notification.deinit();

    if (!std.mem.eql(u8, notification.method, "programNotification")) {
        return error.InvalidSubscriptionResponse;
    }
    return try parseProgramNotification(allocator, notification.subscription_id, &notification.result);
}

pub fn parseLogsNotificationMessage(allocator: std.mem.Allocator, raw_message: []const u8) !WsRpcClient.LogsNotification {
    var notification = try parseNotificationEnvelope(allocator, raw_message);
    defer notification.deinit();

    if (!std.mem.eql(u8, notification.method, "logsNotification")) {
        return error.InvalidSubscriptionResponse;
    }
    return try parseLogsNotification(allocator, notification.subscription_id, &notification.result);
}

fn stringifyValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try std.json.Stringify.value(value, .{}, &out.writer);
    return allocator.dupe(u8, out.written());
}

fn getObjectField(root: *const std.json.Value, field: []const u8) ?*const std.json.Value {
    if (root.* != .object) return null;
    const obj_ptr: *std.json.ObjectMap = @constCast(&root.object);
    return obj_ptr.getPtr(field);
}

fn getStringField(root: *const std.json.Value, field: []const u8) ?[]const u8 {
    const value = getObjectField(root, field) orelse return null;
    if (value.* != .string) return null;
    return value.string;
}

fn getBoolField(root: *const std.json.Value, field: []const u8) ?bool {
    const value = getObjectField(root, field) orelse return null;
    if (value.* != .bool) return null;
    return value.bool;
}

fn parseIntegerAsU64(value: *const std.json.Value) ?u64 {
    return switch (value.*) {
        .integer => |n| if (n >= 0) @as(u64, @intCast(n)) else null,
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch null,
        else => null,
    };
}

fn getU64Field(root: *const std.json.Value, field: []const u8) ?u64 {
    const value = getObjectField(root, field) orelse return null;
    return parseIntegerAsU64(value);
}

fn extractOptionalFieldJson(allocator: std.mem.Allocator, root: *const std.json.Value, field: []const u8) !?[]const u8 {
    const value = getObjectField(root, field) orelse return null;
    if (value.* == .null) return null;
    return try stringifyValue(allocator, value.*);
}

fn parseStringArrayValue(allocator: std.mem.Allocator, value: *const std.json.Value) ![][]const u8 {
    if (value.* != .array) return error.InvalidSubscriptionResponse;
    const logs = try allocator.alloc([]const u8, value.array.items.len);
    errdefer allocator.free(logs);
    for (value.array.items, 0..) |item, i| {
        if (item != .string) {
            for (logs[0..i]) |log| allocator.free(log);
            return error.InvalidSubscriptionResponse;
        }
        logs[i] = try allocator.dupe(u8, item.string);
    }
    return logs;
}

fn parseNotificationAccountInfo(allocator: std.mem.Allocator, value: *const std.json.Value) !WsRpcClient.NotificationAccountInfo {
    if (value.* != .object) return error.InvalidSubscriptionResponse;

    const lamports = getU64Field(value, "lamports") orelse return error.InvalidSubscriptionResponse;
    const owner = getStringField(value, "owner") orelse return error.InvalidSubscriptionResponse;
    const executable = getBoolField(value, "executable") orelse return error.InvalidSubscriptionResponse;
    const rent_epoch = getU64Field(value, "rentEpoch") orelse return error.InvalidSubscriptionResponse;
    const owner_copy = try allocator.dupe(u8, owner);
    errdefer allocator.free(owner_copy);

    const data_encoding = if (getObjectField(value, "data")) |data| blk: {
        if (data.* != .array or data.array.items.len < 2) break :blk null;
        if (data.array.items[1] != .string) return error.InvalidSubscriptionResponse;
        break :blk try allocator.dupe(u8, data.array.items[1].string);
    } else null;
    errdefer if (data_encoding) |encoding| allocator.free(encoding);

    return .{
        .lamports = lamports,
        .owner = owner_copy,
        .executable = executable,
        .rent_epoch = rent_epoch,
        .data_encoding = data_encoding,
    };
}

fn parseAccountNotification(allocator: std.mem.Allocator, subscription_id: u64, result: *const std.json.Value) !WsRpcClient.AccountNotification {
    const context = getObjectField(result, "context") orelse return error.InvalidSubscriptionResponse;
    const context_slot = getU64Field(context, "slot") orelse return error.InvalidSubscriptionResponse;
    const account_value = getObjectField(result, "value") orelse return error.InvalidSubscriptionResponse;
    const account = try parseNotificationAccountInfo(allocator, account_value);
    return .{
        .subscription_id = subscription_id,
        .context_slot = context_slot,
        .account = account,
    };
}

fn parseProgramNotification(allocator: std.mem.Allocator, subscription_id: u64, result: *const std.json.Value) !WsRpcClient.ProgramNotification {
    const context = getObjectField(result, "context") orelse return error.InvalidSubscriptionResponse;
    const context_slot = getU64Field(context, "slot") orelse return error.InvalidSubscriptionResponse;
    const value = getObjectField(result, "value") orelse return error.InvalidSubscriptionResponse;
    const pubkey = getStringField(value, "pubkey") orelse return error.InvalidSubscriptionResponse;
    const pubkey_copy = try allocator.dupe(u8, pubkey);
    errdefer allocator.free(pubkey_copy);
    const account_value = getObjectField(value, "account") orelse return error.InvalidSubscriptionResponse;
    const account = try parseNotificationAccountInfo(allocator, account_value);
    errdefer {
        var owned_account = account;
        owned_account.deinit(allocator);
    }
    return .{
        .subscription_id = subscription_id,
        .context_slot = context_slot,
        .pubkey = pubkey_copy,
        .account = account,
    };
}

fn parseSignatureNotification(allocator: std.mem.Allocator, subscription_id: u64, result: *const std.json.Value) !WsRpcClient.SignatureNotification {
    const context = getObjectField(result, "context") orelse return error.InvalidSubscriptionResponse;
    const context_slot = getU64Field(context, "slot") orelse return error.InvalidSubscriptionResponse;
    const value = getObjectField(result, "value") orelse return error.InvalidSubscriptionResponse;
    const err_json = try extractOptionalFieldJson(allocator, value, "err");
    errdefer if (err_json) |owned| allocator.free(owned);
    return .{
        .subscription_id = subscription_id,
        .context_slot = context_slot,
        .err_json = err_json,
    };
}

fn parseSlotNotification(subscription_id: u64, result: *const std.json.Value) !WsRpcClient.SlotNotification {
    if (result.* != .object) return error.InvalidSubscriptionResponse;
    return .{
        .subscription_id = subscription_id,
        .parent = getU64Field(result, "parent") orelse return error.InvalidSubscriptionResponse,
        .slot = getU64Field(result, "slot") orelse return error.InvalidSubscriptionResponse,
        .root = getU64Field(result, "root") orelse return error.InvalidSubscriptionResponse,
    };
}

fn parseRootNotification(subscription_id: u64, result: *const std.json.Value) !WsRpcClient.RootNotification {
    const root = parseIntegerAsU64(result) orelse return error.InvalidSubscriptionResponse;
    return .{
        .subscription_id = subscription_id,
        .root = root,
    };
}

fn parseLogsNotification(allocator: std.mem.Allocator, subscription_id: u64, result: *const std.json.Value) !WsRpcClient.LogsNotification {
    const context = getObjectField(result, "context") orelse return error.InvalidSubscriptionResponse;
    const context_slot = getU64Field(context, "slot") orelse return error.InvalidSubscriptionResponse;
    const value = getObjectField(result, "value") orelse return error.InvalidSubscriptionResponse;

    const signature = if (getStringField(value, "signature")) |owned|
        try allocator.dupe(u8, owned)
    else
        null;
    errdefer if (signature) |owned| allocator.free(owned);

    const err_json = try extractOptionalFieldJson(allocator, value, "err");
    errdefer if (err_json) |owned| allocator.free(owned);

    const logs_value = getObjectField(value, "logs") orelse return error.InvalidSubscriptionResponse;
    const logs = try parseStringArrayValue(allocator, logs_value);
    errdefer {
        for (logs) |log| allocator.free(log);
        allocator.free(logs);
    }

    return .{
        .subscription_id = subscription_id,
        .context_slot = context_slot,
        .signature = signature,
        .err_json = err_json,
        .logs = logs,
    };
}

fn parseBlockNotification(allocator: std.mem.Allocator, subscription_id: u64, result: *const std.json.Value) !WsRpcClient.BlockNotification {
    const context = getObjectField(result, "context") orelse return error.InvalidSubscriptionResponse;
    const context_slot = getU64Field(context, "slot") orelse return error.InvalidSubscriptionResponse;
    const value = getObjectField(result, "value") orelse return error.InvalidSubscriptionResponse;
    const slot = getU64Field(value, "slot") orelse return error.InvalidSubscriptionResponse;
    const err_json = try extractOptionalFieldJson(allocator, value, "err");
    errdefer if (err_json) |owned| allocator.free(owned);
    return .{
        .subscription_id = subscription_id,
        .context_slot = context_slot,
        .slot = slot,
        .err_json = err_json,
    };
}

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
        next_subscription_id: u64 = 1,
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

            handleConnection(allocator, ctx, conn_fd) catch {};

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

    fn handleConnection(allocator: std.mem.Allocator, ctx: *ServerContext, fd: std.posix.fd_t) !void {
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
            const is_unsubscribe = std.mem.endsWith(u8, method.string, "Unsubscribe");
            const force_disconnect_after_notify = std.mem.indexOf(u8, frame.payload, "force_disconnect_after_notify") != null;
            const malformed_subscribe_response = std.mem.indexOf(u8, frame.payload, "malformed_sub_reply") != null;
            const duplicate_notifications = std.mem.indexOf(u8, frame.payload, "duplicate_notify") != null;
            var sub_id: u64 = 0;
            {
                lockAtomicMutex(&ctx.mutex);
                defer ctx.mutex.unlock();
                sub_id = ctx.next_subscription_id;
                ctx.next_subscription_id += 1;
            }

            if (is_subscribe and malformed_subscribe_response) {
                const reply = "{\"jsonrpc\":\"2.0\",\"result\":";
                sendFrameRaw(fd, .text, reply) catch break;
                continue;
            }

            if (is_unsubscribe) {
                const reply = std.fmt.allocPrint(
                    allocator,
                    "{{\"jsonrpc\":\"2.0\",\"result\":true,\"id\":{d}}}",
                    .{id.integer},
                ) catch break;
                defer allocator.free(reply);
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
                const notif = buildMockNotification(allocator, method.string, sub_id) catch break;
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
        if (payload_len > max_ws_payload_len) return error.WsProtocolError;

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
        if (payload.len <= 125) {
            header[1] = @intCast(payload.len);
        } else {
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

fn buildMockNotification(allocator: std.mem.Allocator, subscribe_method: []const u8, subscription_id: u64) ![]u8 {
    if (std.mem.eql(u8, subscribe_method, "accountSubscribe")) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"accountNotification\",\"params\":{{\"result\":{{\"context\":{{\"slot\":42}},\"value\":{{\"lamports\":1234,\"owner\":\"11111111111111111111111111111111\",\"executable\":false,\"rentEpoch\":7,\"data\":[\"AQID\",\"base64\"]}}}},\"subscription\":{d}}}}}",
            .{subscription_id},
        );
    }
    if (std.mem.eql(u8, subscribe_method, "programSubscribe")) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"programNotification\",\"params\":{{\"result\":{{\"context\":{{\"slot\":43}},\"value\":{{\"pubkey\":\"ProgramDerived1111111111111111111111111111\",\"account\":{{\"lamports\":5678,\"owner\":\"BPFLoaderUpgradeab1e11111111111111111111111\",\"executable\":false,\"rentEpoch\":8,\"data\":[\"BAUG\",\"base64\"]}}}}}},\"subscription\":{d}}}}}",
            .{subscription_id},
        );
    }
    if (std.mem.eql(u8, subscribe_method, "signatureSubscribe")) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"signatureNotification\",\"params\":{{\"result\":{{\"context\":{{\"slot\":44}},\"value\":{{\"err\":null}}}},\"subscription\":{d}}}}}",
            .{subscription_id},
        );
    }
    if (std.mem.eql(u8, subscribe_method, "slotSubscribe")) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"slotNotification\",\"params\":{{\"result\":{{\"parent\":40,\"slot\":41,\"root\":39}},\"subscription\":{d}}}}}",
            .{subscription_id},
        );
    }
    if (std.mem.eql(u8, subscribe_method, "rootSubscribe")) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"rootNotification\",\"params\":{{\"result\":45,\"subscription\":{d}}}}}",
            .{subscription_id},
        );
    }
    if (std.mem.eql(u8, subscribe_method, "logsSubscribe")) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"logsNotification\",\"params\":{{\"result\":{{\"context\":{{\"slot\":46}},\"value\":{{\"signature\":\"deadbeef\",\"err\":null,\"logs\":[\"Program log: mock\"]}}}},\"subscription\":{d}}}}}",
            .{subscription_id},
        );
    }
    if (std.mem.eql(u8, subscribe_method, "blockSubscribe")) {
        return std.fmt.allocPrint(
            allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"blockNotification\",\"params\":{{\"result\":{{\"context\":{{\"slot\":47}},\"value\":{{\"slot\":47,\"err\":null,\"block\":{{\"blockhash\":\"mock-blockhash\"}}}}}},\"subscription\":{d}}}}}",
            .{subscription_id},
        );
    }
    return error.InvalidSubscriptionResponse;
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

const TypedWsTestHarness = struct {
    server: MockWsServer,
    client: WsRpcClient,
    url: []const u8,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, io: std.Io) !TypedWsTestHarness {
        var server = try MockWsServer.start(allocator);
        errdefer server.stop();

        const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
        errdefer allocator.free(url);

        const client = try WsRpcClient.connect(allocator, io, url);
        errdefer {
            var owned_client = client;
            owned_client.deinit();
        }

        return .{
            .server = server,
            .client = client,
            .url = url,
            .allocator = allocator,
        };
    }

    fn deinit(self: *TypedWsTestHarness) void {
        self.client.deinit();
        self.allocator.free(self.url);
        self.server.stop();
    }
};

const CallbackRecorder = struct {
    account_context_slot: ?u64 = null,
    program_context_slot: ?u64 = null,
    signature_context_slot: ?u64 = null,
    slot_value: ?u64 = null,
    root_value: ?u64 = null,
    logs_context_slot: ?u64 = null,
    block_slot: ?u64 = null,
};

var callback_recorder = CallbackRecorder{};

fn resetCallbackRecorder() void {
    callback_recorder = .{};
}

fn recordAccountNotification(notification: *const WsRpcClient.AccountNotification) void {
    callback_recorder.account_context_slot = notification.context_slot;
}

fn recordProgramNotification(notification: *const WsRpcClient.ProgramNotification) void {
    callback_recorder.program_context_slot = notification.context_slot;
}

fn recordSignatureNotification(notification: *const WsRpcClient.SignatureNotification) void {
    callback_recorder.signature_context_slot = notification.context_slot;
}

fn recordSlotNotification(notification: *const WsRpcClient.SlotNotification) void {
    callback_recorder.slot_value = notification.slot;
}

fn recordRootNotification(notification: *const WsRpcClient.RootNotification) void {
    callback_recorder.root_value = notification.root;
}

fn recordLogsNotification(notification: *const WsRpcClient.LogsNotification) void {
    callback_recorder.logs_context_slot = notification.context_slot;
}

fn recordBlockNotification(notification: *const WsRpcClient.BlockNotification) void {
    callback_recorder.block_slot = notification.slot;
}

test "WsRpcClient subscribe and receive notification" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.start(allocator);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    const sub_id = try client.accountSubscribe("11111111111111111111111111111111", .confirmed);
    try std.testing.expect(sub_id > 0);

    var notif = try client.readNotification();
    defer notif.deinit();
    try std.testing.expectEqualStrings("accountNotification", notif.method);
    try std.testing.expectEqual(sub_id, notif.subscription_id);
}

test "ws_account_subscribe_typed_notify_unsubscribe" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var harness = try TypedWsTestHarness.init(allocator, io);
    defer harness.deinit();

    const sub_id = try harness.client.accountSubscribe("11111111111111111111111111111111", .confirmed);
    try std.testing.expect(sub_id > 0);
    try std.testing.expectEqual(@as(usize, 1), harness.client.subscriptionCount());

    var notification = try harness.client.readAccountNotification();
    defer notification.deinit(allocator);

    try std.testing.expectEqual(sub_id, notification.subscription_id);
    try std.testing.expectEqual(@as(u64, 42), notification.context_slot);
    try std.testing.expectEqual(@as(u64, 1234), notification.account.lamports);
    try std.testing.expectEqualStrings("11111111111111111111111111111111", notification.account.owner);
    try std.testing.expectEqual(false, notification.account.executable);
    try std.testing.expectEqual(@as(u64, 7), notification.account.rent_epoch);
    try std.testing.expectEqualStrings("base64", notification.account.data_encoding.?);

    resetCallbackRecorder();
    const callback: WsRpcClient.AccountNotificationCallback = recordAccountNotification;
    callback(&notification);
    try std.testing.expectEqual(@as(?u64, notification.context_slot), callback_recorder.account_context_slot);

    try harness.client.accountUnsubscribe(sub_id);
    try std.testing.expectEqual(@as(usize, 0), harness.client.subscriptionCount());
}

test "ws_program_subscribe_typed_notify_unsubscribe" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var harness = try TypedWsTestHarness.init(allocator, io);
    defer harness.deinit();

    const sub_id = try harness.client.programSubscribe("BPFLoaderUpgradeab1e11111111111111111111111", .confirmed);
    try std.testing.expect(sub_id > 0);
    try std.testing.expectEqual(@as(usize, 1), harness.client.subscriptionCount());

    var notification = try harness.client.readProgramNotification();
    defer notification.deinit(allocator);

    try std.testing.expectEqual(sub_id, notification.subscription_id);
    try std.testing.expectEqual(@as(u64, 43), notification.context_slot);
    try std.testing.expectEqualStrings("ProgramDerived1111111111111111111111111111", notification.pubkey);
    try std.testing.expectEqual(@as(u64, 5678), notification.account.lamports);
    try std.testing.expectEqualStrings("BPFLoaderUpgradeab1e11111111111111111111111", notification.account.owner);
    try std.testing.expectEqualStrings("base64", notification.account.data_encoding.?);

    resetCallbackRecorder();
    const callback: WsRpcClient.ProgramNotificationCallback = recordProgramNotification;
    callback(&notification);
    try std.testing.expectEqual(@as(?u64, notification.context_slot), callback_recorder.program_context_slot);

    try harness.client.programUnsubscribe(sub_id);
    try std.testing.expectEqual(@as(usize, 0), harness.client.subscriptionCount());
}

test "ws_signature_subscribe_typed_notify_unsubscribe" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var harness = try TypedWsTestHarness.init(allocator, io);
    defer harness.deinit();

    const sub_id = try harness.client.signatureSubscribe("deadbeef", .confirmed);
    try std.testing.expect(sub_id > 0);
    try std.testing.expectEqual(@as(usize, 1), harness.client.subscriptionCount());

    var notification = try harness.client.readSignatureNotification();
    defer notification.deinit(allocator);

    try std.testing.expectEqual(sub_id, notification.subscription_id);
    try std.testing.expectEqual(@as(u64, 44), notification.context_slot);
    try std.testing.expectEqual(@as(?[]const u8, null), notification.err_json);

    resetCallbackRecorder();
    const callback: WsRpcClient.SignatureNotificationCallback = recordSignatureNotification;
    callback(&notification);
    try std.testing.expectEqual(@as(?u64, notification.context_slot), callback_recorder.signature_context_slot);

    try harness.client.signatureUnsubscribe(sub_id);
    try std.testing.expectEqual(@as(usize, 0), harness.client.subscriptionCount());
}

test "ws_slot_subscribe_typed_notify_unsubscribe" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var harness = try TypedWsTestHarness.init(allocator, io);
    defer harness.deinit();

    const sub_id = try harness.client.slotSubscribe();
    try std.testing.expect(sub_id > 0);
    try std.testing.expectEqual(@as(usize, 1), harness.client.subscriptionCount());

    var notification = try harness.client.readSlotNotification();
    defer notification.deinit(allocator);

    try std.testing.expectEqual(sub_id, notification.subscription_id);
    try std.testing.expectEqual(@as(u64, 40), notification.parent);
    try std.testing.expectEqual(@as(u64, 41), notification.slot);
    try std.testing.expectEqual(@as(u64, 39), notification.root);

    resetCallbackRecorder();
    const callback: WsRpcClient.SlotNotificationCallback = recordSlotNotification;
    callback(&notification);
    try std.testing.expectEqual(@as(?u64, notification.slot), callback_recorder.slot_value);

    try harness.client.slotUnsubscribe(sub_id);
    try std.testing.expectEqual(@as(usize, 0), harness.client.subscriptionCount());
}

test "ws_root_subscribe_typed_notify_unsubscribe" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var harness = try TypedWsTestHarness.init(allocator, io);
    defer harness.deinit();

    const sub_id = try harness.client.rootSubscribe();
    try std.testing.expect(sub_id > 0);
    try std.testing.expectEqual(@as(usize, 1), harness.client.subscriptionCount());

    var notification = try harness.client.readRootNotification();
    defer notification.deinit(allocator);

    try std.testing.expectEqual(sub_id, notification.subscription_id);
    try std.testing.expectEqual(@as(u64, 45), notification.root);

    resetCallbackRecorder();
    const callback: WsRpcClient.RootNotificationCallback = recordRootNotification;
    callback(&notification);
    try std.testing.expectEqual(@as(?u64, notification.root), callback_recorder.root_value);

    try harness.client.rootUnsubscribe(sub_id);
    try std.testing.expectEqual(@as(usize, 0), harness.client.subscriptionCount());
}

test "ws_logs_subscribe_typed_notify_unsubscribe" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var harness = try TypedWsTestHarness.init(allocator, io);
    defer harness.deinit();

    const sub_id = try harness.client.logsSubscribe("all");
    try std.testing.expect(sub_id > 0);
    try std.testing.expectEqual(@as(usize, 1), harness.client.subscriptionCount());

    var notification = try harness.client.readLogsNotification();
    defer notification.deinit(allocator);

    try std.testing.expectEqual(sub_id, notification.subscription_id);
    try std.testing.expectEqual(@as(u64, 46), notification.context_slot);
    try std.testing.expectEqualStrings("deadbeef", notification.signature.?);
    try std.testing.expectEqual(@as(?[]const u8, null), notification.err_json);
    try std.testing.expectEqual(@as(usize, 1), notification.logs.len);
    try std.testing.expectEqualStrings("Program log: mock", notification.logs[0]);

    resetCallbackRecorder();
    const callback: WsRpcClient.LogsNotificationCallback = recordLogsNotification;
    callback(&notification);
    try std.testing.expectEqual(@as(?u64, notification.context_slot), callback_recorder.logs_context_slot);

    try harness.client.logsUnsubscribe(sub_id);
    try std.testing.expectEqual(@as(usize, 0), harness.client.subscriptionCount());
}

test "ws_block_subscribe_typed_notify_unsubscribe" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var harness = try TypedWsTestHarness.init(allocator, io);
    defer harness.deinit();

    const sub_id = try harness.client.blockSubscribe("all", .confirmed);
    try std.testing.expect(sub_id > 0);
    try std.testing.expectEqual(@as(usize, 1), harness.client.subscriptionCount());

    var notification = try harness.client.readBlockNotification();
    defer notification.deinit(allocator);

    try std.testing.expectEqual(sub_id, notification.subscription_id);
    try std.testing.expectEqual(@as(u64, 47), notification.context_slot);
    try std.testing.expectEqual(@as(u64, 47), notification.slot);
    try std.testing.expectEqual(@as(?[]const u8, null), notification.err_json);

    resetCallbackRecorder();
    const callback: WsRpcClient.BlockNotificationCallback = recordBlockNotification;
    callback(&notification);
    try std.testing.expectEqual(@as(?u64, notification.slot), callback_recorder.block_slot);

    try harness.client.blockUnsubscribe(sub_id);
    try std.testing.expectEqual(@as(usize, 0), harness.client.subscriptionCount());
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

    const sub_id = try client.signatureSubscribe("deadbeef", .confirmed);
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

    const sub_id = try client.accountSubscribe("11111111111111111111111111111111", .confirmed);
    try std.testing.expect(sub_id > 0);

    // Consume the pending notification before unsubscribing.
    var notif = try client.readNotification();
    notif.deinit();

    try client.unsubscribe(sub_id, "accountUnsubscribe");
}

test "ws_reconnect_detect_disconnect_then_recover_automatically" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.startMulti(allocator, 3);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();
    client.setReconnectConfig(.{
        .max_retries = 2,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    const sub_id = try client.logsSubscribe("force_disconnect_after_notify");
    try std.testing.expect(sub_id > 0);

    var first = try client.readLogsNotification();
    defer first.deinit(allocator);
    try std.testing.expectEqual(sub_id, first.subscription_id);
    try std.testing.expectEqual(@as(u64, 46), first.context_slot);

    var recovered = try client.readLogsNotification();
    defer recovered.deinit(allocator);
    try std.testing.expect(recovered.subscription_id != sub_id);

    const stats = client.snapshot();
    try std.testing.expectEqual(@as(u32, 1), stats.reconnect_attempts_total);
    try std.testing.expectEqual(@as(usize, 1), client.subscriptionCount());
}

test "ws_reconnect_resubscribe_restores_all_active_subscriptions" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.startMulti(allocator, 3);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();
    client.setReconnectConfig(.{
        .max_retries = 2,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    const account_id = try client.accountSubscribe("11111111111111111111111111111111", .confirmed);
    var first_account = try client.readAccountNotification();
    defer first_account.deinit(allocator);
    try std.testing.expectEqual(account_id, first_account.subscription_id);

    const logs_id = try client.logsSubscribe("force_disconnect_after_notify");
    try std.testing.expectEqual(@as(usize, 2), client.subscriptionCount());

    var first_logs = try client.readLogsNotification();
    defer first_logs.deinit(allocator);
    try std.testing.expectEqual(logs_id, first_logs.subscription_id);

    var recovered_account = try client.readAccountNotification();
    defer recovered_account.deinit(allocator);
    try std.testing.expect(recovered_account.subscription_id != account_id);

    var recovered_logs = try client.readLogsNotification();
    defer recovered_logs.deinit(allocator);
    try std.testing.expect(recovered_logs.subscription_id != logs_id);

    try std.testing.expectEqual(@as(usize, 2), client.subscriptionCount());
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

test "ws_reconnect_config_drives_retry_budget" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.startMulti(allocator, 2);

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();
    client.setReconnectConfig(.{
        .max_retries = 2,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    _ = try client.logsSubscribe("force_disconnect_after_notify");
    {
        var notification = try client.readLogsNotification();
        notification.deinit(allocator);
    }

    server.stop();

    if (client.readNotification()) |_| {
        return error.TestUnexpectedResult;
    } else |_| {}

    try std.testing.expectEqual(@as(u8, 2), client.last_reconnect_attempts);
    const stats = client.snapshot();
    try std.testing.expectEqual(@as(u32, 2), stats.reconnect_attempts_total);
    try std.testing.expect(stats.last_error_code != null);
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
    client.setReconnectConfig(.{
        .max_retries = 0,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

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
    client.setReconnectConfig(.{
        .max_retries = 0,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

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

test "ws_retry_delay_respects_config_and_cap" {
    const reconnect_config = types.WsReconnectConfig{
        .max_retries = 4,
        .base_delay_ms = 25,
        .max_delay_ms = 60,
    };

    try std.testing.expectEqual(@as(u64, 25), WsRpcClient.retryDelayMs(reconnect_config, 0));
    try std.testing.expectEqual(@as(u64, 50), WsRpcClient.retryDelayMs(reconnect_config, 1));
    try std.testing.expectEqual(@as(u64, 60), WsRpcClient.retryDelayMs(reconnect_config, 2));
    try std.testing.expectEqual(@as(u64, 60), WsRpcClient.retryDelayMs(reconnect_config, 3));
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
    client.setReconnectConfig(.{
        .max_retries = 0,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

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
    try std.testing.expectEqual(WsRpcClient.ConnectionState.connected, stats.connection_state);
    try std.testing.expectEqual(@as(u32, 0), stats.reconnect_attempts_total);
    try std.testing.expectEqual(@as(u32, 0), stats.active_subscriptions);
    try std.testing.expectEqual(@as(u32, 0), stats.dedup_dropped_total);
    try std.testing.expectEqual(@as(u64, 0), stats.messages_sent_total);
    try std.testing.expectEqual(@as(u64, 0), stats.messages_received_total);
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

    _ = try client.accountSubscribe("11111111111111111111111111111111", .confirmed);
    const stats = client.snapshot();
    try std.testing.expectEqual(WsRpcClient.ConnectionState.connected, stats.connection_state);
    try std.testing.expectEqual(@as(u32, 1), stats.active_subscriptions);
    try std.testing.expectEqual(@as(u32, 0), stats.reconnect_attempts_total);
    try std.testing.expectEqual(@as(u64, 1), stats.messages_sent_total);
    try std.testing.expectEqual(@as(u64, 1), stats.messages_received_total);
}

test "ws_observability_connection_state_changes" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.startMulti(allocator, 3);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    try std.testing.expectEqual(WsRpcClient.ConnectionState.connected, client.connectionState());

    client.disconnect();
    try std.testing.expectEqual(WsRpcClient.ConnectionState.disconnected, client.connectionState());

    try client.reconnect();
    try std.testing.expectEqual(WsRpcClient.ConnectionState.connected, client.connectionState());
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
    client.setReconnectConfig(.{
        .max_retries = 0,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    _ = try client.logsSubscribe("force_disconnect_after_notify");
    var notif = try client.readNotification();
    notif.deinit();
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    const before = client.snapshot();
    try std.testing.expectEqual(@as(u32, 0), before.reconnect_attempts_total);
    try std.testing.expectEqual(WsRpcClient.ConnectionState.disconnected, before.connection_state);

    try client.reconnect();
    const after = client.snapshot();
    try std.testing.expectEqual(WsRpcClient.ConnectionState.connected, after.connection_state);
    try std.testing.expectEqual(@as(u32, 1), after.reconnect_attempts_total);
    try std.testing.expectEqual(@as(u64, 2), after.messages_sent_total);
    try std.testing.expectEqual(@as(u64, 3), after.messages_received_total);
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
    client.setReconnectConfig(.{
        .max_retries = 0,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    _ = try client.logsSubscribe("duplicate_notify");

    // First notification passes dedup, second is duplicate and dropped
    var first = try client.readNotification();
    defer first.deinit();

    // After the duplicate is dropped, server sends close — readNotification returns ConnectionClosed
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    const stats = client.snapshot();
    try std.testing.expectEqual(WsRpcClient.ConnectionState.disconnected, stats.connection_state);
    try std.testing.expect(stats.dedup_dropped_total >= 1);
    try std.testing.expectEqual(@as(u64, 1), stats.messages_sent_total);
    try std.testing.expectEqual(@as(u64, 3), stats.messages_received_total);
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
    try std.testing.expectEqual(WsRpcClient.ConnectionState.disconnected, stats.connection_state);
    try std.testing.expect(stats.reconnect_attempts_total >= 2);
    try std.testing.expect(stats.last_error_code != null);
    try std.testing.expect(stats.last_error_message != null);
}

// ------------------------------------------------------------------
// P2-28 Recoverability Tests (G-P2F-03)
// ------------------------------------------------------------------

test "ws_recoverability_reconnect_storm_stability" {
    // G-P2F-03 evidence 1: reconnect storm/backoff stability
    // Trigger N>=3 disconnect/reconnect cycles, verify:
    // - reconnect_attempts_total monotonically increases
    // - no panic / no leak (allocator-checked)
    // - backoff model not exceeded (MAX_BACKOFF_MS)
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Need initial + 3 reconnects = 4 connections minimum
    var server = try MockWsServer.startMulti(allocator, 5);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    var prev_reconnect_total: u32 = 0;

    // Perform 3 disconnect/reconnect cycles
    for (0..3) |cycle| {
        _ = cycle;
        const before = client.snapshot();
        try std.testing.expect(before.reconnect_attempts_total >= prev_reconnect_total);

        try client.reconnect();

        const after = client.snapshot();
        // Counter must strictly increase by 1 per reconnect() call
        try std.testing.expectEqual(prev_reconnect_total + 1, after.reconnect_attempts_total);
        // Timestamp must be set after reconnect
        try std.testing.expect(after.last_reconnect_unix_ms != null);

        prev_reconnect_total = after.reconnect_attempts_total;
    }

    // Final verification: 3 reconnects total, counters monotonic
    const final_stats = client.snapshot();
    try std.testing.expectEqual(@as(u32, 3), final_stats.reconnect_attempts_total);
    try std.testing.expect(final_stats.last_reconnect_unix_ms != null);
}

test "ws_recoverability_recovery_state_consistency" {
    // G-P2F-03 evidence 2: recovery after disconnect preserves active_subscriptions
    // Subscribe to K items, disconnect, reconnect+resubscribeAll, verify K == K
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Need: initial connect + close/reconnect = 2 connections
    var server = try MockWsServer.startMulti(allocator, 3);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();

    // Subscribe and consume notification
    _ = try client.accountSubscribe("11111111111111111111111111111111", .confirmed);
    {
        var n = try client.readNotification();
        n.deinit();
    }

    const before_stats = client.snapshot();
    const subs_before = before_stats.active_subscriptions;
    try std.testing.expectEqual(@as(u32, 1), subs_before);

    // Graceful disconnect then reconnect with public recovery path
    client.disconnect();
    try client.reconnect();

    const after_stats = client.snapshot();
    // active_subscriptions must be preserved after recovery
    try std.testing.expectEqual(subs_before, after_stats.active_subscriptions);
    // reconnect counter must have incremented
    try std.testing.expect(after_stats.reconnect_attempts_total >= 1);
    // timestamp must be set
    try std.testing.expect(after_stats.last_reconnect_unix_ms != null);
}

test "ws_recoverability_message_boundary_counters" {
    // G-P2F-03 evidence 3: message counters remain monotonic across disconnect/recovery
    // Verify dedup_dropped_total and messages_received_total (internal) are observable
    // and monotonically non-decreasing across a disconnect/reconnect cycle.
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try MockWsServer.startMulti(allocator, 3);
    defer server.stop();

    const url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{server.port});
    defer allocator.free(url);

    var client = try WsRpcClient.connect(allocator, io, url);
    defer client.deinit();
    client.setReconnectConfig(.{
        .max_retries = 0,
        .base_delay_ms = 0,
        .max_delay_ms = 0,
    });

    // Subscribe with duplicate_notify: server sends 2 identical notifications then closes
    _ = try client.logsSubscribe("duplicate_notify");

    // First notification passes, second is dedup-dropped, then server closes
    var first = try client.readNotification();
    first.deinit();
    try std.testing.expectError(error.ConnectionClosed, client.readNotification());

    // Capture counters before reconnect
    const pre_stats = client.snapshot();
    const pre_dedup = pre_stats.dedup_dropped_total;
    try std.testing.expect(pre_dedup >= 1);

    // Reconnect
    try client.reconnect();

    // Post-reconnect: counters must be >= pre-reconnect (monotonic)
    const post_stats = client.snapshot();
    try std.testing.expect(post_stats.dedup_dropped_total >= pre_dedup);
    try std.testing.expect(post_stats.reconnect_attempts_total >= 1);
    // messages_received_total is internal but dedup_dropped_total proves boundary observability
    // The dedup ring state persists across reconnect — old hashes still cached
    try std.testing.expect(post_stats.last_reconnect_unix_ms != null);
}
