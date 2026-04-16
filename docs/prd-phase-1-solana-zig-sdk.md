# PRD: Phase 1 — Solana Zig SDK 链下客户端核心

> **Status: COMPLETE** — Phase 1 has shipped. This document reflects the as-shipped state.
> See `docs/19-phase2-planning.md` and `docs/20-phase2-batch2-planning.md` for Phase 2 scope.

## Overview
用 Zig 构建对齐官方 Rust SDK（solana-sdk 4.0.1 / solana-client 3.1.12）语义的 Solana SDK 链下客户端核心。Phase 1 聚焦 core 类型、交易构建/签名、16 个 RPC 方法（远超原始 5 个目标），以及 oracle 向量对照 + Devnet E2E 验收，实现"构造交易 → 签名 → 发送 → 结果解析"端到端闭环。

**实际交付超出原始范围**：新增了 WebSocket 订阅客户端、Token/ComputeBudget/System 指令构建器、Nonce E2E 流程、Surfpool E2E 验证、以及完整 benchmark 基线。

## Goals
- [x] 完成 core 模块：Pubkey/Signature/Keypair/Hash + base58/shortvec 编解码，字节布局与 Rust SDK 4.0.1 一致
- [x] 完成 tx 模块：Instruction/AccountMeta、Message（legacy + v0）、AddressLookupTable、VersionedTransaction（sign/verify/serialize/deserialize）
- [x] 完成 rpc 模块：16 个 RPC 方法（原始目标 5 个）+ transport 抽象 + WebSocket 客户端
- [x] Oracle 向量对照全部通过（非零 pubkey、Keypair sign、Legacy/V0 message serialize、Transaction serialize）
- [x] 每个公共接口至少 Happy Path + Error Path 测试覆盖
- [x] `std.testing.allocator` 全量测试无内存泄漏
- [x] Devnet acceptance path（zig build devnet-e2e）可留档最小交易流程
- [x] Benchmark 基线建立（zig build bench）

## Quality Gates

These commands must pass for every user story:
- `zig build test` — 全量单元测试 + oracle 向量对照
- 内存安全：所有测试使用 `std.testing.allocator`，无泄漏

For E2E stories, also include:
- `zig build devnet-e2e` — Devnet 端到端验收（需配置 SOLANA_RPC_URL）
- `zig build nonce-e2e` — Nonce 账户 E2E 验收
- `zig build e2e` — Surfpool 本地 E2E 验收

## User Stories

### US-001: Pubkey 类型与 base58 编解码
As a Zig 开发者, I want Pubkey 类型支持 32 字节固定布局和 base58 编解码 so that 我可以正确表示和传输 Solana 地址。

**Acceptance Criteria:**
- [ ] Pubkey 为 32 字节固定数组类型
- [ ] 支持从 base58 字符串解码为 Pubkey
- [ ] 支持从 Pubkey 编码为 base58 字符串
- [ ] 处理前导零场景正确
- [ ] 无效 base58 输入返回明确错误
- [ ] Oracle 向量：非零 pubkey 编解码与 Rust SDK 输出一致

### US-002: Signature 类型
As a Zig 开发者, I want Signature 类型支持 64 字节固定布局和 base58 编解码 so that 我可以正确表示和验证交易签名。

**Acceptance Criteria:**
- [ ] Signature 为 64 字节固定数组类型
- [ ] 支持 base58 编解码
- [ ] 支持默认值（全零）表示未签名
- [ ] 无效输入返回明确错误

### US-003: Hash 类型
As a Zig 开发者, I want Hash 类型支持 32 字节固定布局和 base58 编解码 so that 我可以正确表示 blockhash 等哈希值。

**Acceptance Criteria:**
- [ ] Hash 为 32 字节固定数组类型
- [ ] 支持 base58 编解码
- [ ] 支持从字节数组直接构造

### US-004: Keypair 与签名能力
As a Zig 开发者, I want Keypair 支持生成、从种子恢复、签名 so that 我可以在 Zig 中完成交易签名。

**Acceptance Criteria:**
- [ ] 支持随机生成 Keypair
- [ ] 支持从 64 字节种子恢复 Keypair
- [ ] 支持 Ed25519 签名
- [ ] 支持签名验证
- [ ] Oracle 向量：确定性种子签名结果与 Rust SDK 输出一致

### US-005: shortvec 编解码
As a Zig 开发者, I want shortvec 编解码实现 so that Message 序列化中的变长长度字段正确编码。

