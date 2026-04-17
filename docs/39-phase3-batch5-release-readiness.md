# Phase 3 Batch 5 Release Readiness

**Date**: 2026-04-17  
**Status**: Final  
**Owner**: `#88`  
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

## 4. Current Snapshot (final)

- `#79`: `3460ac9`（G-P3D-01/02 PASS）
- `#80`: `e9fd4ff`（G-P3D-01/03 PASS）
- `#81`: `bce967d`（G-P3D-04 PASS）
- `#82`: `b55c165`（G-P3D-05 PASS）
- `#83`: `7671c87`（planning / DoD PASS，Done）
- `#84`: `b02071b`（G-P3E-01/02 PASS，Done）
- `#85`: `23d8cf4`（G-P3E-03 PASS，Done）
- `#86`: `23d8cf4`（G-P3E-04 input PASS，Done）
- `#87`: `9f903e5`（G-P3E-04 PASS，Done）
- `#88`: `ee73045`（G-P3E-05 PASS，Done）

### 4.1 Current strict-model input

- `requestAirdrop = partial_exception`（public devnet rate-limit + local-live success）
- `getAddressLookupTable = accepted_exception_path`（method-not-found / RPC error evidence）
- 两项 open exceptions 均符合 strict exception model 但未关闭 → 不满足升级条件。

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

## 8. Finalization Block

- Batch 5 verdict: `final: 有条件发布`
- Phase 3 aggregate verdict: `final: 有条件发布`
- Open exceptions summary:
  - `requestAirdrop`: `partial_exception`（public devnet rate-limit + local-live success）
  - `getAddressLookupTable`: `accepted_exception_path`（method-not-found / RPC error evidence）
- Closeout commit/hash: `ee73045`
- Test count: 239/239 PASS（baseline `a0984da`）
- Rust baseline: Run 3（harness `b71a899`，review package `9f903e5`；signer 13.7μs Rust vs 36.3μs Zig，base58 81ns Rust vs 1213ns Zig）

### 8.1 Phase 3 Aggregate Verdict Input Rationale

当前输入指向 `有条件发布`，原因：
1. 全部 7 个 interface 模块交付（system / token / token_2022 / compute_budget / memo / stake / ata）
2. Signer 抽象交付（vtable + InMemorySigner + MockExternalSigner）
3. C ABI 导出层交付（core + transaction + RPC scaffold → live transport）
4. Batch 1-4 gate PASS，Batch 5 `G-P3E-05` 待 reviewer 结论
5. 239/239 tests PASS
6. 但仍有 2 项 open exceptions 未关闭，strict model 下不可升级为 `可发布`

### 8.2 Conditional Writeback (candidate)

- `docs/37`：不触发回写（Batch 4 verdict 口径未变）
- `docs/35`：不触发回写（Batch 3 verdict 口径未变）
- `docs/28`：不触发回写（Phase 2 aggregate 升级条件仍不满足）
