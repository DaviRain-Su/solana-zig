# solana-zig 全面重写路线图

**目标**：用 Zig 全面重写 Solana Rust SDK 的链下客户端能力，最终提供与 Rust SDK 行为兼容的完整 Zig SDK。

**基线版本**：Solana Rust SDK 4.0.1（拆分后 crate 体系）

**设计原则**：
- 行为兼容优先于 API 命名兼容
- Zero external dependencies（仅依赖 Zig std）
- 显式内存管理（allocator 参数模式）
- 每 Phase 独立可交付、独立可测试

---

## Phase 1 — 链下客户端核心 ✅ 基本完成

> 详见 [01-prd.md](./01-prd.md)

**交付物**：
- 核心类型：`Pubkey / Signature / Keypair / Hash` + `base58 / shortvec`
- 交易构建：`Instruction / Message (legacy + v0) / VersionedTransaction`
- 高频 RPC（5 个）：`getLatestBlockhash / getAccountInfo / getBalance / simulateTransaction / sendTransaction`
- Oracle 向量验证 + Devnet E2E

**待补齐**（Phase 1 收尾）：
- [ ] Oracle 向量扩充（非零 pubkey、Keypair 签名、Message/Transaction 序列化）
- [ ] `std.testing.allocator` 系统性 leak 检测
- [ ] RPC 高频响应 typed schema（至少 `LatestBlockhash`、`AccountInfo`）
- [ ] 序列化性能 benchmark 基线

---

## Phase 2 — RPC 扩展 + 实时订阅

**目标**：覆盖生产环境常用的 RPC 方法，支持 Websocket 实时订阅。

**交付物**：
- 扩展 RPC 方法（按使用频率）：
  - `getTransaction` / `getSignaturesForAddress` / `getTokenAccountsByOwner`
  - `getSlot` / `getEpochInfo` / `getMinimumBalanceForRentExemption`
  - `requestAirdrop`（测试用）
  - `getAddressLookupTable`（补齐 ALT 管理能力）
- Websocket 订阅：
  - `accountSubscribe` / `logsSubscribe` / `signatureSubscribe`
  - 订阅生命周期管理（connect / reconnect / unsubscribe）
- Durable Nonce 支持：
  - Nonce 账户查询 + Nonce Advance 指令构建
  - 离线签名工作流
- Priority Fees / Compute Budget 指令构建

**验证**：
- 每个新 RPC 方法有 mock 单元测试 + Devnet 集成测试
- Websocket 订阅有连接/断线/重连测试

---

## Phase 3 — 上层抽象 + C ABI

**目标**：提供 Token 程序等高频上层抽象，暴露 C ABI 供其他语言调用。

**交付物**：
- SPL Token Program 交互：
  - `createMint` / `mintTo` / `transfer` / `approve` / `burn`
  - Associated Token Account (ATA) 自动创建
  - Token-2022 扩展支持
- Stake Program 基础操作：
  - `createStakeAccount` / `delegate` / `deactivate` / `withdraw`
- C ABI 导出层：
  - 核心类型 + 交易构建 + RPC 的 C 函数接口
  - 头文件生成（`solana_zig.h`）
  - 内存所有权约定文档
- 性能对比报告（vs Rust SDK）

---

## Phase 4 — 链上程序支持（独立评估）

> **前置条件**：Zig 交叉编译到 SBF 目标的可行性验证

**评估项**：
- Zig -> SBF 交叉编译工具链
- `no_std` 约束下的 Zig std 子集
- 链上程序 entrypoint 约定
- 账户数据序列化（Borsh 兼容）

**预期产出**：独立 `solana-program-zig` 包，与本项目分离生命周期。

---

## 横切关注点（贯穿所有 Phase）

| 关注点 | 策略 |
|--------|------|
| 版本兼容 | 每次 Rust SDK 版本升级时 oracle 向量回归 |
| 测试覆盖 | oracle 向量 + 单元测试 + Devnet E2E + CI 自动化 |
| 内存安全 | `std.testing.allocator` leak 检测覆盖所有测试 |
| 性能追踪 | 每 Phase 更新 benchmark 基线 |
| 文档 | API 文档 + 迁移指南 + 示例代码 |
