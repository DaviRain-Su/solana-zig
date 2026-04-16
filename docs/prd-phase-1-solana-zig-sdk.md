# PRD: Phase 1 — Solana Zig SDK 链下客户端核心

## Overview
用 Zig 构建对齐官方 Rust SDK（solana-sdk 4.0.1 / solana-client 3.1.12）语义的 Solana SDK 链下客户端核心。Phase 1 聚焦 core 类型、交易构建/签名、5 个高频 RPC 方法，以及 oracle 向量对照 + Devnet E2E 验收，实现"构造交易 → 签名 → 发送 → 结果解析"端到端闭环。

## Goals
- 完成 core 模块：Pubkey/Signature/Keypair/Hash + base58/shortvec 编解码，字节布局与 Rust SDK 4.0.1 一致
- 完成 tx 模块：Instruction/AccountMeta、Message（legacy + v0）、VersionedTransaction（sign/verify/serialize/deserialize）
- 完成 rpc 模块：5 个高频方法（getLatestBlockhash、getAccountInfo、getBalance、simulateTransaction、sendTransaction）+ transport 抽象
- Oracle 向量对照全部通过（非零 pubkey、Keypair sign、Legacy/V0 message serialize、Transaction serialize）
- 每个公共接口至少 Happy Path + Error Path 测试覆盖
- `std.testing.allocator` 全量测试无内存泄漏
- Devnet acceptance path（zig build devnet-e2e）可留档最小交易流程

## Quality Gates

These commands must pass for every user story:
- `zig build test` — 全量单元测试 + oracle 向量对照
- 内存安全：所有测试使用 `std.testing.allocator`，无泄漏

For E2E stories, also include:
- `zig build devnet-e2e` — Devnet 端到端验收（需配置 SOLANA_RPC_URL）

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
- [ ] 定义 transport 接口（发送 JSON-RPC 请求，返回响应）
- [ ] 实现基于 std.http.Client 的默认 HTTP transport
- [ ] 支持注入 mock transport 用于测试
- [ ] 请求/响应遵循 JSON-RPC 2.0 规范

### US-011: getLatestBlockhash RPC 方法
As a Zig 开发者, I want 调用 getLatestBlockhash so that 我可以获取最新 blockhash 用于交易构建。

**Acceptance Criteria:**
- [ ] 返回 blockhash（Hash 类型）和 lastValidBlockHeight
- [ ] 支持 commitment 参数（processed/confirmed/finalized）
- [ ] RPC 错误返回结构化错误信息
- [ ] Mock 测试覆盖成功和错误路径

### US-012: getAccountInfo RPC 方法
As a Zig 开发者, I want 调用 getAccountInfo so that 我可以读取链上账户数据。

**Acceptance Criteria:**
- [ ] 返回 AccountInfo（lamports、owner、data、executable、rentEpoch）
- [ ] 账户不存在时返回 null
- [ ] 支持 encoding 参数（base64）
- [ ] Mock 测试覆盖成功、不存在、错误路径

### US-013: getBalance RPC 方法
As a Zig 开发者, I want 调用 getBalance so that 我可以查询账户余额。

**Acceptance Criteria:**
- [ ] 返回 lamports 余额（u64）
- [ ] 支持 commitment 参数
- [ ] Mock 测试覆盖成功和错误路径

### US-014: simulateTransaction RPC 方法
As a Zig 开发者, I want 调用 simulateTransaction so that 我可以在发送前预验证交易。

**Acceptance Criteria:**
- [ ] 接受序列化的交易 base64 编码
- [ ] 返回模拟结果（err、logs、unitsConsumed）
- [ ] 模拟失败时返回具体错误信息
- [ ] Mock 测试覆盖成功和失败路径

### US-015: sendTransaction RPC 方法
As a Zig 开发者, I want 调用 sendTransaction so that 我可以将签名交易提交到网络。

**Acceptance Criteria:**
- [ ] 接受序列化的交易 base64 编码
- [ ] 返回交易签名（Signature 类型）
- [ ] 支持 skipPreflight 等可选参数
- [ ] RPC 错误返回结构化错误信息
- [ ] Mock 测试覆盖成功和错误路径

