# PRD: Phase 3 Batch 3 — Solana Zig SDK Signers、C ABI 与 Stake 完整生命周期

> **Status: REVIEWED (2026-04-17) — PARTIALLY IMPLEMENTED** — 经代码与文档复核，Signer / C ABI / Stake 主体能力已落地，但 PRD 级验收仍有若干缺口未完全闭环。

## Overview

Phase 3 Batch 3 是 Phase 3 的收尾批次，目标是将剩余的核心交付物全部落地：统一 signer 抽象层（解耦交易构建与签名后端）、C ABI 导出层（让非 Zig 语言安全调用最小 Solana 能力）、Stake 程序完整生命周期 builder，以及对应的 benchmark 和文档收口。完成后，Phase 3 的全部 roadmap 目标（interfaces + signers + C ABI）即告达成。

## Goals

- 实现统一 signer 抽象层，支持 in-memory signer 和 mock external signer
- 让 `VersionedTransaction` 正式接入 signer 抽象，保留现有 `Keypair` 便捷路径
- 实现 C ABI 导出层首版，覆盖核心类型、交易构建、RPC 客户端最小能力
- 提供 `solana_zig.h` 头文件，并明确内存所有权与释放约定
- 实现 Stake 程序完整生命周期 builder（create / delegate / deactivate / withdraw）
- 扩展 benchmark 基线，覆盖 signer 签名与 C ABI 调用开销
- 产出 C ABI 使用指南，更新 API 示例文档与覆盖矩阵

## Implementation Review Snapshot (2026-04-17)

| Story | Review status | Evidence | Remaining gap |
|---|---|---|---|
| US-019 Signer 统一接口定义 | done | `src/solana/signers/signer.zig` | — |
| US-020 In-memory Signer 适配 | done | `src/solana/signers/in_memory.zig` + `src/solana/tx/transaction.zig` 已覆盖 signer-path/keypair-path 等价性，且已有 legacy 多签顺序无关证据 | — |
| US-021 Mock External Signer | partial | 已覆盖 backend failure / rejected | `signMessage(...)` 当前忽略输入消息且 `pubkey mismatch` 语义未独立闭环 |
| US-022 Transaction 接入 Signer 抽象 | done | `signWithSigners(...)` 已落地，缺签错误已覆盖 | — |
| US-023 C ABI 核心类型导出 | partial | `src/solana/cabi/core.zig` + `include/solana_zig.h` 已导出 pubkey/signature/hash 基本能力 | `hash compare` 未导出；仓内仍缺稳定的 C 侧集成测试工件 |
| US-024 C ABI 交易构建导出 | done | `src/solana/cabi/transaction.zig` 已覆盖 instruction → message → transaction → serialize 闭环 | — |
| US-025 C ABI RPC 客户端最小导出 | partial | `src/solana/cabi/rpc.zig` 已导出 init/deinit/getLatestBlockhash/getBalance | 当前 RPC handle 仍绑定 dummy transport，C 侧无法直接完成真实链查询 |
| US-026 Stake 完整生命周期 Builder | partial | `src/solana/interfaces/stake.zig` 已实现 create/delegate/deactivate/withdraw | 负路径仍以最小布局校验为主，未补齐非法参数/缺失 authority 断言 |
| US-027 Signer 与 C ABI 性能 Benchmark | done | `zig build bench` 已输出 `signer_in_memory_sign` / `cabi_pubkey_to_base58` | — |
| US-028 Phase 3 文档收口 | done | 已有 `docs/17`、`docs/cabi-guide.md`、`docs/10`、`docs/06` | 本次复核已把“已实现/未闭环”边界显式写回文档 |

### Review Conclusion

- 结论：该 PRD 所列范围并非“全部完成”，当前更准确的状态是“主体能力已实现，但验收闭环仍有剩余缺口”。
- 优先级最高的剩余项：
  1. `MockExternalSigner` 的消息签名正确性与 `pubkey mismatch` 语义；
  2. C ABI 的 live RPC transport / C 侧集成测试 / header-surface 补齐；
  3. stake create helper 的 API/实现契约对齐与负路径测试补齐。

## Quality Gates

These commands must pass for every user story:
- `zig build test` — 全量单元测试 + 内存泄漏检测
- `zig build bench` — benchmark 基线运行，确保数据不衰退且新增项有输出

For signer / RPC / C ABI / E2E stories, also include:
- `zig build devnet-e2e` — Devnet 端到端验收（需配置 `SOLANA_RPC_URL`）
- `zig build e2e` — Surfpool 本地 E2E 验收

