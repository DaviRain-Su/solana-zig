# Phase 5 - Test Spec

## Happy Path

| 测试场景 | 源文件 |
|----------|--------|
| base58 编解码 roundtrip | `src/solana/core/base58.zig` |
| pubkey base58 roundtrip | `src/solana/core/pubkey.zig` |
| keypair sign + verify | `src/solana/core/keypair.zig` |
| shortvec 编解码 roundtrip | `src/solana/core/shortvec.zig` |
| message compile + serialize + deserialize | `src/solana/tx/message.zig` |
| transaction sign + serialize + deserialize + verify | `src/solana/tx/transaction.zig` |

## Boundary

| 测试场景 | 边界值 | 源文件 |
|----------|--------|--------|
| shortvec 边界 | 0 / 1 / 127 / 128 / 255 / 16384 / 1_000_000 | `src/solana/core/shortvec.zig` |
| pubkey/signature/hash 固定长度校验 | 32 / 64 / 32 bytes | 各核心类型文件 |

## Error/Attack

| 测试场景 | 预期错误 | 源文件 |
|----------|----------|--------|
| base58 非法字符（0/O/I/l） | `error.InvalidBase58` | `src/solana/core/base58.zig` |
| shortvec 截断（末字节有续传标志） | `error.InvalidShortVec` | `src/solana/core/shortvec.zig` |
| shortvec 溢出 | `error.IntegerOverflow` | `src/solana/core/shortvec.zig` |
| 缺失必需签名 | `error.MissingRequiredSignature` | `src/solana/tx/transaction.zig` |
| 交易反序列化残留尾字节 | `error.TrailingData` | `src/solana/tx/transaction.zig` |
| RPC HTTP 失败（非 200） | `error.RpcTransport` | `src/solana/rpc/http_transport.zig` |
| RPC 响应含 error 字段 | `RpcResult.rpc_error` | `src/solana/rpc/client.zig` |

## Oracle

- **向量文件**：`testdata/oracle_vectors.json`
- **生成脚本**：`scripts/oracle/generate_vectors.rs`（依赖 solana-sdk 4.0.1）
- **当前覆盖**：
  - all-zeros pubkey base58 编码
  - shortvec(300) 编码
- **待补充**（见 08-evolution）：非零 pubkey、Keypair 签名向量、Message 序列化向量

## Integration

- 当环境变量 `SOLANA_RPC_URL` 存在时，执行 Devnet RPC 集成测试
- 覆盖：getLatestBlockhash / getBalance / getAccountInfo
- 不在 CI 默认路径中运行（需要网络访问）
