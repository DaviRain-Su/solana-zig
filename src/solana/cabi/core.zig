const std = @import("std");
const solana = @import("../mod.zig");
const errors = @import("errors.zig");

// ===================== Pubkey =====================

pub export fn solana_pubkey_from_bytes(bytes: [*c]const u8, len: usize, out: *solana.core.Pubkey) c_int {
    if (bytes == null or len != 32) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.* = solana.core.Pubkey.init(bytes[0..32].*);
    return errors.SOLANA_OK;
}

pub export fn solana_pubkey_to_base58(pubkey: *const solana.core.Pubkey, out_str: *[*c]u8, out_len: *usize) c_int {
    const encoded = pubkey.toBase58Alloc(std.heap.c_allocator) catch return errors.SOLANA_ERR_INTERNAL;
    out_str.* = encoded.ptr;
    out_len.* = encoded.len;
    return errors.SOLANA_OK;
}

pub export fn solana_pubkey_from_base58(str: [*c]const u8, len: usize, out: *solana.core.Pubkey) c_int {
    if (str == null) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.* = solana.core.Pubkey.fromBase58(str[0..len]) catch return errors.SOLANA_ERR_INVALID_ARGUMENT;
    return errors.SOLANA_OK;
}

pub export fn solana_pubkey_equal(a: *const solana.core.Pubkey, b: *const solana.core.Pubkey) c_int {
    return if (a.eql(b.*)) 1 else 0;
}

// ===================== Signature =====================

pub export fn solana_signature_from_bytes(bytes: [*c]const u8, len: usize, out: *solana.core.Signature) c_int {
    if (bytes == null or len != 64) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.* = solana.core.Signature.init(bytes[0..64].*);
    return errors.SOLANA_OK;
}

pub export fn solana_signature_to_base58(sig: *const solana.core.Signature, out_str: *[*c]u8, out_len: *usize) c_int {
    const encoded = sig.toBase58Alloc(std.heap.c_allocator) catch return errors.SOLANA_ERR_INTERNAL;
    out_str.* = encoded.ptr;
    out_len.* = encoded.len;
    return errors.SOLANA_OK;
}

pub export fn solana_signature_equal(a: *const solana.core.Signature, b: *const solana.core.Signature) c_int {
    return if (std.mem.eql(u8, &a.bytes, &b.bytes)) 1 else 0;
}

// ===================== Hash =====================

pub export fn solana_hash_from_bytes(bytes: [*c]const u8, len: usize, out: *solana.core.Hash) c_int {
    if (bytes == null or len != 32) return errors.SOLANA_ERR_INVALID_ARGUMENT;
    out.* = solana.core.Hash.init(bytes[0..32].*);
    return errors.SOLANA_OK;
}

pub export fn solana_hash_to_base58(h: *const solana.core.Hash, out_str: *[*c]u8, out_len: *usize) c_int {
    const encoded = h.toBase58Alloc(std.heap.c_allocator) catch return errors.SOLANA_ERR_INTERNAL;
    out_str.* = encoded.ptr;
    out_len.* = encoded.len;
    return errors.SOLANA_OK;
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

test "cabi signature roundtrip via base58" {
    var bytes: [64]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const original = solana.core.Signature.init(bytes);
    var str: [*c]u8 = undefined;
    var len: usize = 0;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_signature_to_base58(&original, &str, &len));
    defer solana_string_free(str, len);

    var recovered: solana.core.Signature = undefined;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_signature_from_bytes(str, len, &recovered));
    try std.testing.expectEqual(@as(c_int, 1), solana_signature_equal(&original, &recovered));
}

test "cabi hash roundtrip via base58" {
    const original = solana.core.Hash.init([_]u8{4} ** 32);
    var str: [*c]u8 = undefined;
    var len: usize = 0;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_hash_to_base58(&original, &str, &len));
    defer solana_string_free(str, len);

    var recovered: solana.core.Hash = undefined;
    try std.testing.expectEqual(errors.SOLANA_OK, solana_hash_from_bytes(str, len, &recovered));
    try std.testing.expect(std.mem.eql(u8, &original.bytes, &recovered.bytes));
}
