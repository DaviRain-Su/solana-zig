const std = @import("std");
const pubkey_mod = @import("pubkey.zig");
const signature_mod = @import("signature.zig");

pub const Keypair = struct {
    pub const SEED_LENGTH = std.crypto.sign.Ed25519.KeyPair.seed_length;
    pub const SECRET_KEY_LENGTH = std.crypto.sign.Ed25519.SecretKey.encoded_length;

    ed25519: std.crypto.sign.Ed25519.KeyPair,

    pub fn generate(io: std.Io) Keypair {
        return .{ .ed25519 = std.crypto.sign.Ed25519.KeyPair.generate(io) };
    }

    pub fn fromSeed(seed: [SEED_LENGTH]u8) !Keypair {
        return .{ .ed25519 = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed) };
    }

    pub fn fromSecretKey(secret_key_bytes: [SECRET_KEY_LENGTH]u8) !Keypair {
        const secret_key = try std.crypto.sign.Ed25519.SecretKey.fromBytes(secret_key_bytes);
        return .{ .ed25519 = try std.crypto.sign.Ed25519.KeyPair.fromSecretKey(secret_key) };
    }

    pub fn pubkey(self: Keypair) pubkey_mod.Pubkey {
        return .{ .bytes = self.ed25519.public_key.toBytes() };
    }

    pub fn sign(self: Keypair, msg: []const u8) !signature_mod.Signature {
        const sig = try self.ed25519.sign(msg, null);
        return .{ .bytes = sig.toBytes() };
    }

    pub fn verify(self: Keypair, msg: []const u8, signature: signature_mod.Signature) !void {
        try signature.verify(msg, self.pubkey());
    }
};

test "keypair random generation signs and verifies" {
    const kp = Keypair.generate(std.testing.io);

    const msg = "solana-zig-random";
    const sig = try kp.sign(msg);

    try kp.verify(msg, sig);
    try sig.verify(msg, kp.pubkey());
}

test "keypair deterministic sign" {
    const seed = [_]u8{9} ** 32;
    const kp = try Keypair.fromSeed(seed);

    const msg = "solana-zig";
    const sig = try kp.sign(msg);
    try kp.verify(msg, sig);
}

test "keypair recovers from 64-byte secret key" {
    const seed = [_]u8{7} ** Keypair.SEED_LENGTH;
    const original = try Keypair.fromSeed(seed);
    const recovered = try Keypair.fromSecretKey(original.ed25519.secret_key.toBytes());

    try std.testing.expect(original.pubkey().eql(recovered.pubkey()));

    const msg = "solana-zig-recovered";
    const sig = try recovered.sign(msg);
    try sig.verify(msg, original.pubkey());
}

test "keypair rejects mismatched 64-byte secret key" {
    const seed = [_]u8{5} ** Keypair.SEED_LENGTH;
    const keypair = try Keypair.fromSeed(seed);
    var secret_key_bytes = keypair.ed25519.secret_key.toBytes();
    secret_key_bytes[Keypair.SECRET_KEY_LENGTH - 1] ^= 1;

    try std.testing.expectError(error.NonCanonical, Keypair.fromSecretKey(secret_key_bytes));
}
