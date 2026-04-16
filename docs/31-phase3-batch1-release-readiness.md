# Phase 3 Batch 1 Release Readiness

**Date**: 2026-04-16
**Status**: Provisional
**Owner**: `#59`（后续由 Batch 1 docs/gate 线收口）
**Batch**: Phase 3 Batch 1

> 本文件是 Phase 3 Batch 1 专属 release/readiness 产物。  
> 不覆盖 `docs/28-phase2-closeout-readiness.md` 的 phase-level 聚合结论。

## 1. Checklist（最小固定项）

1. Build/Test 结果（canonical）
2. System interface 证据（`transfer` / `createAccount`）
3. Token interface 证据（`mint` / `approve` / `burn`）
4. Exception convergence 证据（`requestAirdrop` / `getAddressLookupTable`）
5. 文档一致性（`docs/06` / `docs/10` / `docs/14a` / `docs/15`）
6. 发布判定（`可发布` / `有条件发布` / `不可发布`）

## 2. Frozen Exception Rule（Batch 1）

### 2.1 requestAirdrop
- 默认成功路径：public devnet 或 local-live 至少一侧成功。
- 若 public devnet rate-limit：
  - 可判 `partial exception`，但必须同时具备 local-live success 证据。
  - 必须登记到 `docs/15`（含原因、重试信息、后续收敛计划）。
- 若两侧均失败或无可复现成功证据：判未收敛 exception。

### 2.2 getAddressLookupTable
- 优先目标：提供可复现成功路径（public devnet 或 local-live 任一）。
- 若 public devnet 持续 method-not-found / RPC error：
  - 可走 RPC error evidence exception path。
  - 必须登记到 `docs/15`，并明确后续收敛阶段（Phase 3 后续批次）。

## 3. Current Snapshot

- Canonical（G-P3A-01）：`PENDING`
- System interface（G-P3A-02）：`PENDING`
- Token interface（G-P3A-03）：`PENDING`
- Exception convergence（G-P3A-04）：`PENDING`
- Docs/Gate（G-P3A-05）：`PENDING`
- Batch 1 verdict：`provisional: 有条件发布`

## 4. Upgrade Rule

仅当以下条件全部满足时，Batch 1 verdict 才允许升级为 `可发布`：
1. `G-P3A-01~G-P3A-05` 全部 PASS；
2. 无未收敛 Batch 1 exception；
3. 若存在 partial exception，已满足 frozen rule 且明确不影响本批 gate。

## 5. Evidence Landing

- 运行证据：`docs/14a-devnet-e2e-run-log.md`
- exception 登记：`docs/15-phase1-execution-matrix.md`
- implementation/gate 汇总：`docs/06-implementation-log.md`, `docs/10-coverage-matrix.md`
