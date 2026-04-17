# Product Phase 3 Batch 4 Planning

**Date**: 2026-04-17
**Status**: In Review (`#78 P3-16`)
**Owner**: `#78`
**Freeze point**: `e3a3794`
**Depends on**: `docs/00-roadmap.md`, `docs/03b-signers-spec.md`, `docs/03d-cabi-spec.md`, `docs/13-benchmark-baseline-spec.md`, `docs/35-phase3-batch3-release-readiness.md`

> Phase 3 Batch 4 继续 planning-first。本文过审前，Batch 4 实现提交保持冻结。

## 1. Objective

Batch 4 目标是“把 Phase 3 从主体已实现推进到 correctness/contract/documentation closeout”：
1. P3-17：signers correctness closure（重点是 `MockExternalSigner`）
2. P3-18：stake lifecycle contract closure（重点是 create helper 契约与负路径证据）
3. P3-19：C ABI reality alignment（surface / header / tests / RPC story）
4. P3-20：repo status/docs reconciliation + follow-up task freeze

## 2. In Scope

### 2.1 P3-17 Signers correctness closure
- 保持 `Signer` / `InMemorySigner` / `signWithSigners(...)` 现有能力不回退
- 修复 `MockExternalSigner.signMessage(...)` 对输入消息的签名语义
- 明确 `pubkey mismatch` 的错误语义与测试路径
- 提供至少 1 组 mock signer transaction-level compile/sign/verify 或明确失败证据

### 2.2 P3-18 Stake lifecycle contract closure
- 对齐 `buildCreateStakeAccountInstruction(...)` 的 API 名称、参数、文档与实际行为
- 保持 `delegate/deactivate/withdraw` 的现有 builder 证据
- 补齐至少一组 stake lifecycle 负路径测试（非法参数 / authority 问题 / contract misuse）

### 2.3 P3-19 C ABI reality alignment
- 明确首版 C ABI 哪些 surface 是“真实可用”，哪些只是 lifecycle scaffold
- 对齐 `include/solana_zig.h`、`src/solana/cabi/*.zig` 与文档中的能力声明
- 至少提供 1 组稳定的仓内 C compile/integration 证据
- 若保留 RPC export，则需明确是真实 transport 还是显式 dummy/stub；不得两种口径混用

### 2.4 P3-20 Repo status / docs reconciliation
- 统一 `README.md`、`docs/00-roadmap.md`、`docs/07-review-report.md`、`docs/10-coverage-matrix.md`
- 冻结“哪些文档是权威状态源”：
  - 状态真相：`docs/10`
  - planning：`docs/36`
  - readiness/gate：`docs/37`
  - narrative log：`docs/06`
  - operator pointer：`notes/project-state.md`

## 3. Out of Scope

1. 外部 KMS/HSM 真实接入（仍仅 mock/stub）
2. C ABI 全量接口暴露（只做首版 reality alignment，不追求 full surface）
3. 新增 RPC 方法族或 websocket 能力扩展
4. Phase 4（on-chain/SBF）相关内容
5. Rust SDK 升级或新的 oracle 向量批次

## 4. Write-set Freeze

### P3-17 Signers
- `src/solana/signers/*`
- `src/solana/tx/transaction.zig`
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要测试触点）

### P3-18 Stake
- `src/solana/interfaces/stake.zig`
- `docs/17-quickstart-and-api-examples.md`
- `docs/03a-interfaces-spec.md`（仅必要口径回写）

### P3-19 C ABI
- `src/solana/cabi/*`
- `include/solana_zig.h`
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要测试触点）

### Docs/Gate
- `README.md`
- `docs/00-roadmap.md`
- `docs/06-implementation-log.md`
- `docs/07-review-report.md`
- `docs/10-coverage-matrix.md`
- `docs/17-quickstart-and-api-examples.md`
- `docs/37-phase3-batch4-release-readiness.md`
- `notes/project-state.md`
- `MEMORY.md`
- `docs/35-phase3-batch3-release-readiness.md`（仅条件回写）
- `docs/28-phase2-closeout-readiness.md`（仅条件触发）

## 5. Carry-in Baseline Governance

- Batch 4 carry-in baseline freeze point 锁定为 `e3a3794`（含该提交及其之前主线）。
- 仅 `<=e3a3794` 的既有变更计入 Batch 4 carry-in baseline。
- freeze point 之后新增提交仅视为 carry-in **candidate**，不自动计入本批；除非后续任务明确重锁 freeze point。
- Batch 4 新增交付只计本批任务线新增实现与证据。

## 6. Artifact / Docs Landing Freeze

1. Batch 4 planning artifact：`docs/36-phase3-batch4-planning.md`
2. Batch 4 release/readiness artifact：`docs/37-phase3-batch4-release-readiness.md`
3. docs/gate reconciliation 固定覆盖：
   - `docs/06-implementation-log.md`
   - `docs/10-coverage-matrix.md`
   - `docs/13a-benchmark-baseline-results.md`
   - `docs/14a-devnet-e2e-run-log.md`
   - `docs/15-phase1-execution-matrix.md`
   - `docs/37-phase3-batch4-release-readiness.md`
4. 条件性回写：
   - 若 Batch 4 影响 Batch 3 verdict，回写 `docs/35-phase3-batch3-release-readiness.md`
   - 若 Batch 4 关闭了 `docs/28` 的 carry-over exception，再回写 `docs/28-phase2-closeout-readiness.md`

## 7. Gate / DoD

### G-P3D-01 canonical
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

### G-P3D-02 signers correctness closure
- `MockExternalSigner` 正确签名输入消息，或其受限语义被清晰降级并文档化
- `pubkey mismatch` / reject / backend failure 均有机械证据
- 不回退现有 `Signer` / `InMemorySigner` / `signWithSigners(...)` 能力

### G-P3D-03 stake lifecycle contract closure
- create helper 的 API/实现/文档口径一致
- `delegate/deactivate/withdraw` 现有证据保持通过
- 至少 1 组负路径测试证据

### G-P3D-04 C ABI reality alignment
- 头文件、导出实现、文档三者口径一致
- 至少 1 组稳定 C compile/integration 证据
- RPC surface 的真实能力边界明确，不再混用“可用/占位”表述

### G-P3D-05 docs/gate reconciliation
必须回写并对账：
- `README.md`
- `docs/00-roadmap.md`
- `docs/06-implementation-log.md`
- `docs/07-review-report.md`
- `docs/10-coverage-matrix.md`
- `docs/17-quickstart-and-api-examples.md`
- `docs/37-phase3-batch4-release-readiness.md`
- `notes/project-state.md`
- `MEMORY.md`
- 条件触发：`docs/35-phase3-batch3-release-readiness.md`, `docs/28-phase2-closeout-readiness.md`

## 8. Dependency Rule

- P3-17 / P3-18 / P3-19 可并行。
- P3-20 必须建立在前三线复核结论之上，再统一回写文档。
- 若仍存在 `partial exception` 或 `accepted exception path`，Batch 4 verdict 只能是 `有条件发布` 或 `不可发布`。
