# Phase 3 Batch 3 Release Readiness

**Date**: 2026-04-17
**Status**: Provisional
**Owner**: `#73`（后续由 Batch 3 docs/gate 线收口）
**Batch**: Phase 3 Batch 3
**Freeze point**: `243ba7f`

> 本文件是 Phase 3 Batch 3 专属 release/readiness 产物。  
> 不覆盖 `docs/33-phase3-batch2-release-readiness.md` 与 `docs/28-phase2-closeout-readiness.md`。

## 1. Checklist（最小固定项）

1. Build/Test 结果（canonical）
2. token-2022 最小 builder 证据
3. stake delegate 最小 builder 证据
4. Exception convergence 证据（`requestAirdrop` / `getAddressLookupTable`）
5. 文档一致性（`docs/06` / `docs/10` / `docs/14a` / `docs/15`）
6. 发布判定（`可发布` / `有条件发布` / `不可发布`）

## 2. Frozen Exception Rule（Batch 3）

### 2.1 requestAirdrop
- 默认成功路径：public devnet 或 local-live 至少一侧成功。
- 若 public devnet rate-limit：
  - 可判 `partial exception`，但必须同时具备 local-live success 证据。
  - 必须登记到 `docs/15`（含原因、重试信息、后续收敛计划）。
- 若两侧均失败或无可复现成功证据：判 `not converged`。

### 2.2 getAddressLookupTable
- 优先目标：提供可复现成功路径（public devnet 或 local-live 任一）。
- 若持续 method-not-found / RPC error：
  - 可走 accepted exception path（RPC error evidence）。
  - 必须登记到 `docs/15`，并明确后续收敛阶段（Batch 4 或更后续）。

## 3. Carry-in Baseline Governance

- 本批承接 `243ba7f` 及其之前主线能力。
- 对 `author=@davirain` 且 `feat: US-*` 前缀的 ralph-tui 提交，统一视作 carry-in baseline，不计入 Batch 3 新增交付计分。

## 4. Current Snapshot

- Canonical（G-P3C-01）：`PENDING`
- token-2022 minimum（G-P3C-02）：`PENDING`
- stake delegate minimum（G-P3C-03）：`PENDING`
- exception convergence（G-P3C-04）：`PENDING`
- docs/gate（G-P3C-05）：`PENDING`
- Batch 3 verdict：`provisional: 有条件发布`

## 5. Upgrade Rule

仅当以下条件全部满足时，Batch 3 verdict 才允许升级为 `可发布`：
1. `G-P3C-01~G-P3C-05` 全部 PASS；
2. 无未收敛 Batch 3 exception；
3. 若存在 partial/accepted exception，已满足 frozen rule 且明确不影响本批 gate。

## 6. Evidence Landing

- 运行证据：`docs/14a-devnet-e2e-run-log.md`
- exception 登记：`docs/15-phase1-execution-matrix.md`
- implementation/gate 汇总：`docs/06-implementation-log.md`, `docs/10-coverage-matrix.md`

## 7. Conditional Phase-level Writeback

若 Batch 3 关闭了 `requestAirdrop/getAddressLookupTable` 对 `docs/28` 的 carry-over 影响，则必须同步回写：
- `docs/28-phase2-closeout-readiness.md`

若未关闭，则保持 `docs/28` 不变并在 `docs/15` 保持 exception 跟踪。
