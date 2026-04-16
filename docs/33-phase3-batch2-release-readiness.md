# Phase 3 Batch 2 Release Readiness

**Date**: 2026-04-16
**Status**: Provisional
**Owner**: `#68`（后续由 Batch 2 docs/gate 线收口）
**Batch**: Phase 3 Batch 2

> 本文件是 Phase 3 Batch 2 专属 release/readiness 产物。  
> 不覆盖 `docs/31-phase3-batch1-release-readiness.md` 与 `docs/28-phase2-closeout-readiness.md`。

## 1. Checklist（最小固定项）

1. Build/Test 结果（canonical）
2. ATA helper 证据（PDA 派生 + create ATA builder）
3. Interface extension 证据（token-2022 / memo / stake 最小 builder）
4. Exception convergence 证据（`requestAirdrop` / `getAddressLookupTable`）
5. 文档一致性（`docs/06` / `docs/10` / `docs/14a` / `docs/15`）
6. 发布判定（`可发布` / `有条件发布` / `不可发布`）

## 2. Frozen Exception Rule（Batch 2）

### 2.1 requestAirdrop
- 默认成功路径：public devnet 或 local-live 至少一侧成功。
- 若 public devnet rate-limit：
  - 可判 `partial exception`，但必须同时具备 local-live success 证据。
  - 必须登记到 `docs/15`（含原因、重试信息、后续收敛计划）。
- 若两侧均失败或无可复现成功证据：判未收敛 exception。

### 2.2 getAddressLookupTable
- 优先目标：提供可复现成功路径（public devnet 或 local-live 任一）。
- 若持续 method-not-found / RPC error：
  - 可走 accepted exception path（RPC error evidence）。
  - 必须登记到 `docs/15`，并明确后续收敛阶段（Phase 3 后续批次）。

## 3. Current Snapshot

- Canonical（G-P3B-01）：`PENDING`
- ATA helper（G-P3B-02）：`PENDING`
- Interface extension（G-P3B-03）：`PENDING`
- Exception convergence（G-P3B-04）：`PENDING`
- Docs/Gate（G-P3B-05）：`PENDING`
- Batch 2 verdict：`provisional: 有条件发布`

## 4. Upgrade Rule

仅当以下条件全部满足时，Batch 2 verdict 才允许升级为 `可发布`：
1. `G-P3B-01~G-P3B-05` 全部 PASS；
2. 无未收敛 Batch 2 exception；
3. 若存在 partial/accepted exception，已满足 frozen rule 且明确不影响本批 gate。

## 5. Evidence Landing

- 运行证据：`docs/14a-devnet-e2e-run-log.md`
- exception 登记：`docs/15-phase1-execution-matrix.md`
- implementation/gate 汇总：`docs/06-implementation-log.md`, `docs/10-coverage-matrix.md`
