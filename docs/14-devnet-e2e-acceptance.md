# Devnet E2E Acceptance Guide

**Date**: 2026-04-16

> 本文定义 Product Phase 1 的 Devnet 验收目标、执行说明和证据留档方式，并明确区分：包装脚本、当前 in-tree live harness，以及尚未补齐的 `sendTransaction` live 路径。

## 1. Goal

当前仓库状态下，Devnet 验收应拆成两层理解：

- **已落地的真实 in-tree live harness**：在配置 `SOLANA_RPC_URL` 时，通过 `zig build devnet-e2e` 可复现 `construct -> sign -> simulate`。
- **仍待补齐的完整 closeout 目标**：若要宣称完整最小闭环已收口，仍需补 `sendTransaction` 的 live 证据，形成 `construct -> sign -> simulate -> send`。

换言之：仓库里已经有真实 harness，但它当前覆盖到 `simulateTransaction` 为止，还不能单独支撑“完整 send 路径已完成”的表述。

## 2. Acceptance Scope

Phase 1 当前需要把以下三类能力区分清楚：

- **包装式验收路径**：`scripts/devnet/phase1_acceptance.sh`
  - 记录 commit / 时间 / endpoint / 离线门禁结果
  - 不直接执行真实 RPC live flow
- **真实 in-tree live harness**：`zig build devnet-e2e`
  - mock 路径始终可跑
  - 在设置 `SOLANA_RPC_URL` 时执行真实 `getLatestBlockhash -> compileLegacy -> sign -> verify -> simulate`
- **仍未收口的 live send 路径**：
  - `sendTransaction` 的真实 Devnet 发送证据尚未纳入当前 harness
  - 因此不能把当前状态写成完整 `construct -> sign -> simulate -> send` 已完成

**重要**：
- 包装脚本通过 `!=` 真实 Devnet harness 完成。
- 真实 harness 跑通到 `simulate` `!=` 完整 `send` 闭环已完成。

## 3. Environment

必需：
- `SOLANA_RPC_URL`

建议：
- `SOLANA_RPC_URL` 指向公开 devnet 或稳定代理
- 本地记录当前 commit sha
- 保留执行日志
- 对 endpoint 做必要脱敏

## 4. Current Acceptance Commands

推荐区分两类命令：

### 4.1 真实 in-tree live harness

```bash
SOLANA_RPC_URL=<your-devnet-endpoint> zig build devnet-e2e
```

说明：
- 当前这是主证据入口
- 会运行 mock + live 两类 case
- live case 当前覆盖 `construct / sign / verify / simulate`
- 尚不覆盖 `sendTransaction` live 发送

### 4.2 包装式验收脚本

```bash
SOLANA_RPC_URL=<your-devnet-endpoint> scripts/devnet/phase1_acceptance.sh
```

说明：
- 当前脚本会记录 commit、时间和测试日志
- 当前脚本 **不会** 在仓库内直接执行真实的 Devnet 交易 live flow
- 当前脚本通过时，只能证明“包装式验收路径可运行”，不能单独证明“真实 Devnet harness 已完成”

## 5. Evidence to Capture

每次包装式验收至少留档：
- commit sha
- 执行时间
- RPC endpoint（可脱敏）
- 是否通过
- 当前脚本的失败阶段（setup / offline-test / env）
- 日志路径

每次真实 harness 运行至少留档：
- commit sha
- 执行时间
- RPC endpoint（可脱敏）
- run type（mock-harness / real-harness）
- 失败阶段（env / getLatestBlockhash / construct / sign / verify / simulate）
- 控制台摘要或 artifact 路径

若后续引入 `sendTransaction` live 路径，则额外记录：
- send 阶段是否执行
- 返回 signature / rpc_error / transport error
- 发送后的结果摘要

## 6. Suggested Acceptance Steps

1. 确认 `SOLANA_RPC_URL` 可访问
2. 优先执行真实 harness：`zig build devnet-e2e`
3. 如需补留档，再执行包装脚本
4. 若失败，先区分：
   - 环境不稳定
   - 离线门禁失败
   - harness / 文档行为不一致
   - live RPC 路径异常
5. 将结果摘要写入 `docs/06-implementation-log.md`
6. 将运行细节记录到 `docs/14a-devnet-e2e-run-log.md`
7. 若存在系统性风险，同步写入 `docs/07-review-report.md`

## 7. Failure Handling Rules

- Devnet 外部故障不应直接否定离线能力
- 但若相同失败可稳定复现，必须按产品缺陷处理
- 若依赖外部环境波动，需在日志中明确标记为 `env-flaky`
- 若当前只有包装脚本通过，不得把结果表述为“真实 Devnet harness 已完成”
- 若当前只有 `construct -> sign -> simulate` live 证据，不得把结果表述为“完整 `construct -> sign -> simulate -> send` 已完成”

## 8. Task Mapping

| 验收内容 | 对应任务 |
|---|---|
| live harness / env gate | `T4-14` |
| 可复现示例 / send 路径补齐 | `T4-15` |
| 文档收口 | `T4-16` |

## 9. Acceptance Criteria

- 包装脚本可执行
- 至少产出一份 `zig build devnet-e2e` 真实 harness 日志
- 日志中可追踪 commit 与执行时间
- 文档说明与 harness 行为一致
- 若宣称“当前 in-tree Devnet live harness 已存在”，`construct -> sign -> simulate` 证据即可支撑
- 若宣称“完整 Devnet E2E (`construct -> sign -> simulate -> send`) 已完成”，必须另有 `sendTransaction` live 证据
