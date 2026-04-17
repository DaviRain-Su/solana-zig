# solana-zig 全面重写路线图

**目标**：用 Zig 全面重写 Solana Rust SDK 的链下客户端能力，最终提供与 Rust SDK 行为兼容的完整 Zig SDK。

**基线版本**：Solana Rust SDK 4.0.1（拆分后 crate 体系）

**设计原则**：
- 行为兼容优先于 API 命名兼容
- 优先 Zig std，默认不引入外部依赖；如确有必要，仅允许最小外部依赖并需显式 ADR 记录
- 显式内存管理（allocator 参数模式）
- 每个 Product Phase 独立可交付、独立可测试

## 命名约定

- **Product Phase**：指本路线图中的产品阶段，统一使用 `Phase 1 ~ Phase 4`。
- **Milestone（M）**：仅用于当前 `Phase 1` 的执行节点，统一使用 `M1 ~ M3`。
- **文档序号 `docs/01-08`**：表示文档生命周期顺序（PRD / Architecture / Spec / Task / Test / Log / Review / Evolution），**不等于** Product Phase 编号。

---

## Phase 1 — 链下客户端核心（✅ 已完成）

> 详见 [01-prd.md](./01-prd.md) 和 [prd-phase-1-solana-zig-sdk.md](./prd-phase-1-solana-zig-sdk.md)

**交付物**：
- 核心类型：`Pubkey / Signature / Keypair / Hash` + `base58 / shortvec`
- 交易构建：`Instruction / AccountMeta / Message (legacy + v0) / VersionedTransaction`
- 高频 RPC（5 个）：`getLatestBlockhash / getAccountInfo / getBalance / simulateTransaction / sendTransaction`
- Oracle 向量验证 + Devnet E2E + Benchmark 基线

---

## Phase 2 — RPC 扩展 + 实时订阅（✅ 已完成）

**目标**：覆盖生产环境常用的 RPC 方法，支持 Websocket 实时订阅。

**交付物**：
- 扩展 RPC 方法（11 个）：
  - `getTransaction` / `getSignaturesForAddress` / `getTokenAccountsByOwner`
  - `getSlot` / `getEpochInfo` / `getMinimumBalanceForRentExemption`
  - `requestAirdrop`（测试用）
  - `getAddressLookupTable`（补齐 ALT 管理能力）
  - `getTokenAccountBalance` / `getTokenSupply`
  - `getSignatureStatuses`
- RPC 统一重试策略：exponential backoff + rate limit 感知
- Websocket 订阅（7 种）：
  - `accountSubscribe` / `programSubscribe` / `signatureSubscribe`
  - `slotSubscribe` / `rootSubscribe` / `logsSubscribe` / `blockSubscribe`
  - 订阅生命周期管理（connect / reconnect / unsubscribe / resubscribe）
  - 生产级硬化：heartbeat、deterministic backoff、dedup ring buffer、WsStats 可观测性
- Durable Nonce 支持：
  - Nonce 账户查询 + Nonce Advance 指令构建
  - 离线签名工作流 + E2E 验证
- Priority Fees / Compute Budget 指令构建：
  - `SetComputeUnitLimit` / `SetComputeUnitPrice`

**验证**：
- 每个新 RPC 方法有 mock 单元测试 + Devnet 集成测试
- Websocket 订阅有连接/断线/重连/去重/可观测性测试
- Nonce E2E 完整流程（create → query → advance → send → confirm）

---

## Phase 3 — Interfaces + Signers + C ABI（✅ 已完成）

**目标**：提供 Token 等高频接口层抽象、可插拔 signer 后端，并暴露 C ABI 供其他语言调用。

**交付物**：
- Interfaces：
  - `system`（Transfer / CreateAccount / AdvanceNonceAccount / Assign）
  - `token`（TransferChecked / CloseAccount / MintTo / Approve / Burn）
  - `token_2022`（Mint / Approve / Burn + program-id 区分）
  - `compute_budget`（SetComputeUnitLimit / SetComputeUnitPrice）
  - `memo`（dual-mode: signer / no-signer）
  - `stake`（Create / Delegate / Deactivate / Withdraw）
  - `ata`（Associated Token Account: find + create builder）
- Signers：
  - `Signer` vtable 抽象
  - `InMemorySigner`（内存签名）
  - `MockExternalSigner`（模拟外部拒签/错误语义）
- C ABI 导出层：
  - 核心类型 + 交易构建 + RPC 的 C 函数接口
  - 头文件生成（`include/solana_zig.h`）
  - 内存所有权约定文档（`docs/cabi-guide.md`）
- Benchmark 扩展：signer + C ABI 基线

**当前状态（2026-04-17 Phase 3 closeout）**：
- 全部 7 个 interface 模块已交付：system / token / token_2022 / compute_budget / memo / stake / ata
- Signer 抽象已交付：Signer vtable + InMemorySigner + MockExternalSigner
- C ABI 导出层已交付：core + transaction + RPC（live transport）
- 头文件 `include/solana_zig.h` 已生成并一致
- Rust baseline 对比完成（Run 3：signer 3.35x slower, base58 14.61x slower）
- Batch 1-5 全部 gate PASS，239/239 tests PASS
- Phase 3 verdict: `有条件发布`（2 open exceptions: requestAirdrop partial, getAddressLookupTable accepted）

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

## 交付跟踪文档

- 总索引：`docs/README.md`
- 一致性审查：`docs/09-doc-consistency-checklist.md`
- 能力覆盖矩阵：`docs/10-coverage-matrix.md`
- Phase 1 收口清单：`docs/11-phase1-closeout-checklist.md`
- Oracle 向量扩展计划：`docs/12-oracle-vector-expansion-plan.md`
- Benchmark 基线规范：`docs/13-benchmark-baseline-spec.md`
- Benchmark 结果模板：`docs/13a-benchmark-baseline-results.md`
- Devnet E2E 验收说明：`docs/14-devnet-e2e-acceptance.md`
- Devnet E2E 运行记录模板：`docs/14a-devnet-e2e-run-log.md`
- Phase 1 执行矩阵：`docs/15-phase1-execution-matrix.md`
- 用户 / 安全说明：`docs/16-consumer-profiles-and-security-notes.md`
- 子规格：
  - `docs/03a-interfaces-spec.md`
  - `docs/03b-signers-spec.md`
  - `docs/03c-rpc-extended-spec.md`
  - `docs/03d-cabi-spec.md`
- ADR：
  - `docs/adr/README.md`
  - `docs/adr/ADR-template.md`

## 横切关注点（贯穿所有 Phase）

| 关注点 | 策略 |
|--------|------|
| 版本兼容 | 每次 Rust SDK 版本升级时 oracle 向量回归 |
| 测试覆盖 | oracle 向量 + 单元测试 + Devnet E2E + CI 自动化 |
| 内存安全 | `std.testing.allocator` leak 检测覆盖所有测试 |
| 性能追踪 | 每 Phase 更新 benchmark 基线 |
| 文档 | API 文档 + 迁移指南 + 示例代码 + 覆盖矩阵维护 |
