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
| `rpc.Websocket subscriptions` | closed | `#20`, `#22`, `#23`, `#24`, `#33` | ~~`WsRpcClient` 主任务 `#20` 仍在集成提审前阶段；当前已完成 transport compile fix 与 subscription lifecycle 证据，但产品面尚未最终放行~~ → **已完成**：`#20` 完成最小可用闭环，`#33` 在 `c57b189` 完成 re-stabilize / re-expose，公开导出恢复并形成统一 canonical 证据包 | `ws_unsubscribe_ack_success` + `ws_reconnect_subscription_response_malformed` + `ws_resubscribe_idempotent_same_filter_returns_same_id` + `62/62 tests passed` | `src/solana/rpc/ws_client.zig` tests + `docs/06` + `docs/10` + 本矩阵 | 生命周期证据与 public surface 一致；`G-P2-04` 历史口径与 `G-P2C-01/G-P2C-03/G-P2C-05` 已闭环 |
| `rpc.Websocket reconnect lifecycle` | closed | `#20`, `#22`, `#23`, `#24`, `#33` | ~~断线检测 / reconnect / resubscribe 证据已齐，但仍待 `WsRpcClient` 集成段与最终 gate 汇总~~ → **已完成**：`#33` 在 websocket 稳态恢复中补齐 backoff、connection flap、幂等 resubscribe 与 dedup 证据，reconnect 生命周期正式闭环 | `ws_reconnect_detect_disconnect_then_reconnect` + `ws_reconnect_resubscribe_after_reconnect` + `ws_reconnect_notify_path_with_server_close` + `ws_backoff_reconnect_retry_budget` + `ws_connection_flap_reconnect_with_backoff` + `62/62 tests passed` | `src/solana/rpc/ws_client.zig` tests + `docs/06` + `docs/10` + 本矩阵 | 已满足历史 reconnect 生命周期口径；`#33` 达到 `re-expose` 条件，docs 与 gate 对账完成 |

## 7. Phase 2 Batch 2 Extension Tracking

> 按 `docs/20-phase2-batch2-planning.md` 的冻结口径，第二批实现 / 例外 / gate 统一继续落在本矩阵中留痕。以下状态不影响 Phase 1 closeout，仅用于跟踪 Phase 2 Batch 2 的实现收口与 `Batch 2 exception`。

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `rpc.Batch B methods` | in-progress | `#27` | **代码在分支 `0070fa8` 中，尚未合并到 `main`**。此前文档过早标记为 `closed`，与主线代码状态不符。分支内已完成：canonical 三件套（`0070fa8`, clean worktree, `32/32 tests passed`），`requestAirdrop` local-live 成功，`getEpochInfo/getMinimumBalanceForRentExemption` 具备 `public devnet + local-live`，`getAddressLookupTable` 已按 `Batch 2 exception` 收口 | `getEpochInfo/getMinimumBalanceForRentExemption/requestAirdrop/getAddressLookupTable` 的 typed parse + `happy/rpc_error/malformed`；`requestAirdrop` live；只读方法 integration / exception 证据 | 分支 `0070fa8` + `docs/06` + `docs/10` + 本矩阵 | `0070fa8` 合并到 `main` 后，重新执行 `zig build test` 并复核文档一致性 |
| `interfaces.ComputeBudget builders` | closed | `#29` | ~~builders / 导出 / 字节对照与边界测试已落地，当前只差 canonical 三件套留档~~ → **已完成**：canonical 三件套到位（`fffbc87`, clean status, `42/42 tests passed`），`G-P2B-04`/`G-P2B-05` 均已满足 | `setComputeUnitLimit` / `setComputeUnitPrice` builder + Rust 参考字节对照 + boundary（0 / max）+ 全量 `zig build test` 通过 | `src/solana/interfaces/compute_budget.zig` + `src/solana/mod.zig` + `src/root.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2B-01` canonical 三件套；已满足 `G-P2B-04` 证据；docs/gate 对账完成 |
| `interfaces.System Durable Nonce workflow` | closed | `#28` | ~~Nonce parse / builder / workflow 尚未正式留痕~~ → **已完成**：canonical 三件套到位（`5eca510`, clean status, `zig build test` PASS），`NonceState` 双模式解析、`advance_nonce_account` builder、最小 workflow test 均已满足 | `parseNonceAccountData`（direct + `Versions` wrapper）+ `buildAdvanceNonceAccountInstruction` 字节/账户顺序 + `query -> build -> compile/sign` workflow | `src/solana/interfaces/system.zig` + `src/solana/mod.zig` + `src/root.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2B-01` canonical 三件套；已满足 `G-P2B-03` 流程与 builder 证据；docs/gate 对账完成 |

