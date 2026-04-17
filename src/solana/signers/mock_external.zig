const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const signature_mod = @import("../core/signature.zig");
const signer_mod = @import("signer.zig");

pub const MockExternalSignerError = error{
    BackendFailure,
    Rejected,
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
            var mismatched = self.pubkey.bytes;
            mismatched[mismatched.len - 1] ^= 0xFF;
            return pubkey_mod.Pubkey.init(mismatched);
        }
        return self.pubkey;
    }

    fn signMessage(ctx: *anyopaque, _: std.mem.Allocator, msg: []const u8) anyerror!signature_mod.Signature {
        const self: *MockExternalSigner = @ptrCast(@alignCast(ctx));
        if (self.should_fail) {
            return signer_mod.SignerError.SignerBackendFailure;
        }
        if (self.should_reject) {
            return signer_mod.SignerError.SignerRejected;
        }
        const kp = try @import("../core/keypair.zig").Keypair.fromSeed(self.seed);
        return try kp.sign(msg);
    }

    fn deinit(_: *anyopaque, _: std.mem.Allocator) void {}
};

test "mock external signer happy path" {
    const gpa = std.testing.allocator;
    var signer = try MockExternalSigner.init([_]u8{21} ** 32);
    const s = signer.asSigner();

    const pk = try s.getPubkey();
    try std.testing.expect(pk.eql(signer.pubkey));

    const msg = "test";
    const sig = try s.signMessage(gpa, msg);
    try sig.verify(msg, pk);
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

test "mock external signer mismatch returns a different pubkey" {
    var signer = try MockExternalSigner.init([_]u8{24} ** 32);
    signer.should_mismatch = true;
    const s = signer.asSigner();

    const mismatched = try s.getPubkey();
    try std.testing.expect(!mismatched.eql(signer.pubkey));
}

test "mock external signer transaction path verifies signatures" {
    const gpa = std.testing.allocator;
    const instruction_mod = @import("../tx/instruction.zig");
    const message_mod = @import("../tx/message.zig");
    const transaction_mod = @import("../tx/transaction.zig");
    const hash_mod = @import("../core/hash.zig");

    var signer = try MockExternalSigner.init([_]u8{25} ** 32);
    const receiver = pubkey_mod.Pubkey.init([_]u8{26} ** 32);
    const program = pubkey_mod.Pubkey.init([_]u8{27} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{28} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = signer.pubkey, .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &[_]u8{0xCD} },
    };

    var msg = try message_mod.Message.compileLegacy(gpa, signer.pubkey, &ixs, blockhash);
    errdefer msg.deinit();

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();

    try tx.signWithSigners(&[_]signer_mod.Signer{signer.asSigner()});
    try tx.verifySignatures();
}

test "mock external signer mismatch leaves required signature missing" {
    const gpa = std.testing.allocator;
    const instruction_mod = @import("../tx/instruction.zig");
    const message_mod = @import("../tx/message.zig");
    const transaction_mod = @import("../tx/transaction.zig");
    const hash_mod = @import("../core/hash.zig");

    var signer = try MockExternalSigner.init([_]u8{29} ** 32);
    signer.should_mismatch = true;
    const receiver = pubkey_mod.Pubkey.init([_]u8{30} ** 32);
    const program = pubkey_mod.Pubkey.init([_]u8{31} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{32} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = signer.pubkey, .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &[_]u8{0xEF} },
    };

    var msg = try message_mod.Message.compileLegacy(gpa, signer.pubkey, &ixs, blockhash);
    errdefer msg.deinit();

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();

    try std.testing.expectError(
        signer_mod.SignerError.MissingRequiredSignature,
        tx.signWithSigners(&[_]signer_mod.Signer{signer.asSigner()}),
    );
}
