# Batch 6 Release Readiness Checklist

**Date**: 2026-04-16  
**Status**: Final（`#53` closeout, verdict = `有条件发布`）  
**Owner**: `#53`  
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

## 3. 当前状态（after `#50/#51/#52`）

- Build/Test：`PASS`（latest canonical closeout：`1e53cd1`, `131/131 tests passed`）
- Smoke(public devnet)：`MISSING`
- Smoke(local-live)：`MISSING`
- Docs consistency：`PASS`
- Exception register：**required**
- Verdict：`final: 有条件发布`

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

## 7. Batch 6 Final Gate Summary

- `#50` `G-P2F-02`：PASS（SPL Token 交易流，默认成功模型已到位）
- `#51` `G-P2F-03`：PASS（recoverability 三条机械证据全部通过）
- `#52` `G-P2F-04`：PASS（preflight 主入口 / 报告规范 / exception-path 样例到位）
- `#53` `G-P2F-05`：PASS（docs/gate 对账完成）
- Final verdict：`有条件发布`
