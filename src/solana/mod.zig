pub const errors = @import("errors.zig");

pub const core = struct {
    pub const base58 = @import("core/base58.zig");
    pub const shortvec = @import("core/shortvec.zig");
    pub const pubkey = @import("core/pubkey.zig");
    pub const signature = @import("core/signature.zig");
    pub const keypair = @import("core/keypair.zig");
    pub const hash = @import("core/hash.zig");

    pub const Pubkey = pubkey.Pubkey;
    pub const Signature = signature.Signature;
    pub const Keypair = keypair.Keypair;
    pub const Hash = hash.Hash;
};

pub const tx = struct {
    pub const instruction = @import("tx/instruction.zig");
    pub const address_lookup_table = @import("tx/address_lookup_table.zig");
    pub const message = @import("tx/message.zig");
    pub const transaction = @import("tx/transaction.zig");

    pub const AccountMeta = instruction.AccountMeta;
    pub const Instruction = instruction.Instruction;
    pub const AddressLookupTable = address_lookup_table.AddressLookupTable;
    pub const Message = message.Message;
    pub const VersionedTransaction = transaction.VersionedTransaction;
};

pub const rpc = struct {
    pub const types = @import("rpc/types.zig");
    pub const transport = @import("rpc/transport.zig");
    pub const http_transport = @import("rpc/http_transport.zig");
    pub const client = @import("rpc/client.zig");
    pub const ws_client = @import("rpc/ws_client.zig");

    pub const RpcClient = client.RpcClient;
    pub const Transport = transport.Transport;
    pub const OwnedJson = types.OwnedJson;
    pub const WsClient = ws_client.WsClient;
    pub const WsRpcClient = ws_client.WsRpcClient;
};

pub const compat = struct {
    pub const oracle_vector = @import("compat/oracle_vector.zig");
    pub const bincode_compat = @import("compat/bincode_compat.zig");
};