### Batch 2 Exception Register

- `#27 rpc.Batch B methods` → `getAddressLookupTable`
  - 当前例外口径：`public devnet` 与 `local-live` 均返回 `-32601 Method not found`
  - 本批处理：以 `mock + local-live RPC error evidence` 收口
  - 后续收敛：下一阶段继续补实际可用 endpoint / integration 路径

## 8. Phase 2 Batch 3 Extension Tracking

> 按 `docs/21-phase2-batch3-planning.md` 的冻结口径，第三批实现 / 例外 / gate 统一继续落在本矩阵中留痕。以下状态不影响 Phase 1 closeout，仅用于跟踪 Phase 2 Batch 3 的实现收口与 `Batch 3 exception`。

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `rpc.getTokenAccountsByOwner` | closed | `#32` | ~~代码侧虽已完成 typed parse / 三类测试 / public devnet integration 空结果证据，但共享工作树上的 `#33` websocket hang 一度阻塞全量 `zig build test`，导致 canonical 三件套未闭环~~ → **已完成**：通过隔离 worktree 固化 canonical 三件套（`b99d7fc`, clean status, `47/47 tests passed`），`public devnet` integration 空结果证据已留档，无需 Batch 3 exception | `getTokenAccountsByOwner` typed parse + `happy/rpc_error/malformed` + `public devnet` empty-result integration + isolated canonical 三件套 | `src/solana/rpc/client.zig` + `src/solana/rpc/types.zig` + `docs/14a-devnet-e2e-run-log.md` + `docs/06` + 本矩阵 | 已满足 `G-P2C-01` canonical 三件套；已满足 `G-P2C-02` RPC gate；`G-P2C-05` 文档回写完成 |
| `rpc.Websocket re-stabilize / re-expose` | closed | `#33` | ~~共享工作树一度存在 websocket 基线损坏/混合态与测试 hang，导致 `#35` 只能保持 pending~~ → **已完成**：`c57b189` 恢复稳定基线并补齐 backoff / idempotent resubscribe / dedup / connection flap 证据，公开导出恢复 | `ws_backoff_reconnect_retry_budget` + `ws_resubscribe_idempotent_same_filter_returns_same_id` + `ws_dedup_skip_duplicate_notifications` + `ws_connection_flap_reconnect_with_backoff` + canonical 三件套（`c57b189`, clean, `62/62 tests passed`） | `src/solana/rpc/ws_client.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2C-01` canonical 三件套；已满足 `G-P2C-03` websocket gate；`G-P2C-05` 文档回写完成；已达到 `re-expose` 条件 |
| `interfaces.System Durable Nonce live workflow` | closed | `#34` | ~~仅最小 `query -> build -> compile/sign` workflow 已闭环，live `send/confirm` 与 run-log 尚未留档~~ → **已完成**：canonical 三件套到位（`dd6bdff`, clean status, `47/47 tests passed`），`nonce-e2e` mock/live `2/2 passed`，`query -> build -> compile/sign -> send/confirm` local-live 证据已在 `docs/14a` Run 6 留档 | `query nonce -> build advance -> compile/sign -> send/confirm` live run；create nonce tx / advance nonce tx / confirmed poll 0；canonical 三件套 | `src/e2e/nonce_e2e.zig` + `build.zig` + `docs/14a-devnet-e2e-run-log.md` + `docs/06` + 本矩阵 | 已满足 `G-P2C-01` canonical 三件套；已满足 `G-P2C-04` live 证据；`G-P2C-05` 文档回写完成 |

