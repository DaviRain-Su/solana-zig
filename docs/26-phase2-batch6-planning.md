# Product Phase 2 Batch 6 Planning

**Date**: 2026-04-16  
**Status**: Planning draft（`#48 P2-26`）  
**Owner**: `#48`  
**Depends on**: `docs/00-roadmap.md`, `docs/03a-interfaces-spec.md`, `docs/03c-rpc-extended-spec.md`, `docs/24-phase2-batch5-planning.md`, `docs/25-batch5-release-readiness.md`, `docs/10-coverage-matrix.md`, `docs/14a-devnet-e2e-run-log.md`

> 本文用于冻结 Product Phase 2 第六批范围、DoD、执行顺序与 gate。  
> 在本文过审前，第六批实现任务保持冻结，不进入实现提交。

## 1. 背景与目标

Phase 2 Batch 1~5 已闭环，Batch 5 当前状态为 `final: 有条件发布`（等待 smoke 收敛升级）。  
Batch 6 聚焦三条主线：
1. SPL Token 从“builder 可用”推进到“交易流可验证”
2. Websocket 从“可观测”推进到“可恢复性深化”
3. 发布前从“脚本可执行”推进到“流水线固化”

Batch 6 目标：
1. 完成 SPL Token 最小交易流（build -> compile/sign -> send/confirm 证据）
2. 完成 websocket recoverability 的可复现验收证据
3. 固化发布流水线输入输出，减少人工拼装步骤

## 2. In Scope（冻结版）

### 2.1 P2-27：SPL Token 交易流（Flow）

最小交付：
- 复用 Batch 5 的 `transferChecked` / `closeAccount` builders，形成最小交易流验证：
  - compose instruction
  - compile/sign transaction
  - 默认成功路径：至少一条 `send/confirm` 证据
- 增加 flow 级别测试：
  - happy path
  - account/meta mismatch failure path（最小一条）

integration 口径（Batch 6 固定模型）：
- 默认要求 `public devnet` 或 `local-live` 至少 1 条 `send/confirm` 可复现流程证据
- 若本批只能达到 `compile/sign + simulate`（无 `send/confirm`），必须在 `docs/15` 登记 `Batch 6 exception`（原因 + 收敛阶段）

### 2.2 P2-28：Websocket 可恢复性深化（Recoverability）

最小交付：
- 在现有 observability 基础上补 recoverability 证据：
  - reconnect storm 场景下 backoff 行为稳定
  - resubscribe/recovery 后状态一致性
  - 断线/恢复期间消息处理边界可复现（不要求新增订阅类型）
- 保持 deterministic backoff 模型，不引入 jitter

### 2.3 P2-29：发布流水线固化（Release Pipeline）

最小交付：
- 将 Batch 5 preflight 结果纳入固定流水线入口（脚本层/CI 入口二选一，至少一条固定主入口）
- 统一产物规范：
  - preflight 报告路径
  - smoke 日志路径
  - release verdict 输入项
- 产出 Batch 6 专属 release artifact：`docs/27-batch6-release-readiness.md`
- 与 `docs/25-batch5-release-readiness.md` 口径兼容，但不覆盖 Batch 5 已锁结论

## 3. Out of Scope（Batch 6 非目标）

1. SPL Token 完整生命周期接口（mint/burn/freeze/ATA 扩展）
2. websocket 新协议或新订阅族
3. 多链/多环境发布编排
4. C ABI 与语言绑定扩展

## 4. 执行顺序与依赖

### 4.1 串并行规则

1. `#48` 通过前：第六批实现提交冻结  
2. `#48` 通过后：
   - `P2-27` 与 `P2-28` 可并行
   - `P2-29` 依赖 `P2-27/P2-28` 证据并并行收敛
   - docs/gate 跟随线实时回写

### 4.2 写集归属（冻结）

- `P2-27`：`src/solana/interfaces/token.zig` + `src/solana/tx/legacy.zig`（仅 compile/sign 适配需要时触碰）+ 必要测试写集
- `P2-28`：`src/solana/rpc/ws_client.zig` + 必要测试写集
- `P2-29`：`scripts/release/*` + `docs/27-batch6-release-readiness.md`（流水线/文档口径）

## 5. Gate / DoD

### G-P2F-01 Test Gate（canonical）

所有提审线统一三件套：
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

并满足：
- 无新增编译 blocker
- 无新增 leak / 死锁信号

### G-P2F-02 SPL Token Flow Gate（P2-27）

- 默认成功模型：`build -> compile/sign -> send/confirm`（至少一条可复现链路）
- 至少 1 条 flow failure-path 证据
- integration 口径（Batch 6 固定模型）：
  - 默认 `public devnet` 或 `local-live` 至少一侧 `send/confirm` 通过
  - 若仅 `compile/sign + simulate`（无 `send/confirm`），必须登记 `Batch 6 exception`

### G-P2F-03 WS Recoverability Gate（P2-28）

- 最小证据集（机械验收）：
  - 1 条 `reconnect storm/backoff` 稳定性证据
  - 1 条 recovery 后状态一致性证据（`active_subscriptions` 恢复一致）
  - 1 条断线/恢复消息边界证据（消息 drop 或边界行为必须可观测并可复现）
- 上述证据必须可由 `snapshot()/WsStats` 字段证明（至少包含）：
  - `reconnect_attempts_total`
  - `active_subscriptions`
  - `dedup_dropped_total`
  - `last_error_code` / `last_error_message`
  - `last_reconnect_unix_ms`
- deterministic backoff 保持不变

### G-P2F-04 Release Pipeline Gate（P2-29）

- preflight 主入口固定并可执行
- 输出产物路径与字段规范固定
- `docs/27` 回填链路可重复执行
- release verdict 支持：`可发布 / 有条件发布 / 不可发布`

### G-P2F-05 Docs Gate（持续对账）

每条任务提审必须同步回写：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/14a-devnet-e2e-run-log.md`
- `docs/15-phase1-execution-matrix.md`
- `docs/27-batch6-release-readiness.md`

## 6. Housekeeping（非产品 gate）

以下项仅做看板治理，不作为第六批产品放行条件：
- `#15` 继续维持凭证阻塞状态（发布凭证任务独立处理）

## 7. 放行条件

第六批实现任务进入提交前需满足：
1. 本文完成结构性 review 并确认冻结
2. 每条任务线程显式引用本文 gate
3. owner 与写集冲突清理完成
