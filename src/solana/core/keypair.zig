const std = @import("std");
const pubkey_mod = @import("pubkey.zig");
const signature_mod = @import("signature.zig");

pub const Keypair = struct {
    ed25519: std.crypto.sign.Ed25519.KeyPair,

    pub fn fromSeed(seed: [32]u8) !Keypair {
        return .{ .ed25519 = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed) };
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

test "keypair deterministic sign" {
    const seed = [_]u8{9} ** 32;
    const kp = try Keypair.fromSeed(seed);

    const msg = "solana-zig";
    const sig = try kp.sign(msg);
    try kp.verify(msg, sig);
}
