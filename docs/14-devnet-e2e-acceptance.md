# Devnet E2E Acceptance Guide

**Date**: 2026-04-16

> 本文定义 Product Phase 1 的 Devnet E2E 验收目标、执行说明和证据留档方式。

## 1. Goal

在配置 `SOLANA_RPC_URL` 时，形成可复现的最小闭环：
- 构造交易
- 签名交易
- 模拟交易
- 发送交易

## 2. Acceptance Scope

Phase 1 不要求复杂业务场景，只要求：
- 能使用当前 `RpcClient`
- 能走完整链下客户端主路径
- 结果可留档并复现

## 3. Environment

必需：
- `SOLANA_RPC_URL`

建议：
- `SOLANA_RPC_URL` 指向公开 devnet 或稳定代理
- 本地记录当前 commit sha
- 保留执行日志

## 4. Current Acceptance Command

当前建议使用：

```bash
SOLANA_RPC_URL=<your-devnet-endpoint> scripts/devnet/phase1_acceptance.sh
```

说明：
- 当前脚本会记录 commit、时间和测试日志
- 随着 T4-14/T4-15 落地，可逐步替换为更细粒度的 E2E harness

## 5. Evidence to Capture

每次验收至少留档：
- commit sha
- 执行时间
- RPC endpoint（可脱敏）
- 是否通过
- 失败阶段（construct / sign / simulate / send / parse）
- 日志路径

## 6. Suggested Acceptance Steps

1. 确认 `SOLANA_RPC_URL` 可访问
2. 执行验收脚本
3. 若失败，先区分：
   - 环境不稳定
   - RPC 解析问题
   - 签名/序列化问题
   - Devnet 外部波动
4. 将结果摘要写入 `docs/06-implementation-log.md`
5. 若存在系统性风险，同步写入 `docs/07-review-report.md`

## 7. Failure Handling Rules

- Devnet 外部故障不应直接否定离线能力
- 但若相同失败可稳定复现，必须按产品缺陷处理
- 若依赖外部环境波动，需在日志中明确标记为 `env-flaky`

## 8. Task Mapping

| 验收内容 | 对应任务 |
|---|---|
| E2E harness / env gate | `T4-14` |
| 可复现示例 | `T4-15` |
| 文档收口 | `T4-16` |

## 9. Acceptance Criteria

- 脚本可执行
- 至少产出一份验收日志
- 日志中可追踪 commit 与执行时间
- 文档说明与脚本行为一致
