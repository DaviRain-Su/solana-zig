# Coverage Matrix

**Date**: 2026-04-17
**Last reviewed**: 2026-04-17
**Last synced docs commit**: `e3a3794`

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
| `solana-keypair` | `core.Keypair` | done | `src/solana/core/keypair.zig` | `docs/03` 3.1 / `docs/05` 4.3 | 固定 seed 签名向量已补齐（`#9`），oracle 向量通过 |
| `solana-hash` | `core.Hash` | done | `src/solana/core/hash.zig` | `docs/03` 2.1 / `docs/05` 4.3 | roundtrip/boundary 已覆盖 |
| `solana-short-vec` | `core.shortvec` | done | `src/solana/core/shortvec.zig` | `docs/03` 2.2 / `docs/05` 4.2 | 基础覆盖 + 溢出边界已覆盖 |
| base58 codec | `core.base58` | done | `src/solana/core/base58.zig` | `docs/03` 3.1 / `docs/05` 4.1 | roundtrip + 非法字符 + oracle 向量通过 |

## 2. Transaction / Message Capabilities

| Rust 参考能力 | Zig 模块 | 状态 | 代码入口 | 测试/文档映射 | 备注 |
|---|---|---|---|---|---|
| `solana-instruction` 风格账户模型 | `tx.AccountMeta` / `tx.Instruction` | done | `src/solana/tx/instruction.zig` | `docs/03` 2.3 / `docs/05` 4.4 | 基础结构已稳定 |
| legacy message compile/serialize | `tx.Message` | done | `src/solana/tx/message.zig` | `docs/03` 3.2 / `docs/05` 4.4 | 已有编译/序列化/反序列化测试 |
| v0 message compile/serialize | `tx.Message` | done | `src/solana/tx/message.zig` | `docs/03` 5.2 / `docs/05` 4.4 | 已补失败路径（`#8`），ALT 权限语义已收口 |
| ALT lookup model | `tx.AddressLookupTable` | done | `src/solana/tx/address_lookup_table.zig` | `docs/03` 5.2 / `docs/05` 4.4 | 关键失败路径已补（`#8`），行为稳定 |
| versioned transaction sign/verify | `tx.VersionedTransaction` | done | `src/solana/tx/transaction.zig` | `docs/03` 3.2 / `docs/05` 4.4 | sign/verify/serialize/deserialize 正反路径已覆盖（`#8`） |

## 3. RPC Capabilities (Current Product Phase 1)

