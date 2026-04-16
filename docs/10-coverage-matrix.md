# Coverage Matrix

**Date**: 2026-04-16
**Last reviewed**: 2026-04-16
**Last synced docs commit**: `3db9939`

> 注：本矩阵按最近一次文档同步基线维护；若工作区存在未提交代码改动，实际实现状态可能先于本文。

> 本文档用于把“Rust 参考能力 → Zig 模块 → 当前状态 → 测试/文档映射”明确化，避免“已规划”与“已实现”混淆。
>
> 状态约定：
> - `done`：已有实现与测试入口
> - `partial`：已有部分实现，但测试、typed parse、oracle 或 E2E 仍未收口
> - `planned`：已进入 roadmap / spec / task backlog，但尚未实现
> - `out-of-scope-now`：当前产品阶段不承诺

## 1. Core / Component Capabilities

| Rust 参考能力 | Zig 模块 | 状态 | 代码入口 | 测试/文档映射 | 备注 |
|---|---|---|---|---|---|
| `solana-pubkey` | `core.Pubkey` | done | `src/solana/core/pubkey.zig` | `docs/03` 2.1 / `docs/05` 4.3 | 已支持 base58 roundtrip |
| `solana-signature` | `core.Signature` | done | `src/solana/core/signature.zig` | `docs/03` 2.1 / `docs/05` 4.3 | 已支持 verify |
| `solana-keypair` | `core.Keypair` | partial | `src/solana/core/keypair.zig` | `docs/03` 3.1 / `docs/05` 4.3 | 固定 seed 签名向量已补齐（`#9`），仍可继续扩样本规模 |
| `solana-hash` | `core.Hash` | partial | `src/solana/core/hash.zig` | `docs/03` 2.1 / `docs/05` 4.3 | roundtrip/边界仍可继续加固 |
| `solana-short-vec` | `core.shortvec` | partial | `src/solana/core/shortvec.zig` | `docs/03` 2.2 / `docs/05` 4.2 | 已有基础覆盖，仍待更多溢出边界 |
| base58 codec | `core.base58` | partial | `src/solana/core/base58.zig` | `docs/03` 3.1 / `docs/05` 4.1 | oracle 向量仍偏少 |

## 2. Transaction / Message Capabilities

| Rust 参考能力 | Zig 模块 | 状态 | 代码入口 | 测试/文档映射 | 备注 |
|---|---|---|---|---|---|
| `solana-instruction` 风格账户模型 | `tx.AccountMeta` / `tx.Instruction` | done | `src/solana/tx/instruction.zig` | `docs/03` 2.3 / `docs/05` 4.4 | 基础结构已稳定 |
| legacy message compile/serialize | `tx.Message` | done | `src/solana/tx/message.zig` | `docs/03` 3.2 / `docs/05` 4.4 | 已有编译/序列化/反序列化测试 |
| v0 message compile/serialize | `tx.Message` | partial | `src/solana/tx/message.zig` | `docs/03` 5.2 / `docs/05` 4.4 | 已补失败路径（`#8`），ALT 权限语义仍作为收口观察项 |
| ALT lookup model | `tx.AddressLookupTable` | partial | `src/solana/tx/address_lookup_table.zig` | `docs/03` 5.2 / `docs/05` 4.4 | 关键失败路径已补（`#8`），行为稳定性由 `docs/15` 持续跟踪 |
| versioned transaction sign/verify | `tx.VersionedTransaction` | partial | `src/solana/tx/transaction.zig` | `docs/03` 3.2 / `docs/05` 4.4 | sign/verify/serialize/deserialize 正反路径已覆盖（`#8`） |

## 3. RPC Capabilities (Current Product Phase 1)

