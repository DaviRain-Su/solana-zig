# Release Readiness Checklist — Phase 2 Batch 4

**Date**: 2026-04-16
**Status**: In Progress
**Owner**: `#39 P2-19`
**Gate**: `G-P2D-04`
**Depends on**: `docs/22-phase2-batch4-planning.md`

> 本文按 `G-P2D-04` 最小清单口径（测试结果、内存检查、文档一致性、发布判定）产出可执行证据。
>
> Exception 与 release verdict 关系（`docs/22` 冻结规则）：
> - 允许 `PASS-with-exception`
> - 有未收敛 exception → release verdict = `不可发布` 或 `有条件发布`
> - 无未收敛 exception → release verdict = `可发布`

---

## 1. 测试结果（Test Results）

### 1.1 全量测试基线

- Commit: `4b1f8e4`
- Command: `zig build test --summary all`
- Result: **PASS**
- Total tests: 72
- Pass / Fail / Skip: 72 / 0 / 0
- New compilation blockers: none
- New leak / deadlock signals: none（`std.testing.allocator` 强制零泄漏，全部通过）

### 1.2 Batch 4 新增测试

#### P2-17 Token Accounts 深化（#37）

| 方法 | happy | rpc_error | malformed | integration | 状态 |
|------|-------|-----------|-----------|-------------|------|
| `getTokenAccountBalance` | PASS | PASS | PASS | pending | commit `4b1f8e4` |
| `getTokenSupply` | PASS | PASS | PASS | pending | commit `4b1f8e4` |

#### P2-18 WS Production Hardening（#38）

| 验收点 | 测试证据 | 状态 |
|--------|----------|------|
| heartbeat + timeout | `ws_production_heartbeat_ping_pong` PASS | commit `6d3c58c` |
| deterministic backoff + 硬上限 | `ws_production_backoff_hard_limit` PASS（10 retries capped to 5） | commit `6d3c58c` |
| cleanup + state consistency | `ws_production_cleanup_state_consistency` PASS（reconnect 后 subscriptionCount 不变） | commit `6d3c58c` |
| dedup cache boundary | `ws_production_dedup_cache_boundary` PASS（ring 满后 oldest evicted） | commit `6d3c58c` |

### 1.3 E2E / Smoke 测试

| Run | 类型 | 命令 | 结果 | 备注 |
|-----|------|------|------|------|
| local-live smoke | pending | `SOLANA_RPC_URL=http://127.0.0.1:8899 zig build devnet-e2e` | pending | |
| public devnet smoke | pending | `SOLANA_RPC_URL=https://api.devnet.solana.com zig build devnet-e2e` | pending | |

---

## 2. 内存检查（Memory Check）

### 2.1 Allocator 基线

- `std.testing.allocator` 强制零泄漏：全量测试是否通过 = **PASS**（72/72，commit `4b1f8e4`）
- GPA（GeneralPurposeAllocator）检测结果：**PASS**（所有 E2E 测试使用 GPA 且零泄漏）

### 2.2 已知内存相关项

| 项 | 状态 | 备注 |
|----|------|------|
| RPC response 生命周期（`deinit` 覆盖） | 已有 | 各 typed parse 测试均使用 `defer result.deinit(...)` |
| WS subscription cleanup | PASS | `ws_production_cleanup_state_consistency` 验证 reconnect 后 count 一致 |
| Dedup cache 无限增长 | PASS | ring buffer `DEDUP_CACHE_SIZE=16`，`ws_production_dedup_cache_boundary` 验证 eviction |

---

## 3. 文档一致性（Documentation Consistency）

### 3.1 必须同步的文档

| 文档 | 最后同步 commit | 当前一致？ | 备注 |
|------|-----------------|-----------|------|
| `docs/06-implementation-log.md` | pending | pending | 需包含 Batch 4 所有实现条目 |
| `docs/10-coverage-matrix.md` | pending | pending | 需更新 Token Accounts / WS production 状态 |
| `docs/14a-devnet-e2e-run-log.md` | pending | pending | 需包含 Batch 4 smoke run |
| `docs/15-phase1-execution-matrix.md` | pending | pending | 需包含 Batch 4 tracking + exception |

### 3.2 API 文档与实现对照

| 能力 | 代码入口 | 文档映射 | 一致？ |
|------|----------|----------|--------|
| `getTokenAccountBalance` | `rpc/client.zig` | `docs/03c` + `docs/10` | pending |
| `getTokenSupply` | `rpc/client.zig` | `docs/03c` + `docs/10` | pending |
| WS heartbeat / timeout | `rpc/ws_client.zig` | `docs/10` | pending |
| WS backoff hardening | `rpc/ws_client.zig` | `docs/10` | pending |

---

## 4. 发布判定（Release Verdict）

### 4.1 判定条件

| 条件 | 状态 | 备注 |
|------|------|------|
| 全量测试通过（无新增 blocker） | pending | |
| 内存检查通过（零泄漏） | pending | |
| 文档一致（docs/06/10/14a/15 同步） | pending | |
| Batch 4 gate 全部 PASS | pending | G-P2D-01~05 |
| 无未收敛 exception | pending | |

### 4.2 Exception Register（Batch 4）

| Exception | 原因 | 后续收敛阶段 | release verdict 影响 |
|-----------|------|-------------|---------------------|
| (暂无) | | | |

### 4.3 Release Verdict

- **Verdict**: `(pending — 待 #37/#38/#40 全部闭环后填写)`
- **判定日期**: `(pending)`
- **判定人**: `@CC-Opus`

可选值：
- `可发布` — 无未收敛 exception，所有 gate PASS
- `有条件发布` — 存在已登记 exception，gate PASS-with-exception
- `不可发布` — 存在 gate FAIL 或关键 blocker

---

## 5. 配套文档

- 范围冻结：`docs/22-phase2-batch4-planning.md`
- 实现日志：`docs/06-implementation-log.md`
- 覆盖矩阵：`docs/10-coverage-matrix.md`
- E2E 运行记录：`docs/14a-devnet-e2e-run-log.md`
- 执行矩阵：`docs/15-phase1-execution-matrix.md`