**Acceptance Criteria:**
- [ ] 实现 shortvec encode/decode
- [ ] 与 solana-short-vec 3.2.0 行为一致
- [ ] 覆盖边界值测试（0、127、128、16383、16384 等）

### US-006: Instruction 与 AccountMeta
As a Zig 开发者, I want Instruction 和 AccountMeta 结构 so that 我可以构造交易指令。

**Acceptance Criteria:**
- [ ] Instruction 包含 program_id、accounts、data 字段
- [ ] AccountMeta 包含 pubkey、is_signer、is_writable 字段
- [ ] 字段布局与 Rust SDK 对齐

### US-007: Legacy Message 编译与序列化
As a Zig 开发者, I want 构建和序列化 legacy Message so that 我可以构造传统格式交易。

**Acceptance Criteria:**
- [ ] 支持从 Instructions + payer + blockhash 编译 legacy Message
- [ ] 序列化结果与 Rust SDK 字节一致
- [ ] 支持反序列化
- [ ] 正确排列 account keys（signer-writable → signer-readonly → non-signer-writable → non-signer-readonly）
- [ ] Oracle 向量：多 instruction legacy message 序列化与 Rust 输出一致

### US-008: V0 Message 编译与序列化
As a Zig 开发者, I want 构建和序列化 v0 Message（含 Address Lookup Table）so that 我可以使用新版交易格式。

**Acceptance Criteria:**
- [ ] 支持 v0 Message 编译（含 ALT 引用）
- [ ] 序列化结果与 Rust SDK 字节一致
- [ ] 支持反序列化
- [ ] MessageAddressTableLookup 结构正确
- [ ] Oracle 向量：含 ALT 的 v0 message 序列化与 Rust 输出一致

### US-009: VersionedTransaction 签名与序列化
As a Zig 开发者, I want VersionedTransaction 支持签名、验签、序列化和反序列化 so that 我可以完成完整的交易流程。

**Acceptance Criteria:**
- [ ] 支持对 legacy 和 v0 Message 的 VersionedTransaction 构建
- [ ] 支持单签和多签
- [ ] sign 后 verify 通过
- [ ] 序列化/反序列化往返一致
- [ ] Oracle 向量：完整 Transaction serialize（签名 + message）与 Rust 输出一致

### US-010: RPC Transport 抽象与 HTTP 客户端
As a Zig 开发者, I want RPC transport 可插拔 so that 我可以在测试中 mock，在生产中使用 HTTP。

**Acceptance Criteria:**
- [x] 定义 transport 接口（发送 JSON-RPC 请求，返回响应）— `Transport` struct with `post_json_fn`/`deinit_fn` vtable
- [x] 实现基于 std.http.Client 的默认 HTTP transport — `HttpTransport`
- [x] 支持注入 mock transport 用于测试 — `noopDeinit` + custom `postJson`
- [x] 请求/响应遵循 JSON-RPC 2.0 规范

### US-011: getLatestBlockhash RPC 方法
As a Zig 开发者, I want 调用 getLatestBlockhash so that 我可以获取最新 blockhash 用于交易构建。

**Acceptance Criteria:**
- [x] 返回 blockhash（Hash 类型）和 lastValidBlockHeight
- [x] 支持 commitment 参数（processed/confirmed/finalized）— `getLatestBlockhashWithCommitment`
- [x] RPC 错误返回结构化错误信息 — `RpcErrorObject` with code/message/data_json
- [x] Mock 测试覆盖成功和错误路径

### US-012: getAccountInfo RPC 方法
As a Zig 开发者, I want 调用 getAccountInfo so that 我可以读取链上账户数据。

**Acceptance Criteria:**
- [x] 返回 AccountInfo（lamports、owner、data、executable、rentEpoch）+ raw_json 保留
- [x] 账户不存在时返回 null
- [x] 支持 encoding 参数（base64）— 自动解码 base64 data 字段
- [x] Mock 测试覆盖成功、不存在、错误路径

### US-013: getBalance RPC 方法
As a Zig 开发者, I want 调用 getBalance so that 我可以查询账户余额。

**Acceptance Criteria:**
- [x] 返回 lamports 余额（u64）
- [x] 支持 commitment 参数 — `getBalanceWithCommitment`
- [x] Mock 测试覆盖成功和错误路径

