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
    pub const MessageAddressTableLookup = message.MessageAddressTableLookup;
    pub const VersionedTransaction = transaction.VersionedTransaction;
};

pub const rpc = struct {
    pub const types = @import("rpc/types.zig");
    pub const transport = @import("rpc/transport.zig");
    pub const http_transport = @import("rpc/http_transport.zig");
    pub const client = @import("rpc/client.zig");
    pub const ws_client = @import("rpc/ws_client.zig");

    pub const RpcClient = client.RpcClient;
    pub const RpcRetryConfig = types.RpcRetryConfig;
    pub const Transport = transport.Transport;
    pub const Commitment = types.Commitment;
    pub const OwnedJson = types.OwnedJson;
    pub const WsClient = ws_client.WsClient;
    pub const WsRpcClient = ws_client.WsRpcClient;
};

pub const interfaces = struct {
    pub const system = @import("interfaces/system.zig");
    pub const compute_budget = @import("interfaces/compute_budget.zig");
    pub const token = @import("interfaces/token.zig");
    pub const token_2022 = @import("interfaces/token_2022.zig");
    pub const memo = @import("interfaces/memo.zig");
    pub const ata = @import("interfaces/ata.zig");
    pub const stake = @import("interfaces/stake.zig");
};

pub const signers = struct {
    pub const Signer = @import("signers/signer.zig").Signer;
    pub const SignerError = @import("signers/signer.zig").SignerError;
    pub const InMemorySigner = @import("signers/in_memory.zig").InMemorySigner;
    pub const MockExternalSigner = @import("signers/mock_external.zig").MockExternalSigner;
};

pub const cabi = struct {
    pub const core = @import("cabi/core.zig");
    pub const transaction = @import("cabi/transaction.zig");
    pub const rpc = @import("cabi/rpc.zig");
    pub const errors = @import("cabi/errors.zig");
};

pub const compat = struct {
    pub const oracle_vector = @import("compat/oracle_vector.zig");
    pub const bincode_compat = @import("compat/bincode_compat.zig");
};
