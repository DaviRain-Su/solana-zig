# Phase 4 Release Readiness

**Date**: 2026-04-17  
**Status**: Provisional  
**Owner**: `#89` / delta `#99`  
**Review Scope**: planning delta review（toolchain baseline switch）

## 1. Scope Freeze（from `docs/40`）

- Phase 4 主 scope：on-chain SBF feasibility、runtime/entrypoint 边界、CPI + Borsh、System/SPL wrappers、示例程序、收口发布。
- 工具链主基线：`zignocchio`（standard Zig BPF + `sbpf-linker`）。
- `solana-zig-bootstrap` 在本批仅作为背景对照，不作为实施计分对象。

## 2. Gate Map

| Gate | 目标 | 当前状态 |
|------|------|----------|
| `G-P4A` | 可行性（zignocchio compile/smoke + decision records） | `pending` |
| `G-P4B` | 核心框架（entrypoint + hello-world） | `pending` |
| `G-P4C` | CPI + Borsh + CU baseline | `pending` |
| `G-P4D` | System/SPL + 示例程序 + CU baseline | `pending` |
| `G-P4E` | docs/CI/integration closeout + final verdict | `pending` |

## 3. Batch 0 Task-to-Gate Mapping

- `#95/#96`：`zignocchio` 路线可行性（compile + smoke）
- `#97`：test harness ADR
- `#98`：core types ADR
- `#94`：perf sidecar（不阻塞 `G-P4A`，但必须在 `G-P4E` 前落盘）

`G-P4A` 只计 `#95/#96/#97/#98`；`#94` 不作为解锁项。

## 4. Phase 3 Open Exceptions Boundary

- Phase 3 open exceptions 不纳入 Phase 4 实现 scope：
  - `requestAirdrop = partial_exception`
  - `getAddressLookupTable = accepted_exception_path`
- Phase 4 不回改 Phase 3 strict-model verdict（保持 `final: 有条件发布`）。

## 5. Decision Records Required for `G-P4A`

1. `#95` Zig compat matrix（基于 zignocchio 路线）
2. `#97` Test harness ADR（validator vs program-test）
3. `#98` Core types ADR（@import vs vendor + layout/freestanding evidence）
4. `#95/#96` compile + smoke evidence

## 6. Current Snapshot (in review)

- `#89`: `done`（planning baseline）
- `#99`: `in_review`（toolchain baseline delta）
- `#95/#96`: `paused scoring`（等待 `#99` 结构审结论后恢复计分）
- `#94`: `in_progress`（sidecar）
- `#97/#98`: `in_progress`（资料收集/草案阶段）

## 7. Evidence Landing (Batch 0)

- planning delta: `docs/40-phase4-planning.md` / `docs/41-phase4-release-readiness.md`
- execution docs（中间态）：`docs/06` / `docs/10` / `docs/13a` / `docs/15`

## 8. Finalization Block (pending reviewer)

- Structural review baseline: `pending #99 docs-only commit`
- `#99` review verdict: `pending`
- Phase 4 Batch 0 scoring mode: `partial active`（`#94` active, `#95/#96` paused-scoring）