### US-014: simulateTransaction RPC 方法
As a Zig 开发者, I want 调用 simulateTransaction so that 我可以在发送前预验证交易。

**Acceptance Criteria:**
- [x] 接受序列化的交易 base64 编码
- [x] 返回模拟结果（err_json、logs、units_consumed）+ raw_json
- [x] 模拟失败时返回具体错误信息
- [x] Mock 测试覆盖成功和失败路径

### US-015: sendTransaction RPC 方法
As a Zig 开发者, I want 调用 sendTransaction so that 我可以将签名交易提交到网络。

**Acceptance Criteria:**
- [x] 接受序列化的交易 base64 编码
- [x] 返回交易签名（Signature 类型）
- [x] 支持 skipPreflight 和 preflightCommitment 可选参数 — `sendTransactionWithOptions`
- [x] RPC 错误返回结构化错误信息
- [x] Mock 测试覆盖成功和错误路径

### US-016: Oracle 向量对照测试补齐
As a 维护者, I want oracle 向量对照覆盖关键路径 so that Zig 实现与 Rust SDK 字节兼容性可回归验证。

**Acceptance Criteria:**
- [x] 非零 pubkey（含前导零场景）向量通过
- [x] Keypair sign → Signature（确定性种子）向量通过
- [x] Legacy message serialize（多 instruction）向量通过
- [x] V0 message serialize（含 ALT）向量通过
- [x] 完整 Transaction serialize（签名 + message）向量通过
- [x] 向量数据以 `testdata/oracle_vectors.json` 静态文件嵌入（`@embedFile`）

### US-017: Devnet E2E 验收路径
As a 维护者, I want Devnet 端到端测试 so that 我可以验证真实网络上的完整交易流程。

**Acceptance Criteria:**
- [x] `zig build devnet-e2e` 可执行端到端流程
- [x] 覆盖 construct → sign → simulate → send → confirm 流程（含 airdrop + balance poll）
- [x] 通过环境变量 SOLANA_RPC_URL 门控，不设置时跳过
- [x] 测试结果可留档（log 输出包含交易签名等关键信息）
- [x] Mock 模式始终运行（scripted RPC responses）
- [x] 新增 Nonce E2E（`zig build nonce-e2e`）：create → query → advance → send → confirm
- [x] 新增 Surfpool E2E（`zig build e2e`）：K3-H1 happy + K3-F1 failure

### US-018: Benchmark 基线建立
As a 维护者, I want 序列化/反序列化 benchmark 基线 so that 后续优化有数据对比基础。

**Acceptance Criteria:**
- [x] `zig build bench` 可运行 benchmark
- [x] 覆盖 Pubkey base58 编解码、shortvec 编解码、legacy/v0 message 序列化/反序列化、transaction 序列化/反序列化、ed25519 sign/verify
- [x] 输出包含 ops/sec、ns/op 等量化指标（BENCH|op|profile|iters|total_us|ns_op|ops_sec）
- [x] 结果可记录对比（不要求优于 Rust，仅需建立基线）

## Functional Requirements
- FR-01: [x] 支持固定长度类型（Pubkey 32B、Signature 64B、Hash 32B）与 base58/shortvec 编解码
- FR-02: [x] 支持 legacy/v0 message 从 Instructions 编译、序列化与反序列化
- FR-03: [x] 支持 VersionedTransaction 签名、验签、序列化、反序列化
- FR-04: [x] 支持 16 个 RPC 方法（getLatestBlockhash、getAccountInfo、getBalance、simulateTransaction、sendTransaction、getSlot、getEpochInfo、getMinimumBalanceForRentExemption、requestAirdrop、getAddressLookupTable、getSignaturesForAddress、getTokenAccountsByOwner、getTokenAccountBalance、getTokenSupply、getTransaction、getSignatureStatuses）并保留 RPC error 结构
- FR-05: [x] 支持 transport 抽象注入，便于 mock 与测试
- FR-06: [x] 支持 Devnet 最小交易流程端到端验收
- FR-07: [x] 支持 WebSocket 订阅（account/logs/signature）+ reconnect + dedup + observability
- FR-08: [x] 支持 System Program 指令构建（Transfer、CreateAccount、AdvanceNonceAccount、NonceState 解析）
- FR-09: [x] 支持 SPL Token 指令构建（TransferChecked、CloseAccount、MintTo、Approve、Burn）
- FR-10: [x] 支持 ComputeBudget 指令构建（SetComputeUnitLimit、SetComputeUnitPrice）
- FR-11: [x] 支持 Nonce 账户完整 E2E 流程（create → query → advance → send → confirm）
- FR-12: [x] 支持 Surfpool 本地 E2E 验证

