const std = @import("std");
const keypair_mod = @import("../core/keypair.zig");
const pubkey_mod = @import("../core/pubkey.zig");
const signature_mod = @import("../core/signature.zig");
const signer_mod = @import("signer.zig");

/// In-memory signer wrapping an existing Keypair.
pub const InMemorySigner = struct {
    keypair: keypair_mod.Keypair,

    pub fn init(keypair: keypair_mod.Keypair) InMemorySigner {
        return .{ .keypair = keypair };
    }

    pub fn asSigner(self: *InMemorySigner) signer_mod.Signer {
        return .{
            .ctx = self,
            .get_pubkey_fn = getPubkey,
            .sign_message_fn = signMessage,
            .deinit_fn = deinit,
        };
    }

    fn getPubkey(ctx: *anyopaque) anyerror!pubkey_mod.Pubkey {
        const self: *InMemorySigner = @ptrCast(@alignCast(ctx));
        return self.keypair.pubkey();
    }

    fn signMessage(ctx: *anyopaque, _: std.mem.Allocator, msg: []const u8) anyerror!signature_mod.Signature {
        const self: *InMemorySigner = @ptrCast(@alignCast(ctx));
        return try self.keypair.sign(msg);
    }

    fn deinit(_: *anyopaque, _: std.mem.Allocator) void {}
};

test "in-memory signer produces same signature as keypair" {
    const gpa = std.testing.allocator;
    const kp = try keypair_mod.Keypair.fromSeed([_]u8{11} ** 32);
    var signer = InMemorySigner.init(kp);
    const s = signer.asSigner();

    const pk = try s.getPubkey();
    try std.testing.expect(kp.pubkey().eql(pk));

    const msg = "hello solana";
    const sig = try s.signMessage(gpa, msg);
    const direct_sig = try kp.sign(msg);
    try std.testing.expectEqualSlices(u8, &direct_sig.bytes, &sig.bytes);
}

test "in-memory signer verifies its own signature" {
    const gpa = std.testing.allocator;
    const kp = try keypair_mod.Keypair.fromSeed([_]u8{12} ** 32);
    var signer = InMemorySigner.init(kp);
    const s = signer.asSigner();

    const msg = "verify me";
    const sig = try s.signMessage(gpa, msg);
    try sig.verify(msg, try s.getPubkey());
}