### US-016: Oracle 向量对照测试补齐
As a 维护者, I want oracle 向量对照覆盖关键路径 so that Zig 实现与 Rust SDK 字节兼容性可回归验证。

**Acceptance Criteria:**
- [ ] 非零 pubkey（含前导零场景）向量通过
- [ ] Keypair sign → Signature（确定性种子）向量通过
- [ ] Legacy message serialize（多 instruction）向量通过
- [ ] V0 message serialize（含 ALT）向量通过
- [ ] 完整 Transaction serialize（签名 + message）向量通过
- [ ] 向量数据以静态文件或 comptime 嵌入，不依赖外部服务

### US-017: Devnet E2E 验收路径
As a 维护者, I want Devnet 端到端测试 so that 我可以验证真实网络上的完整交易流程。

**Acceptance Criteria:**
- [ ] `zig build devnet-e2e` 可执行端到端流程
- [ ] 覆盖 construct → sign → simulate → send → confirm 流程
- [ ] 通过环境变量 SOLANA_RPC_URL 门控，不设置时跳过
- [ ] 测试结果可留档（log 输出包含交易签名等关键信息）

### US-018: Benchmark 基线建立
As a 维护者, I want 序列化/反序列化 benchmark 基线 so that 后续优化有数据对比基础。

**Acceptance Criteria:**
- [ ] `zig build bench` 可运行 benchmark
- [ ] 覆盖 Pubkey base58 编解码、Message 序列化、Transaction 序列化/反序列化
- [ ] 输出包含 ops/sec 或 ns/op 等量化指标
- [ ] 结果可记录对比（不要求优于 Rust，仅需建立基线）

## Functional Requirements
- FR-01: 支持固定长度类型（Pubkey 32B、Signature 64B、Hash 32B）与 base58/shortvec 编解码
- FR-02: 支持 legacy/v0 message 从 Instructions 编译、序列化与反序列化
- FR-03: 支持 VersionedTransaction 签名、验签、序列化、反序列化
- FR-04: 支持 5 个高频 RPC 方法（getLatestBlockhash、getAccountInfo、getBalance、simulateTransaction、sendTransaction）并保留 RPC error 结构
- FR-05: 支持 transport 抽象注入，便于 mock 与测试
- FR-06: 支持 Devnet 最小交易流程端到端验收

## Non-Goals (Out of Scope)
- 链上程序运行时语义（no_std/SBF）— Phase 4
- 低频 RPC 方法全量覆盖 — Phase 2
- WebSocket 订阅 — Phase 2
- Token Program / Associated Token Account 上层抽象 — Phase 3
- C ABI 导出 — Phase 3
- 与 Rust API 命名 1:1 一致（行为兼容优先）
- 异步 I/O（当前使用 std.http.Client 阻塞模式）
- 自定义序列化框架（当前手写 bincode 兼容层）

## Technical Considerations
- **基线锁定**: solana-sdk 4.0.1 / solana-client 3.1.12，所有行为与字节布局对齐此版本
- **模块依赖方向**: core → tx → rpc，禁止反向依赖
- **Zig 版本**: 0.16.0
- **序列化**: 手写 bincode 兼容层（src/solana/compat/）
- **HTTP**: std.http.Client 阻塞 I/O
- **签名**: Ed25519（Zig std 或对齐实现）
- **已知差异**: 无宏系统用 comptime 替代、无 trait 用函数指针/vtable 替代、无 tokio 用阻塞 I/O

## Success Metrics
- `zig build test` 全量通过，零内存泄漏
- Oracle 向量最低覆盖集 5 类场景全部通过
- 每个公共接口至少 1 Happy + 1 Error 测试
- `zig build devnet-e2e` 可留档完整交易流程
- `zig build bench` 建立序列化基线数据

## Open Questions
- solana-client 4.0.0 稳定后是否需要升级基线？
- 是否需要在 Phase 1 引入 CI 自动化（GitHub Actions）？
- Devnet E2E 测试的 funded account 管理策略？