## Non-Goals (Out of Scope)
- 链上程序运行时语义（no_std/SBF）— Phase 4
- Token Program / Associated Token Account 上层抽象 — ~~Phase 3~~ 已在 Phase 2 交付基础指令构建
- C ABI 导出 — Phase 3
- 与 Rust API 命名 1:1 一致（行为兼容优先）
- 异步 I/O（当前使用 std.http.Client 阻塞模式）
- 自定义序列化框架（当前手写 bincode 兼容层）
- WebSocket TLS 支持（当前仅 ws://，wss:// 返回 error.InvalidUrl）

## Technical Considerations
- **基线锁定**: solana-sdk 4.0.1 / solana-client 3.1.12，所有行为与字节布局对齐此版本
- **模块依赖方向**: core → tx → rpc，禁止反向依赖
- **Zig 版本**: 0.16.0
- **序列化**: 手写 bincode 兼容层（src/solana/compat/）
- **HTTP**: std.http.Client 阻塞 I/O
- **WebSocket**: 手动实现 RFC 6455 帧协议（ws:// 明文），含 reconnect + backoff + dedup ring buffer
- **签名**: Ed25519（Zig std.crypto.sign.Ed25519）
- **已知差异**: 无宏系统用 comptime 替代、无 trait 用函数指针/vtable 替代、无 tokio 用阻塞 I/O
- **JSON 解析**: std.json.Parsed(std.json.Value) — 无自定义 deserializer

## Module Structure (As-Shipped)
```
src/solana/
├── core/
│   ├── base58.zig          # encodeAlloc / decodeAlloc / decodeFixed
│   ├── shortvec.zig        # encodeToList / encodeAlloc / decode
│   ├── pubkey.zig          # Pubkey (32B)
│   ├── signature.zig       # Signature (64B) + verify
│   ├── keypair.zig         # Keypair (generate/fromSeed/fromSecretKey/sign)
│   └── hash.zig            # Hash (32B) + fromData(sha256)
├── tx/
│   ├── instruction.zig     # Instruction / AccountMeta
│   ├── address_lookup_table.zig  # AddressLookupTable / LookupEntry
│   ├── message.zig         # Message (legacy + v0 compile/serialize/deserialize)
│   └── transaction.zig     # VersionedTransaction (initUnsigned/sign/verifySignatures/serialize/deserialize)
├── rpc/
│   ├── types.zig           # RPC result types + Commitment + OwnedJson
│   ├── transport.zig       # Transport vtable + initHttpTransport
│   ├── http_transport.zig  # HttpTransport (std.http.Client)
│   ├── client.zig          # RpcClient (16 RPC methods + mock test helpers)
│   └── ws_client.zig       # WsClient + WsRpcClient (WebSocket + subscribe/reconnect/dedup/observability)
├── interfaces/
│   ├── system.zig          # System Program: Transfer/CreateAccount/AdvanceNonceAccount + NonceState 解析
│   ├── token.zig           # SPL Token: TransferChecked/CloseAccount/MintTo/Approve/Burn
│   └── compute_budget.zig  # ComputeBudget: SetComputeUnitLimit/SetComputeUnitPrice
├── compat/
│   ├── bincode_compat.zig  # appendU16Le/appendU32Le/appendU64Le/readU64Le
│   └── oracle_vector.zig   # Oracle vector schema + embedded validation tests
├── errors.zig              # SolanaError union
└── mod.zig                 # Module root (re-exports)
```

## Success Metrics
- [x] `zig build test` 全量通过，零内存泄漏
- [x] Oracle 向量最低覆盖集 5 类场景全部通过
- [x] 每个公共接口至少 1 Happy + 1 Error 测试
- [x] `zig build devnet-e2e` 可留档完整交易流程
- [x] `zig build bench` 建立序列化基线数据
- [x] `zig build nonce-e2e` Nonce 完整 E2E 流程
- [x] `zig build e2e` Surfpool 本地验证

## Open Questions
- solana-client 4.0.0 稳定后是否需要升级基线？
- 是否需要在 Phase 1 引入 CI 自动化（GitHub Actions）？
- Devnet E2E 测试的 funded account 管理策略？