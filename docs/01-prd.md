# Phase 1 - PRD

**基线版本：Solana Rust SDK 4.0.1**

## Goal
使用 Zig 重写 Solana Rust SDK 4.0.1 的链下客户端关键能力，优先保证行为兼容。

## In Scope
- **核心类型**：`Pubkey/Signature/Keypair/Hash` + 编码（base58/shortvec）
- **交易构建**：`Instruction/AccountMeta/Message(legacy+v0)/VersionedTransaction`
- **高频 RPC**：`getLatestBlockhash/getAccountInfo/getBalance/simulateTransaction/sendTransaction`
- **测试基础设施**：oracle 向量生成脚本 + Devnet E2E 入口

## Out of Scope
- 链上程序运行时语义（no_std/SBF）
- 首发覆盖全部低频 RPC
- Token Program / Associated Token Account 等上层抽象

## Audience
- **Zig 客户端开发者**：构建 DApp、自动化交易脚本、链下工具
- **从 Rust SDK 迁移的团队**：需要在 Zig 生态中保持与 Rust SDK 行为一致的交易构建与提交能力

## Success Metrics
- 字节级编解码测试通过（base58/shortvec/message/transaction roundtrip）
- oracle 向量一致（Zig 输出 == Rust SDK 4.0.1 输出）
- Devnet E2E（有网络和 `SOLANA_RPC_URL` 时）通过

## Risks

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| Rust SDK 版本演进导致行为变化 | 中 | 高 | 锚定 4.0.1 基线，版本升级时 oracle 向量回归 |
| Zig 与 Rust 在序列化细节上的差异 | 低 | 高 | 字节级 oracle 向量对照 |
| RPC 端点返回结构差异 | 低 | 中 | 动态 JSON 解析 + 后续增加 typed schema |
