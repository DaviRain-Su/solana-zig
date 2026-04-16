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
| `core.Keypair` | closeable | `T4-05` | 固定 seed / 多消息 oracle 样本已补齐，待 closeout review 固化 | 多消息 sign/verify + 固定 seed 向量 | `src/solana/core/keypair.zig` tests + `testdata/oracle_vectors.json` + `docs/06` | 确定性签名样本齐全 |
| `tx.Message (v0)` | in-progress | `T4-06`, `T4-07` | 已补反序列化失败路径与 Rust oracle 对照；剩余 blocker 是 ALT 权限正确性与更系统的 closeout 留档 | ALT 正向/重复/冲突/过量账户测试 + writable/readonly 权限错配断言 | `src/solana/tx/message.zig` tests + `testdata/oracle_vectors.json` + `docs/06/07` | v0 关键语义闭环 |
| `tx.AddressLookupTable` | open | `T4-06`, `T4-07` | 目前主要停留在 compile 语义，lookup 权限正确性尚未形成完整 closeout 证据 | lookup 注入、冲突语义与 writable-vs-readonly 正确性用例 | `src/solana/tx/message.zig` tests + `docs/06/07` | lookup 行为有证据固定 |
| `tx.VersionedTransaction` | closeable | `T4-08`, `T4-09` | 失败路径与 legacy/v0 oracle 对照已补齐，待 closeout review 固化 | sign/verify/serialize/deserialize 正反测试 | `src/solana/tx/transaction.zig` tests + `testdata/oracle_vectors.json` + `docs/06` | tx 边界场景到位 |
| `rpc.RpcClient` 基础解析 | in-progress | `T4-11`, `T4-12`, `T4-13` | typed parse 虽已明显收敛，但其余 malformed / 生命周期 / closeout 留档仍需继续固化 | malformed/rpc_error/number_string/生命周期测试 | `src/solana/rpc/client.zig` tests + `docs/06/07` | 关键方法解析稳定 |
| `getLatestBlockhash` | closeable | `T4-11` | typed schema 还可收紧 | happy + malformed + rpc_error | `src/solana/rpc/client.zig` tests + `docs/06` | LatestBlockhash 结构稳定 |
| `getAccountInfo` | closeable | `T4-11`, `T4-12` | 已完成 typed 子集收敛（`AccountInfo`）并保留 `raw_json` 旁路，待 gate 固化 | happy/rpc_error/malformed 三类覆盖 + typed 字段断言 | `src/solana/rpc/client.zig` tests + `docs/03/06/07` | typed 子集进入 gate 固化即可 |
| `getBalance` | closeable | `T4-11` | 主要剩回归与留档 | happy + error + number_string | `src/solana/rpc/client.zig` tests + `docs/06` | 测试与文档映射闭环 |
| `simulateTransaction` | closeable | `T4-12`, `T4-14` | 已完成 `SimulateTransactionResult` typed parse；剩余工作主要是 closeout 留档与 send 路径解耦表述 | base64 输入 + 模拟 happy/error + live harness 证据 | `src/solana/rpc/client.zig` tests + `docs/06/14` | `simulate` 路径可独立稳定支撑 live harness |
| `sendTransaction` | closed | `T4-12`, `T4-14`, `T4-15` | ~~发送路径缺少 live 证据~~ → ~~仅 send 证据~~ → **已完成**：send + confirm 均已在 surfnet 验证（`docs/14a` Run 4 send + Run 5 confirm） | base64 happy/error + Devnet 发送 + 确认证据 | `src/solana/rpc/client.zig` tests + `src/e2e/devnet_e2e.zig` + `docs/14a` | send + confirm 链路已在 live 环境闭环 |
| `compat.oracle_vector` | closed | `T4-01` + `T4-02~T4-09` | 已扩到 `docs/12` 最低集合；Zig 消费断言覆盖 core/keypair/message/transaction | 扩充后的 JSON + Zig 消费测试 | `testdata/oracle_vectors.json` + `scripts/oracle/*` + `src/solana/compat/oracle_vector.zig` tests + `docs/12` | 满足 `docs/12` 最低集合 |
| benchmark baseline | closeable | `T4-16` | 首版基线已记录（`docs/13a` Run 1），待 closeout review 确认 | 至少一版基线记录 | `docs/13` + `docs/13a-benchmark-baseline-results.md` + `src/benchmark.zig` + `docs/06` | 满足 `docs/13` 要求 |
| Devnet E2E evidence | closed | `T4-14`, `T4-15`, `T4-16` | ~~`sendTransaction` live 发送仍缺~~ → ~~仅 send 证据~~ → **已完成**：mock + simulate live + send live + confirm live 全部通过（`docs/14a` Run 2/3/4/5） | 验收日志 + 提交哈希 + live harness 输出 + 发送 + 确认证据 | `src/e2e/devnet_e2e.zig` + `docs/14a-devnet-e2e-run-log.md` + `docs/06/07` | `construct -> sign -> simulate -> send -> confirm` 完整闭环已在 live 环境验证 |

