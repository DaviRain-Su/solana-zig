# Devnet E2E Acceptance Guide

**Date**: 2026-04-16

> 本文定义 Product Phase 1 的 Devnet 验收目标、执行说明和证据留档方式，并区分“当前包装脚本”与“未来真正的 E2E harness”。

## 1. Goal

Product Phase 1 的目标仍是：在配置 `SOLANA_RPC_URL` 时，形成可复现的最小闭环：
- 构造交易
- 签名交易
- 模拟交易
- 发送交易

但截至当前仓库状态，**尚未提供真正的 in-tree Devnet E2E harness**；现有脚本只负责记录环境与执行离线门禁。

## 2. Acceptance Scope

Phase 1 不要求复杂业务场景，但需要把以下两类能力区分清楚：
- 当前已存在：外部/包装式验收路径，可记录 `SOLANA_RPC_URL`、commit、时间和 `zig build test` 结果
- 目标仍待落地：真实 Devnet `construct -> sign -> simulate -> send` 闭环 harness

**重要**：包装脚本通过 `!=` 真实 Devnet E2E 完成；只有真实 harness 留下的闭环证据，才能支持“Devnet E2E 已完成”的表述。

## 3. Environment

必需：
- `SOLANA_RPC_URL`

建议：
- `SOLANA_RPC_URL` 指向公开 devnet 或稳定代理
- 本地记录当前 commit sha
- 保留执行日志

## 4. Current Acceptance Command

当前建议使用的包装脚本：

```bash
SOLANA_RPC_URL=<your-devnet-endpoint> scripts/devnet/phase1_acceptance.sh
```

说明：
- 当前脚本会记录 commit、时间和测试日志
- 当前脚本 **不会** 在仓库内直接执行真实的 Devnet `construct / sign / simulate / send` 闭环
- 当前脚本通过时，只能证明“包装式验收路径可运行”，不能单独证明“真实 Devnet E2E 已完成”
- 随着 T4-14/T4-15 落地，应替换为真正的 E2E harness

## 5. Evidence to Capture

每次包装式验收至少留档：
- commit sha
- 执行时间
- RPC endpoint（可脱敏）
- 是否通过
- 当前脚本的失败阶段（setup / offline-test / env）
- 日志路径

若后续引入真正 E2E harness，则额外记录：
- 失败阶段（construct / sign / simulate / send / parse）

## 6. Suggested Acceptance Steps

1. 确认 `SOLANA_RPC_URL` 可访问
2. 执行当前包装脚本
3. 若失败，先区分：
   - 环境不稳定
   - 离线门禁失败
   - 包装脚本行为与文档不一致
4. 若需要真实 E2E 证据，使用自建 harness 直接调用 `RpcClient`
5. 将结果摘要写入 `docs/06-implementation-log.md`
6. 若存在系统性风险，同步写入 `docs/07-review-report.md`

## 7. Failure Handling Rules

- Devnet 外部故障不应直接否定离线能力
- 但若相同失败可稳定复现，必须按产品缺陷处理
- 若依赖外部环境波动，需在日志中明确标记为 `env-flaky`
- 若当前只有包装脚本通过，不得把结果表述为“真实 Devnet E2E 已完成”

## 8. Task Mapping

| 验收内容 | 对应任务 |
|---|---|
| E2E harness / env gate | `T4-14` |
| 可复现示例 | `T4-15` |
| 文档收口 | `T4-16` |

## 9. Acceptance Criteria

- 当前包装脚本可执行
- 至少产出一份验收日志
- 日志中可追踪 commit 与执行时间
- 文档说明与脚本行为一致
- 若宣称“Devnet E2E 已完成”，必须另有真实 harness 证据，而不是只依赖当前脚本
