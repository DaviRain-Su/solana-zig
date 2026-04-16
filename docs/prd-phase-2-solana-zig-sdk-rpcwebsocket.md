# PRD: Phase 2 — Solana Zig SDK 扩展 RPC、Websocket 订阅与生产级硬化

> **Status: CORE DELIVERED** — RPC 方法、WebSocket 客户端、重试策略已实现。
> 待完成：benchmark 扩展、E2E 验证、文档。
> 参见 `docs/prd-phase-1-solana-zig-sdk.md`（Phase 1 已完成）。

## Overview
在 Phase 1 已完成的 core/tx/rpc 5 个高频方法基础上，Phase 2 聚焦扩展 RPC 方法全量收口、Websocket 订阅生命周期生产级硬化、统一重试策略与 benchmark 基线扩展。目标是实现对链下数据查询和实时订阅的完整覆盖，并确保所有新增功能在 Devnet 上可验证、在 benchmark 上可度量。

**实际交付**：11 个扩展 RPC 方法全部实现（含 options 变体），WebSocket 客户端支持 7 种订阅类型 + 自动重连 + 去重 + 可观测性指标，RPC 统一重试策略（exponential backoff + rate limit 感知）。

## Goals
- [x] 完成 11 个扩展 RPC 方法的实现（含 options 变体 + 结构化错误）
- [x] 完成 Websocket 客户端生产级硬化：7 种订阅类型、重连/去重/resubscribe、可观测性指标
- [x] 实现 RPC 统一重试策略（exponential backoff + max retries + rate limit 感知）
- [ ] 扩展 benchmark 基线：新增 RPC 响应解析与 Websocket 消息编解码 benchmark
- [x] 保证 Phase 1 现有测试最终回归通过，允许必要的重构
- [ ] 产出 RPC 方法用法示例文档与 Websocket 使用指南

## Quality Gates

These commands must pass for every user story:
- `zig build test` — 全量单元测试 + 内存泄漏检测
- `zig build bench` — benchmark 基线运行，确保数据不衰退且新增项有输出

For RPC / Websocket / E2E stories, also include:
- `zig build devnet-e2e` — Devnet 端到端验收（需配置 SOLANA_RPC_URL）
- `zig build nonce-e2e` — Nonce 账户 E2E 验收
- `zig build e2e` — Surfpool 本地 E2E 验收

## User Stories

### US-001: getTransaction RPC 方法
As a Zig 开发者, I want 调用 getTransaction so that 我可以查询已确认交易的详情与元数据。

**Acceptance Criteria:**
- [x] 支持按签名查询交易详情 — `getTransaction` + `getTransactionWithOptions`
- [x] 返回 slot、blockTime、meta（fee、logMessages、err 等）+ raw_json
- [x] 支持 commitment 与 maxSupportedTransactionVersion 参数
- [ ] Mock 测试覆盖成功、交易不存在、错误路径
- [ ] Devnet E2E 验证：发送交易后查询并解析结果

### US-002: getSignaturesForAddress RPC 方法
As a Zig 开发者, I want 调用 getSignaturesForAddress so that 我可以获取某地址的历史交易签名列表。

**Acceptance Criteria:**
- [x] 返回签名列表（含 slot、blockTime、err、memo）+ raw_json — `SignatureStatusInfo`
- [x] 支持 before/until/limit 分页参数 — `getSignaturesForAddressWithOptions`
- [ ] Mock 测试覆盖成功、空列表、错误路径
- [ ] Devnet E2E 验证：查询已知活跃地址的签名历史

### US-003: getSignatureStatuses RPC 方法
As a Zig 开发者, I want 调用 getSignatureStatuses so that 我可以批量查询交易确认状态。

**Acceptance Criteria:**
- [x] 支持批量签名输入 — `getSignatureStatuses` + `getSignatureStatusesWithOptions`
- [x] 返回每个签名的 slot、confirmations、err、confirmationStatus — `SignatureStatus`
- [x] 支持 searchTransactionHistory 参数 — `GetSignatureStatusesOptions`
- [ ] Mock 测试覆盖成功、部分不存在、错误路径
- [x] Devnet E2E 验证：发送交易后轮询状态（已在 devnet_e2e.zig `waitForConfirmedSignature` 中实现）

### US-004: getSlot / getEpochInfo RPC 方法
As a Zig 开发者, I want 调用 getSlot 和 getEpochInfo so that 我可以获取网络时隙与纪元信息。

