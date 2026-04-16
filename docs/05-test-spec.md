# Phase 5 - Test Spec

## Happy Path
- base58/pubkey roundtrip
- keypair sign + verify
- message compile + serialize + deserialize
- transaction sign + serialize + deserialize + verify

## Boundary
- shortvec: 0/127/128/16384
- pubkey/signature/hash 固定长度校验

## Error/Attack
- base58 非法字符
- shortvec 截断
- 缺失必需签名
- 交易反序列化残留尾字节
- RPC 非法响应结构

## Oracle
- `testdata/oracle_vectors.json`
- 对照 pubkey/base58 与 shortvec(300)

## Integration
- 当 `SOLANA_RPC_URL` 提供时，执行 Devnet 相关 RPC 集成测试
