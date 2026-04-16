# Product Phase 2 Batch 3 Planning

**Date**: 2026-04-16  
**Status**: Planning draft（`#31 P2-11`）  
**Owner**: `#31`  
**Depends on**: `docs/00-roadmap.md`, `docs/03c-rpc-extended-spec.md`, `docs/03a-interfaces-spec.md`, `docs/20-phase2-batch2-planning.md`

> 本文用于冻结 Product Phase 2 第三批范围、DoD、执行顺序与 gate。  
> 在本文过审前，第三批实现任务保持冻结，不进入实现提交。

## 1. 背景与目标

Phase 2 前两批已完成：
- Batch 1：send/confirm、RPC Batch A、Websocket 最小可用收口
- Batch 2：RPC Batch B、Durable Nonce 最小可用、ComputeBudget builders 收口

第三批目标：
1. 补齐高频查询能力 `getTokenAccountsByOwner`
2. 对 websocket 做 re-stabilize / re-expose 收口（按当前文档基线，不直接承诺已公开能力上的“增量增强”）
3. 把 Nonce workflow 从“最小可用”推进到“live 证据可复现”

## 2. In Scope（冻结版）

### 2.1 P2-12：`getTokenAccountsByOwner` typed parse + 边界测试

最小交付：
- `getTokenAccountsByOwner` 方法实现
- typed parse 最小稳定子集（账户 pubkey、owner、lamports、data/encoding 旁路）
- 三类方法级测试：`happy + rpc_error + malformed`
- integration 证据（Batch 3 固定模型）：
  - 默认要求 `public devnet` integration 证据
  - 若本批只能提供 `local-live`，必须在 `docs/15` 显式登记 `Batch 3 exception`（原因 + 后续收敛阶段）

### 2.2 P2-13：Websocket re-stabilize / re-expose gate

最小交付：
- reconnect/backoff 行为增强（可配置重试上限与间隔）
- resubscribe 幂等性保障（避免重复订阅污染）
- notification 去重策略（最小可行）
- 失败路径补强（malformed/connection flap）

说明：本条以当前 `docs/10` 基线为准（websocket prototype 不作为默认/公开能力承诺），目标是完成可再次公开的稳定化 gate，不扩订阅种类范围。

### 2.3 P2-14：Nonce live 深化

最小交付：
- 在 live 环境复现 `query nonce -> build advance -> compile/sign -> send/confirm`（local 优先）
- 形成一条稳定 run-log 证据（必要时可先 local-live，再补 public）
- 若链语义或环境依赖导致不稳定，按 Batch 规则登记例外

## 3. Out of Scope（Batch 3 非目标）

1. Token 全接口层（`token/token-2022/ATA`）完整实现
2. websocket 新订阅类型扩展（仅增强现有 lifecycle）
3. signers/C ABI（Phase 3）
4. 链上程序支持（Phase 4）

## 4. 执行顺序与依赖

### 4.1 串并行规则

1. `#31` 通过前：第三批实现提交冻结
2. `#31` 通过后：
   - `P2-12` 与 `P2-13` 可并行
   - `P2-14` 建议在 `P2-12` 稳定后并行（依赖部分 RPC 能力）
   - docs/gate 跟随线全程实时回写

### 4.2 推荐顺序

1. `P2-12`（先补高频 RPC 缺口）
2. `P2-13`（并行增强 websocket 稳态）
3. `P2-14`（Nonce live 深化并留证）

## 5. Gate / DoD

## G-P2C-01 Test Gate（canonical）

所有提审线统一三件套：
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

并满足：
- 无新增编译 blocker
- 无新增 leak / 死锁信号

## G-P2C-02 RPC Gate（P2-12）

- `getTokenAccountsByOwner` 完成 typed parse
- 三类方法级测试齐全：`happy + rpc_error + malformed`
- integration 口径（Batch 3 固定模型）：
  - 默认要求 `public devnet` integration 证据
  - 若本批只能提供 `local-live`，必须在 `docs/15` 显式登记 `Batch 3 exception`（原因 + 后续收敛阶段）

## G-P2C-03 WS Hardening Gate（P2-13）

- reconnect/backoff 可验证
- resubscribe 幂等性有测试证据
- 至少 1 条 failure-path 强化证据
- notification 去重策略有明确测试证据（至少 1 条“重复通知不重复交付/不污染状态”用例）

## G-P2C-04 Nonce Live Gate（P2-14）

- `query -> build -> compile/sign -> send/confirm` 至少 1 条可复现 live 证据
- 若仅可 local-live，需在执行矩阵登记例外与后续收敛阶段

## G-P2C-05 Docs Gate（持续对账）

每条任务提审必须同步回写：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/15-phase1-execution-matrix.md`（继续承载 Phase 2 tracking）
- live 证据落点固定：
  - `P2-12` 若产生 integration run（devnet/local-live）并需留可复现日志，写入 `docs/14a-devnet-e2e-run-log.md`
  - `P2-14` 的 Nonce live run 证据必须写入 `docs/14a-devnet-e2e-run-log.md`

## 6. Housekeeping（非产品 gate）

以下项仅做看板治理，不作为第三批产品放行条件：
- `#22` 标记为 superseded（由 `#25` 取代）
- `#15` 保持 paused（等待独立发布决策）

## 7. 放行条件

第三批实现任务进入提交前需满足：
1. 本文完成结构性 review 并确认冻结
2. 每条任务线程显式引用本文 gate
3. owner 与写集冲突清理完成
