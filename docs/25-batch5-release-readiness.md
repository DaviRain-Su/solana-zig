# Batch 5 Release Readiness Checklist

**Date**: 2026-04-16  
**Status**: Provisional（`#46` preflight automation baseline）  
**Owner**: `#46` / `P2-24`  
**Batch**: Product Phase 2 Batch 5

> 该文件是 Batch 5 专属 release readiness 产物。  
> 不覆盖 `docs/23-release-readiness-checklist.md`（Batch 4 final artifact）。

## 1. Checklist（最小固定项）

1. 测试结果（build/test）
2. Smoke 证据（public devnet + local-live）
3. 文档一致性（docs/06 + docs/10 + docs/14a + docs/15）
4. 发布判定（可发布 / 有条件发布 / 不可发布）

## 2. Smoke 与 Exception 规则（Batch 5 冻结）

1. 默认必需 smoke：`public devnet` 与 `local-live` 各至少一条
2. 任一侧缺失或不稳定：必须在 `docs/15` 登记 `Batch 5 exception`
3. 存在未收敛 exception：verdict 只能为 `有条件发布` 或 `不可发布`
4. 无未收敛 exception：才允许 `可发布`

## 3. 当前状态（按 `#46` baseline 填充）

- Build/Test：`PASS`（canonical：`3e34225`，`82/82 tests passed`）
- Smoke(public devnet)：`MISSING`（执行环境未提供 `SOLANA_RPC_URL`）
- Smoke(local-live)：`MISSING`（执行环境未提供 `SURFPOOL_RPC_URL`）
- Docs consistency：`PASS`
- Exception register：**required**
- Verdict：`provisional: 有条件发布`

## 4. Preflight Automation（P2-24）

- Script path: `scripts/release/preflight_batch5.sh`
- Usage:
  - baseline: `scripts/release/preflight_batch5.sh`
  - allow exception verdict: `ALLOW_BATCH5_EXCEPTION=true scripts/release/preflight_batch5.sh`
- Output:
  - report: `artifacts/release/batch5-preflight-<timestamp>-<commit>.md`
  - logs: `artifacts/release/batch5-*.log`

## 5. Sample Run（`#46`）

- command:
  - `ALLOW_BATCH5_EXCEPTION=true scripts/release/preflight_batch5.sh /tmp/batch5-preflight-3e34225`
- report:
  - `/tmp/batch5-preflight-3e34225/batch5-preflight-20260416-194418-3e34225.md`
- result summary:
  - `build/test`: `PASS`
  - `smoke(public devnet)`: `MISSING`
  - `smoke(local-live)`: `MISSING`
  - `docs consistency`: `PASS`
  - `exception_required`: `true`
  - `verdict`: `有条件发布`

## 6. Batch 5 Exception（当前）

- `Batch 5 Exception (P2-24 preflight smoke)`
  - `public devnet` smoke missing（执行环境未提供 `SOLANA_RPC_URL`）
  - `local-live` smoke missing（执行环境未提供 `SURFPOOL_RPC_URL`）
  - 当前按 `ALLOW_BATCH5_EXCEPTION=true` 走 `有条件发布`
  - 收敛计划：在 CI / nightly 环境补齐双侧 smoke 后，将 verdict 升级到 `可发布`
