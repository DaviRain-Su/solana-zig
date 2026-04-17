# Phase 4 Release Readiness

**Date**: 2026-04-17  
**Status**: Provisional  
**Owner**: `#89`  
**Review Scope**: Phase 4 planning/release draft review  

## 1. Scope Freeze (from `docs/40`)

- Phase 4 主 scope：on-chain SBF feasibility、runtime/entrypoint 边界、CPI + Borsh、System/SPL wrappers、示例程序、收口发布。
- 执行路线：`Evaluate -> Selective Integrate -> Extend`。
- 交付载体：独立仓库 `solana-program-zig`（Batch 0 完成 feasibility，Batch 1 前完成分仓决策）。

## 2. Gate Map

| Gate | 目标 | 当前状态 |
|------|------|----------|
| `G-P4A` | 可行性（compile/smoke + decision records） | `pending` |
| `G-P4B` | 核心框架（entrypoint + hello-world） | `pending` |
| `G-P4C` | CPI + Borsh + CU baseline | `pending` |
| `G-P4D` | System/SPL + 示例程序 + CU baseline | `pending` |
| `G-P4E` | docs/CI/integration closeout + final verdict | `pending` |

## 3. Perf Calibration Ownership

- `P4-Pre-1`（native Zig vs native Rust / cabi-vs-cabi 对齐）归属 Phase 4 Batch 0。
- 解锁语义：`P4-Pre-1` 为 sidecar，不阻塞 Batch 1 解锁。
- 约束语义：`P4-Pre-1` 报告必须在 `G-P4E` 前落盘并纳入最终 verdict 输入。

## 4. Phase 3 Open Exceptions Handling (strict boundary)

- Phase 3 两条 open exceptions **不纳入** Phase 4 实现 scope：
  - `requestAirdrop = partial_exception`
  - `getAddressLookupTable = accepted_exception_path`
- Phase 4 不回改 Phase 3 strict-model 结论；Phase 3 verdict 保持 `final: 有条件发布`。
- 仅允许在 Phase 4 文档中“引用现状”，不允许在 Phase 4 gate 中重定义 Phase 3 verdict 规则。

## 5. Decision Records Required in Batch 0

`G-P4A` 关闭前必须落盘以下决策产物：

1. Zig compat matrix（目标 Zig 版本与 bootstrap/sdk 兼容性）
2. Core types 策略 ADR（`@import` 共享 vs vendor split）
3. Test harness ADR（`solana-test-validator` vs `solana-program-test`）
4. Batch 0->1 分仓决策记录（独立仓库时机）

## 6. Current Snapshot (in review)

- `#89`: `in_review`（planning package under structural review）
- 实现线状态：`frozen`（结构审 PASS 前不放行）

## 7. Evidence Landing (Phase 4)

- planning: `docs/40-phase4-planning.md`
- readiness: `docs/41-phase4-release-readiness.md`
- execution/coverage/run-log（后续批次回写）：`docs/06` / `docs/10` / `docs/13a` / `docs/14a` / `docs/15`

## 8. Finalization Block (pending reviewer)

- Structural review baseline: `pending #89 docs-only commit`
- `#89` 结构审结论：`pending`
- Phase 4 实现冻结：`active`
