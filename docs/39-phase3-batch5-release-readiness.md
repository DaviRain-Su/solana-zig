# Phase 3 Batch 5 Release Readiness

**Date**: 2026-04-17  
**Status**: Provisional  
**Owner**: `#83`  
**Batch**: Phase 3 Batch 5  
**Freeze point**: `b55c165`

> 本文件同时承载：  
> 1) Batch 5 release/readiness；  
> 2) Phase 3 aggregate verdict（在 G-P3E-05 关单时固化）。

## 1. Checklist

1. `G-P3E-01` canonical
2. `G-P3E-02` exception final convergence
3. `G-P3E-03` C ABI RPC/live alignment
4. `G-P3E-04` stake + Rust baseline + aggregate input
5. `G-P3E-05` docs/gate reconciliation
6. Batch 5 verdict
7. Phase 3 aggregate verdict

## 2. Frozen Exception Rule (Batch 5 / Phase 3 aggregate)

### 2.1 requestAirdrop

- `success`: 至少一侧成功，且不落 strict exception 分类；
- `partial_exception`: public devnet rate-limit + local-live success；
- `not_converged`: 两侧均失败或无成功证据。

### 2.2 getAddressLookupTable

- 优先目标：至少一侧稳定成功；
- `accepted_exception_path`: method-not-found / RPC error evidence；
- `not_converged`: 无成功路径且无可接受 exception evidence。

## 3. Carry-in Baseline Governance

- freeze point 锁定 `b55c165`；
- 仅 `<=b55c165` 的提交计入本批 baseline；
- 之后新增提交默认为 candidate，不自动计入。

## 4. Current Snapshot (provisional)

- `#79`: `3460ac9`（G-P3D-01/02 PASS）
- `#80`: `e9fd4ff`（G-P3D-01/03 PASS）
- `#81`: `bce967d`（G-P3D-04 PASS）
- `#82`: `b55c165`（G-P3D-05 PASS）
- `#83`（Batch 5 planning）: In Review

## 5. Upgrade Rule (strict)

仅当以下条件全部满足时，Batch 5/Phase 3 aggregate verdict 才可升级为 `可发布`：

1. `G-P3E-01~05` 全部 PASS；
2. `requestAirdrop` 与 `getAddressLookupTable` 均关闭 open exceptions；
3. 不存在 `partial_exception` / `accepted_exception_path`。

任一条件不满足，verdict 只能是 `有条件发布` 或 `不可发布`。

## 6. Evidence Landing

- implementation/gate 汇总：`docs/06-implementation-log.md`，`docs/10-coverage-matrix.md`
- benchmark：`docs/13a-benchmark-baseline-results.md`
- e2e / exception 运行证据：`docs/14a-devnet-e2e-run-log.md`
- execution matrix / exception register：`docs/15-phase1-execution-matrix.md`
- 本批 readiness：`docs/39-phase3-batch5-release-readiness.md`

## 7. Conditional Writeback

若 Batch 5 结论影响历史判定，条件回写：

- `docs/37-phase3-batch4-release-readiness.md`
- `docs/35-phase3-batch3-release-readiness.md`
- `docs/28-phase2-closeout-readiness.md`

默认不触发；仅在满足对应升级条件时回写。

## 8. Finalization Block (to be filled at closeout)

- Batch 5 verdict: `provisional` -> `final: ...`
- Phase 3 aggregate verdict: `provisional` -> `final: ...`
- Open exceptions summary:
  - `requestAirdrop`: TBD
  - `getAddressLookupTable`: TBD
- Closeout commit/hash: TBD