**Acceptance Criteria:**
- [x] getSlot 返回当前 slot（u64）— `getSlot` + `getSlotWithOptions`
- [x] getEpochInfo 返回 epoch、slotIndex、slotsInEpoch、absoluteSlot、blockHeight、transactionCount — `EpochInfo` + raw_json
- [x] 支持 commitment 参数 — `GetSlotOptions` / `GetEpochInfoOptions`
- [ ] Mock 测试覆盖成功和错误路径
- [ ] Devnet E2E 验证：返回值大于 0 且结构完整

### US-005: getMinimumBalanceForRentExemption RPC 方法
As a Zig 开发者, I want 调用 getMinimumBalanceForRentExemption so that 我可以计算创建账户所需最低租金豁免余额。

**Acceptance Criteria:**
- [x] 按数据长度（usize）返回 lamports（u64）
- [ ] Mock 测试覆盖成功和错误路径
- [x] Devnet E2E 验证：常见数据长度返回值与预期一致（已在 nonce_e2e.zig 中通过 raw transport 调用验证）

### US-006: requestAirdrop RPC 方法
As a Zig 开发者, I want 调用 requestAirdrop so that 我可以在 Devnet 上为测试账户获取 SOL。

**Acceptance Criteria:**
- [x] 接受目标 Pubkey 和 lamports 数量 — `requestAirdrop`
- [x] 返回 airdrop 交易签名 — `RequestAirdropResult`
- [ ] Mock 测试覆盖成功和错误路径
- [x] Devnet E2E 验证：成功请求并确认余额增加（已在 devnet_e2e.zig / nonce_e2e.zig 中通过 raw transport 调用验证）

### US-007: getAddressLookupTable RPC 方法
As a Zig 开发者, I want 调用 getAddressLookupTable so that 我可以读取链上地址查找表内容用于 v0 交易。

**Acceptance Criteria:**
- [x] 返回 AddressLookupTableAccount（key、state 含 addresses）— `AddressLookupTableResult` / `AddressLookupTableState` + raw_json
- [x] 账户不存在时返回 null
- [ ] Mock 测试覆盖成功、不存在、错误路径
- [ ] Devnet E2E 验证：查询已知 ALT 账户并解析地址列表

### US-008: getTokenAccountsByOwner RPC 方法
As a Zig 开发者, I want 调用 getTokenAccountsByOwner so that 我可以查询某地址持有的所有 Token 账户。

**Acceptance Criteria:**
- [x] 返回 Token 账户列表（pubkey、accountInfo）— `TokenAccountsByOwnerResult` / `TokenAccountInfo`
- [x] 支持 programId 和 mint 两种过滤条件 — `GetTokenAccountsByOwnerFilter` union
- [x] 支持 encoding 参数（base64）— `AccountEncoding`
- [ ] Mock 测试覆盖成功、空列表、错误路径
- [ ] Devnet E2E 验证：查询已知持有 Token 的地址

### US-009: getTokenAccountBalance / getTokenSupply RPC 方法
As a Zig 开发者, I want 调用 getTokenAccountBalance 和 getTokenSupply so that 我可以查询 Token 余额与总供应量。

**Acceptance Criteria:**
- [x] getTokenAccountBalance 返回 amount、decimals、uiAmountString — `TokenAmount` + raw_json
- [x] getTokenSupply 返回相同结构
- [ ] Mock 测试覆盖成功、账户不存在、错误路径
- [ ] Devnet E2E 验证：查询已知 Token mint 和账户

### US-010: RPC 统一重试策略
As a Zig 开发者, I want RPC 客户端具备统一重试策略 so that 网络抖动或 rate limit 时可自动恢复。

**Acceptance Criteria:**
- [x] 实现 exponential backoff 重试机制 — `callAndParse` 内部循环 + `retryDelayMs`
- [x] 支持配置 maxRetries、baseDelayMs、maxDelayMs — `RpcRetryConfig`（默认 3 retries, 100ms base, 1000ms max）
- [x] 对 HTTP 429（rate limit）和 transient 网络错误触发重试 — 429/500/502/503/504 + RpcTransport/RpcTimeout
- [x] 对不可恢复错误（如 400 Bad Request）直接失败 — 非 retryable HTTP status 直接返回
- [ ] Mock 测试覆盖重试成功、重试耗尽、非重试错误路径（`RetryMockTransport` 已存在但未完整测试）

