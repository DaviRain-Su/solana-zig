# Product Phase 3 Batch 2 Planning

**Date**: 2026-04-16
**Status**: In Review (`#68 P3-6`)
**Owner**: `#68`
**Depends on**: `docs/00-roadmap.md`, `docs/03a-interfaces-spec.md`, `docs/10-coverage-matrix.md`, `docs/14a-devnet-e2e-run-log.md`, `docs/15-phase1-execution-matrix.md`, `docs/30-phase3-batch1-planning.md`, `docs/31-phase3-batch1-release-readiness.md`

> Phase 3 Batch 2 继续 planning-first。本文过审前，Batch 2 实现提交保持冻结。

## 1. Objective

Batch 2 目标是“扩展 interfaces 覆盖面 + 收敛 Batch 1 carry-over exception”：
1. P3-07: ATA helper 最小可用（PDA 派生 + create ATA builder）
2. P3-08: 接口扩展（token-2022 / memo / stake）最小可用
3. P3-09: Batch 1 exception 收敛推进（requestAirdrop / getAddressLookupTable）

## 2. In Scope

### 2.1 P3-07 ATA helper
- `findAssociatedTokenAddress(owner, mint, token_program_id)`（PDA 派生）
- `buildCreateAssociatedTokenAccountInstruction(...)`
- 对应 byte layout / account metas / compile-sign 证据

### 2.2 P3-08 interface extension (minimum set)
- token-2022:
  - program id 常量与 builder program id 注入能力
  - `mint/approve/burn` 至少一组与 token 程序平行的构建证据
- memo:
  - `buildMemoInstruction(data)`
- stake:
  - `buildDelegateStakeInstruction(...)`（最小 builder）

### 2.3 P3-09 exception convergence (carry-over)
- `requestAirdrop`：
  - public devnet + local-live 双侧重试验证（最多 3 次，指数退避）
  - 三态机械判定：success / partial exception / not converged
- `getAddressLookupTable`：
  - 优先成功路径（public devnet 或 local-live 任一）
  - 若仍 method-not-found / RPC error，走 accepted exception path，但必须明确后续收敛批次与升级条件

## 3. Out of Scope

1. token-2022 全量指令族（仅最小 builder 集）
2. stake 完整生命周期（仅 delegate 最小 builder）
3. signer external adapter / C ABI（留在后续批次）

## 4. Write-set Freeze

### P3-07 ATA helper
- `src/solana/interfaces/token.zig`
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要 compile/test 引用）

### P3-08 interface extension
- `src/solana/interfaces/token.zig`
- `src/solana/interfaces/memo.zig`（若不存在则新建）
- `src/solana/interfaces/stake.zig`（若不存在则新建）
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要 compile/test 引用）

### P3-09 exception convergence
- `src/solana/rpc/client.zig`
- `src/solana/rpc/types.zig`（仅必要 typed parse/exception 结构最小触碰）
- `src/e2e/*`（仅证据收敛所需最小 harness 触碰）
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/33-phase3-batch2-release-readiness.md`

### Docs/Gate
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/README.md`

## 5. Artifact / Docs Landing Freeze

1. Batch 2 planning artifact：`docs/32-phase3-batch2-planning.md`
2. Batch 2 release/readiness artifact：`docs/33-phase3-batch2-release-readiness.md`
3. docs/gate reconciliation 固定覆盖：
   - `docs/06-implementation-log.md`
   - `docs/10-coverage-matrix.md`
   - `docs/14a-devnet-e2e-run-log.md`
   - `docs/15-phase1-execution-matrix.md`
   - `docs/33-phase3-batch2-release-readiness.md`

## 6. Gate / DoD

### G-P3B-01 canonical
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

### G-P3B-02 ATA helper
- PDA 派生结果可复现（owner/mint/program id 输入确定）
- create ATA builder 的 byte layout + account metas 证据齐
- 至少 1 条 compile/sign 证据

### G-P3B-03 interface extension
- token-2022/memo/stake 最小 builder 均落地
- 每类至少 1 条 byte layout + account metas 证据
- token-2022 与 legacy token program id 语义可机械区分

### G-P3B-04 exception convergence
- requestAirdrop 三态可机械判定（success / partial / not converged）
- getAddressLookupTable 成功路径或 accepted exception path 二选一
- 若保留 exception，必须落 `docs/15` 并写明后续收敛批次

### G-P3B-05 docs/gate reconciliation
必须回写并对账：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/33-phase3-batch2-release-readiness.md`

## 7. Dependency Rule

- P3-07 与 P3-08 可并行。
- P3-09 可并行推进，但 Batch 2 final verdict 必须建立在三线证据都到位后。
- 若 P3-09 存在未收敛 exception，Batch 2 verdict 只能是 `有条件发布` 或 `不可发布`。
