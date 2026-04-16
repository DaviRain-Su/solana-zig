# Product Phase 3 Batch 3 Planning

**Date**: 2026-04-17
**Status**: In Review (`#73 P3-11`)
**Owner**: `#73`
**Freeze point**: `243ba7f`
**Depends on**: `docs/00-roadmap.md`, `docs/03a-interfaces-spec.md`, `docs/10-coverage-matrix.md`, `docs/14a-devnet-e2e-run-log.md`, `docs/15-phase1-execution-matrix.md`, `docs/32-phase3-batch2-planning.md`, `docs/33-phase3-batch2-release-readiness.md`

> Phase 3 Batch 3 继续 planning-first。本文过审前，Batch 3 实现提交保持冻结。

## 1. Objective

Batch 3 目标是“补齐 Phase 3 interfaces 延后项 + 继续收敛 Batch 2 条件发布原因”：
1. P3-12: token-2022 最小 builder 能力
2. P3-13: stake delegate 最小 builder 能力
3. P3-14: exception convergence 继续推进（`requestAirdrop` / `getAddressLookupTable`）与 verdict-upgrade 评估

## 2. In Scope

### 2.1 P3-12 token-2022 (minimum)
- token-2022 program id 常量与 builder program id 机械区分能力
- 至少 1 组与 legacy token 平行的最小 builder 证据（含 byte layout/account metas）
- 至少 1 条 compile/sign 证据

### 2.2 P3-13 stake delegate (minimum)
- `buildDelegateStakeInstruction(...)` 最小 builder
- account metas 顺序与 signer/writable 约束证据
- 至少 1 条 compile/sign 证据

### 2.3 P3-14 exception convergence (carry-over)
- `requestAirdrop`：
  - 继续按 strict tri-state 机械判定（success / partial exception / not converged）
  - 尝试将 partial exception 从“可接受”推进到“可关闭”
- `getAddressLookupTable`：
  - 优先获得可复现成功路径（public devnet 或 local-live）
  - 若仍 method-not-found / RPC error，仅允许 accepted exception path，并需明确下一轮收敛条件
- 产出 Batch 3 verdict-upgrade 结论（能否从 `有条件发布` 升级）

## 3. Out of Scope

1. token-2022 全量指令族（仅最小 builder）
2. stake 完整生命周期（仅 delegate 最小 builder）
3. signer external adapter / C ABI（后续批次）

## 4. Write-set Freeze

### P3-12 token-2022
- `src/solana/interfaces/token_2022.zig`（若不存在则新建）
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要 compile/test 引用）

### P3-13 stake delegate
- `src/solana/interfaces/stake.zig`
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要 compile/test 引用）

### P3-14 exception convergence
- `src/solana/rpc/client.zig`
- `src/solana/rpc/types.zig`（仅必要 typed parse/exception 结构最小触碰）
- `src/e2e/*`（仅证据收敛所需最小 harness 触碰）
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/35-phase3-batch3-release-readiness.md`

### Docs/Gate
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/README.md`
- `docs/35-phase3-batch3-release-readiness.md`
- `docs/28-phase2-closeout-readiness.md`（仅条件触发）

## 5. Carry-in Baseline Governance

- Batch 3 carry-in baseline freeze point 锁定为 `243ba7f`（含该提交及其之前主线）。
- 仅 `<=243ba7f` 的 `feat: US-*` 提交计入 Batch 3 carry-in baseline（当前固定为 US-001..US-009）。
- freeze point 之后新增的 `feat: US-*` 提交仅视为 carry-in **candidate**，不自动计入本批；除非后续任务明确重锁 freeze point。
- Batch 3 新增交付只计本批任务线新增实现与证据。

## 6. Artifact / Docs Landing Freeze

1. Batch 3 planning artifact：`docs/34-phase3-batch3-planning.md`
2. Batch 3 release/readiness artifact：`docs/35-phase3-batch3-release-readiness.md`
3. docs/gate reconciliation 固定覆盖：
   - `docs/06-implementation-log.md`
   - `docs/10-coverage-matrix.md`
   - `docs/14a-devnet-e2e-run-log.md`
   - `docs/15-phase1-execution-matrix.md`
   - `docs/35-phase3-batch3-release-readiness.md`
4. phase-level artifact 条件回写：
   - 若 `P3-14` 关闭影响 `docs/28` 的 carry-over exception，才触发 `docs/28-phase2-closeout-readiness.md` 回写。

## 7. Gate / DoD

### G-P3C-01 canonical
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

### G-P3C-02 token-2022 minimum
- token-2022 builder 最小能力落地
- 至少 1 组 byte layout + account metas 证据
- token-2022 与 legacy token program id 可机械区分
- 至少 1 条 compile/sign 证据

### G-P3C-03 stake delegate minimum
- `buildDelegateStakeInstruction` 落地
- 至少 1 组 byte layout + account metas 证据
- 至少 1 条 compile/sign 证据

### G-P3C-04 exception convergence
- `requestAirdrop` strict tri-state 可机械复现
- `getAddressLookupTable` 成功路径或 accepted exception path 二选一
- 若仍保留 exception，必须在 `docs/15` 写明原因与下一轮收敛条件
- 输出明确 verdict-upgrade 判定（是否可从 `有条件发布` 升级）

### G-P3C-05 docs/gate reconciliation
必须回写并对账：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/35-phase3-batch3-release-readiness.md`
- 条件触发：`docs/28-phase2-closeout-readiness.md`

## 8. Dependency Rule

- P3-12 与 P3-13 可并行。
- P3-14 可并行推进，但 Batch 3 final verdict 必须建立在三线证据都到位后。
- 若 P3-14 仍存在未收敛 exception，Batch 3 verdict 只能是 `有条件发布` 或 `不可发布`。
