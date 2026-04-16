# Phase 1 PRD — 链下客户端核心

> 本文档是 [solana-zig 顶层路线图](./00-roadmap.md) 的 Phase 1 子 PRD。

**基线版本：Solana Rust SDK 4.0.1**

> **参考 crate 说明**：Solana SDK 自 v2.x 起进行了 crate 拆分重组。本项目锚定的 `4.0.1` 指拆分后的版本体系。实际参考的核心 crate 包括：
> - `solana-pubkey` / `solana-signature` / `solana-keypair` — 核心类型
> - `solana-transaction` / `solana-message` — 交易构建
> - `solana-rpc-client` — RPC 客户端
>
> 后续版本升级时需同步更新 oracle 向量生成脚本中的依赖版本。

## Goal
使用 Zig 重写 Solana Rust SDK 4.0.1 的链下客户端关键能力，优先保证行为兼容。

## In Scope
- **核心类型**：`Pubkey/Signature/Keypair/Hash` + 编码（base58/shortvec）
- **交易构建**：`Instruction/AccountMeta/Message(legacy+v0)/VersionedTransaction`
- **高频 RPC**：`getLatestBlockhash/getAccountInfo/getBalance/simulateTransaction/sendTransaction`
- **测试基础设施**：oracle 向量生成脚本 + Devnet E2E 入口

## Out of Scope（Phase 1）
- 链上程序运行时语义（no_std/SBF）→ 见路线图 Phase 4
- 首发覆盖全部低频 RPC → 见路线图 Phase 2
- Token Program / Associated Token Account 等上层抽象 → 见路线图 Phase 3
- Websocket 订阅 → 见路线图 Phase 2
- C ABI 导出 → 见路线图 Phase 3

## Audience
- **Zig 客户端开发者**：构建 DApp、自动化交易脚本、链下工具
- **从 Rust SDK 迁移的团队**：需要在 Zig 生态中保持与 Rust SDK 行为一致的交易构建与提交能力
- **嵌入式/系统级场景**：IoT 设备、硬件钱包等资源受限环境（Zig zero-overhead + 无 GC）
- **C FFI 消费者**：其他语言通过 C ABI 调用 Solana 功能（Phase 3 导出）
- **性能敏感场景**：MEV 搜索者、做市商等延迟敏感系统

## Success Metrics
- 字节级编解码测试通过（base58/shortvec/message/transaction roundtrip）
- oracle 向量一致（Zig 输出 == Rust SDK 4.0.1 输出），**最低覆盖**：
  - 非零 pubkey（含前导零场景）
  - Keypair sign -> Signature（确定性种子）
  - Legacy message serialize（多 instruction）
  - V0 message serialize（含 ALT）
  - 完整 Transaction serialize（签名 + message）
- Devnet E2E（有网络和 `SOLANA_RPC_URL` 时）通过
- `std.testing.allocator` 全量测试无内存泄漏
- *(基线)* 序列化/反序列化吞吐量 benchmark 建立（不要求优于 Rust，但需记录数据供后续对比）

## Risks

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| Rust SDK 版本演进导致行为变化 | 中 | 高 | 锚定 4.0.1 基线，版本升级时 oracle 向量回归 |
| Zig 与 Rust 在序列化细节上的差异 | 低 | 高 | 字节级 oracle 向量对照 |
| RPC 端点返回结构差异 | 低 | 中 | 动态 JSON 解析 + 后续增加 typed schema |
| Oracle 向量覆盖不足导致隐蔽兼容性问题 | 中 | 高 | Phase 1 完成前补齐上述最低向量集 |
