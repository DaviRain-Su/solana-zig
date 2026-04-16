# Product Phase 3 Batch 4 Planning

**Date**: 2026-04-17
**Status**: In Review (`#78 P3-16`)
**Owner**: `#78`
**Freeze point**: `e3a3794`
**Depends on**: `docs/00-roadmap.md`, `docs/03b-signers-spec.md`, `docs/03d-cabi-spec.md`, `docs/13-benchmark-baseline-spec.md`, `docs/35-phase3-batch3-release-readiness.md`

> Phase 3 Batch 4 继续 planning-first。本文过审前，Batch 4 实现提交保持冻结。

## 1. Objective

Batch 4 目标是“补齐 Phase 3 剩余主交付，并给出 verdict 升级评估输入”：
1. P3-17：signers 最小可用闭环（抽象 + in-memory + mock external + tx 接入）
2. P3-18：C ABI 最小闭环（核心导出 + 所有权/错误码 + header 一致性）
3. P3-19：benchmark 扩展（signers + C ABI）与 verdict 升级评估

## 2. In Scope

### 2.1 P3-17 Signers minimum
- `Signer` 抽象与最小 vtable 形状落地
- `InMemorySigner` 与现有 Keypair 路径行为兼容
- `MockExternalSigner` 的拒签/后端错误语义透传
- `VersionedTransaction` 的 signer 抽象接入（含缺失 required signer 错误）
- 至少 1 组 compile/sign + verify 证据

### 2.2 P3-18 C ABI minimum
- `solana_zig.h` 最小导出集（value types + transaction/rpc 最小入口）
- 稳定错误码与 ownership/free 约定最小闭环
- `abi_version` 查询能力与头文件版本宏一致
- 至少 1 组 C 调用闭环证据（create/use/free）

### 2.3 P3-19 Benchmark & Verdict-upgrade evaluation
- 扩展 benchmark 基线：signers 路径 + C ABI 路径
- 在 strict exception model 下输出 Batch 4 verdict-upgrade 判定输入：
  - 若仍存在 `partial exception` / `accepted exception path`，不得升级为 `可发布`
  - 若无未收敛 exception 且 gates 全 PASS，才可评估升级

## 3. Out of Scope

1. 外部 KMS/HSM 真实接入（仅 mock/stub）
2. C ABI 全量接口暴露（仅最小闭环）
3. 新增 RPC 方法族或 websocket 能力扩展
4. Phase 4（on-chain/SBF）相关内容

## 4. Write-set Freeze

### P3-17 Signers
- `src/solana/signers/*`
- `src/solana/transaction.zig`（仅 signer 接入最小触碰）
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要测试触点）

### P3-18 C ABI
- `src/solana/cabi/*`
- `include/solana_zig.h`
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要测试触点）

### P3-19 Benchmark & Verdict
- `src/benchmark.zig`
- `docs/13a-benchmark-baseline-results.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/37-phase3-batch4-release-readiness.md`

### Docs/Gate
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/35-phase3-batch3-release-readiness.md`（仅条件回写）
- `docs/37-phase3-batch4-release-readiness.md`
- `docs/README.md`
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

### G-P3D-02 signers minimum
- `Signer` 抽象 + in-memory + mock external 落地
- 至少 1 组 required signer 匹配/缺失错误机械证据
- 至少 1 条 compile/sign + verify 证据

### G-P3D-03 C ABI minimum
- 最小导出能力可调用（value/tx/rpc 至少一组）
- ownership/free 规则机械可复现
- 头文件与导出符号一致性证据

### G-P3D-04 benchmark + verdict-upgrade input
- signer/C ABI benchmark 基线已扩展并留档
- strict exception model 判定输入完整
- 明确输出本批 verdict-upgrade 结论

### G-P3D-05 docs/gate reconciliation
必须回写并对账：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/13a-benchmark-baseline-results.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/37-phase3-batch4-release-readiness.md`
- 条件触发：`docs/35-phase3-batch3-release-readiness.md`, `docs/28-phase2-closeout-readiness.md`

## 8. Dependency Rule

- P3-17 与 P3-18 可并行。
- P3-19 可并行推进，但 Batch 4 final verdict 必须建立在三线证据都到位后。
- 若仍存在 `partial exception` 或 `accepted exception path`，Batch 4 verdict 只能是 `有条件发布` 或 `不可发布`。