### US-011: Websocket 订阅类型扩展
As a Zig 开发者, I want Websocket 客户端支持完整订阅类型 so that 我可以实时监听链上事件。

**Acceptance Criteria:**
- [x] 支持 accountSubscribe / accountUnsubscribe
- [x] 支持 programSubscribe / programUnsubscribe
- [x] 支持 signatureSubscribe / signatureUnsubscribe
- [x] 支持 slotSubscribe / slotUnsubscribe
- [x] 支持 rootSubscribe / rootUnsubscribe
- [x] 支持 logsSubscribe / logsUnsubscribe
- [x] 支持 blockSubscribe / blockUnsubscribe
- [x] 每种订阅类型有独立的回调类型与反序列化逻辑 — 7 种 notification struct + parse 函数
- [ ] Mock 测试覆盖订阅、通知、取消订阅流程

### US-012: Websocket 重连与 Resubscribe 生产级硬化
As a Zig 开发者, I want Websocket 客户端在断线后自动重连并恢复订阅 so that 生产环境可用。

**Acceptance Criteria:**
- [x] 断线后自动重连，支持指数退避 — `reconnectWithConfig` + `retryDelayMs` + `sleepBeforeReconnect`
- [x] 重连后自动恢复之前所有活跃订阅 — `resubscribeAll`
- [x] 订阅去重：同一订阅参数不重复发送 — `ensureSubscribed` 查重 + `DEDUP_CACHE_SIZE=16` ring buffer
- [x] 支持配置重连间隔、最大重试次数 — `WsReconnectConfig` + `MAX_RECONNECT_RETRIES=5` + `MAX_BACKOFF_MS=30000`
- [ ] Mock 测试覆盖断线、重连、resubscribe 完整流程
- [ ] Devnet E2E 验证：断开网络后恢复并继续接收通知

### US-013: Websocket 可观测性与指标
As a 维护者, I want Websocket 客户端暴露运行时指标 so that 我可以监控连接健康状态。

**Acceptance Criteria:**
- [x] 暴露连接状态（connected / disconnected / reconnecting）— `connectionState()` + `WsStats.connection_state`
- [x] 暴露活跃订阅数量 — `subscriptionCount()` + `WsStats.active_subscriptions`
- [x] 暴露已发送/已接收消息计数 — `WsStats.messages_sent_total` / `messages_received_total`
- [x] 暴露重连次数计数 — `WsStats.reconnect_attempts_total`
- [x] 提供查询接口或回调供外部集成 — `snapshot()` 返回完整 `WsStats` + `last_error_code`/`last_error_message`/`last_reconnect_unix_ms`

### US-014: RPC 响应解析 benchmark
As a 维护者, I want 扩展 RPC 响应解析 benchmark so that 大规模数据解析性能可度量。

**Acceptance Criteria:**
- [ ] 新增 getAccountInfo 大 data 字段解析 benchmark
- [ ] 新增 getTransaction 复杂 meta 解析 benchmark
- [ ] 新增批量 getSignatureStatuses 解析 benchmark
- [ ] 输出 ns/op 或 ops/sec 指标
- [ ] `zig build bench` 包含新增项且运行成功

### US-015: Websocket 消息编解码 benchmark
As a 维护者, I want Websocket 消息编解码 benchmark so that 订阅通知吞吐可度量。

**Acceptance Criteria:**
- [ ] 新增订阅请求序列化 benchmark
- [ ] 新增通知消息反序列化 benchmark（account / program / logs）
- [ ] 输出 ns/op 或 ops/sec 指标
- [ ] `zig build bench` 包含新增项且运行成功

### US-016: Devnet E2E 扩展验收
As a 维护者, I want Devnet 端到端覆盖扩展 RPC 与 Websocket so that 真实网络可用性可验证。

**Acceptance Criteria:**
- [ ] `zig build devnet-e2e` 覆盖所有扩展 RPC 方法至少一个场景
- [ ] `zig build devnet-e2e` 覆盖 Websocket accountSubscribe 与 signatureSubscribe
- [ ] 通过环境变量 SOLANA_RPC_URL 和 SOLANA_WS_URL 门控，未设置时跳过
- [ ] 测试结果可留档（log 输出关键信息）