### Batch 3 Exception Register

- `#32 rpc.getTokenAccountsByOwner`
  - 当前口径：**无例外**
  - 原因：已取得 `public devnet` integration 空结果证据，不需要退回 `local-live`
- `#33 rpc.Websocket re-stabilize / re-expose`
  - 当前口径：**无例外**
  - 原因：本轮按 canonical 三件套 + websocket 稳态测试证据收口，不涉及 `local-live` / `public devnet` 替代模型
- `#34 interfaces.System Durable Nonce live workflow`
  - 当前例外口径：本批 live 证据为 `local-live`（`http://127.0.0.1:8899`），尚未形成 `public devnet` 对应 run-log
  - 本批处理：以 `local-live send/confirm + docs/14a run-log` 收口
  - 后续收敛：下一阶段继续补 `public devnet` Nonce live run，并校验与当前 `recent_blockhashes sysvar` 语义的一致性

## 9. Phase 2 Batch 4 Extension Tracking

> 按 `docs/22-phase2-batch4-planning.md` 的冻结口径，第四批实现 / 例外 / gate 统一继续落在本矩阵中留痕。以下状态不影响 Phase 1 closeout，仅用于跟踪 Phase 2 Batch 4 的实现收口与 `Batch 4 exception`。

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `rpc.Token amount queries` | closed | `#37` | ~~等待 `getTokenAccountBalance/getTokenSupply` typed parse、integration 与 canonical 三件套统一收口~~ → **已完成**：隔离 worktree 固化 canonical 三件套（`4b1f8e4`, clean status, `69/69 tests passed`），`public devnet` integration 已留档，无需 Batch 4 exception | `getTokenAccountBalance/getTokenSupply` typed parse + 每方法 `happy/rpc_error/malformed` + `public devnet` integration + isolated canonical 三件套 | `src/solana/rpc/client.zig` + `src/solana/rpc/types.zig` + `docs/14a-devnet-e2e-run-log.md` + `docs/06` + 本矩阵 | 已满足 `G-P2D-01` canonical 三件套；已满足 `G-P2D-02` Token Accounts gate；`G-P2D-05` 文档回写完成 |
| `rpc.Websocket production hardening` | closed | `#38` | ~~等待 heartbeat / timeout / cleanup consistency / dedup boundary 证据与 canonical 三件套统一收口~~ → **已完成**：`6d3c58c` 已补齐 heartbeat、deterministic backoff 硬上限、cleanup/state consistency、dedup cache boundary，canonical 三件套完成（`69/69 tests passed`） | `ws_production_heartbeat_ping_pong` + `ws_production_backoff_hard_limit` + `ws_production_cleanup_state_consistency` + `ws_production_dedup_cache_boundary` + canonical 三件套 | `src/solana/rpc/ws_client.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2D-01` canonical 三件套；已满足 `G-P2D-03` websocket production gate；`G-P2D-05` 文档回写完成 |
| `release.Batch 4 readiness verdict` | closed | `#39` | ~~release checklist / smoke / docs consistency / verdict 仍为 provisional，待 `#40` 统一对账~~ → **已完成**：`docs/23` 已收为 final，`72/72 tests passed` + public devnet smoke + 历史 local-live 证据 + 无未收敛 exception，release verdict = `可发布` | release readiness checklist + `72/72 tests passed` + public devnet smoke（Run 9）+ local-live historical runs（Run 4/5/6）+ final verdict | `docs/23-release-readiness-checklist.md` + `docs/14a-devnet-e2e-run-log.md` + `docs/06` + 本矩阵 | 已满足 `G-P2D-01` canonical 三件套；已满足 `G-P2D-04` release readiness gate；`G-P2D-05` 文档回写完成 |

### Batch 4 Exception Register

- `#37 rpc.Token amount queries`
  - 当前口径：**无例外**
  - 原因：已取得 `public devnet` integration 证据，不需要退回 `local-live`