For C ABI stories, also include:
- C ABI 头文件一致性检查 — `solana_zig.h` 与导出符号一致（通过 C 编译测试或脚本验证）

## User Stories

### US-019: Signer 统一接口定义
As a Zig 开发者, I want 统一的 signer 抽象接口 so that 交易构建与签名后端解耦。

**Acceptance Criteria:**
- [ ] 定义 `Signer` vtable 结构（至少包含 `get_pubkey_fn`、`sign_message_fn`、`deinit_fn`）
- [ ] 在 `src/solana/signers/` 新建模块目录并落地 `signer.zig`
- [ ] 定义 signer 相关错误枚举（`MissingRequiredSignature`、`SignerUnavailable`、`SignerBackendFailure`、`SignerRejected`、`UnsupportedSignerOperation`、`SignatureCountMismatch`）
- [ ] `zig build test` 编译通过

### US-020: In-memory Signer 适配
As a Zig 开发者, I want 基于现有 `Keypair` 的 in-memory signer so that 现有签名行为与 signer 抽象兼容。

**Acceptance Criteria:**
- [ ] 提供 `InMemorySigner` 实现，包装现有 `Keypair`
- [ ] 行为与现有 `VersionedTransaction.sign(keypairs)` 等价
- [ ] 单元测试覆盖单 signer、多 signer 签名，并与现有 keypair 路径结果一致

### US-021: Mock External Signer
As a Zig 开发者, I want mock 外部 signer adapter so that 远程签名场景可测试。

**Acceptance Criteria:**
- [ ] 提供 `MockExternalSigner` 实现
- [ ] 支持模拟后端失败、拒签、pubkey 不匹配等错误场景
- [ ] 单元测试覆盖错误语义透传（后端失败映射到 `SignerBackendFailure`，拒签映射到 `SignerRejected`）

### US-022: Transaction 接入 Signer 抽象
As a Zig 开发者, I want `VersionedTransaction` 支持 signer 抽象签名 so that 可插拔 signer 后端可用。

**Acceptance Criteria:**
- [ ] 在 `VersionedTransaction` 上新增 `signWithSigners(signers: []const Signer) !void`
- [ ] 保留现有 `sign(keypairs)` 便捷 API，内部可复用 `signWithSigners`
- [ ] 单元测试覆盖 signer 切换对交易序列化无副作用
- [ ] 错误路径测试覆盖缺失 required signer 时返回 `MissingRequiredSignature`

### US-023: C ABI 核心类型导出
As a C 开发者, I want 使用 C 语言调用 Solana Zig SDK 核心类型 so that 可集成到非 Zig 项目。

**Acceptance Criteria:**
- [ ] 导出 `solana_pubkey_*`、`solana_signature_*`、`solana_hash_*` 系列函数（创建、转换、比较、释放）
- [ ] 提供 `include/solana_zig.h` 头文件
- [ ] 单元测试/C 编译测试覆盖创建 / 调用 / 销毁闭环
- [ ] 所有堆分配输出必须提供对等的 `free` / `destroy` API

### US-024: C ABI 交易构建导出
As a C 开发者, I want 通过 C ABI 构建和序列化交易 so that 非 Zig 语言可发起交易。

**Acceptance Criteria:**
- [ ] 导出 `solana_instruction_*`、`solana_message_*`、`solana_transaction_*` 系列函数
- [ ] 支持从 C 侧构造 instruction、编译 message、创建 transaction、签名、序列化
- [ ] 明确所有权：谁分配谁提供释放函数
- [ ] 单元测试覆盖完整构建流程（instruction -> message -> transaction -> serialize）

### US-025: C ABI RPC 客户端最小导出
As a C 开发者, I want 通过 C ABI 调用最小 RPC 能力 so that 可查询链上数据。

**Acceptance Criteria:**
- [ ] 导出 `solana_rpc_client_*` 系列函数（init、deinit、getLatestBlockhash、getBalance）
- [ ] 返回稳定整数错误码（`SOLANA_OK = 0`、`SOLANA_ERR_INVALID_ARGUMENT`、`SOLANA_ERR_RPC_TRANSPORT`、`SOLANA_ERR_RPC_PARSE`、`SOLANA_ERR_BACKEND_FAILURE`、`SOLANA_ERR_INTERNAL`）
- [ ] 单元测试覆盖成功和错误路径
- [ ] 提供 `solana_string_free` 等配套释放函数

### US-026: Stake 完整生命周期 Builder
As a Zig 开发者, I want 构建 Stake 程序完整生命周期指令 so that 可进行质押操作。