### US-017: RPC 方法用法示例文档
As a Zig 开发者, I want 每个扩展 RPC 方法有用法示例 so that 我可以快速上手。

**Acceptance Criteria:**
- [ ] 为每个扩展 RPC 方法编写独立代码示例
- [ ] 示例包含构造请求、处理响应、处理错误
- [ ] 文档存放于 docs/rpc-examples.md 或类似位置

### US-018: Websocket 使用指南
As a Zig 开发者, I want Websocket 使用指南 so that 我可以正确集成订阅功能。

**Acceptance Criteria:**
- [ ] 文档包含连接、订阅、处理通知、取消订阅、错误处理完整流程
- [ ] 文档包含重连行为说明与配置项说明
- [ ] 文档存放于 docs/websocket-guide.md 或类似位置

## Functional Requirements
- FR-01: [x] 支持 11 个扩展 RPC 方法（getTransaction、getSignaturesForAddress、getSignatureStatuses、getSlot、getEpochInfo、getMinimumBalanceForRentExemption、requestAirdrop、getAddressLookupTable、getTokenAccountsByOwner、getTokenAccountBalance、getTokenSupply）并保留结构化错误
- FR-02: [x] RPC 客户端必须实现统一重试策略，支持 exponential backoff、max retries、rate limit 感知
- FR-03: [x] Websocket 客户端必须支持 7 种订阅类型（account、program、signature、slot、root、logs、block）
- FR-04: [x] Websocket 客户端断线后必须自动重连并恢复所有活跃订阅
- FR-05: [x] Websocket 客户端必须暴露连接状态、订阅数量、消息计数、重连次数等运行时指标
- FR-06: [ ] `zig build bench` 必须覆盖扩展 RPC 响应解析与 Websocket 消息编解码
- FR-07: [ ] `zig build devnet-e2e` 必须覆盖扩展 RPC 方法与 Websocket 订阅的 Devnet 验证
- FR-08: [ ] 必须产出 RPC 方法示例文档与 Websocket 使用指南

## Non-Goals (Out of Scope)
- 链上程序运行时语义（no_std/SBF）— Phase 4
- WebSocket TLS (wss) 强制支持 — 当前 ws_client.zig 仅支持 ws://，wss:// 返回 error.InvalidUrl
- 异步 I/O（继续使用阻塞模式）
- 自定义序列化框架（继续使用手写 bincode 兼容层）

## Technical Considerations
- **基线锁定**: solana-sdk 4.0.1 / solana-client 3.1.12，所有行为与字节布局对齐此版本
- **模块依赖方向**: core → tx → rpc，ws_client.zig 依赖 rpc/types.zig
- **Zig 版本**: 0.16.0
- **HTTP**: std.http.Client 阻塞 I/O
- **WebSocket**: 手动实现 RFC 6455 帧协议（ws:// 明文），基于 std.posix fd 读写 + SHA1 handshake
- **重试策略**: RpcClient `callAndParse` 统一封装，指数退避 + HTTP status 429/500/502/503/504 感知
- **WS 重连**: `reconnectWithConfig` 指数退避 + `resubscribeAll` 自动恢复 + ring buffer 去重
- **WS 可观测性**: `WsStats` snapshot schema（P2-23, frozen in docs/24），含 8 个指标字段
- **JSON 解析**: std.json.Parsed(std.json.Value) — 无自定义 deserializer
- **已知差异**: 无 trait 用函数指针/vtable 替代、无 tokio 用阻塞 I/O

## Success Metrics
- [x] `zig build test` 全量通过，零内存泄漏
- [ ] 11 个扩展 RPC 方法均有 mock 测试 + Devnet E2E 覆盖
- [ ] 7 种 Websocket 订阅类型均有 mock 测试，核心类型有 Devnet E2E
- [ ] `zig build bench` 输出扩展 RPC 与 Websocket 的量化性能指标
- [ ] `zig build devnet-e2e` 可验证扩展 RPC 与 Websocket 完整流程
- [ ] 文档（rpc-examples.md、websocket-guide.md）完整可用

## Open Questions
- wss (TLS) 支持是否应在 Phase 2 末期作为 stretch goal 尝试？
- 是否需要引入外部 websocket 库以简化 blockSubscribe 的大负载处理？
- Devnet E2E 测试的 funded account / airdrop 速率限制如何应对？
- 是否需要为 RPC 重试策略引入可插拔的 jitter 策略？