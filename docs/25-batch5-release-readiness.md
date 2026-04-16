# Batch 5 Release Readiness Checklist

**Date**: 2026-04-16  
**Status**: Final（upgraded by `#49`, revalidated by `#56`, verdict = `可发布`）  
**Owner**: `#47` / `P2-25`  
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

## 3. 当前状态（Batch 5 final）

- Build/Test：`PASS`（original closeout：`a6f2f3b`, `91/91 tests passed`；latest revalidation：`21656d3`, `152/152 tests passed`）
- Smoke(public devnet)：`PASS`（original closeout：`6/6`；latest revalidation：`SOLANA_RPC_URL=https://api.devnet.solana.com zig build devnet-e2e --summary all` → `7/7`）
- Smoke(local-live)：`PASS`（original closeout：`SURFPOOL_RPC_URL=https://api.devnet.solana.com zig build e2e --summary all` → `2/2`；latest revalidation：`SURFPOOL_RPC_URL=http://127.0.0.1:8899 zig build e2e --summary all` → `2/2`）
- Docs consistency：`PASS`
- Exception register：**cleared**
- Verdict：`final: 可发布`

## 4. Preflight Automation（P2-24）

- Script path: `scripts/release/preflight_batch5.sh`
- Usage:
  - baseline: `scripts/release/preflight_batch5.sh`
  - allow exception verdict: `ALLOW_BATCH5_EXCEPTION=true scripts/release/preflight_batch5.sh`
- Output:
  - report: `artifacts/release/batch5-preflight-<timestamp>-<commit>.md`
  - logs: `artifacts/release/batch5-*.log`

## 5. Sample Run（`#49` smoke upgrade）

- command:
  - `SOLANA_RPC_URL=https://api.devnet.solana.com zig build devnet-e2e --summary all`
  - `SURFPOOL_RPC_URL=https://api.devnet.solana.com zig build e2e --summary all`
  - `SOLANA_RPC_URL=... SURFPOOL_RPC_URL=... ALLOW_BATCH5_EXCEPTION=false ./scripts/release/preflight_batch5.sh /tmp/batch5-preflight-smoke-upgrade-4`
- report:
  - `/tmp/batch5-preflight-smoke-upgrade-4/batch5-preflight-20260416-195856-a6f2f3b.md`
- result summary:
  - `build/test`: `PASS`
  - `smoke(public devnet)`: `PASS`
  - `smoke(local-live)`: `PASS`
  - `docs consistency`: `PASS`
  - `exception_required`: `false`
  - `verdict`: `可发布`

## 6. Batch 5 Exception（当前）

- 无未收敛 Batch 5 exception。

## 7. Batch 5 Final Gate Summary

- `#44` `G-P2E-02`：PASS（SPL Token builders，无 exception）
- `#45` `G-P2E-03`：PASS（WS observability，无 exception）
- `#46` `G-P2E-04`：PASS（preflight automation，Batch 5 smoke exception 已由 `#49` 收敛）
- `#47` `G-P2E-05`：PASS（docs/gate 对账完成）
- `#49` smoke upgrade：PASS（public devnet + local-live + preflight verdict）
- `#56` smoke revalidation：PASS（latest main baseline `21656d3`, public devnet `7/7`, local-live `2/2`）
- Final verdict：`可发布`