## 3. Blocker Summary

### High-priority blockers
- v0 / ALT 语义的正反路径仍未完全收口
- ALT 权限正确性（writable 账户不能被 readonly lookup 错配）仍需作为独立收口信号固定

### Medium-priority blockers
- benchmark baseline 已建立第一版记录，但仍待 closeout review 固化

### Resolved blockers
- ~~Devnet live harness 虽已落地，但当前只覆盖到 `simulate`~~ → send + confirm 完整闭环已验证（`docs/14a` Run 4/5）
- ~~`sendTransaction` 的真实发送链路证据仍待补齐~~ → send + confirm 均已在 surfnet live 环境通过

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

## 6. Phase 2 Batch 1 Extension Tracking

> 按 `docs/19-phase2-planning.md` 的冻结口径，Phase 2 第一批的执行条目继续统一落在本矩阵中留痕。以下状态**不影响** Phase 1 closeout 结论，仅用于跟踪 Phase 2 batch 的实现 / 证据 / 文档收口。

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `rpc.Websocket subscriptions` | in-progress | `#20`, `#22`, `#23`, `#24` | `WsRpcClient` 主任务 `#20` 仍在集成提审前阶段；当前已完成 transport compile fix 与 subscription lifecycle 证据，但产品面尚未最终放行 | `ws_unsubscribe_ack_success` + `ws_reconnect_subscription_response_malformed` + 单次 `zig build test` 通过 | `src/solana/rpc/ws_client.zig` tests + `docs/06` + `docs/10` | `#20` 提审通过，生命周期证据与 public surface 一致 |
| `rpc.Websocket reconnect lifecycle` | in-progress | `#20`, `#22`, `#23`, `#24` | 断线检测 / reconnect / resubscribe 证据已齐，但仍待 `WsRpcClient` 集成段与最终 gate 汇总 | `ws_reconnect_detect_disconnect_then_reconnect` + `ws_reconnect_resubscribe_after_reconnect` + `ws_reconnect_notify_path_with_server_close` + 单次 `zig build test` 通过 | `src/solana/rpc/ws_client.zig` tests + `docs/06` + `docs/10` | `G-P2-04` 由 `#20` 最终提审统一闭环，docs 与 gate 对账完成 |

## 7. Phase 2 Batch 2 Extension Tracking

> 按 `docs/20-phase2-batch2-planning.md` 的冻结口径，第二批实现 / 例外 / gate 统一继续落在本矩阵中留痕。以下状态不影响 Phase 1 closeout，仅用于跟踪 Phase 2 Batch 2 的实现收口与 `Batch 2 exception`。

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `rpc.Batch B methods` | closed | `#27` | ~~4 个方法的 typed parse 与三类测试代码已落地，但 canonical 三件套与 integration-evidence 尚未提交；只读方法是否使用 `mock + local-live` 例外也尚未正式留痕~~ → **已完成**：canonical 三件套到位（`0070fa8`, clean worktree, `32/32 tests passed`），`requestAirdrop` local-live 成功，`getEpochInfo/getMinimumBalanceForRentExemption` 具备 `public devnet + local-live`，`getAddressLookupTable` 已按 `Batch 2 exception` 收口 | `getEpochInfo/getMinimumBalanceForRentExemption/requestAirdrop/getAddressLookupTable` 的 typed parse + `happy/rpc_error/malformed`；`requestAirdrop` live；只读方法 integration / exception 证据 | `src/solana/rpc/client.zig` + `src/solana/rpc/types.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2B-01` canonical 三件套；已满足 `G-P2B-02` integration-evidence；`getAddressLookupTable` 例外已登记 |
| `interfaces.ComputeBudget builders` | closed | `#29` | ~~builders / 导出 / 字节对照与边界测试已落地，当前只差 canonical 三件套留档~~ → **已完成**：canonical 三件套到位（`fffbc87`, clean status, `42/42 tests passed`），`G-P2B-04`/`G-P2B-05` 均已满足 | `setComputeUnitLimit` / `setComputeUnitPrice` builder + Rust 参考字节对照 + boundary（0 / max）+ 全量 `zig build test` 通过 | `src/solana/interfaces/compute_budget.zig` + `src/solana/mod.zig` + `src/root.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2B-01` canonical 三件套；已满足 `G-P2B-04` 证据；docs/gate 对账完成 |

### Batch 2 Exception Register

- `#27 rpc.Batch B methods` → `getAddressLookupTable`
  - 当前例外口径：`public devnet` 与 `local-live` 均返回 `-32601 Method not found`
  - 本批处理：以 `mock + local-live RPC error evidence` 收口
  - 后续收敛：下一阶段继续补实际可用 endpoint / integration 路径
