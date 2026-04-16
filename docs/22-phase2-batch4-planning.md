# Product Phase 2 Batch 4 Planning

**Date**: 2026-04-16  
**Status**: Planning draft（`#36 P2-16`）  
**Owner**: `#36`  
**Depends on**: `docs/00-roadmap.md`, `docs/03c-rpc-extended-spec.md`, `docs/21-phase2-batch3-planning.md`, `docs/10-coverage-matrix.md`

> 本文用于冻结 Product Phase 2 第四批范围、DoD、执行顺序与 gate。  
> 在本文过审前，第四批实现任务保持冻结，不进入实现提交。

## 1. 背景与目标

Phase 2 Batch 1~3 已闭环，当前缺口集中在两类：
1. Token Accounts 生产可用度仍偏“查询单点”，缺少围绕账户余额/供应等常见读取能力的最小闭环
2. Websocket 已完成 re-stabilize/re-expose，但距离 production hardening 仍有工程化缺口（连接健康、资源回收、边界压测）

Batch 4 目标：
1. 完成 Token Accounts 查询能力的第二层收口（在不进入 Phase 3 token interface 的前提下）
2. 完成 websocket production hardening 最小闭环
3. 输出可执行的发布前技术清单（release checklist）并形成可复现实证

## 2. In Scope（冻结版）

### 2.1 P2-17：Token Accounts 深化（查询层）

最小交付：
- 新增 `getTokenAccountBalance` typed parse + `happy/rpc_error/malformed`
- 新增 `getTokenSupply` typed parse + `happy/rpc_error/malformed`
- 与已完成 `getTokenAccountsByOwner` 形成查询闭环的最小样例测试

integration 口径（Batch 4 固定模型）：
- 默认要求 `public devnet` integration 证据
- 若本批只能提供 `local-live`，必须在 `docs/15` 显式登记 `Batch 4 exception`（原因 + 后续收敛阶段）

### 2.2 P2-18：Websocket production hardening

最小交付：
- 连接健康管理：heartbeat（ping/pong）与读写超时策略
- reconnect/backoff 的上限与抖动（或明确固定退避模型）
- subscription cleanup 与 reconnect 后状态一致性验证
- 在现有 dedup 基础上增加窗口/缓存边界测试（防止无限增长）

说明：本条是 production hardening，不扩新增订阅类型。

### 2.3 P2-19：发布前技术清单（release readiness）

最小交付：
- 建立 Batch 4 发布前清单文档条目（测试、性能、内存、文档一致性）
- 至少 1 次 local-live + 1 次 public devnet 的 smoke 证据（若 devnet 不稳定按 exception 规则登记）
- 输出“可发布/不可发布”判定条件

## 3. Out of Scope（Batch 4 非目标）

1. Token program 完整接口层（transfer/mint/burn/ATA 等）——归 Phase 3 interfaces
2. 新 websocket 订阅类型扩展（仅 hardening 现有能力）
3. C ABI、signers 抽象扩展（Phase 3）
4. 链上程序支持（Phase 4）

## 4. 执行顺序与依赖

### 4.1 串并行规则

1. `#36` 通过前：第四批实现提交冻结
2. `#36` 通过后：
   - `P2-17` 与 `P2-18` 可并行
   - `P2-19` 依赖 `P2-17/P2-18` 的证据输出并并行收敛
   - docs/gate 跟随线全程实时回写

### 4.2 推荐顺序

1. `P2-17`（先补查询层核心缺口）
2. `P2-18`（并行推进生产硬化）
3. `P2-19`（汇总发布前技术判定）

## 5. Gate / DoD

### G-P2D-01 Test Gate（canonical）

所有提审线统一三件套：
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

并满足：
- 无新增编译 blocker
- 无新增 leak / 死锁信号

### G-P2D-02 Token Accounts Gate（P2-17）

- `getTokenAccountBalance` / `getTokenSupply` typed parse 完成
- 每方法三类测试齐全：`happy + rpc_error + malformed`
- integration 口径（Batch 4 固定模型）：
  - 默认要求 `public devnet`
  - 若仅 `local-live`，必须在 `docs/15` 登记 `Batch 4 exception`

### G-P2D-03 WS Production Gate（P2-18）

- heartbeat + timeout 行为可验证
- reconnect/backoff 在连接波动场景可验证
- cleanup + state consistency 有测试证据
- dedup/cache 边界有至少 1 条可复现证据

### G-P2D-04 Release Readiness Gate（P2-19）

- 发布前技术清单落盘并与当前实现状态一致
- smoke 证据完整（local-live + public devnet；若 devnet 不稳定按 exception 规则）
- 给出明确“可发布/不可发布”判定

### G-P2D-05 Docs Gate（持续对账）

每条任务提审必须同步回写：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/15-phase1-execution-matrix.md`（继续承载 Phase 2 tracking）
- live/integration 证据落点：`docs/14a-devnet-e2e-run-log.md`

## 6. Housekeeping（非产品 gate）

以下项仅做看板治理，不作为第四批产品放行条件：
- `#15` 维持凭证阻塞状态（发布任务独立处理，不阻塞产品实现线）

## 7. 放行条件

第四批实现任务进入提交前需满足：
1. 本文完成结构性 review 并确认冻结
2. 每条任务线程显式引用本文 gate
3. owner 与写集冲突清理完成
