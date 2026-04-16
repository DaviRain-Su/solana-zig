# Phase 3 - Technical Spec

## Byte Contracts

| 类型 | 大小 | 说明 |
|------|------|------|
| `Pubkey` | 32 bytes | Ed25519 公钥 |
| `Signature` | 64 bytes | Ed25519 签名 |
| `Hash` | 32 bytes | SHA-256 摘要（用于 blockhash 等） |
| `shortvec` | 1-3 bytes | 7-bit continuation varint，每字节低 7 位为数据，最高位为续传标志 |

### shortvec 编码细节
- 单字节最大值：`127`（0x7f）
- 双字节最大值：`16383`（0x3fff）
- 溢出保护：shift 超过 `@bitSizeOf(usize)` 时返回 `error.IntegerOverflow`
- 截断输入（最后一字节仍有续传标志）返回 `error.InvalidShortVec`

## Message Contracts

### Header 结构
```
MessageHeader {
    num_required_signatures: u8,
    num_readonly_signed_accounts: u8,
    num_readonly_unsigned_accounts: u8,
}
```

### Legacy Message 序列化布局
```
header (3 bytes)
+ shortvec(account_keys.len) + account_keys (32 * len)
+ recent_blockhash (32 bytes)
+ shortvec(instructions.len) + instructions[...]
```

### V0 Message 序列化布局
```
0x80 前缀字节（版本标识：byte & 0x7f == 0 表示 v0）
+ legacy body（同上）
+ shortvec(address_table_lookups.len) + lookups[...]
```

反序列化时：首字节 `>= 0x80` 为 versioned message，`< 0x80` 为 legacy message。

### CompiledInstruction 布局
```
program_id_index: u8
+ shortvec(accounts.len) + accounts (u8[])
+ shortvec(data.len) + data (u8[])
```

## Transaction Contracts
- signatures: `shortvec(len) + Signature(64) * len`
- message bytes 为签名的 payload（签名覆盖完整的序列化 message）
- 签名算法：`std.crypto.sign.Ed25519`

## RPC Contracts
- JSON-RPC 2.0 envelope（`jsonrpc: "2.0"`, `id`, `method`, `params`）
- 非 200 HTTP 状态码视为 `error.RpcTransport`
- 响应中 `error` 字段存在时返回 `RpcResult.rpc_error`（保留 code/message/data_json）
- 响应中 `result` 字段存在时返回 `RpcResult.ok(T)`

## State Machine
```
Draft -> CompiledMessage -> SignedTx -> SerializedTx -> Submitted
         (compileLegacy/     (sign)     (serialize)     (sendTransaction)
          compileV0)
```

## Defaults
- RPC commitment: `confirmed`
- send/simulate encoding: `base64`
