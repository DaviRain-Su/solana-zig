# Product Phase 3 Batch 1 Planning

**Date**: 2026-04-16
**Status**: In Review (`#59 P3-1`)
**Owner**: `#59`
**Depends on**: `docs/00-roadmap.md`, `docs/03a-interfaces-spec.md`, `docs/10-coverage-matrix.md`, `docs/14a-devnet-e2e-run-log.md`, `docs/15-phase1-execution-matrix.md`, `docs/28-phase2-closeout-readiness.md`

> Phase 3 Batch 1 继续 planning-first。本文过审前，Batch 1 实现提交保持冻结。

## 1. Objective

Batch 1 目标是“Phase 3 能力主线起步 + Phase 2 遗留 exception 进入机械收敛路径”，不做超范围扩散：
1. P3-02: System interface 最小可用（`transfer` / `createAccount`）
2. P3-03: Token interface builder 扩展（`mint` / `approve` / `burn`；ATA helper 延后）
3. P3-04: Phase 2 carry-over exception 收敛（`requestAirdrop` / `getAddressLookupTable`）

## 2. In Scope

### 2.1 P3-02: System interface
- 新增/完善 `transfer` 与 `createAccount` builder
- 覆盖 `happy / rpc_error-or-signing_error / malformed` 最小三类证据（按本批接口语义映射）
- 必须给出 compile/sign 流证据

### 2.2 P3-03: Token interface builder
- 新增 `mint` / `approve` / `burn` builder
- 复用 `src/solana/interfaces/token.zig` 既有模块
- 本批明确 **不包含 ATA helper**（延后到 Batch 2）

### 2.3 P3-04: Exception convergence（method-level frozen rule）
- `requestAirdrop`：
  - 默认成功路径：public devnet 或 local-live 至少一侧成功
  - public devnet 若出现 rate-limit，允许 partial exception，但必须有 local-live success 证据
  - 重试规则：最多 3 次，指数退避；超上限仍失败且无另一侧成功则记为未收敛 exception
- `getAddressLookupTable`：
  - 目标优先级 1：给出可复现成功路径（public devnet 或 local-live 任一）
  - 若 public devnet 持续 `-32601`/method-not-found，可走 RPC error evidence exception path
  - 该 exception path 必须登记到 `docs/15`，并明确收敛阶段（Phase 3 后续批次）

## 3. Out of Scope

1. ATA PDA helper 与 ATA 批量辅助 API（延后 Batch 2）
2. `token-2022` / `memo` / `stake` 接口新增（延后后续批次）
3. C ABI 与 signer external adapter 实装（不在本批）

## 4. Write-set Freeze

### P3-02 (System)
- `src/solana/interfaces/system.zig`
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要 compile/test 引用）

### P3-03 (Token)
- `src/solana/interfaces/token.zig`
- `src/solana/mod.zig`（仅必要导出）
- `src/root.zig`（仅必要 compile/test 引用）

### P3-04 (Exception convergence)
- `src/solana/rpc/client.zig`
- `src/solana/rpc/types.zig`（仅必要 typed parse/异常结构最小触碰）
- `src/e2e/*`（仅收敛证据所需最小 harness 触碰）
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/31-phase3-batch1-release-readiness.md`

### Docs/Gate
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/README.md`

## 5. Artifact / Docs Landing Freeze

1. Batch 1 planning artifact（本文件）：`docs/30-phase3-batch1-planning.md`
2. Batch 1 release/readiness artifact：`docs/31-phase3-batch1-release-readiness.md`
3. docs/gate reconciliation 固定覆盖：
   - `docs/06-implementation-log.md`
   - `docs/10-coverage-matrix.md`
   - `docs/14a-devnet-e2e-run-log.md`
   - `docs/15-phase1-execution-matrix.md`
   - `docs/31-phase3-batch1-release-readiness.md`
4. phase-level 聚合结论（`docs/28`）仅由后续 phase-level closeout 线更新；本批不直接改写 phase-level final 结论。

## 6. Gate / DoD

### G-P3A-01 canonical
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

### G-P3A-02 system interface
- `transfer` / `createAccount` builder 均落地
- 至少各 1 条 byte layout + account metas 证据
- 至少 1 条 compile/sign 证据通过

### G-P3A-03 token interface
- `mint` / `approve` / `burn` builder 均落地
- 至少各 1 条 byte layout + account metas 证据
- 本批 ATA 明确 out-of-scope；若误触 ATA helper，视为 freeze violation

### G-P3A-04 exception convergence
- `requestAirdrop`：
  - 成功/partial exception/未收敛 三态必须可机械判定
  - 若进入 partial exception，必须同时满足：
    - public devnet rate-limit 证据
    - local-live success 证据
    - `docs/15` exception 登记
- `getAddressLookupTable`：
  - 成功路径或 RPC error evidence exception path 二选一
  - 走 exception path 时必须写明后续收敛阶段与升级条件

### G-P3A-05 docs/gate reconciliation
必须回写并对账：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/31-phase3-batch1-release-readiness.md`

## 7. Dependency Rule

- `P3-04` 可与 `P3-02/P3-03` 并行推进，但 `docs/31` 的 final verdict 必须建立在三线证据都到位之后。
- 若 `P3-04` 仍存在未收敛 exception，Batch 1 verdict 只能是 `有条件发布` 或 `不可发布`。
