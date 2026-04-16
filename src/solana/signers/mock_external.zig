const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const signature_mod = @import("../core/signature.zig");
const signer_mod = @import("signer.zig");

pub const MockExternalSignerError = error{
    BackendFailure,
    Rejected,
    PubkeyMismatch,
};

/// Mock external signer for testing remote signing scenarios.
pub const MockExternalSigner = struct {
    pubkey: pubkey_mod.Pubkey,
    seed: [32]u8,
    should_fail: bool = false,
    should_reject: bool = false,
    should_mismatch: bool = false,

    pub fn init(seed: [32]u8) !MockExternalSigner {
        const kp = try @import("../core/keypair.zig").Keypair.fromSeed(seed);
        return .{
            .pubkey = kp.pubkey(),
            .seed = seed,
        };
    }

    pub fn asSigner(self: *MockExternalSigner) signer_mod.Signer {
        return .{
            .ctx = self,
            .get_pubkey_fn = getPubkey,
            .sign_message_fn = signMessage,
            .deinit_fn = deinit,
        };
    }

    fn getPubkey(ctx: *anyopaque) anyerror!pubkey_mod.Pubkey {
        const self: *MockExternalSigner = @ptrCast(@alignCast(ctx));
        if (self.should_mismatch) {
            return signer_mod.SignerError.SignerBackendFailure;
        }
        return self.pubkey;
    }

    fn signMessage(ctx: *anyopaque, _: std.mem.Allocator, _: []const u8) anyerror!signature_mod.Signature {
        const self: *MockExternalSigner = @ptrCast(@alignCast(ctx));
        if (self.should_fail) {
            return signer_mod.SignerError.SignerBackendFailure;
        }
        if (self.should_reject) {
            return signer_mod.SignerError.SignerRejected;
        }
        const kp = try @import("../core/keypair.zig").Keypair.fromSeed(self.seed);
        return try kp.sign("");
    }

    fn deinit(_: *anyopaque, _: std.mem.Allocator) void {}
};

test "mock external signer happy path" {
    const gpa = std.testing.allocator;
    var signer = try MockExternalSigner.init([_]u8{21} ** 32);
    const s = signer.asSigner();

    const pk = try s.getPubkey();
    _ = pk;
    const sig = try s.signMessage(gpa, "test");
    _ = sig;
}

test "mock external signer backend failure" {
    var signer = try MockExternalSigner.init([_]u8{22} ** 32);
    signer.should_fail = true;
    const s = signer.asSigner();

    try std.testing.expectError(signer_mod.SignerError.SignerBackendFailure, s.signMessage(std.testing.allocator, "test"));
}

test "mock external signer rejected" {
    var signer = try MockExternalSigner.init([_]u8{23} ** 32);
    signer.should_reject = true;
    const s = signer.asSigner();

    try std.testing.expectError(signer_mod.SignerError.SignerRejected, s.signMessage(std.testing.allocator, "test"));
}