| Rust 参考能力 | Zig 模块 | 状态 | 代码入口 | 测试/文档映射 | 备注 |
|---|---|---|---|---|---|
| JSON-RPC client base | `rpc.RpcClient` | done | `src/solana/rpc/client.zig` | `docs/03` 3.3 / `docs/05` 4.5 | 16 个方法全部 typed parse，统一重试策略 |
| transport abstraction | `rpc.Transport` | done | `src/solana/rpc/transport.zig` | `docs/02` 4.1 / `docs/07` 3 | 注入式 mock 已建立 |
| HTTP transport | `rpc.HttpTransport` | done | `src/solana/rpc/http_transport.zig` | `docs/02` 4.1 | 默认实现已接入 |
| `getLatestBlockhash` | `rpc.RpcClient.getLatestBlockhash` | done | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | typed schema 已收紧 |
| `getAccountInfo` | `rpc.RpcClient.getAccountInfo` | done | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | typed 子集收敛 + `raw_json` 旁路（`#7`） |
| `getBalance` | `rpc.RpcClient.getBalance` | done | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | number_string 已兼容 |
| `simulateTransaction` | `rpc.RpcClient.simulateTransaction` | done | `src/solana/rpc/client.zig` | `docs/03` 6.1 / `docs/05` 4.5 | typed 收敛；devnet + surfnet live 证据已留档（`#7/#10`） |
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
| 扩展 RPC methods | `rpc/client.zig` 扩展或拆分 typed 子层 | partial | `docs/00` Phase 2 / `docs/04` T4-17~T4-19 / `docs/03c-rpc-extended-spec.md` | Batch A 已完成 `getTransaction / getSignaturesForAddress / getSlot`（`#18`）；`getSignatureStatuses` 作为 `send/confirm` 支撑方法也已落地；Batch B 已在 `#55` / `6d5f1be` 主干化 `getEpochInfo / getMinimumBalanceForRentExemption / requestAirdrop / getAddressLookupTable`，并由 `#56` 在 `be31510` 上补齐双侧 smoke revalidation（`152/152 tests passed`）。当前按 Batch 7 最终口径：`getEpochInfo/getMinimumBalanceForRentExemption` public devnet integration 已到位，`requestAirdrop` 以 local-live 成功侧收口并登记 public devnet rate-limit exception，`getAddressLookupTable` 继续按 RPC error evidence exception 路径收口 |
| `getTokenAccountsByOwner` | `rpc/client.zig` + `rpc/types.zig` | done | `docs/21` P2-12 / `docs/03c-rpc-extended-spec.md` | `#32` 已在 `b99d7fc` 完成 typed parse、`happy/rpc_error/malformed` 三类测试、`public devnet` 空结果 integration；canonical 三件套已通过隔离 worktree固化 |
| `getTokenAccountBalance` / `getTokenSupply` | `rpc/client.zig` + `rpc/types.zig` | done | `docs/22` P2-17 / `docs/03c-rpc-extended-spec.md` | `#37` 已在 `4b1f8e4` 完成 `TokenAmount` typed parse、两方法共 6 条 `happy/rpc_error/malformed` 测试、`public devnet` integration，以及隔离 worktree canonical 三件套（`69/69 tests passed`） |
| SPL Token builders (`transferChecked` / `closeAccount`) | `src/solana/interfaces/token.zig` + `src/solana/mod.zig` + `src/root.zig` | done | `docs/24` P2-22 / `docs/03a-interfaces-spec.md` | `#44` 已在 `d6ab74d` 完成 `transferChecked` / `closeAccount` builders、boundary 测试、signed legacy transaction compile/sign 证据，以及隔离 worktree canonical 三件套（`91/91 tests passed`） |
| SPL Token transaction flow (`build -> compile/sign -> send/confirm`) | `src/solana/interfaces/token.zig` + `src/solana/rpc/client.zig` | done | `docs/26` P2-27 / `docs/03a-interfaces-spec.md` | `#50` 已在 `1e53cd1` 完成 flow 级成功路径与 failure-path（account/meta mismatch → `rpc_error`）证据，canonical 三件套已通过（`131/131 tests passed`） |
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
| system interface | `src/solana/interfaces/system/*` | partial | `docs/00` Phase 3 / `docs/30` P3-02 / `docs/03a-interfaces-spec.md` | Batch 1 `#60` 已完成 `transfer/createAccount` builders（`35a731f`）；后续批次继续补其它 system 指令 |
| token / token-2022 / ATA | `src/solana/interfaces/token*/*` | partial | `docs/00` Phase 3 / `docs/30` P3-03 / `docs/03a-interfaces-spec.md` | Batch 1 `#61` 已完成 `mint/approve/burn` builders（`b840f75`）；ATA 明确延后，不在 Batch 1 |
| memo | `src/solana/interfaces/memo.zig` | done | `docs/00` Phase 3 / `docs/03a-interfaces-spec.md` | Batch 2 `#70` 完成 dual-mode builder |
| compute_budget | `src/solana/interfaces/compute_budget.zig` | done | `docs/00` Phase 3 / `docs/03a-interfaces-spec.md` | Phase 2 完成 `setComputeUnitLimit` / `setComputeUnitPrice` |
| stake | `src/solana/interfaces/stake.zig` | partial | `docs/00` Phase 3 / `docs/03a-interfaces-spec.md` | create/delegate/deactivate/withdraw builders 已落地；`buildCreateStakeAccountInstruction(...)` 当前仍偏 initialize-only，且负路径测试不足 |
| signer abstraction | `src/solana/signers/*` | done | `docs/00` Phase 3 / `docs/04` T4-26 / `docs/03b-signers-spec.md` | `Signer` vtable + `InMemorySigner` + `signWithSigners(...)` 已落地；已有 signer-path/keypair-path 等价与 legacy 多签证据 |
| external signer adapter | `src/solana/signers/mock_external.zig` | partial | `docs/00` Phase 3 / `docs/04` T4-26 / `docs/05` 5.2 | 已覆盖 backend failure / rejected；当前仍存在“忽略输入消息签名”与 `pubkey mismatch` 语义未闭环问题 |
| C ABI | `src/solana/cabi/*` + `include/solana_zig.h` | partial | `docs/00` Phase 3 / `docs/04` T4-27 / `docs/05` 5.2 / `docs/03d-cabi-spec.md` | 核心类型 + 交易构建可用；RPC handle 仍为 dummy transport，且 header/core/test surface 仍需对齐 |
| performance comparison report | `docs/13` + Phase 3 report artifact | partial | `docs/00` Phase 3 / `docs/04` T4-28 / `docs/05` 5.2 | Batch 3 完成 signer + C ABI benchmark 基线；vs Rust SDK 对比仍待后续 |

