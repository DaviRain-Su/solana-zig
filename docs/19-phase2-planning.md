# Product Phase 2 Planning

**Date**: 2026-04-16  
**Status**: Draft frozen for review (A 方案)  
**Owner**: `#16 P2-1`

> 本文用于锁定 Product Phase 2 第一批实现范围、DoD 与执行顺序。  
> 在本文通过评审前，`#17/#18/#20` 不应被表述为“已按本计划正式放行”。

## 1. 背景与目标

Phase 1 的核心实现已明显收敛，但 closeout 尚未最终宣告完成。  
因此这里把 Phase 2 作为**提前规划文档**，优先梳理后续高价值路径：

1. `sendTransaction` live send/confirm 证据  
2. 更广泛 RPC typed parse 扩展  
3. Websocket 订阅最小可用能力

Phase 2 第一批目标：**把“可发送 + 可订阅 + 可结构化解析”形成可复现闭环**。

## 2. 第一批范围（In Scope）

### 2.1 `#17 P2-2` — sendTransaction/confirm 真实链路

- 在 live 环境补齐：`construct -> sign -> send -> confirm`
- 覆盖最小失败路径：
  - 签名无效
  - 余额/资金不足（或等价链上拒绝）
  - 超时/未确认
- 证据落点：
  - `docs/14a-devnet-e2e-run-log.md`
  - `docs/15-phase1-execution-matrix.md`（Phase 2 条目延续写入本矩阵）

### 2.2 `#18 P2-3` — 扩展 RPC Batch A

Batch A 固定为 3 个方法（与 `docs/00` / `docs/03c` 对齐）：

1. `getTransaction`
2. `getSignaturesForAddress`
3. `getSlot`

每个方法必须具备：

- typed parse
- `happy`
- `rpc_error`
- `malformed/invalid response`

### 2.3 `#20 P2-4b` — Websocket 最小可用（订阅目标以文档定义为准）

最低订阅集合：

1. `accountSubscribe`
2. `logsSubscribe`
3. `signatureSubscribe`

最低生命周期能力：

- connect
- disconnect detect
- reconnect
- unsubscribe

## 3. 非目标（Out of Scope for Batch 1）

本批不做以下内容：

1. Phase 2 全量 RPC（仅 Batch A 三方法）
2. Durable Nonce 全流程
3. Priority Fees / Compute Budget 指令层完整实现
4. JS/TS 子包发布与改名（仍保持非主线）

## 4. 执行顺序与依赖

## 4.1 串行/并行规则

1. `#17` 与 `#18` 可并行
2. `#20` 可在 `#18` typed parse 框架稳定后并行推进
3. 文档统一回写在每条线提审时同步完成，不做“最后一次性补文档”

### 4.2 推荐顺序

1. `#17`（优先消化 Phase 1 exception）
2. `#18`（Batch A typed parse）
3. `#20`（Websocket 最小可用）
4. 收口复核（gate consistency + docs 对账）

## 5. Gate / DoD

## G-P2-01 Test Gate

- `zig build test` 通过
- 无新增内存泄漏
- 无编译 blocker

## G-P2-02 Send Gate（#17）

- live `send + confirm` 证据可复现（public devnet 或 local validator/surfnet）
- 至少 1 条成功 + 1 条失败证据留档

> Batch 1 放行解释（残项固化）：  
> 若 live 环境的失败场景受外部条件影响而不稳定，可采用
> - `1` 条稳定的 live success（send + confirm）
> - 外加代码层失败分支覆盖与已有失败测试证据
> 作为当前批次放行依据；该解释需在 `docs/06` 与执行矩阵中留痕。

## G-P2-03 RPC Gate（#18）

- Batch A 三方法全部达到 typed parse + 三类用例覆盖
- 每方法有明确错误语义与生命周期处理

## G-P2-04 WS Gate（#20）

- 三类订阅可建立、可重连、可取消
- 至少 1 条断线重连路径验证

## G-P2-05 Docs Gate

每条任务提审必须同步回写：

- `docs/06-implementation-log.md`
- `docs/07-review-report.md`（必要时）
- `docs/10-coverage-matrix.md`
- `docs/14a-devnet-e2e-run-log.md`（若涉及 live）
- `docs/15-phase1-execution-matrix.md`（新增 Phase 2 条目，统一落点）

## 6. 证据环境角色

- `mock`: parser 边界与错误语义稳定性
- `local validator/surfnet`: 可控 live 复现
- `public devnet`: 对外可复现的真实网络证据

要求：至少 `mock + 1 live`；关键链路优先补 public devnet 证据。

## 7. 任务分配建议（冻结版）

1. `#17`：@CC（live send/confirm 链路 + 证据留档）
2. `#18`：@codex_5_3（Batch A typed parse + 边界用例）
3. `#20`：@kimi（Websocket 最小可用 + 生命周期测试）
4. 跨线复核：@codex_5_4（gate consistency / docs 对账）

> 若 owner 变更，需在任务线程显式同步，避免并行冲突。

## 8. 进入实现的放行条件

以下条件全部满足才放行 `#17/#18/#20` 进入实现：

1. 本文档被确认执行（当前为 review-frozen，待确认）
2. owner 冲突清理完成
3. 每条任务线程有明确 DoD 引用（指向本文）
