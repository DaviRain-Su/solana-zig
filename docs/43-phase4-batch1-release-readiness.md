# Phase 4 Batch 1 Release Readiness

**Date**: 2026-04-17  
**Status**: Provisional  
**Owner**: `#100`  
**Review Scope**: Batch 1 planning-first structural review

## 1. Scope Freeze（from `docs/42`）

Batch 1 只覆盖 core framework：

- 独立包边界与构建骨架
- entrypoint runtime skeleton
- account deserialization
- instruction parse + dispatch
- canonical smoke demo

不覆盖 CPI 深化/Borsh 完整对账/System/SPL wrappers。

## 2. Inherited Baseline（已关闭）

- `G-P4A`: PASS
- `D-01`: PASS (`#95` / `8abf769`)
- `D-02`: PASS (`#98` / `dc2136e`)
- `D-03`: PASS (`#97` supersede / `3291d2b`)
- `D-04`: owner confirmed（同仓独立包）
- `D-05`: PASS（host matrix 已固化）
- `#94` sidecar：accepted-input（已落盘）

## 3. Batch 1 Gate Map

| Gate | 目标 | 当前状态 |
|------|------|----------|
| `G-P4B-01` | 独立包边界 + canonical host compile | `pending` |
| `G-P4B-02` | entrypoint + account deserialization + instruction parse + surfpool smoke（linux-x86_64） | `pending` |
| `G-P4B-03` | docs/gate reconciliation | `pending` |

## 4. Task-to-Gate Mapping（planned）

- `#101` → `G-P4B-01`
- `#102/#103/#104` → `G-P4B-02`
- `#105` → `G-P4B-03`

`#103` 为 `G-P4B-02` 必经项，不可绕开。

## 5. Canonical Execution Policy

1. scoring host：`linux-x86_64`
2. smoke backend：`surfpool-first`
3. `darwin-arm64`：dev-only / non-scoring
4. reviewer-safe rule：未签收前仅使用 `in_review/pending` 状态，不预写 PASS

## 6. Required Evidence（for `G-P4B` closeout）

1. clean isolated canonical package（commit/hash + clean status）
2. package boundary 证据（固定目录、allowed import boundary、negative write-set）
3. compile + deploy + smoke 机械证据（同一 canonical host）
4. account deserialization 机械证据：
   - 1 条正路径（合法账户视图解析）
   - 2 条负路径（数据长度不足 + owner/account meta 不匹配）
5. docs 对账（`docs/06` / `docs/10` / `docs/15` / `docs/41` / `docs/43`）

## 7. Current Snapshot

- `#100`: `in_review`（planning draft）
- Batch 1 implementation tasks: `pending creation`
- Gate mode: planning-first（结构审 PASS 前冻结实现提交）

## 8. Finalization Block (pending reviewer)

- structural review baseline: `pending supersede`
- `#100` verdict: `pending`
- Batch 1 implementation mode: `frozen`
