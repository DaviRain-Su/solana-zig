# Phase 3 Batch 4 Release Readiness

**Date**: 2026-04-17
**Status**: Draft
**Owner**: `#78`
**Batch**: Phase 3 Batch 4
**Freeze point**: `e3a3794`

> 本文件是 Phase 3 Batch 4 专属 release/readiness 产物。  
> 不覆盖 `docs/35-phase3-batch3-release-readiness.md` 与 `docs/28-phase2-closeout-readiness.md`。

## 1. Checklist（最小固定项）

1. Build/Test 结果（canonical）
2. signers 最小闭环证据
3. C ABI 最小闭环证据
4. benchmark 扩展结果（signers + C ABI）
5. exception convergence 与 verdict-upgrade 判定输入
6. 文档一致性（`docs/06` / `docs/10` / `docs/13a` / `docs/14a` / `docs/15`）
7. 发布判定（`可发布` / `有条件发布` / `不可发布`）

## 2. Frozen Exception Rule（Batch 4）

### 2.1 requestAirdrop
- 成功路径：public devnet 或 local-live 至少一侧成功。
- 若 public devnet rate-limit：
  - 可判 `partial exception`，但必须同时具备 local-live success 证据。
  - 必须登记到 `docs/15`（原因、重试信息、后续收敛计划）。
- 若两侧均失败或无可复现成功证据：判 `not converged`。

### 2.2 getAddressLookupTable
- 优先目标：提供可复现成功路径（public devnet 或 local-live 任一）。
- 若持续 method-not-found / RPC error：
  - 可走 accepted exception path（RPC error evidence）。
  - 必须登记到 `docs/15`，并明确后续收敛阶段。

## 3. Carry-in Baseline Governance

- 本批 carry-in baseline freeze point 锁定为 `e3a3794`。
- 仅 `<=e3a3794` 的既有变更计入 Batch 4 carry-in baseline。
- freeze point 之后新增提交仅视为 carry-in candidate，不自动计入本批计分，除非后续任务明确重锁 freeze point。

## 4. Current Snapshot

- Canonical（G-P3D-01）：`pending`
- Signers minimum（G-P3D-02）：`pending`
- C ABI minimum（G-P3D-03）：`pending`
- Benchmark + verdict input（G-P3D-04）：`pending`
- Docs/gate（G-P3D-05）：`pending`
- Batch 4 verdict：`pending`

## 5. Upgrade Rule

仅当以下条件全部满足时，Batch 4 verdict 才允许升级为 `可发布`：
1. `G-P3D-01~G-P3D-05` 全部 PASS；
2. 无未收敛 Batch 4 exception；
3. 不存在 `partial exception` 或 `accepted exception path`（延续 strict exception model）。

若任一条件不满足，Batch 4 verdict 只能是 `有条件发布` 或 `不可发布`。

## 6. Evidence Landing

- 运行证据：`docs/14a-devnet-e2e-run-log.md`
- benchmark 结果：`docs/13a-benchmark-baseline-results.md`
- exception 登记：`docs/15-phase1-execution-matrix.md`
- implementation/gate 汇总：`docs/06-implementation-log.md`, `docs/10-coverage-matrix.md`

## 7. Conditional Writeback

若 Batch 4 对上游 verdict 产生影响，需条件回写：
- `docs/35-phase3-batch3-release-readiness.md`
- `docs/28-phase2-closeout-readiness.md`
