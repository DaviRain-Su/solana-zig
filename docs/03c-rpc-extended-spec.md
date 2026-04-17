# Phase 3c - RPC Extended Spec

> 本文是 `docs/03-technical-spec.md` 的子规格，承接 Product Phase 2 的扩展 RPC、Websocket，以及 Phase 1 最小 typed schema 之后的 typed parse 扩展。

## 1. Scope

计划覆盖：
- 扩展 JSON-RPC 方法
- typed parse 子层
- Websocket 订阅生命周期
- ALT / Nonce / 交易查询相关能力

## 2. Phase 2 Target Methods

### 2.1 已落地的全部扩展 RPC 方法（✅ 已完成）

当前 16 个 RPC 方法全部实现（5 Phase 1 + 11 Phase 2），含 `*WithOptions` 变体共 25 个公开函数：
- `getTransaction` / `getTransactionWithOptions`
- `getSignaturesForAddress` / `getSignaturesForAddressWithOptions`
- `getSignatureStatuses` / `getSignatureStatusesWithOptions`
- `getSlot` / `getSlotWithOptions`
- `getEpochInfo` / `getEpochInfoWithOptions`
- `getMinimumBalanceForRentExemption`
- `requestAirdrop`
- `getAddressLookupTable`
- `getTokenAccountsByOwner` / `getTokenAccountsByOwnerWithOptions`
- `getTokenAccountBalance`
- `getTokenSupply`

### 2.2 TokenAmount Type

`TokenAmount` 是 `getTokenAccountBalance` 和 `getTokenSupply` 的返回结构：

| Field | Type | Notes |
|---|---|---|
| `ui_amount` | `?f64 = null` | 人类可读数值，若代币不支持 decimals 则为 null |
| `ui_amount_string` | `?[]const u8 = null` | 字符串格式，可能包含 trailing zeros |
| `amount` | `[]const u8` | 最小单位（lamports-like）的字符串表示 |
| `decimals` | `u8` | 代币小数位 |
| `raw_json` | `?[]const u8 = null` | 原始 JSON 保留，用于排障 |

注意：`ui_amount_string` 在 Solana 某些代币类型下可能为 null，代码中已按 `?[]const u8 = null` 处理。

### 2.3 后续优先级

所有 Phase 2 目标方法已交付。后续扩展方向：
- 更多低频 RPC 方法（见 Product Phase 4 评估）
- `jsonParsed` encoding 支持（当前 `getTransaction` 以 `json` encoding 为基线）
- typed parse 子层继续扩展（当前 5 个高频方法 + 11 个扩展方法均已 typed）

## 3. Parse Strategy

当前 `RpcClient` 已完成一轮 Phase 1 高频方法 typed 收敛：
- `getLatestBlockhash` / `getBalance` 为直接 typed 返回
- `getAccountInfo` 返回 `AccountInfo`（最小 typed 子集 + `data` + `raw_json`）
- `simulateTransaction` 返回 `SimulateTransactionResult`（`err_json/logs/units_consumed/raw_json`）
- `sendTransaction` 返回 `SendTransactionResult`

边界约定：
- **Phase 1 closeout** 仅要求对当前 5 个高频方法完成“最小可接受”的 typed schema 收敛。
- 其中 `AccountInfo` 的最小 typed 子集至少包括：`lamports`、`owner`、`executable`、`rent_epoch`；不稳定扩展仍可经 `raw_json` 保留。
- `simulateTransaction` 的错误语义与原始响应不再以纯 `OwnedJson` 暴露，而是通过 `err_json/raw_json` 旁路保真。
- **Phase 2** 再继续推进更广泛的 typed parse 子层与扩展 RPC 的结构化输出。

Phase 2 的目标是逐步引入 typed parse 子层：

```zig
pub const ParsedAccountInfo = struct { ... };
pub const ParsedTransaction = struct { ... };
```

约束：
- 新增 typed parse 时，不破坏现有错误保真策略
- 无法稳定建模的字段可继续通过 `raw_json` / 局部原始字段保留
- 先做“高价值、结构稳定”的字段 typed 化，再扩展到完整 schema

## 4. Websocket Lifecycle

至少要定义：
- connect
- subscribe
- receive
- reconnect
- unsubscribe
- close

当前实现快照（✅ 生产级硬化完成）：
- `WsClient` / `WsRpcClient` 已完整实现并进入公开包面（2681 行）
- 7 种订阅全部支持：`accountSubscribe` / `programSubscribe` / `signatureSubscribe` / `slotSubscribe` / `rootSubscribe` / `logsSubscribe` / `blockSubscribe`
- 生产级硬化：heartbeat、deterministic backoff、dedup ring buffer、WsStats 可观测性
- 连接/断线/重连/去重/可观测性测试全覆盖
- 订阅生命周期完整：connect → subscribe → receive → reconnect → resubscribe → unsubscribe → close

默认策略：
- 断线后可配置是否自动重连
- 重连后应重新建立有效订阅
- 如果订阅 id 失效，必须显式报错，不 silent drop

## 5. ALT / Nonce / Transaction Workflow

### 5.1 ALT
- `getAddressLookupTable` 应输出足够支持 v0 compile 的 typed 结构
- ALT 数据若无法完整 typed，可先保留原始字段以便排查

### 5.2 Nonce
- 应支持 nonce 账户查询
- **锁定决策**：Nonce Advance 指令构造归属 `interfaces/system`；涉及查询、组装与离线签名协同的流程，可由 tx/rpc helper 组合完成
- 离线签名路径不得依赖隐式网络查询

### 5.3 Transaction Query
- **锁定决策**：`getTransaction` 第一版以 `json` encoding 作为基线，不在首版同时展开 `jsonParsed` / `base64`
- 后续若扩展更多 encoding，需通过 ADR 或子规格修订明确

## 6. Error Model

至少需要表达：
- `RpcTransport`
- `RpcParse`
- `InvalidRpcResponse`
- `RpcTimeout`
- `WebsocketDisconnected`
- `SubscriptionLost`
- `UnsupportedEncoding`

仍需遵守：JSON-RPC `error` 对象走 `RpcResult.rpc_error`，不丢失 `code/message/data`。

## 7. Test Mapping Requirements

映射到 `docs/05-test-spec.md`：
- `I-RPCX-001`
- `I-RPCX-002`
- `I-RPCX-003`
- `I-RPCX-004`
- `I-WS-001`
- `I-TXW-001`
- `I-TXW-002`

至少覆盖：
- Happy：mock + Devnet 双路径
- Boundary：number_string、缺字段、空 result、断线重连
- Error：非 200、malformed JSON、rpc_error、订阅丢失

## 8. Implementation Snapshot（✅ 全部交付）

Phase 2 全部 16 个 RPC 方法 + 7 种 WebSocket 订阅 + Nonce 工作流 + Compute Budget 均已交付。详见 `docs/00-roadmap.md` Phase 2 交付物清单。

后续方向：
- `jsonParsed` encoding 支持（当前 `getTransaction` 以 `json` encoding 为基线）
- 更多低频 RPC 方法（Product Phase 4 评估）
- typed parse 子层继续扩展

## 9. Open Questions

- Websocket 是否放在 `rpc/` 下，还是独立 `subscriptions/` 模块？
- typed parse 是否需要单独文件层级（如 `rpc/parsed/*`）？
