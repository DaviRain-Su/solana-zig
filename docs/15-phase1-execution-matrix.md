# Phase 1 Execution Matrix

**Date**: 2026-04-16

> 本文把 `docs/10-coverage-matrix.md` 中的 `partial` 项进一步映射成可执行收口矩阵：
> - 对应哪个 `T4-xx`
> - 当前 blocker 是什么
> - 需要什么证据
> - 到什么状态才能宣称 Phase 1 closeout

## 1. Status Legend

- `open`: 尚未满足收口条件
- `in-progress`: 已有部分覆盖，但仍缺关键证据
- `closeable`: 只差收口验证/留档
- `closed`: 可计入 Phase 1 closeout

## 2. Execution Matrix

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | Closeout 条件 |
|---|---|---|---|---|---|
| `core.base58` | in-progress | `T4-02` | 边界与更多 oracle 样本不足 | 非法字符/前导零/长输入覆盖 + oracle 样本 | 通过测试并纳入 oracle 集 |
| `core.shortvec` | in-progress | `T4-03` | 溢出/截断边界仍需系统补齐 | 边界测试 + 溢出/截断断言 | 关键边界覆盖齐全 |
| `core.Hash` | in-progress | `T4-04` | roundtrip / 非零样本与文档映射仍可增强 | roundtrip 测试 + 非零样本 | 和 PRD 最低集合对齐 |
| `core.Keypair` | in-progress | `T4-05` | 多消息签名与 oracle 对照不足 | 多消息 sign/verify + 固定 seed 向量 | 确定性签名样本齐全 |
| `tx.Message (v0)` | open | `T4-06`, `T4-07` | 正向/失败路径覆盖与 Rust oracle 对照不足 | ALT 正向/重复/冲突/过量账户测试 | v0 关键语义闭环 |
| `tx.AddressLookupTable` | open | `T4-06`, `T4-07` | 目前主要停留在 compile 语义 | lookup 注入与冲突语义用例 | lookup 行为有证据固定 |
| `tx.VersionedTransaction` | in-progress | `T4-08`, `T4-09` | v0 tx 路径、失败路径、尾字节等还可继续补 | sign/verify/serialize/deserialize 正反测试 | tx 边界场景到位 |
| `rpc.RpcClient` 基础解析 | in-progress | `T4-11`, `T4-12`, `T4-13` | 动态 JSON 解析仍偏多，typed parse 收敛不足 | malformed/rpc_error/number_string/生命周期测试 | 关键方法解析稳定 |
| `getLatestBlockhash` | closeable | `T4-11` | typed schema 还可收紧 | happy + malformed + rpc_error | LatestBlockhash 结构稳定 |
| `getAccountInfo` | open | `T4-11`, `T4-12` | 当前仍以 `OwnedJson` 为主 | typed 子字段或明确边界说明 | 至少达到 PRD 认可的 typed 收敛水平 |
| `getBalance` | closeable | `T4-11` | 主要剩回归与留档 | happy + error + number_string | 测试与文档映射闭环 |
| `simulateTransaction` | open | `T4-12`, `T4-14` | 仍以 `OwnedJson` 输出，E2E 证据不足 | base64 输入 + 模拟 happy/error + Devnet 证据 | 能支撑最小 E2E 闭环 |
| `sendTransaction` | open | `T4-12`, `T4-14`, `T4-15` | 发送路径 Devnet 验证不足 | base64 happy/error + Devnet 发送证据 | 发送链路可复现 |
| `compat.oracle_vector` | open | `T4-01` + `T4-02~T4-09` | 向量集规模明显不足 | 扩充后的 JSON + Zig 消费测试 | 满足 `docs/12` 最低集合 |
| benchmark baseline | open | `T4-16` | 尚未建立记录模板与首版结果 | 至少一版基线记录 | 满足 `docs/13` 要求 |
| Devnet E2E evidence | open | `T4-14`, `T4-15`, `T4-16` | 尚缺统一脚本/说明/留档模板 | 验收日志 + 提交哈希 + 结果摘要 | 满足 `docs/14` 要求 |

## 3. Blocker Summary

### High-priority blockers
- v0 / ALT 语义的正反路径仍未完全收口
- oracle 向量集无法支撑 Phase 1 最低声明
- Devnet E2E 仍缺稳定证据链

### Medium-priority blockers
- `getAccountInfo` / `simulateTransaction` / `sendTransaction` 的 typed parse 或边界说明仍不够收敛
- benchmark baseline 尚未建立第一版记录

## 4. Phase 1 Closeout Rule

只有当本矩阵中所有 `open` 项都被处理为以下两者之一时，才可宣称 closeout：
- 变为 `closed`
- 被正式记录为 Phase 1 例外项，且不违背 `docs/11-phase1-closeout-checklist.md`

## 5. Recommended Update Rule

每完成一个 `T4-xx`：
1. 更新本矩阵对应行状态
2. 回写 `docs/10-coverage-matrix.md`
3. 在 `docs/06-implementation-log.md` 留输入/输出/风险/验证
4. 必要时更新 `docs/07-review-report.md`
