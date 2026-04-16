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

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `core.base58` | in-progress | `T4-02` | 边界与更多 oracle 样本不足 | 非法字符/前导零/长输入覆盖 + oracle 样本 | `src/solana/core/base58.zig` tests + `testdata/oracle_vectors.json` + `docs/06` | 通过测试并纳入 oracle 集 |
| `core.shortvec` | in-progress | `T4-03` | 溢出/截断边界仍需系统补齐 | 边界测试 + 溢出/截断断言 | `src/solana/core/shortvec.zig` tests + `testdata/oracle_vectors.json` + `docs/06` | 关键边界覆盖齐全 |
| `core.Hash` | in-progress | `T4-04` | roundtrip / 非零样本与文档映射仍可增强 | roundtrip 测试 + 非零样本 | `src/solana/core/hash.zig` tests + `testdata/oracle_vectors.json` + `docs/06` | 和 PRD 最低集合对齐 |
| `core.Keypair` | in-progress | `T4-05` | 多消息签名与 oracle 对照不足 | 多消息 sign/verify + 固定 seed 向量 | `src/solana/core/keypair.zig` tests + `testdata/oracle_vectors.json` + `docs/06` | 确定性签名样本齐全 |
| `tx.Message (v0)` | open | `T4-06`, `T4-07` | 正向/失败路径覆盖与 Rust oracle 对照不足；ALT 权限正确性仍需更系统证据 | ALT 正向/重复/冲突/过量账户测试 + writable/readonly 权限错配断言 | `src/solana/tx/message.zig` tests + `testdata/oracle_vectors.json` + `docs/06/07` | v0 关键语义闭环 |
| `tx.AddressLookupTable` | open | `T4-06`, `T4-07` | 目前主要停留在 compile 语义，lookup 权限正确性尚未形成完整 closeout 证据 | lookup 注入、冲突语义与 writable-vs-readonly 正确性用例 | `src/solana/tx/message.zig` tests + `docs/06/07` | lookup 行为有证据固定 |
| `tx.VersionedTransaction` | in-progress | `T4-08`, `T4-09` | v0 tx 路径、失败路径、尾字节等还可继续补 | sign/verify/serialize/deserialize 正反测试 | `src/solana/tx/transaction.zig` tests + `testdata/oracle_vectors.json` + `docs/06` | tx 边界场景到位 |
| `rpc.RpcClient` 基础解析 | in-progress | `T4-11`, `T4-12`, `T4-13` | 动态 JSON 解析仍偏多，typed parse 收敛不足 | malformed/rpc_error/number_string/生命周期测试 | `src/solana/rpc/client.zig` tests + `docs/06/07` | 关键方法解析稳定 |
| `getLatestBlockhash` | closeable | `T4-11` | typed schema 还可收紧 | happy + malformed + rpc_error | `src/solana/rpc/client.zig` tests + `docs/06` | LatestBlockhash 结构稳定 |
| `getAccountInfo` | open | `T4-11`, `T4-12` | 当前仍以 `OwnedJson` 为主 | typed 子字段或明确边界说明 | `src/solana/rpc/client.zig` tests + `docs/03/06/07` | 至少达到 PRD 认可的 typed 收敛水平 |
| `getBalance` | closeable | `T4-11` | 主要剩回归与留档 | happy + error + number_string | `src/solana/rpc/client.zig` tests + `docs/06` | 测试与文档映射闭环 |
| `simulateTransaction` | open | `T4-12`, `T4-14` | 仍以 `OwnedJson` 输出，且当前没有真实 Devnet harness 证据 | base64 输入 + 模拟 happy/error + Devnet 证据 | `src/solana/rpc/client.zig` tests + `artifacts/devnet/*` + `docs/06/14` | 能支撑最小 E2E 闭环 |
| `sendTransaction` | open | `T4-12`, `T4-14`, `T4-15` | 发送路径缺少真实 Devnet harness 验证 | base64 happy/error + Devnet 发送证据 | `src/solana/rpc/client.zig` tests + `artifacts/devnet/*` + `docs/06/14` | 发送链路可复现 |
| `compat.oracle_vector` | open | `T4-01` + `T4-02~T4-09` | 向量集规模明显不足 | 扩充后的 JSON + Zig 消费测试 | `testdata/oracle_vectors.json` + `scripts/oracle/*` + `src/solana/compat/oracle_vector.zig` tests + `docs/12` | 满足 `docs/12` 最低集合 |
| benchmark baseline | open | `T4-16` | 尚未形成首版真实记录 | 至少一版基线记录 | `docs/13` + `docs/13a-benchmark-baseline-results.md` + benchmark artifact/result file + `docs/06` | 满足 `docs/13` 要求 |
| Devnet E2E evidence | open | `T4-14`, `T4-15`, `T4-16` | 当前只有包装脚本与说明，尚无真实 `construct/sign/simulate/send` harness | 验收日志 + 提交哈希 + 结果摘要 + 真实 E2E 证据 | `scripts/devnet/phase1_acceptance.sh` + `artifacts/devnet/*` + `docs/14` + `docs/14a-devnet-e2e-run-log.md` + `docs/06` | 满足 `docs/14` 要求 |

## 3. Blocker Summary

### High-priority blockers
- v0 / ALT 语义的正反路径仍未完全收口
- ALT 权限正确性（writable 账户不能被 readonly lookup 错配）仍需作为独立收口信号固定
- oracle 向量集无法支撑 Phase 1 最低声明
- Devnet E2E 仍缺稳定证据链

### Medium-priority blockers
- `getAccountInfo` / `simulateTransaction` / `sendTransaction` 的 typed parse 或边界说明仍不够收敛
- benchmark baseline 尚未建立第一版真实记录

## 4. Phase 1 Closeout Rule

只有当本矩阵中所有收口项都被处理为以下两者之一时，才可宣称 closeout：
- 变为 `closed`
- 被正式记录为 Phase 1 例外项，且不违背 `docs/11-phase1-closeout-checklist.md`

换言之，`open / in-progress / closeable` 都不能作为 Phase 1 closeout 时的最终停留状态。

## 5. Recommended Update Rule

每完成一个 `T4-xx`：
1. 更新本矩阵对应行状态
2. 回写 `docs/10-coverage-matrix.md`
3. 在 `docs/06-implementation-log.md` 留输入/输出/风险/验证
4. 必要时更新 `docs/07-review-report.md`
