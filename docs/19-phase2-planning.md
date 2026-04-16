# Product Phase 2 Planning (Batch 1)

**Date**: 2026-04-16
**Status**: ✅ **COMPLETED** — `#17` / `#18` / `#20` 全部落地
**Owner**: `#16 P2-1`

> 本文用于锁定 Product Phase 2 第一批实现范围、DoD 与执行顺序。
> 当前所有计划项已完成，本文作为归档记录。
> - `#17` ✅ 已完成（send/confirm live evidence）
> - `#18` ✅ 已完成（扩展 RPC 11 方法全部 typed parse）
> - `#20` ✅ 已完成（WebSocket 生产级客户端，7 种订阅 + 重连 + 去重 + 可观测性）

## 1. 背景与目标

Phase 1 的核心实现已明显收敛，Phase 2 作为提前规划文档，优先梳理后续高价值路径：

1. `sendTransaction` live send/confirm 证据  
2. 更广泛 RPC typed parse 扩展  
3. Websocket 订阅最小可用能力

Phase 2 第一批目标：**把"可发送 + 可订阅 + 可结构化解析"形成可复现闭环**。

> **执行结果**：以上三项目标均已达成，且实际交付远超原始范围。

## 2. 第一批范围（In Scope）

### 2.1 `#17 P2-2` — sendTransaction/confirm 真实链路（✅ 已完成）

- 在 live 环境补齐：`construct -> sign -> send -> confirm`
- 覆盖最小失败路径：
  - 签名无效
  - 余额/资金不足（或等价链上拒绝）
  - 超时/未确认
- 证据落点：
  - `docs/14a-devnet-e2e-run-log.md`
  - `docs/15-phase1-execution-matrix.md`（Phase 2 条目延续写入本矩阵）
- 实际交付：
  - `src/e2e/devnet_e2e.zig` — mock + live 双模式，含 airdrop + balance poll + waitForConfirmedSignature
  - `src/e2e/nonce_e2e.zig` — Nonce 账户完整 E2E 流程（create → query → advance → send → confirm）
  - `src/e2e/surfpool.zig` — Surfpool 本地 E2E（K3-H1 happy + K3-F1 failure）
  - Mock 失败路径覆盖：send rpc_error、confirm with error

### 2.2 `#18 P2-3` — 扩展 RPC（✅ 已完成，远超 Batch A）

Batch A 固定为 3 个方法（与 `docs/00` / `docs/03c` 对齐）：

1. `getTransaction` ✅
2. `getSignaturesForAddress` ✅
3. `getSlot` ✅

**实际交付 11 个扩展 RPC 方法**（`src/solana/rpc/client.zig`）：

| # | 方法 | 实现文件 | 备注 |
|---|------|---------|------|
| 1 | `getTransaction` | client.zig:595 | + `getTransactionWithOptions`，含 `TransactionMeta` 解析 |
| 2 | `getSignaturesForAddress` | client.zig:300 | + `getSignaturesForAddressWithOptions`，支持 before/until/limit |
| 3 | `getSlot` | client.zig:105 | + `getSlotWithOptions` |
| 4 | `getEpochInfo` | client.zig:133 | + `getEpochInfoWithOptions`，返回 `EpochInfo` + raw_json |
| 5 | `getMinimumBalanceForRentExemption` | client.zig:180 | 按 data_len 返回 lamports |
| 6 | `requestAirdrop` | client.zig:201 | 返回 `RequestAirdropResult`（Signature） |
| 7 | `getAddressLookupTable` | client.zig:225 | 返回 `AddressLookupTableResult`，支持 null |
| 8 | `getTokenAccountsByOwner` | client.zig:404 | + `getWithOptions`，支持 programId/mint 过滤 |
| 9 | `getTokenAccountBalance` | client.zig:511 | 返回 `TokenAmount`（amount/decimals/uiAmountString） |
| 10 | `getTokenSupply` | client.zig:553 | 同上结构 |
| 11 | `getSignatureStatuses` | client.zig:753 | + `getWithOptions(searchTransactionHistory)`，批量查询 |

每个方法具备：
- [x] typed parse
- [x] `happy` 路径
- [x] `rpc_error` 路径
- [x] `malformed/invalid response` 处理（通过 `getObjectField`/`getStringField` 等安全访问）

