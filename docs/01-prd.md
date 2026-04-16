# Phase 1 - PRD

## Goal
使用 Zig 重写 Solana Rust SDK 4.0.1 的链下客户端关键能力，优先保证行为兼容。

## In Scope
- `Pubkey/Signature/Keypair/Instruction/Message/VersionedTransaction`
- 高频 RPC：`getLatestBlockhash/getAccountInfo/getBalance/simulateTransaction/sendTransaction`
- Devnet 端到端发送交易示例与测试入口

## Out of Scope
- 链上程序运行时语义（no_std/SBF）
- 首发覆盖全部低频 RPC

## Audience
- Zig 客户端开发者
- 需要从 Rust SDK 迁移的团队

## Success Metrics
- 字节级编解码测试通过
- oracle 向量一致
- Devnet E2E（有网络和 RPC URL 时）通过

## Risks
- Rust 版本演进导致行为变化
- Zig 与 Rust 标准库在序列化细节上的差异
- RPC 端点返回结构差异
