pub const SolanaError = error{
    InvalidBase58,
    InvalidLength,
    InvalidCharacter,
    InvalidShortVec,
    IntegerOverflow,
    MissingAccountKey,
    MissingProgramId,
    MissingPayer,
    MissingRecentBlockhash,
    TooManyAccounts,
    DuplicateLookupKey,
    UnsupportedMessageVersion,
    InvalidMessage,
    InvalidTransaction,
    SignatureCountMismatch,
    MissingRequiredSignature,
    InvalidRpcResponse,
    RpcTransport,
    RpcTimeout,
    RpcParse,
};

pub const RpcErrorObject = struct {
    code: i64,
    message: []const u8,
    data_json: ?[]const u8 = null,
};

pub fn RpcResult(comptime T: type) type {
    return union(enum) {
        ok: T,
        rpc_error: RpcErrorObject,
    };
}