| Rust 参考能力 | Zig 模块 | 状态 | 代码入口 | 测试/文档映射 | 备注 |
|---|---|---|---|---|---|
| JSON-RPC client base | `rpc.RpcClient` | partial | `src/solana/rpc/client.zig` | `docs/03` 3.3 / `docs/05` 4.5 | typed parse 仍以动态 JSON 为主 |
| transport abstraction | `rpc.Transport` | done | `src/solana/rpc/transport.zig` | `docs/02` 4.1 / `docs/07` 3 | 注入式 mock 已建立 |
| HTTP transport | `rpc.HttpTransport` | done | `src/solana/rpc/http_transport.zig` | `docs/02` 4.1 | 默认实现已接入 |
| `getLatestBlockhash` | `rpc.RpcClient.getLatestBlockhash` | partial | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | typed schema 可继续收紧 |
| `getAccountInfo` | `rpc.RpcClient.getAccountInfo` | partial | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | 已完成 typed 子集收敛并保留 `raw_json` 旁路（`#7`） |
| `getBalance` | `rpc.RpcClient.getBalance` | partial | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | number_string 已兼容 |
| `simulateTransaction` | `rpc.RpcClient.simulateTransaction` | partial | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | 已完成 typed 收敛；devnet + surfnet live 证据已留档（`#7/#10`） |
| `sendTransaction` | `rpc.RpcClient.sendTransaction` | done | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | `send + confirm` live 证据已补齐（`docs/14a` Run 4/5，`#17`） |
| `getSignatureStatuses` | `rpc.RpcClient.getSignatureStatuses` | done | `src/solana/rpc/client.zig` | `docs/19` G-P2-02 | typed parse `SignatureStatus`，含 happy/null/error 测试（`#17`） |
| RPC error preservation | `rpc.types.RpcErrorObject/RpcResult` | done | `src/solana/rpc/types.zig` | `docs/03` 7 / `docs/07` 3 | code/message/data_json 已保留 |

## 4. Compat / Oracle

| Rust 参考能力 | Zig 模块 | 状态 | 代码入口 | 测试/文档映射 | 备注 |
|---|---|---|---|---|---|
| oracle vector loading | `compat.oracle_vector` | done | `src/solana/compat/oracle_vector.zig` | `docs/05` 4.6 | Phase 1 最低集合已补齐并通过 Zig 消费断言（`#9`） |
| bincode helper subset | `compat.bincode_compat` | partial | `src/solana/compat/bincode_compat.zig` | `docs/03` 1 / `docs/07` 2 | 当前仅最小辅助能力 |
| Rust vector generator (`v2` core) | `scripts/oracle/*` | done | `scripts/oracle/generate_vectors.rs` | `README` / `docs/01` 11 | 已扩到 `core + keypair + message + transaction`（`#9`） |

## 5. Product Phase 2 Planned Coverage