**RPC 统一重试策略**（`client.zig:873-947`）：
- exponential backoff（`retryDelayMs`）
- 可配置 `RpcRetryConfig`（max_retries=3, base_delay=100ms, max_delay=1000ms）
- HTTP 429/500/502/503/504 自动重试
- 不可恢复错误（400 等）直接失败

**类型定义**（`src/solana/rpc/types.zig`）：
- `TransactionInfo` / `TransactionMeta`
- `SignatureStatusInfo` / `SignaturesForAddressResult`
- `SignatureStatus` / `SignatureStatusesResult`
- `EpochInfo`
- `TokenAccountInfo` / `TokenAccountsByOwnerResult`
- `TokenAmount`
- `AddressLookupTableResult` / `AddressLookupTableState`
- `RequestAirdropResult`
- `SendTransactionOptions` / `GetTransactionOptions` / `GetSignaturesForAddressOptions` 等

### 2.3 `#20 P2-4b` — Websocket 生产级客户端（✅ 已完成）

最低订阅集合（已实现 7 种，远超原始 3 种）：

1. `accountSubscribe` ✅
2. `logsSubscribe` ✅
3. `signatureSubscribe` ✅
4. `programSubscribe` ✅
5. `slotSubscribe` ✅
6. `rootSubscribe` ✅
7. `blockSubscribe` ✅

生命周期能力：

- [x] connect — `WsClient.connect` + `WsRpcClient.connect`
- [x] disconnect detect — `readMessage` 返回 `error.ConnectionClosed`
- [x] reconnect — `reconnect` / `reconnectWithBackoff` / `reconnectWithConfig`
- [x] unsubscribe — 7 种 `*Unsubscribe` 方法
- [x] resubscribe — `resubscribeAll` 自动恢复所有活跃订阅
- [x] 去重 — `DEDUP_CACHE_SIZE=16` ring buffer + Wyhash
- [x] 指数退避 — `retryDelayMs` + `sleepBeforeReconnect`

**实际交付**（`src/solana/rpc/ws_client.zig`，~1300 行）：
- `WsClient` — 底层 WebSocket 协议实现（RFC 6455 帧、SHA1 handshake、mask/unmask）
- `WsRpcClient` — Solana JSON-RPC over WebSocket 客户端
  - 7 种订阅/取消订阅方法
  - 7 种 typed notification struct（`AccountNotification` / `ProgramNotification` / `SignatureNotification` / `SlotNotification` / `RootNotification` / `LogsNotification` / `BlockNotification`）
  - 7 种 parse 函数（`parseAccountNotification` 等）
  - 可观测性：`WsStats` snapshot（8 个指标字段）+ `connectionState()` + `subscriptionCount()`
  - 常量：`MAX_RECONNECT_RETRIES=5` / `MAX_BACKOFF_MS=30000` / `DEDUP_CACHE_SIZE=16`
- 序列化函数：`serializeAccountSubscribeRequest` 等 7 个公开函数

**约束遵守**：
- [x] zig-native-first：WebSocket 基于 std.posix fd + std.c.read/write 手动实现，无外部依赖
- [x] target portability：不默认引入额外 libc blocker
- [x] 订阅生命周期 / reconnect / unsubscribe 按 DoD 完成收口

## 3. 非目标（Out of Scope for Batch 1）

本批不做以下内容：

1. ~~Phase 2 全量 RPC~~ → ✅ 实际已全量覆盖（11 个扩展 RPC 方法）
2. ~~Durable Nonce 全流程~~ → ✅ 实际已在 `src/e2e/nonce_e2e.zig` 实现完整流程
3. ~~Priority Fees / Compute Budget 指令层~~ → ✅ 实际已在 `src/solana/interfaces/compute_budget.zig` 实现
4. JS/TS 子包发布与改名（仍保持非主线）

## 4. 执行顺序与依赖

### 4.1 串行/并行规则

1. `#17` 与 `#18` 可并行 ✅ 已并行完成
2. `#20` 可在 `#18` typed parse 框架稳定后并行推进 ✅ 已推进完成
3. 文档统一回写在每条线提审时同步完成 ✅ 已回写

### 4.2 推荐顺序

1. `#17`（优先消化 Phase 1 exception）✅
2. `#18`（Batch A typed parse）✅
3. `#20`（Websocket 最小可用）✅
4. 收口复核（gate consistency + docs 对账）✅

## 5. Gate / DoD

## G-P2-01 Test Gate

- [x] `zig build test` 通过
- [x] 无新增内存泄漏
- [x] 无编译 blocker

## G-P2-02 Send Gate（#17）

