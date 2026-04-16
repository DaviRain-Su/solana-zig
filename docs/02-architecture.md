# Phase 2 - Architecture

## Module Graph
- `core -> tx -> rpc`
- `compat` 仅用于测试和对照，不进入生产路径

## Package Layout
- `src/solana/core/*`
- `src/solana/tx/*`
- `src/solana/rpc/*`
- `src/solana/compat/*`

## Error Strategy
- 编解码/签名/消息交易错误使用统一错误集
- RPC 错误保留 `code/message/data_json`

## Feature Flags (planned)
- `full` default
- `rpc`
- `devnet-integration-tests`