- `#38 rpc.Websocket production hardening`
  - 当前口径：**无例外**
  - 原因：本轮按 canonical 三件套 + websocket production hardening 测试证据收口，不涉及 live/integration 替代模型

## 10. Phase 2 Batch 5 Extension Tracking

> 按 `docs/24-phase2-batch5-planning.md` 的冻结口径，第五批实现 / 例外 / gate 统一继续落在本矩阵中留痕。以下状态不影响 Phase 1 closeout，仅用于跟踪 Phase 2 Batch 5 的实现收口与 `Batch 5 exception`。

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `interfaces.SPL Token builders` | closed | `#44` | ~~等待 `transferChecked/closeAccount` builders、boundary 证据、compile/sign 闭环与 canonical 三件套统一收口~~ → **已完成**：`d6ab74d` 已补齐 `transferChecked` / `closeAccount` builders、boundary 测试与 signed legacy transaction compile/sign 证据，canonical 三件套完成（`91/91 tests passed`），无 Batch 5 exception | `programId returns Tokenkeg...` + `transferChecked byte layout and account metas` + `transferChecked boundary zero/max` + `closeAccount byte layout and account metas` + `token builders compile into signed legacy transaction` + canonical 三件套 | `src/solana/interfaces/token.zig` + `src/solana/mod.zig` + `src/root.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2E-01` canonical 三件套；已满足 `G-P2E-02` SPL Token builders gate；`G-P2E-05` 文档回写完成 |
| `rpc.Websocket observability` | closed | `#45` | ~~等待冻结 snapshot schema、counter/state 可复现证据与 canonical 三件套统一收口~~ → **已完成**：`e7f8987` 已补齐冻结 `WsStats` schema、reconnect / dedup / subscription / error state instrumentation，canonical 三件套完成（`82/82 tests passed`），无 Batch 5 exception | `ws_observability_snapshot_initial_state` + `ws_observability_counters_after_subscribe` + `ws_observability_reconnect_counter_increments` + `ws_observability_dedup_dropped_counter` + `ws_observability_backoff_error_state` + canonical 三件套 | `src/solana/rpc/ws_client.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2E-01` canonical 三件套；已满足 `G-P2E-03` websocket observability gate；`G-P2E-05` 文档回写完成 |
| `release.Batch 5 preflight automation` | closed | `#46` | ~~等待 preflight 入口脚本 / 标准报告 / verdict 输入与 canonical 三件套统一收口~~ → **已完成**：`3e34225` 已新增 `scripts/release/preflight_batch5.sh`，对齐 `docs/25` 报告格式并形成可复现 conditional 路径样例，canonical 三件套完成（`82/82 tests passed`） | `scripts/release/preflight_batch5.sh` + `ALLOW_BATCH5_EXCEPTION=true` 样例运行 + 标准报告路径 + canonical 三件套 | `scripts/release/preflight_batch5.sh` + `docs/25-batch5-release-readiness.md` + `docs/06` + 本矩阵 | 已满足 `G-P2E-01` canonical 三件套；已满足 `G-P2E-04` preflight automation gate；`G-P2E-05` 文档回写完成 |

### Batch 5 Exception Register

- `#44 interfaces.SPL Token builders`
  - 当前口径：**无例外**
  - 原因：本轮按 builder + boundary + compile/sign 冻结 gate 收口，不依赖 live/integration 替代模型
- `#45 rpc.Websocket observability`
  - 当前口径：**无例外**
  - 原因：本轮按 canonical 三件套 + observability 测试证据收口，不涉及 live/integration 替代模型
- `#46 release.Batch 5 preflight automation`
  - 原例外口径：`public devnet` smoke 与 `local-live` smoke 在样例运行环境中均缺失
  - 当前状态：**已收敛 / resolved by `#49`**
  - 收口证据：
    - `zig build test --summary all` → `91/91 tests passed`
    - `SOLANA_RPC_URL=https://api.devnet.solana.com zig build devnet-e2e --summary all` → `6/6`
    - `SURFPOOL_RPC_URL=https://api.devnet.solana.com zig build e2e --summary all` → `2/2`
    - `ALLOW_BATCH5_EXCEPTION=false ./scripts/release/preflight_batch5.sh ...` → `verdict = 可发布`
  - 证据落点：`docs/14a-devnet-e2e-run-log.md` Run 10 + `docs/25-batch5-release-readiness.md`