| 目标能力 | 计划 Zig 模块/文件 | 状态 | 文档映射 | 备注 |
|---|---|---|---|---|
| 扩展 RPC methods | `rpc/client.zig` 扩展或拆分 typed 子层 | partial | `docs/00` Phase 2 / `docs/04` T4-17~T4-19 / `docs/03c-rpc-extended-spec.md` | Batch A 已完成 `getTransaction / getSignaturesForAddress / getSlot`（`#18`）；`getSignatureStatuses` 作为 `send/confirm` 支撑方法也已落地；Batch B 的 `getEpochInfo / getMinimumBalanceForRentExemption / requestAirdrop / getAddressLookupTable` 在分支 `0070fa8` 中已完成 typed parse + 三类测试 + canonical 三件套，但**尚未合并到 `main`**，`getAddressLookupTable` 按 Batch 2 exception 以 `mock + local-live RPC error evidence` 收口 |
| `getTokenAccountsByOwner` | `rpc/client.zig` + `rpc/types.zig` | done | `docs/21` P2-12 / `docs/03c-rpc-extended-spec.md` | `#32` 已在 `b99d7fc` 完成 typed parse、`happy/rpc_error/malformed` 三类测试、`public devnet` 空结果 integration；canonical 三件套已通过隔离 worktree固化 |
| `getTokenAccountBalance` / `getTokenSupply` | `rpc/client.zig` + `rpc/types.zig` | done | `docs/22` P2-17 / `docs/03c-rpc-extended-spec.md` | `#37` 已在 `4b1f8e4` 完成 `TokenAmount` typed parse、两方法共 6 条 `happy/rpc_error/malformed` 测试、`public devnet` integration，以及隔离 worktree canonical 三件套（`69/69 tests passed`） |
| SPL Token builders (`transferChecked` / `closeAccount`) | `src/solana/interfaces/token.zig` + `src/solana/mod.zig` + `src/root.zig` | done | `docs/24` P2-22 / `docs/03a-interfaces-spec.md` | `#44` 已在 `d6ab74d` 完成 `transferChecked` / `closeAccount` builders、boundary 测试、signed legacy transaction compile/sign 证据，以及隔离 worktree canonical 三件套（`91/91 tests passed`） |
| Websocket subscriptions | `src/solana/rpc/ws_client.zig` + `src/solana/mod.zig` + `src/root.zig` | done | `docs/21` P2-13 / `docs/00` Phase 2 / `docs/04` T4-20 / `docs/05` 5.1 | `#33` 已在 `c57b189` 完成 websocket re-stabilize / re-expose：恢复可工作基线，补齐 backoff reconnect、idempotent resubscribe、dedup、connection flap 四类证据，并重新接通公开导出；canonical 三件套已通过（`62/62 tests passed`） |
| Websocket production hardening | `src/solana/rpc/ws_client.zig` | done | `docs/22` P2-18 / `docs/05` 5.1 | `#38` 已在 `6d3c58c` 完成 heartbeat/ping-pong、deterministic backoff 硬上限、cleanup/state consistency、dedup cache boundary；canonical 三件套已通过（`69/69 tests passed`） |
| Websocket observability | `src/solana/rpc/ws_client.zig` | done | `docs/24` P2-23 / `docs/05` 5.1 | `#45` 已在 `e7f8987` 完成冻结 `WsStats` snapshot schema、reconnect/dedup/subscription/error state instrumentation 与 5 条 observability 证据；canonical 三件套已通过（`82/82 tests passed`） |
| Websocket recoverability | `src/solana/rpc/ws_client.zig` | done | `docs/26` P2-28 / `docs/05` 5.1 | `#51` 已在 `a49ec19` 完成 reconnect storm/backoff 稳定性、recovery 后状态一致性、消息边界三条机械证据；canonical 三件套已通过（`94/94 tests passed`） |
| Durable Nonce workflow | `interfaces/system` + tx/rpc helper composition | done | `docs/00` Phase 2 / `docs/04` T4-21 / `docs/05` 5.1 | `#28` 已完成 nonce account 双模式 typed parse、`advance_nonce_account` builder、最小 `query -> build -> compile/sign` workflow 测试；`#34` 进一步完成 `query -> build -> compile/sign -> send/confirm` local-live 深化并形成 `docs/14a` run-log。当前按 Batch 3 fixed model 记为 `local-live` 例外收口，后续继续补 public devnet |
| Priority Fees / Compute Budget | `interfaces/compute_budget` | done | `docs/00` Phase 2 / `docs/04` T4-22 / `docs/03a-interfaces-spec.md` | `#29` 已完成 `setComputeUnitLimit` / `setComputeUnitPrice` builders、参数边界校验与 Rust 参考字节对照；canonical 三件套已由 `fffbc87` + `42/42 tests passed` 固化 |
| Release preflight automation | `scripts/release/preflight_batch6.sh` + `docs/27-batch6-release-readiness.md` | done | `docs/26` P2-29 / `docs/05` 5.2 | `#52` 已在 `93bb638` 固定 Batch 6 preflight 主入口、report/log 产物规范与 exception-path 标准样例；canonical 三件套已通过（`91/91 tests passed`），最终 release verdict 仍待后续 batch 证据继续收敛 |