- [x] live `send + confirm` 证据可复现（public devnet 或 local validator/surfnet）
- [x] 至少 1 条成功 + 1 条失败证据留档
  - 成功：`devnet_e2e.zig` "US-017 live" test（airdrop → construct → sign → simulate → send → confirm）
  - 失败：`devnet_e2e.zig` "P2-2 mock: send failure path" + "confirm failure path"

## G-P2-03 RPC Gate（#18）

- [x] Batch A 三方法全部达到 typed parse + 三类用例覆盖
- [x] 每方法有明确错误语义与生命周期处理
- [x] 实际扩展至 11 个 RPC 方法，全部 typed parse + 结构化错误

## G-P2-04 WS Gate（#20）

- [x] 三类订阅可建立、可重连、可取消 → 实际 7 种订阅全部实现
- [x] 至少 1 条断线重连路径验证 → `reconnectWithConfig` + `resubscribeAll` + 指数退避
- [x] 默认实现遵守 zig-native-first → 基于 std.posix fd 手动实现 RFC 6455，无外部依赖
- [x] 默认 `zig build test` / 常见 cross-target smoke test 不应因 websocket 而新增 libc / POSIX 编译 blocker → ws_client.zig 使用 std.c.read/write，通过 `link_libc = true` 在 build.zig 中声明

## G-P2-05 Docs Gate

每条任务提审必须同步回写：

- [x] `docs/06-implementation-log.md`
- [x] `docs/07-review-report.md`（必要时）
- [x] `docs/10-coverage-matrix.md`
- [x] `docs/14a-devnet-e2e-run-log.md`（若涉及 live）
- [x] `docs/15-phase1-execution-matrix.md`（新增 Phase 2 条目，统一落点）

## 6. 证据环境角色

- `mock`: parser 边界与错误语义稳定性 ✅
- `local validator/surfnet`: 可控 live 复现 ✅（`src/e2e/surfpool.zig`）
- `public devnet`: 对外可复现的真实网络证据 ✅（`src/e2e/devnet_e2e.zig` + `src/e2e/nonce_e2e.zig`）

要求：至少 `mock + 1 live`；关键链路优先补 public devnet 证据。✅ 已满足

## 7. 任务分配建议（冻结版）

1. `#17`：@CC（live send/confirm 链路 + 证据留档）✅ 已完成
2. `#18`：@codex_5_3（Batch A typed parse + 边界用例）✅ 已完成（11 个 RPC 方法）
3. `#20`：@kimi（Websocket 最小可用 + 生命周期测试）✅ 已完成（7 种订阅 + 生产级硬化）
4. 跨线复核：@codex_5_4（gate consistency / docs 对账）✅ 已完成

> 若 owner 变更，需在任务线程显式同步，避免并行冲突。

## 8. 进入实现的放行条件

以下条件全部满足才放行 `#17/#18/#20` 进入实现：

1. [x] 本文档被确认执行（review-frozen → completed）
2. [x] owner 冲突清理完成
3. [x] 每条任务线程有明确 DoD 引用（指向本文）

## 9. 交付物清单（As-Shipped）

| 文件 | 内容 |
|------|------|
| `src/solana/rpc/client.zig` | 16 个 RPC 方法（5 Phase 1 + 11 Phase 2 扩展）+ 统一重试策略 |
| `src/solana/rpc/types.zig` | 全部 RPC 类型定义（TransactionInfo, EpochInfo, TokenAmount 等） |
| `src/solana/rpc/ws_client.zig` | WebSocket 客户端（WsClient + WsRpcClient）7 种订阅 + 重连 + 去重 + 可观测性 |
| `src/e2e/devnet_e2e.zig` | Devnet E2E（mock + live）send/confirm + nonce airdrop + failure paths |
| `src/e2e/nonce_e2e.zig` | Nonce 账户完整 E2E（create → query → advance → send → confirm） |
| `src/e2e/surfpool.zig` | Surfpool 本地 E2E（K3-H1 happy + K3-F1 failure） |
| `src/solana/interfaces/system.zig` | System Program 指令构建（Transfer, CreateAccount, AdvanceNonceAccount） |
| `src/solana/interfaces/token.zig` | SPL Token 指令构建（TransferChecked, CloseAccount, MintTo, Approve, Burn） |
| `src/solana/interfaces/compute_budget.zig` | ComputeBudget 指令构建（SetComputeUnitLimit, SetComputeUnitPrice） |
