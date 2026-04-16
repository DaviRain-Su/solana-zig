# Product Phase 2 Batch 5 Planning

**Date**: 2026-04-16  
**Status**: Planning draft（`#43 P2-21`）  
**Owner**: `#43`  
**Depends on**: `docs/00-roadmap.md`, `docs/03a-interfaces-spec.md`, `docs/03c-rpc-extended-spec.md`, `docs/22-phase2-batch4-planning.md`, `docs/23-release-readiness-checklist.md`, `docs/10-coverage-matrix.md`, `docs/14a-devnet-e2e-run-log.md`

> 本文用于冻结 Product Phase 2 第五批范围、DoD、执行顺序与 gate。  
> 在本文过审前，第五批实现任务保持冻结，不进入实现提交。

## 1. 背景与目标

Phase 2 Batch 1~4 已闭环并达到 `final: 可发布`。Batch 5 聚焦“可用能力继续扩展 + 生产可观测性 + 发布动作自动化”三条线：
1. 在已有 Token 查询能力基础上，补齐 SPL Token 指令构建的最小可用闭环
2. 将 websocket 从“hardening”推进到“可观测可诊断”的生产基线
3. 把发布前清单从文档流程升级为可执行自动化 preflight

Batch 5 目标：
1. 交付可复用的 SPL Token 指令 builders（不进入完整 token product surface）
2. 交付 websocket 观测面（指标/状态快照）并有可复现证据
3. 交付发布前自动化脚本与标准化产物

## 2. In Scope（冻结版）

### 2.1 P2-22：SPL Token 指令集深化（builder 层）

最小交付：
- 新增 `interfaces/token` 模块（或等价冻结写集）并实现最小 builders：
  - `transferChecked`
  - `closeAccount`
- 每条指令必须有：
  - 字节序列化对照测试
  - 参数边界/错误语义测试
  - compile/sign 级别流程证据

integration 口径（Batch 5 固定模型）：
- 默认要求 `public devnet` 或 `local-live` 至少 1 条可复现流程证据
- 若仅能提供 compile/sign（无稳定链上执行），必须在 `docs/15` 显式登记 `Batch 5 exception`（原因 + 后续收敛阶段）

### 2.2 P2-23：Websocket 生产可观测性（observability）

最小交付：
- 增加最小观测指标/状态面（至少包含）：
  - `reconnect_attempts_total`（counter）
  - `active_subscriptions`（state）
  - `dedup_dropped_total`（counter）
  - `last_error_code`（nullable state）
  - `last_error_message`（nullable state）
  - `last_reconnect_unix_ms`（nullable state）
- 提供查询接口（snapshot）与测试证据
- 保持 deterministic backoff 模型，不引入 jitter
- 不新增订阅类型，只增强现有行为的可观测性

snapshot schema 冻结规则：
- 字段名按上述列表冻结，必须全部公开（可为 nullable 的字段可为空）
- `counter` 字段必须单调不减
- `state` 字段必须反映最近一次事件后的可诊断状态

### 2.3 P2-24：发布前自动化（preflight automation）

最小交付：
- 新增可执行 preflight 脚本（或等价命令封装），统一收集：
  - build/test 状态
  - smoke 状态
  - docs 一致性检查状态
  - release verdict 输入
- 输出标准化报告文件（markdown 或 json）
- 产出 Batch 5 专属 checklist：`docs/25-batch5-release-readiness.md`
- 与 `docs/23-release-readiness-checklist.md` 保持口径兼容，但不覆盖 Batch 4 已锁 final artifact
- 保留人工复核入口

## 3. Out of Scope（Batch 5 非目标）

1. 完整 SPL Token 产品接口（mint/burn/freeze/ATA 全家桶）
2. websocket 新协议/新订阅族扩展
3. C ABI 与多语言绑定扩展（Phase 3）
4. 发布系统外部平台接入（仅仓内 preflight）

## 4. 执行顺序与依赖

### 4.1 串并行规则

1. `#43` 通过前：第五批实现提交冻结  
2. `#43` 通过后：
   - `P2-22` 与 `P2-23` 可并行
   - `P2-24` 依赖 `P2-22/P2-23` 证据并并行收敛
   - docs/gate 跟随线实时回写

### 4.2 写集归属（冻结）

- `P2-22`：`src/solana/interfaces/token.zig`（或同级唯一 token 模块文件）+ `src/solana/mod.zig` + 必要测试写集
- `P2-23`：`src/solana/rpc/ws_client.zig` + 必要测试写集
- `P2-24`：`scripts/*` + `docs/25-batch5-release-readiness.md`（docs/automation only）

## 5. Gate / DoD

### G-P2E-01 Test Gate（canonical）

所有提审线统一三件套：
- clean `git status`
- commit hash
- 单次全量 `zig build test` 原始结果

并满足：
- 无新增编译 blocker
- 无新增 leak / 死锁信号

### G-P2E-02 SPL Token Builder Gate（P2-22）

- `transferChecked` / `closeAccount` builder 落地
- 每方法至少 `happy + boundary/error` 测试
- 至少 1 条 compile/sign 流程证据
- integration 口径（Batch 5 固定模型）：
  - 默认要求 `public devnet` 或 `local-live` 流程证据
  - 若仅 compile/sign，必须登记 `Batch 5 exception`

### G-P2E-03 WS Observability Gate（P2-23）

- snapshot 必须包含并公开以下冻结字段：
  - `reconnect_attempts_total`
  - `active_subscriptions`
  - `dedup_dropped_total`
  - `last_error_code`
  - `last_error_message`
  - `last_reconnect_unix_ms`
- 观测计数/状态变更有可复现测试证据：
  - counter 字段单调不减
  - reconnect 后 `last_reconnect_unix_ms` 更新
  - failure-path 后 `last_error_*` 更新
- 与现有 reconnect/resubscribe/dedup 行为不冲突
- deterministic backoff 模型保持不变

### G-P2E-04 Preflight Automation Gate（P2-24）

- preflight 脚本可执行，输出标准化报告
- 报告至少包含：test/smoke/docs/release verdict inputs
- 与 `docs/23` 判定口径一致，不产生双轨标准
- 结论支持 `可发布 / 有条件发布 / 不可发布`
- smoke / exception / verdict 关系冻结：
  - 默认必需 smoke：`public devnet` + `local-live`
  - 任一 smoke 缺失或不稳定时，必须在 `docs/15` 登记 `Batch 5 exception`（原因 + 收敛阶段）
  - 有未收敛 exception 时，本批 verdict 只能是 `有条件发布` 或 `不可发布`
  - 仅当无未收敛 exception 时，才允许 `可发布`

### G-P2E-05 Docs Gate（持续对账）

每条任务提审必须同步回写：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/15-phase1-execution-matrix.md`（继续承载 Phase 2 tracking）
- live/smoke 证据落点：`docs/14a-devnet-e2e-run-log.md`
- release 总结：`docs/25-batch5-release-readiness.md`

## 6. Housekeeping（非产品 gate）

以下项仅做看板治理，不作为第五批产品放行条件：
- `#15` 继续维持凭证阻塞状态（发布凭证任务独立处理）

## 7. 放行条件

第五批实现任务进入提交前需满足：
1. 本文完成结构性 review 并确认冻结
2. 每条任务线程显式引用本文 gate
3. owner 与写集冲突清理完成