## 6. Product Phase 3 Planned Coverage

| 目标能力 | 计划 Zig 模块/文件 | 状态 | 文档映射 | 备注 |
|---|---|---|---|---|
| system interface | `src/solana/interfaces/system/*` | planned | `docs/00` Phase 3 / `docs/04` T4-23 / `docs/03a-interfaces-spec.md` | 先做 transfer/create |
| token / token-2022 / ATA | `src/solana/interfaces/token*/*` | planned | `docs/00` Phase 3 / `docs/04` T4-24~T4-25 / `docs/03a-interfaces-spec.md` | 与 ATA helper 一起定义 |
| memo / stake | `src/solana/interfaces/memo|stake/*` | planned | `docs/00` Phase 3 / `docs/03a-interfaces-spec.md` | 第二批接口层能力 |
| signer abstraction | `src/solana/signers/*` | planned | `docs/00` Phase 3 / `docs/04` T4-26 / `docs/03b-signers-spec.md` | 先抽象接口，再接入 tx |
| external signer adapter | `src/solana/signers/external_*` | planned | `docs/00` Phase 3 / `docs/04` T4-26 / `docs/05` 5.2 | mock/KMS/HSM stub |
| C ABI | `src/c/*` 或等价导出层 | planned | `docs/00` Phase 3 / `docs/04` T4-27 / `docs/05` 5.2 | 需补所有权与释放规则 |
| performance comparison report | `docs/13` + Phase 3 report artifact | planned | `docs/00` Phase 3 / `docs/04` T4-28 / `docs/05` 5.2 | 需形成 vs Rust SDK 的可复跑对比说明 |

## 7. Product Phase 4 / Out of Scope for Now

| 目标能力 | 状态 | 文档映射 | 备注 |
|---|---|---|---|
| on-chain SBF / no_std runtime parity | out-of-scope-now | `docs/00` Phase 4 / `docs/01` 3.3 | 作为独立 `solana-program-zig` 子项目评估 |
| full runtime / program entrypoint support | out-of-scope-now | `docs/00` Phase 4 / `docs/08` Phase 4 | 不与当前 client SDK 生命周期耦合 |

## 8. 当前最值得补齐的缺口

1. `core.base58` / `core.shortvec` / `core.Hash` 的边界样本仍可继续扩充（不阻塞当前 closeout 评审）。
2. v0/ALT 语义虽已补关键失败路径，仍建议继续累积高复杂度场景样本。
3. benchmark baseline 与 execution-matrix 的最终 closeout 处置仍需继续收口。
4. Devnet E2E 的 simulate/send/confirm 首版 live 证据已形成，后续重点是持续回归与文档同步。

## 9. 配套文档

- 收口判定：`docs/11-phase1-closeout-checklist.md`
- oracle 计划：`docs/12-oracle-vector-expansion-plan.md`
- benchmark 规范：`docs/13-benchmark-baseline-spec.md`
- benchmark 结果模板：`docs/13a-benchmark-baseline-results.md`
- Devnet E2E：`docs/14-devnet-e2e-acceptance.md`
- Devnet 运行记录模板：`docs/14a-devnet-e2e-run-log.md`
- 执行矩阵：`docs/15-phase1-execution-matrix.md`
- 用户 / 安全说明：`docs/16-consumer-profiles-and-security-notes.md`
- ADR 索引：`docs/adr/README.md`

## 10. 维护规则

- 每新增一个公共能力，至少同步更新：`docs/03`, `docs/05`, `docs/10`。
- 每变更一个 Product Phase 的范围，至少同步更新：`docs/00`, `docs/01`, `docs/04`, `docs/08`, `docs/10`。
- `docs/10` 只记录“能力与状态”，不替代任务文档和技术规格。
