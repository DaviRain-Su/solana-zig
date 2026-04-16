# Phase 3c - RPC Extended Spec

> 本文是 `docs/03-technical-spec.md` 的子规格，承接 Product Phase 2 的扩展 RPC、Websocket 与 typed parse 收敛。

## 1. Scope

计划覆盖：
- 扩展 JSON-RPC 方法
- typed parse 子层
- Websocket 订阅生命周期
- ALT / Nonce / 交易查询相关能力

## 2. Phase 2 Target Methods

首批优先级：
- `getAddressLookupTable`
- `getTransaction`
- `getSignaturesForAddress`
- `getTokenAccountsByOwner`
- `getSlot`
- `getEpochInfo`
- `getMinimumBalanceForRentExemption`
- `requestAirdrop`

## 3. Parse Strategy

当前 `RpcClient` 已可工作，但仍较多返回 `OwnedJson`。Phase 2 的目标是逐步引入 typed parse 子层：

```zig
pub const ParsedAccountInfo = struct { ... };
pub const ParsedTransaction = struct { ... };
```

约束：
- 新增 typed parse 时，不破坏现有错误保真策略
- 无法稳定建模的字段可继续保留 `OwnedJson` 子字段
- 先做“高价值、结构稳定”的字段 typed 化，再扩展到完整 schema

## 4. Websocket Lifecycle

至少要定义：
- connect
- subscribe
- receive
- reconnect
- unsubscribe
- close

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
- 应支持与 `system` 指令层配合完成 nonce advance 工作流
- 离线签名路径不得依赖隐式网络查询

### 5.3 Transaction Query
- `getTransaction` 需先明确返回编码策略（json / jsonParsed / base64）
- 第一版建议锁单一编码，避免同时展开全部解析形态

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
- `I-WS-001`
- `I-TXW-001`
- `I-TXW-002`

至少覆盖：
- Happy：mock + Devnet 双路径
- Boundary：number_string、缺字段、空 result、断线重连
- Error：非 200、malformed JSON、rpc_error、订阅丢失

## 8. First Implementation Order

1. `getAddressLookupTable`
2. `getTransaction` / `getSignaturesForAddress`
3. `getSlot` / `getEpochInfo` / `getMinimumBalanceForRentExemption` / `requestAirdrop`
4. typed parse 子层（先高频结果）
5. Websocket 订阅骨架
6. Durable Nonce 工作流联调

## 9. Open Questions

- Websocket 是否放在 `rpc/` 下，还是独立 `subscriptions/` 模块？
- typed parse 是否需要单独文件层级（如 `rpc/parsed/*`）？
- `getTransaction` 第一版应选哪种 encoding 作为锁定基线？
