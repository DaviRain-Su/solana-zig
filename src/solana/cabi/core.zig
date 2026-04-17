const std = @import("std");
const solana = @import("../mod.zig");
const errors = @import("errors.zig");

pub export fn solana_zig_abi_version() c_int {
    return 1;
}

// ===================== Pubkey =====================

pub export fn solana_pubkey_from_bytes(bytes: [*c]const u8, len: usize, out: ?*solana.core.Pubkey) c_int {
    if (bytes == null or out == null or len != 32) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.?.* = solana.core.Pubkey.init(bytes[0..32].*);
    return errors.SOLANA_OK;
}

pub export fn solana_pubkey_to_base58(pubkey: ?*const solana.core.Pubkey, out_str: ?*[*c]u8, out_len: ?*usize) c_int {
    if (pubkey == null or out_str == null or out_len == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    var buf: [64]u8 = undefined;
    const len = pubkey.?.toBase58Fast(&buf);
    const encoded = std.heap.c_allocator.dupe(u8, buf[0..len]) catch return errors.SOLANA_ERR_INTERNAL;
    out_str.?.* = encoded.ptr;
    out_len.?.* = encoded.len;
    return errors.SOLANA_OK;
}

pub export fn solana_pubkey_from_base58(str: [*c]const u8, len: usize, out: ?*solana.core.Pubkey) c_int {
    if (str == null or out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.?.* = solana.core.Pubkey.fromBase58(str[0..len]) catch return errors.SOLANA_ERR_INVALID_ARGUMENT;
    return errors.SOLANA_OK;
}

pub export fn solana_pubkey_equal(a: ?*const solana.core.Pubkey, b: ?*const solana.core.Pubkey) c_int {
    if (a == null or b == null) return 0;
    return if (a.?.eql(b.?.*)) 1 else 0;
}

// ===================== Signature =====================

pub export fn solana_signature_from_bytes(bytes: [*c]const u8, len: usize, out: ?*solana.core.Signature) c_int {
    if (bytes == null or out == null or len != 64) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.?.* = solana.core.Signature.init(bytes[0..64].*);
    return errors.SOLANA_OK;
}

pub export fn solana_signature_from_base58(str: [*c]const u8, len: usize, out: ?*solana.core.Signature) c_int {
    if (str == null or out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.?.* = solana.core.Signature.fromBase58(str[0..len]) catch return errors.SOLANA_ERR_INVALID_ARGUMENT;
    return errors.SOLANA_OK;
}

pub export fn solana_signature_to_base58(sig: ?*const solana.core.Signature, out_str: ?*[*c]u8, out_len: ?*usize) c_int {
    if (sig == null or out_str == null or out_len == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    var buf: [128]u8 = undefined;
    const len = sig.?.toBase58Fast(&buf);
    const encoded = std.heap.c_allocator.dupe(u8, buf[0..len]) catch return errors.SOLANA_ERR_INTERNAL;
    out_str.?.* = encoded.ptr;
    out_len.?.* = encoded.len;
    return errors.SOLANA_OK;
}

pub export fn solana_signature_equal(a: ?*const solana.core.Signature, b: ?*const solana.core.Signature) c_int {
    if (a == null or b == null) return 0;
    return if (std.mem.eql(u8, &a.?.bytes, &b.?.bytes)) 1 else 0;
}

// ===================== Hash =====================

pub export fn solana_hash_from_bytes(bytes: [*c]const u8, len: usize, out: ?*solana.core.Hash) c_int {
    if (bytes == null or out == null or len != 32) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.?.* = solana.core.Hash.init(bytes[0..32].*);
    return errors.SOLANA_OK;
}

pub export fn solana_hash_from_base58(str: [*c]const u8, len: usize, out: ?*solana.core.Hash) c_int {
    if (str == null or out == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.?.* = solana.core.Hash.fromBase58(str[0..len]) catch return errors.SOLANA_ERR_INVALID_ARGUMENT;
    return errors.SOLANA_OK;
}

pub export fn solana_hash_to_base58(h: ?*const solana.core.Hash, out_str: ?*[*c]u8, out_len: ?*usize) c_int {
    if (h == null or out_str == null or out_len == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    const encoded = h.?.toBase58Alloc(std.heap.c_allocator) catch return errors.SOLANA_ERR_INTERNAL;
    out_str.?.* = encoded.ptr;
    out_len.?.* = encoded.len;
    return errors.SOLANA_OK;
}

pub export fn solana_hash_equal(a: ?*const solana.core.Hash, b: ?*const solana.core.Hash) c_int {
    if (a == null or b == null) return 0;
    return if (std.mem.eql(u8, &a.?.bytes, &b.?.bytes)) 1 else 0;
}

// ===================== General free =====================

pub export fn solana_string_free(str: [*c]u8, len: usize) void {
    if (str == null) return;
    const slice = str[0..len];
    std.heap.c_allocator.free(slice);
}

test "cabi pubkey roundtrip via base58" {
    const original = solana.core.Pubkey.init([_]u8{1} ** 32);
    var str: [*c]u8 = undefined;
    var len: usize = 0;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_pubkey_to_base58(&original, &str, &len));
    defer solana_string_free(str, len);

    var recovered: solana.core.Pubkey = undefined;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_pubkey_from_base58(str, len, &recovered));
    try std.testing.expect(original.eql(recovered));
}

test "cabi pubkey equal" {
    const a = solana.core.Pubkey.init([_]u8{2} ** 32);
    const b = solana.core.Pubkey.init([_]u8{2} ** 32);
    const c = solana.core.Pubkey.init([_]u8{3} ** 32);
    try std.testing.expectEqual(@as(c_int, 1), solana_pubkey_equal(&a, &b));
    try std.testing.expectEqual(@as(c_int, 0), solana_pubkey_equal(&a, &c));
}

test "cabi abi version matches header constant" {
    try std.testing.expectEqual(@as(c_int, 1), solana_zig_abi_version());
}

test "cabi signature roundtrip via base58" {
    var bytes: [64]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const original = solana.core.Signature.init(bytes);
    var str: [*c]u8 = undefined;
    var len: usize = 0;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_signature_to_base58(&original, &str, &len));
    defer solana_string_free(str, len);

    var recovered: solana.core.Signature = undefined;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_signature_from_base58(str, len, &recovered));
    try std.testing.expectEqual(@as(c_int, 1), solana_signature_equal(&original, &recovered));
}

test "cabi hash roundtrip via base58" {
    const original = solana.core.Hash.init([_]u8{4} ** 32);
    var str: [*c]u8 = undefined;
    var len: usize = 0;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_hash_to_base58(&original, &str, &len));
    defer solana_string_free(str, len);

    var recovered: solana.core.Hash = undefined;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_hash_from_base58(str, len, &recovered));
    try std.testing.expectEqual(@as(c_int, 1), solana_hash_equal(&original, &recovered));
}
