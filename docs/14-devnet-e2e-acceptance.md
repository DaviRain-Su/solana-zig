# Devnet E2E Acceptance Guide

**Date**: 2026-04-16

> 本文定义 Product Phase 1 的 Devnet 验收目标、执行说明和证据留档方式，并明确区分：包装脚本、当前 in-tree live harness，以及最终 closeout 判定所需的证据包边界。

## 1. Goal

当前仓库状态下，Devnet 验收应拆成两层理解：

- **已落地的真实 in-tree live harness**：在配置 `SOLANA_RPC_URL` 时，通过 `zig build devnet-e2e` 已可留下两类 live 证据：
  - `construct -> sign -> simulate`
  - `construct -> sign -> sendTransaction`
- **已补齐的 closeout 相关 live 证据**：`docs/14a` 已记录 send 后的确认留档，可把 `simulate/send/confirm` 串成完整 E2E evidence pack。
- **最终 closeout 目标**：将这些 live 证据与 mock / 离线门禁 / 执行矩阵一起组成可审计的 closeout evidence pack。

换言之：`sendTransaction` live 证据已经纳入当前 harness；当前是否能宣称 Phase 1 closeout，取决于 `docs/15` 的整体收口状态，而不再是“send 证据缺失”。

## 2. Acceptance Scope

Phase 1 当前需要把以下三类能力区分清楚：

- **包装式验收路径**：`scripts/devnet/phase1_acceptance.sh`
  - 记录 commit / 时间 / endpoint / 离线门禁结果
  - 不直接执行真实 RPC live flow
- **真实 in-tree live harness**：`zig build devnet-e2e`
  - mock 路径始终可跑
  - 在设置 `SOLANA_RPC_URL` 时执行真实 live case
  - 当前已覆盖 `simulateTransaction` 与 `sendTransaction` 两条链路的 live 证据
  - send 后的确认留档见 `docs/14a` 对应 run 记录
- **最终 closeout 判定**：
  - 不能只看某一次 live run 就宣布 Phase 1 全部完成
  - 仍需结合 `docs/15-phase1-execution-matrix.md` 的整体状态统一判定

**重要**：
- 包装脚本通过 `!=` 真实 Devnet harness 完成。
- 已有 `simulate/send/confirm` live 证据 `!=` Product Phase 1 已自动 closeout。

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
- live case 当前覆盖：
  - `construct / sign / verify / simulate`
  - `requestAirdrop / getBalance / construct / sign / sendTransaction`
- send 后的确认留档可通过 `docs/14a` 对应 run 继续补全 closeout evidence pack
- public devnet 若遇到 airdrop rate limit，可保留 skip / fallback 日志；local surfnet 仍可作为可控 live 证据

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

若执行 `sendTransaction` live case，则额外记录：
- send 阶段是否执行
- 返回 signature / rpc_error / transport error
- 发送后的结果摘要
- 若依赖 airdrop / 余额预热，需记录 funding 方式与是否成功

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
- 若只有单条 live 证据，也不得跳过 `docs/15` 的整体收口判定直接宣称 Phase 1 closeout

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
- 若宣称“当前 in-tree Devnet live harness 已存在”，应至少有 `simulate` 或 `sendTransaction` 的 live 证据
- 若宣称“当前 closeout evidence pack 已包含完整 `construct -> sign -> simulate -> send -> confirm` 路径证据”，应引用 `docs/14a` 中的 simulate + send + confirm run
- 若宣称“Product Phase 1 已 closeout”，仍必须满足 `docs/11` 与 `docs/15` 的整体规则