## 7. Product Phase 4 / Out of Scope for Now

| 目标能力 | 状态 | 文档映射 | 备注 |
|---|---|---|---|
| on-chain SBF / no_std runtime parity | out-of-scope-now | `docs/00` Phase 4 / `docs/01` 3.3 | 作为独立 `solana-program-zig` 子项目评估 |
| full runtime / program entrypoint support | out-of-scope-now | `docs/00` Phase 4 / `docs/08` Phase 4 | 不与当前 client SDK 生命周期耦合 |

## 8. 当前最值得补齐的缺口

> Phase 1/2 已完成；Phase 3 主体能力已落地，但仍处于 Batch 4 closeout。以下为当前最值得补齐的缺口：

1. strict exception model 仍存在两条未收敛路径：`requestAirdrop=partial_exception`、`getAddressLookupTable=accepted exception path`。
2. 在上述 exception 未关闭前，Phase 3 当前批次 verdict 维持 `有条件发布`，不满足升级到 `可发布` 的条件。
3. `docs/35` / `docs/28` 条件回写仍未触发，需后续批次提供 exception 关闭证据再评估。

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

## 11. Phase 3 Batch 1 Tracking (canonical board: #60~#63)

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `interfaces.System builders` | closed | `#60` | — | `35a731f`，`transfer/createAccount` byte layout + account metas + compile/sign，`162/162 tests passed` | `src/solana/interfaces/system.zig` + `docs/06` + `docs/31` | `G-P3A-01` + `G-P3A-02` PASS |
| `interfaces.Token builders` | closed | `#61` | — | `b840f75`，`mint/approve/burn` byte layout + account metas + compile/sign，ATA 未触碰 | `src/solana/interfaces/token.zig` + `docs/06` + `docs/31` | `G-P3A-01` + `G-P3A-03` PASS |
| `rpc.Exception convergence` | closed | `#62` | — | `f54dbe5` + `7aa4aab`，tri-state + success-or-exception 路径，双 env 全量 `163/163 tests passed` | `src/solana/rpc/client.zig` + `docs/14a` + `docs/15` + `docs/31` | `G-P3A-01` + `G-P3A-04` PASS |