**Acceptance Criteria:**
- [ ] 在 `src/solana/interfaces/stake.zig` 新建模块
- [ ] 实现 `buildCreateStakeAccountInstruction`、`buildDelegateStakeInstruction`、`buildDeactivateStakeInstruction`、`buildWithdrawStakeInstruction`
- [ ] 覆盖账户顺序、授权角色、字节布局与 Rust SDK 对齐
- [ ] 单元测试覆盖 happy 路径和错误路径（非法参数、缺失 authority）

### US-027: Signer 与 C ABI 性能 Benchmark
As a 维护者, I want 扩展 benchmark 覆盖 signer 和 C ABI 路径 so that 可与 Rust SDK 进行性能对比。

**Acceptance Criteria:**
- [ ] 新增 in-memory signer 签名 benchmark（单消息签名吞吐）
- [ ] 新增 C ABI 调用开销 benchmark（如 `solana_pubkey_to_base58` 往返）
- [ ] 输出 ns/op 或 ops/sec 指标
- [ ] `zig build bench` 包含新增项且运行成功

### US-028: Phase 3 文档收口
As a Zig 开发者, I want Phase 3 新增能力的完整文档 so that 可快速集成 signer、C ABI 和新增 interfaces。

**Acceptance Criteria:**
- [ ] 更新 `docs/17-quickstart-and-api-examples.md`，补充 signer 使用示例和 C ABI 最小示例
- [ ] 新建 `docs/cabi-guide.md`，包含 C ABI 使用指南、内存所有权约定、错误码说明
- [ ] 更新 `docs/10-coverage-matrix.md`，标记 Phase 3 全部能力为已完成
- [ ] 更新 `docs/06-implementation-log.md`，记录 Batch 3 交付项与 commit hash

## Functional Requirements

- FR-09: 必须实现统一 signer 抽象（vtable 风格），支持 in-memory 和 mock external 后端
- FR-10: `VersionedTransaction` 必须同时支持 `sign(keypairs)` 和 `signWithSigners(signers)`
- FR-11: C ABI 必须导出核心类型、交易构建、RPC 客户端的最小可用能力
- FR-12: C ABI 必须提供 `solana_zig.h` 头文件和稳定的整数错误码体系
- FR-13: 必须实现 Stake 程序的 `createStakeAccount`、`delegateStake`、`deactivateStake`、`withdrawStake` builder
- FR-14: `zig build bench` 必须覆盖 signer 签名和 C ABI 调用开销的量化性能指标
- FR-15: 必须产出 C ABI 使用指南并更新 API 示例文档
- FR-16: 必须更新覆盖矩阵与实现日志，完成 Phase 3 文档收口

## Non-Goals (Out of Scope)

- 真实 KMS/HSM 后端集成（仅提供 mock/stub 接口）
- 异步 signer 接口（保持同步阻塞模式）
- 在 C ABI 首版中暴露全部内部 Zig 类型
- WebAssembly 绑定
- Phase 4 链上程序支持（SBF / no_std）评估与实现
- token-2022 扩展指令族的完整覆盖（保持 Batch 2 的最小 builder 集）

## Technical Considerations

- **模块依赖方向**: `core → tx → rpc → ws → interfaces → signers → cabi`，禁止反向依赖
- **Zig 版本**: 0.16.0
- **C ABI 所有权模型**: 采用 opaque handle + 显式 free 模式；谁分配谁提供释放函数
- **Signer 敏感数据**: in-memory signer 尽量缩短 secret material 生命周期，优先采用显式 zeroization（若 Zig std 支持）
- **Stake 对齐**: 账户顺序、discriminant、data layout 必须与 Solana Rust SDK 4.0.1 一致
- **头文件策略**: 首版集中在 `include/solana_zig.h`，opaque handle 使用前置声明

## Success Metrics

- `zig build test` 全量通过，零内存泄漏
- signer 抽象有完整的 mock 单元测试覆盖（happy / boundary / error）
- C ABI 通过 C 编译测试或头文件一致性检查
- `zig build bench` 输出 signer 和 C ABI 的量化性能指标
- Stake builder 的 4 条指令均有单元测试证据
- 文档（`cabi-guide.md`、quickstart）完整可用并同步到代码仓库

## Open Questions

- C ABI 的 `last error message` 是否采用 thread-local storage、全局静态缓冲，还是 caller-provided buffer？
- 外部 signer 的 C ABI 暴露是否仅限制为 opaque handle，不在首版暴露 vtable 细节？
- Stake builder 是否需要同时支持 `Lockup` 和 `Authorized` 的完整可选字段，还是首版只支持最小必填参数？
- benchmark 是否需要引入 Rust SDK 的对比 harness，还是仅记录本项目的 ns/op 基线？