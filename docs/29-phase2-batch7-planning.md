# Product Phase 2 Batch 7 Planning

**Date**: 2026-04-16
**Status**: In Review (`#54 P2-31`)
**Owner**: `#54`
**Depends on**: `docs/00-roadmap.md`, `docs/10-coverage-matrix.md`, `docs/14a-devnet-e2e-run-log.md`, `docs/15-phase1-execution-matrix.md`, `docs/25-batch5-release-readiness.md`, `docs/27-batch6-release-readiness.md`, `docs/28-phase2-closeout-readiness.md`

> Batch 7 继续 planning-first。本文过审前，Batch 7 实现提交保持冻结。

## 1. Objective

Batch 7 目标是“收敛与落地”，不是新增功能扩散：
1. P2-32: Batch B RPC 方法主干化并补齐机械化 integration 口径
2. P2-33: Batch 5/6 双侧 smoke 缺口收敛，推动发布结论升级
3. P2-34: 产出 Phase 2 跨批次收口专属 artifact（不污染 `docs/25` / `docs/27`）

## 2. In Scope

### 2.1 P2-32: Batch B RPC landing + integration
- landing 范围：`getEpochInfo` / `getMinimumBalanceForRentExemption` / `requestAirdrop` / `getAddressLookupTable`
- 保留 typed parse + `happy/rpc_error/malformed` 三类测试
- landing 到 main 后必须补跑 canonical + integration 复核

### 2.2 P2-33: smoke closure (Batch 5/6)
- 补齐 `public devnet` + `local-live` 双侧 smoke
- 回写 `docs/14a` / `docs/15` / `docs/25` / `docs/27`

### 2.3 P2-34: Phase 2 closeout artifact
- 维护 `docs/28-phase2-closeout-readiness.md`
- 输出 Phase 2 聚合 verdict 与升级条件

## 3. Out of Scope

1. 新增第 5 个 Batch B 之外 RPC 方法
2. websocket 新 transport 家族
3. CI 平台迁移或发布通道策略重构

## 4. Write-set Freeze

### P2-32
- `src/solana/rpc/client.zig`
- `src/solana/rpc/types.zig`
- `src/solana/rpc/*` 中仅与 Batch B 4 方法相关的测试写集
- 合并约束：仅允许 `0070fa8` 承载的 Batch B 范围写集进入本批

### P2-33
- `scripts/release/preflight_batch5.sh`
- `scripts/release/preflight_batch6.sh`
- `src/e2e/*`（仅 smoke harness 最小触碰）
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/25-batch5-release-readiness.md`
- `docs/27-batch6-release-readiness.md`

### P2-34
- `docs/28-phase2-closeout-readiness.md`
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/README.md`

## 5. Gate / DoD

### G-P2G-01 canonical
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

### G-P2G-02 Batch B landing（机械规则）
- `getEpochInfo`：默认要求 public devnet integration 成功证据
- `getMinimumBalanceForRentExemption`：默认要求 public devnet integration 成功证据
- `requestAirdrop`：public devnet 或 local-live 至少一侧成功；缺另一侧需登记 Batch 7 exception
- `getAddressLookupTable`：允许 RPC error evidence 例外路径（含 method-not-found）；必须登记 Batch 7 exception 与后续收敛阶段
- landing 到 main 后必须重跑：canonical 三件套 + 方法级 integration 复核

### G-P2G-03 smoke closure
- 双侧 smoke（public devnet + local-live）均需可复现
- 任一缺失必须登记 Batch 7 exception，且不得判 `可发布`

### G-P2G-04 phase2 closeout artifact
- `docs/28` 必须包含：
  - Batch 5/6 来源 verdict
  - exception 汇总状态
  - Phase 2 aggregate verdict 及升级条件

### G-P2G-05 docs/gate reconciliation
必须回写并对账：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/25-batch5-release-readiness.md`
- `docs/27-batch6-release-readiness.md`
- `docs/28-phase2-closeout-readiness.md`

## 6. Dependency Rule (P2-33 -> P2-34)

`P2-34` final phase verdict 只能建立在 `P2-33` 完成后：
- 若 `P2-33` 仍有未收敛 smoke exception，Phase 2 final verdict 只能是 `有条件发布` 或 `不可发布`。