## 11. Phase 2 Batch 6 Extension Tracking

> 按 `docs/26-phase2-batch6-planning.md` 的冻结口径，第六批实现 / 例外 / gate 统一继续落在本矩阵中留痕。以下状态不影响 Phase 1 closeout，仅用于跟踪 Phase 2 Batch 6 的实现收口与 `Batch 6 exception`。

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `interfaces.SPL Token transaction flow` | closed | `#50` | ~~等待 `build -> compile/sign -> send/confirm` 默认成功路径与 failure-path 证据、canonical 三件套统一收口~~ → **已完成**：`1e53cd1` 已补齐 flow success + failure-path 证据，canonical 三件套完成（`131/131 tests passed`），无 Batch 6 exception | `token flow build -> compile/sign -> send/confirm (mock transport)` + `token flow failure-path: account/meta mismatch returns rpc_error` + canonical 三件套 | `src/solana/interfaces/token.zig` + `src/solana/rpc/client.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2F-01` canonical 三件套；已满足 `G-P2F-02` flow gate；`G-P2F-05` 文档回写完成 |
| `rpc.Websocket recoverability` | closed | `#51` | ~~等待 reconnect storm / recovery consistency / message-boundary 三条机械证据与 canonical 三件套统一收口~~ → **已完成**：`a49ec19` 已补齐三条 `snapshot()/WsStats` 机械证据，canonical 三件套完成（`94/94 tests passed`），无 Batch 6 exception | `ws_recoverability_reconnect_storm_stability` + `ws_recoverability_recovery_state_consistency` + `ws_recoverability_message_boundary_counters` + canonical 三件套 | `src/solana/rpc/ws_client.zig` + `docs/06` + `docs/10` + 本矩阵 | 已满足 `G-P2F-01` canonical 三件套；已满足 `G-P2F-03` websocket recoverability gate；`G-P2F-05` 文档回写完成 |
| `release.Batch 6 preflight automation` | closed | `#52` | ~~等待 Batch 6 preflight 主入口 / report 规范 / 样例运行与 canonical 三件套统一收口~~ → **已完成**：`93bb638` 已固定 `scripts/release/preflight_batch6.sh`、report/log 产物规范与 exception-path 样例；canonical 三件套完成（`91/91 tests passed`） | `scripts/release/preflight_batch6.sh` + `ALLOW_BATCH6_EXCEPTION=true` 样例运行 + 标准报告路径 + canonical 三件套 | `scripts/release/preflight_batch6.sh` + `docs/27-batch6-release-readiness.md` + `docs/06` + 本矩阵 | 已满足 `G-P2F-01` canonical 三件套；已满足 `G-P2F-04` preflight automation gate；`G-P2F-05` 文档回写完成 |

### Batch 6 Exception Register

- `#50 interfaces.SPL Token transaction flow`
  - 当前口径：**无例外**
  - 原因：本轮已达到默认成功模型 `build -> compile/sign -> send/confirm`，不需要降级到 `compile/sign + simulate`
- `#51 rpc.Websocket recoverability`
  - 当前口径：**无例外**
  - 原因：本轮按 canonical 三件套 + `snapshot()/WsStats` 三条机械 recoverability 证据收口，不涉及 live/integration 替代模型
- `#52 release.Batch 6 preflight automation`
  - 当前例外口径：样例运行中 `public devnet` smoke 与 `local-live` smoke 均缺失
  - 本批处理：以 `ALLOW_BATCH6_EXCEPTION=true` 生成标准报告，当前 Batch 6 release readiness 仅保持 `provisional: 有条件发布`
  - 直接原因：
    - `public devnet` smoke missing
    - `local-live` smoke missing
  - 后续收敛：在后续 Batch 6 证据链中补齐双侧 smoke 后，再将 `docs/27` verdict 升级到 `可发布`
