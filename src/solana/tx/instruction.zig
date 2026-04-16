const pubkey_mod = @import("../core/pubkey.zig");

pub const AccountMeta = struct {
    pubkey: pubkey_mod.Pubkey,
    is_signer: bool,
    is_writable: bool,
};

pub const Instruction = struct {
    program_id: pubkey_mod.Pubkey,
    accounts: []const AccountMeta,
    data: []const u8,
};
