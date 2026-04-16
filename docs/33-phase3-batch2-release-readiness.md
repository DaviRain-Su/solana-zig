# Phase 3 Batch 2 Release Readiness

**Date**: 2026-04-17  
**Status**: Final  
**Owner**: `#72`  
**Batch**: Phase 3 Batch 2  
**Freeze point**: `dfa5a69`（US-001..US-009 carry-in baseline）

> 本文件是 Phase 3 Batch 2 专属 release/readiness 产物。  
> 不覆盖 `docs/31-phase3-batch1-release-readiness.md` 与 `docs/28-phase2-closeout-readiness.md`。

## 1. Checklist（Batch 2 固定项）

1. Canonical 基线（`G-P3B-01`）
2. ATA helper（`G-P3B-02`）
3. Interface 补齐（assign + memo dual-mode，`G-P3B-03`）
4. Exception convergence（`G-P3B-04`）
5. Docs/Gate reconciliation（`G-P3B-05`）

## 2. Carry-in Baseline Governance

本批 carry-in baseline 统一承接 `dfa5a69` 及其前置 US 提交链（US-001..US-009）：

- `53d5c94` US-001 `getTransaction`
- `242a613` US-002 `getSignaturesForAddress`
- `325d47e` US-003 `getSignatureStatuses`
- `229255e` US-004 `getSlot/getEpochInfo`
- `f5068ee` US-005 `getMinimumBalanceForRentExemption`
- `e869233` US-006 `requestAirdrop`
- `222b089` US-007 `getAddressLookupTable`
- `24f916c` US-008 `getTokenAccountsByOwner`
- `dfa5a69` US-009 `getTokenAccountBalance/getTokenSupply`

上述提交均视为 Batch 2 carry-in baseline，**不计入 Batch 2 新增交付计分**。

## 3. Frozen Exception Rule（Batch 2）

### 3.1 `requestAirdrop` strict tri-state

- `success`：至少一侧成功。
- `partial exception`：public devnet rate-limit + local-live success。
- `not converged`：两侧均失败或无成功证据。

### 3.2 `getAddressLookupTable` success-or-exception

- 优先成功路径（public devnet 或 local-live 任一）。
- 若持续 method-not-found / RPC error：
  - 允许 accepted exception path；
  - 必须在 `docs/15` 登记原因与后续收敛阶段。

## 4. Final Snapshot

- `G-P3B-01` Canonical：**PASS**
- `G-P3B-02` ATA helper：**PASS**（`#69`, `616c42c`）
- `G-P3B-03` Interface supplement：**PASS**（`#70`, `efe3070`）
- `G-P3B-04` Exception convergence：**PASS**（`#71`, `efe3070`）
- `G-P3B-05` Docs/Gate：**PASS**（`#72`）

Batch 2 task status:

- `#69` Done
- `#70` Done
- `#71` Done
- `#72` Done

## 5. Release Verdict

Batch 2 final verdict: **`有条件发布`**

原因（按 frozen exception rule）：

1. `requestAirdrop` 仍按 `partial exception` 收口（public devnet rate-limit + local-live success）
2. `getAddressLookupTable` 仍按 accepted exception path 收口（method-not-found / RPC error evidence）

## 6. Evidence Landing

- Implementation log: `docs/06-implementation-log.md`
- Coverage matrix: `docs/10-coverage-matrix.md`
- Run evidence: `docs/14a-devnet-e2e-run-log.md`（Run 13）
- Exception register: `docs/15-phase1-execution-matrix.md`

## 7. Phase 2 Artifact Writeback

本批不触发 `docs/28-phase2-closeout-readiness.md` 回写。  
Phase 2 aggregate verdict 的升级条件（无未收敛 exception）当前仍不满足。