## 12. Phase 3 Batch 2 Tracking (canonical board: #69~#72)

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `interfaces.ATA helper minimal` | closed | `#69` | — | `616c42c`，`createProgramAddress/findProgramAddress` + `findAssociatedTokenAddress(owner,mint,token_program_id)` + `createATA builder`，`193/193 tests passed` | `src/solana/core/pubkey.zig` + `src/solana/interfaces/ata.zig` + `docs/06` + `docs/33` | `G-P3B-01` + `G-P3B-02` PASS |
| `interfaces.assign + memo dual-mode` | closed | `#70` | — | `efe3070`，`buildAssignInstruction` + `buildMemoInstruction(signer_mode)`，no-signer/signer 双路径证据，`193/193 tests passed` | `src/solana/interfaces/system.zig` + `src/solana/interfaces/memo.zig` + `docs/06` + `docs/33` | `G-P3B-01` + `G-P3B-03` PASS |
| `rpc.Exception convergence` | closed | `#71` | — | `efe3070`，`requestAirdrop` strict tri-state + `getAddressLookupTable` success-or-exception，双 env 全量 `193/193 tests passed` | `src/solana/rpc/client.zig` + `docs/14a` + `docs/15` + `docs/33` | `G-P3B-01` + `G-P3B-04` PASS |
| `batch2.docs/gate reconciliation` | closed | `#72` | — | `docs/06+10+14a+15+33` 对账完成 | 本矩阵 + `docs/33` | `G-P3B-05` PASS |

### Phase 3 Batch 2 Exception Register

- `requestAirdrop`
  - 当前口径：`partial exception` 可接受（public devnet rate-limit + local-live success）
  - 后续收敛：继续提升 public devnet 成功率
- `getAddressLookupTable`
  - 当前口径：`accepted exception path` 可接受（method-not-found / RPC error evidence）
  - 后续收敛：后续批次补稳定成功路径

## 13. Phase 3 Batch 3 Tracking (canonical board: #74~#77)

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `interfaces.token_2022 minimum builders` | closed | `#74` | — | `da93cfb`，token-2022 `mint/approve/burn` + program-id 区分；LE amount/meta 顺序/signer-writable 机械断言；isolated canonical `197/197` | `src/solana/interfaces/token_2022.zig` + `docs/06` + `docs/35` | `G-P3C-01` + `G-P3C-02` PASS |
| `interfaces.stake delegate minimum` | closed | `#75` | — | `4d35e30`，`buildDelegateStakeInstruction` + 6 账户 metas 机械断言 + compile/sign/verify；isolated canonical `204/204` | `src/solana/interfaces/stake.zig` + `docs/06` + `docs/35` | `G-P3C-01` + `G-P3C-03` PASS |
| `rpc.exception convergence` | closed | `#76` | — | `da93cfb`，strict tri-state 保持 + `code==429` 分类收紧；双 env 收敛证据与 verdict-upgrade 输入；isolated canonical `197/197` | `src/solana/rpc/client.zig` + `docs/14a` + `docs/15` + `docs/35` | `G-P3C-01` + `G-P3C-04` PASS |
| `batch3.docs/gate reconciliation` | closed | `#77` | — | `39f368f`，`docs/06+10+14a+15+35` 对账完成（`docs/28` 本轮不触发） | 本矩阵 + `docs/35` | `G-P3C-05` PASS |

### Phase 3 Batch 3 Exception Register

- `requestAirdrop`
  - 当前口径：`partial_exception`（public devnet rate-limit + local-live success）
  - strict model 下仍未关闭
- `getAddressLookupTable`
  - 当前口径：`accepted exception path`（method-not-found / RPC error evidence）
  - strict model 下仍未关闭

> 结论：Batch 3 本轮仍不满足升级到 `可发布` 的条件。

## 14. PRD Review — Signers / C ABI / Stake (`docs/prd-phase-3-batch-3-solana-zig-sdk-signersc-abi-stake.md`)

