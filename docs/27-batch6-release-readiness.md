# Batch 6 Release Readiness Checklist

**Date**: 2026-04-16  
**Status**: Provisional（`#52` / `P2-29`, verdict = `有条件发布`）  
**Owner**: `#52` / `#53`  
**Batch**: Product Phase 2 Batch 6

> 该文件是 Batch 6 专属 release readiness 产物。  
> 不覆盖 `docs/25-batch5-release-readiness.md`（Batch 5 final artifact）。

## 1. Checklist（最小固定项）

1. 测试结果（build/test）
2. Smoke 证据（public devnet + local-live）
3. 文档一致性（docs/06 + docs/10 + docs/14a + docs/15）
4. 发布判定（可发布 / 有条件发布 / 不可发布）

## 2. Smoke 与 Exception 规则（Batch 6 冻结）

1. 默认必需 smoke：`public devnet` 与 `local-live` 各至少一条
2. 任一侧缺失或不稳定：必须在 `docs/15` 登记 `Batch 6 exception`
3. 存在未收敛 exception：verdict 只能为 `有条件发布` 或 `不可发布`
4. 无未收敛 exception：才允许 `可发布`

## 3. 当前状态（after `#52` preflight automation）

- Build/Test：`PASS`（`93bb638`, `91/91 tests passed`）
- Smoke(public devnet)：`MISSING`
- Smoke(local-live)：`MISSING`
- Docs consistency：pending（待 `#50/#51/#53` 继续收敛）
- Exception register：**required**
- Verdict：`provisional: 有条件发布`

## 4. Preflight Automation（P2-29）

- Script path: `scripts/release/preflight_batch6.sh`
- Usage:
  - baseline: `scripts/release/preflight_batch6.sh`
  - allow exception verdict: `ALLOW_BATCH6_EXCEPTION=true scripts/release/preflight_batch6.sh`
- Output:
  - report: `artifacts/release/batch6-preflight-<timestamp>-<commit>.md`
  - logs: `artifacts/release/batch6-*.log`

## 5. Sample Run（`#52` exception path）

- command:
  - `ALLOW_BATCH6_EXCEPTION=true scripts/release/preflight_batch6.sh /tmp/batch6-preflight-93bb638`
- report:
  - `/tmp/batch6-preflight-93bb638/batch6-preflight-20260416-200221-93bb638.md`
- result summary:
  - `build/test`: `PASS`
  - `smoke(public devnet)`: `MISSING`
  - `smoke(local-live)`: `MISSING`
  - `exception_required`: `true`
  - `verdict`: `有条件发布`

## 6. Batch 6 Exception（当前）

- `Batch 6 Exception (P2-29 preflight smoke)`
  - `public devnet` smoke missing
  - `local-live` smoke missing
  - 当前按 `ALLOW_BATCH6_EXCEPTION=true` 走 `有条件发布`
  - 收敛计划：在后续 Batch 6 证据链中补齐双侧 smoke 后，再将 verdict 升级到 `可发布`
