# Phase 3 Batch 5 Planning (P3-21)

**Date**: 2026-04-17  
**Status**: Draft (In Review)  
**Owner**: `#83`  
**Batch**: Phase 3 Batch 5  
**Freeze point**: `b55c165`

> 本批是 Phase 3 的最后一批。  
> Batch 5 closeout 必须同时产出 **Phase 3 aggregate verdict**。

## 1. Scope Freeze

Batch 5 固定四条实现/收口线：

- `P3-22` Exception final convergence
  - 目标：推进关闭 `requestAirdrop` 与 `getAddressLookupTable` 的 open exceptions。
- `P3-23` C ABI RPC/live alignment
  - 目标：使 C ABI RPC 最小入口与真实 RPC 路径一致，不再停留于“仅导出可编译”。
- `P3-24` Stake create + negative-path closure
  - 目标：补齐 `buildCreateStakeAccountInstruction(...)` 契约一致性和负路径机械证据。
- `P3-25` Rust baseline comparison + Phase 3 aggregate verdict input
  - 目标：补齐 Zig vs Rust 对比基线与 aggregate verdict 判定输入。

## 2. Out of Scope

以下不在 Batch 5 内：

- Phase 4（SBF/on-chain runtime）相关任何实现；
- 新增非冻结接口族（超出本批四条主线）；
- 未经重锁 freeze point 的 carry-in 新功能自动计分。

## 3. Carry-in Baseline Governance

- Batch 5 carry-in baseline freeze point 锁定为 `b55c165`。
- 仅 `<= b55c165` 的提交计入本批 baseline。
- freeze point 之后新增提交仅视为 candidate，不自动计分，除非单独重锁 freeze point。

## 4. Write-set Freeze

### 4.1 P3-22 Exception final convergence

- `src/solana/rpc/client.zig`
- `src/e2e/devnet_e2e.zig`
- `src/e2e/nonce_e2e.zig`（仅在需要补充 convergence 证据时）

### 4.2 P3-23 C ABI RPC/live alignment

- `src/solana/cabi/rpc.zig`
- `src/solana/cabi/core.zig`
- `include/solana_zig.h`
- `src/solana/rpc/http_transport.zig`（仅最小必要）
- `src/solana/rpc/transport.zig`（仅最小必要）

### 4.3 P3-24 Stake create + negative-path closure

- `src/solana/interfaces/stake.zig`
- `src/root.zig`（仅测试入口与最小编译触点）

### 4.4 P3-25 Rust baseline comparison + aggregate verdict input

- `src/benchmark.zig`
- `docs/13a-benchmark-baseline-results.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/39-phase3-batch5-release-readiness.md`

### 4.5 P3-26 docs/gate reconciliation

- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/13a-benchmark-baseline-results.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/39-phase3-batch5-release-readiness.md`
- 条件触发：`docs/37-phase3-batch4-release-readiness.md`, `docs/35-phase3-batch3-release-readiness.md`, `docs/28-phase2-closeout-readiness.md`

## 5. Artifact Landing

- Batch 5 planning artifact：`docs/38-phase3-batch5-planning.md`
- Batch 5 release/readiness artifact：`docs/39-phase3-batch5-release-readiness.md`
- docs index：`docs/README.md`

## 6. Gate / DoD

### G-P3E-01 canonical

- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

### G-P3E-02 exception final convergence

- `requestAirdrop` 与 `getAddressLookupTable` 都给出本批最终可复现结论；
- 明确区分：`closed` / `partial_exception` / `accepted_exception` / `not_converged`；
- 输出 verdict-upgrade 输入，不得仅给代码变更无判定。

### G-P3E-03 C ABI RPC/live alignment

- C ABI RPC 最小入口对真实 RPC 路径可调用；
- header/export consistency 与 abi version 规则保持一致；
- create/use/free 证据与 error model 机械可复现。

### G-P3E-04 stake + rust baseline input

- stake create helper 契约与负路径证据闭环；
- Zig vs Rust baseline 对比结果落 `docs/13a`；
- aggregate verdict 输入写入 `docs/15` 与 `docs/39`。

### G-P3E-05 docs/gate reconciliation + aggregate closeout

必须回写并对账：

- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/13a-benchmark-baseline-results.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/39-phase3-batch5-release-readiness.md`

并在 `docs/39` 固化 **Phase 3 aggregate verdict**。

## 7. Verdict Rule (strict)

- 若仍存在任一 `partial_exception` 或 `accepted_exception_path`，Batch 5 与 Phase 3 aggregate verdict 只能是 `有条件发布` 或 `不可发布`。
- 仅当所有 gates PASS 且 open exceptions 全关闭，才允许升级到 `可发布`。

## 8. Dependency Rule

- `P3-22`、`P3-23`、`P3-24` 可并行；
- `P3-25` 可并行准备，但 aggregate verdict 必须等待三线证据到齐；
- `P3-26` 最终收口必须依赖 `P3-22~P3-25` 完整证据。
