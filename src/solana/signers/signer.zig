const std = @import("std");
const pubkey_mod = @import("../core/pubkey.zig");
const signature_mod = @import("../core/signature.zig");

pub const SignerError = error{
    MissingRequiredSignature,
    SignerUnavailable,
    SignerBackendFailure,
    SignerRejected,
    UnsupportedSignerOperation,
    SignatureCountMismatch,
};

/// Unified signer abstraction.
/// Decouples transaction construction from signing backends.
pub const Signer = struct {
    ctx: *anyopaque,
    get_pubkey_fn: *const fn (ctx: *anyopaque) anyerror!pubkey_mod.Pubkey,
    sign_message_fn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, msg: []const u8) anyerror!signature_mod.Signature,
    deinit_fn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,

    pub fn getPubkey(self: Signer) !pubkey_mod.Pubkey {
        return self.get_pubkey_fn(self.ctx);
    }

    pub fn signMessage(self: Signer, allocator: std.mem.Allocator, msg: []const u8) !signature_mod.Signature {
        return self.sign_message_fn(self.ctx, allocator, msg);
    }

    pub fn deinit(self: Signer, allocator: std.mem.Allocator) void {
        self.deinit_fn(self.ctx, allocator);
    }
};
