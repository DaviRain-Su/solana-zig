const std = @import("std");
const config = @import("config");

// Ed25519 sign/verify wrapper with tiered backends:
//   1. ring staticlib (BoringSSL-based, fastest on aarch64 when keypair is cached)
//   2. ed25519-dalek staticlib (same backend as Rust ed25519-dalek)
//   3. libsodium (fast C implementation)
//   4. Zig std.crypto.sign.Ed25519 (portable fallback)

pub const Error = error{
    SignFailed,
    SignatureVerificationFailed,
};

// --- Backend 1: ring (BoringSSL) ---
const RingKeypair = opaque {};

extern "C" fn ring_ed25519_keypair_new(seed32: *const [32]u8) ?*RingKeypair;
extern "C" fn ring_ed25519_keypair_sign(
    kp: *RingKeypair,
    msg_ptr: [*]const u8,
    msg_len: usize,
    out_sig: *[64]u8,
) c_int;
extern "C" fn ring_ed25519_keypair_free(kp: ?*RingKeypair) void;
extern "C" fn ring_ed25519_verify(
    sig_ptr: *const [64]u8,
    msg_ptr: [*]const u8,
    msg_len: usize,
    pk32: *const [32]u8,
) c_int;

// --- Backend 2: ed25519-dalek (Rust) ---
extern "C" fn dalek_ed25519_sign(
    msg_ptr: [*]const u8,
    msg_len: usize,
    seed32: *const [32]u8,
    out_sig: *[64]u8,
) c_int;

extern "C" fn dalek_ed25519_verify(
    sig_ptr: *const [64]u8,
    msg_ptr: [*]const u8,
    msg_len: usize,
    pk32: *const [32]u8,
) c_int;

// --- Backend 3: libsodium ---
extern "sodium" fn crypto_sign_ed25519_detached(
    sig: *[64]u8,
    siglen_p: ?*u64,
    m: [*]const u8,
    mlen: u64,
    sk: *const [64]u8,
) c_int;

extern "sodium" fn crypto_sign_ed25519_verify_detached(
    sig: *const [64]u8,
    m: [*]const u8,
    mlen: u64,
    pk: *const [32]u8,
) c_int;

const RingCache = struct {
    seed: [32]u8,
    kp: *RingKeypair,
};

threadlocal var ring_cache: ?RingCache = null;

/// Sign `message` using a 64-byte Ed25519 expanded secret key.
/// Tries ring first (with threadlocal keypair cache), then dalek, then libsodium, then Zig std.
pub fn sign(message: []const u8, secret_key: *const [64]u8) ![64]u8 {
    if (config.enable_ring) {
        const seed = secret_key[0..32];
        if (ring_cache) |*cache| {
            if (!std.mem.eql(u8, &cache.seed, seed)) {
                ring_ed25519_keypair_free(cache.kp);
                const kp = ring_ed25519_keypair_new(seed) orelse return error.SignFailed;
                cache.* = .{ .seed = seed.*, .kp = kp };
            }
        } else {
            const kp = ring_ed25519_keypair_new(seed) orelse return error.SignFailed;
            ring_cache = .{ .seed = seed.*, .kp = kp };
        }
        var sig: [64]u8 = undefined;
        const rc = ring_ed25519_keypair_sign(ring_cache.?.kp, message.ptr, message.len, &sig);
        if (rc == 0) return sig;
    }

    if (config.enable_dalek) {
        var sig: [64]u8 = undefined;
        const seed = secret_key[0..32];
        const rc = dalek_ed25519_sign(message.ptr, message.len, seed, &sig);
        if (rc == 0) return sig;
    }

    if (config.enable_libsodium) {
        var sig: [64]u8 = undefined;
        const rc = crypto_sign_ed25519_detached(&sig, null, message.ptr, message.len, secret_key);
        if (rc == 0) return sig;
    }

    const sk = try std.crypto.sign.Ed25519.SecretKey.fromBytes(secret_key.*);
    const kp = try std.crypto.sign.Ed25519.KeyPair.fromSecretKey(sk);
    const sig = try kp.sign(message, null);
    return sig.toBytes();
}

/// Verify `signature` on `message` using a 32-byte Ed25519 public key.
/// Tries ring first, then dalek, then libsodium, then Zig std.
pub fn verify(signature: *const [64]u8, message: []const u8, pubkey: *const [32]u8) !void {
    if (config.enable_ring) {
        const rc = ring_ed25519_verify(signature, message.ptr, message.len, pubkey);
        if (rc == 0) return;
    }

    if (config.enable_dalek) {
        const rc = dalek_ed25519_verify(signature, message.ptr, message.len, pubkey);
        if (rc == 0) return;
    }

    if (config.enable_libsodium) {
        const rc = crypto_sign_ed25519_verify_detached(signature, message.ptr, message.len, pubkey);
        if (rc == 0) return;
    }

    const pk = try std.crypto.sign.Ed25519.PublicKey.fromBytes(pubkey.*);
    const sig = std.crypto.sign.Ed25519.Signature.fromBytes(signature.*);
    try sig.verify(message, pk);
}