| PRD Story | 当前状态 | 代码证据 | 备注 |
|---|---|---|---|
| US-019 `Signer` 接口定义 | done | `src/solana/signers/signer.zig` | `Signer` vtable + `SignerError` 已落地 |
| US-020 `InMemorySigner` | done | `src/solana/signers/in_memory.zig`, `src/solana/tx/transaction.zig` | signer-path/keypair-path 等价已覆盖，legacy 多签顺序无关证据已存在 |
| US-021 `MockExternalSigner` | partial | `src/solana/signers/mock_external.zig` | 已覆盖 backend failure / rejected；仍需修复“忽略输入消息签名”与 `pubkey mismatch` 语义 |
| US-022 `signWithSigners(...)` | done | `src/solana/tx/transaction.zig` | 缺签错误与 keypair-path 单 signer 等价已覆盖 |
| US-023 C ABI 核心类型 | partial | `src/solana/cabi/core.zig`, `include/solana_zig.h` | header/core/test surface 仍未完全对齐，且仓内无稳定 C integration test |
| US-024 C ABI 交易构建 | done | `src/solana/cabi/transaction.zig` | instruction → message → tx → serialize 闭环已覆盖 |
| US-025 C ABI RPC 最小导出 | partial | `src/solana/cabi/rpc.zig` | surface 已导出，但 runtime 仍绑定 dummy transport |
| US-026 Stake 完整生命周期 | partial | `src/solana/interfaces/stake.zig` | 四类 builder 已有；create helper 契约与负路径测试仍不足 |
| US-027 benchmark 扩展 | done | `src/benchmark.zig` | `zig build bench` 已输出 signer/C ABI 指标 |
| US-028 文档收口 | done | `docs/prd-phase-3-batch-3-solana-zig-sdk-signersc-abi-stake.md`, `docs/17-quickstart-and-api-examples.md`, `docs/cabi-guide.md`, `docs/06-implementation-log.md`, `docs/10-coverage-matrix.md` | 2026-04-17 已按复核结论回写 |

## 15. Phase 3 Batch 4 Tracking (canonical board: #79~#82)

| 能力项 | 当前状态 | 对应任务 | 当前 blocker | 收口证据 | 证据落点 | Closeout 条件 |
|---|---|---|---|---|---|---|
| `signers minimum closure` | closed | `#79` | — | `3460ac9`，`Signer` 抽象 + `InMemorySigner` + `MockExternalSigner` + `signWithSigners`，isolated canonical `205/205` | `src/solana/signers/*` + `src/solana/tx/transaction.zig` + `docs/06` + `docs/37` | `G-P3D-01` + `G-P3D-02` PASS |
| `C ABI minimum closure` | closed | `#80` | — | `e9fd4ff`，`SOLANA_ZIG_ABI_VERSION` + `solana_zig_abi_version()` + header/export consistency + RPC 最小入口，isolated canonical `206/206` | `src/solana/cabi/*` + `include/solana_zig.h` + `docs/06` + `docs/37` | `G-P3D-01` + `G-P3D-03` PASS |
| `benchmark + verdict-upgrade input` | closed | `#81` | — | `bce967d`，`docs/13a` Run 2（signers/C ABI baseline）+ strict model verdict input，isolated canonical `208/208` | `docs/13a-benchmark-baseline-results.md` + `docs/15-phase1-execution-matrix.md` + `docs/37` | `G-P3D-04` PASS |
| `batch4.docs/gate reconciliation` | closed | `#82` | — | 本轮回写 `docs/06+10+13a+15+37`；`docs/14a` 沿用既有 exception 证据链；conditional writeback 未触发 | 本矩阵 + `docs/37` | `G-P3D-05` PASS |

### Phase 3 Batch 4 Exception Register

- `requestAirdrop`
  - 当前状态：`partial_exception`（public devnet rate-limit + local-live success）
  - strict model 下未关闭，继续阻塞升级到 `可发布`
- `getAddressLookupTable`
  - 当前状态：`accepted exception path`（method-not-found / RPC error evidence）
  - strict model 下未关闭，继续阻塞升级到 `可发布`

### Phase 3 Batch 4 Verdict

- 当前结论：`final: 有条件发布`
- 原因：仍存在 `partial_exception` + `accepted exception path`
- 条件回写：
  - `docs/35-phase3-batch3-release-readiness.md`：不触发
  - `docs/28-phase2-closeout-readiness.md`：不触发
