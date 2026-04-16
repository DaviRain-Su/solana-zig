const pubkey_mod = @import("../core/pubkey.zig");

pub const LookupEntry = struct {
    index: u8,
    pubkey: pubkey_mod.Pubkey,
};

pub const AddressLookupTable = struct {
    account_key: pubkey_mod.Pubkey,
    writable: []const LookupEntry,
    readonly: []const LookupEntry,
};
