# Phase 2 - Architecture

> 注：本文标题中的“Phase 2”是文档生命周期序号（架构文档），不是产品路线图中的 Product Phase 2。

## 1. 架构目标

- 在不破坏当前 Product Phase 1 可用性的前提下，支持后续产品阶段持续扩展。
- 保持模块解耦：`core` 为基础层，`tx` 仅依赖 `core`，`rpc/interfaces` 依赖 `core/tx`，`signers` 依赖 `core` 并通过适配层接入上层流程。
- 以行为兼容与可测试性为中心，确保每层都有独立验证路径。

## 2. 分层与职责

### 2.1 core

职责：
- 固定长度类型（`Pubkey/Signature/Hash`）
- 编解码（`base58/shortvec`）
- 密码学签名基础（`Keypair`）

约束：
- 不依赖 `tx/rpc/interfaces/signers`

### 2.2 tx

职责：
- `Instruction/AccountMeta`
- `Message`（legacy/v0）编译与字节编解码
- `VersionedTransaction` 签名、验签、编解码

约束：
- 仅依赖 `core`

### 2.3 rpc

职责：
- JSON-RPC 客户端协议封装
- transport 抽象与默认 HTTP 实现
- RPC error 保真（`code/message/data_json`）

约束：
- 依赖 `core/tx`
- 不依赖 `interfaces/signers`

### 2.4 interfaces（主要位于 Product Phase 3；compute-budget 等最小交易辅助可在 Product Phase 2 提前落地）

职责：
- 对应 Rust 生态 interface crates 的 Zig 封装（system/token/token-2022/compute-budget/memo 等）
- 聚焦指令构造、数据布局、常量与错误语义，不承担网络访问职责

约束：
- 依赖 `core/tx`
- 若未来需要更高层的联网 helper，应拆到独立 `program_clients/*` 或等价模块，而不是让 `interfaces` 直接承担 RPC 客户端职责
- 不反向影响 `core/tx`

### 2.5 signers（Product Phase 3）

职责：
- 可插拔签名后端抽象（内存、KMS、HSM 等）

约束：
- 依赖 `core`（签名数据结构）
- 通过抽象接口与 `tx/rpc` 对接

### 2.6 compat

职责：
- oracle 向量加载与对照
- bincode/序列化兼容辅助

约束：
- 测试优先，不作为业务核心依赖

## 3. 包结构

当前：
- `src/solana/core/*`
- `src/solana/tx/*`
- `src/solana/rpc/*`
- `src/solana/compat/*`

规划扩展：
- `src/solana/interfaces/*`
- `src/solana/signers/*`

统一导出入口：
- `src/solana/mod.zig`
- `src/root.zig`

## 4. 关键设计决策

### 4.1 Transport 抽象

- `RpcClient` 通过 transport 接口发送请求，默认实现为 `HttpTransport`。
- 测试中可注入 fake transport，避免网络依赖。

### 4.2 错误模型

- 通用错误集放在 `errors.zig`。
- RPC 业务错误通过 `rpc/types.zig` 的 `RpcErrorObject/RpcResult(T)` 承载。
- 禁止吞错，禁止 silent fallback。

### 4.3 兼容策略

- 行为兼容优先于 API 命名兼容。
- 字节布局、签名语义、错误语义必须可对照 Rust 基线。

### 4.4 版本与演进

- 当前基线：`solana-sdk 4.0.1`
- 版本升级走“兼容矩阵 + 增量回归测试”流程。

## 5. 依赖方向（强制）

- 允许：
  - `tx -> core`
  - `rpc -> core/tx`
  - `interfaces -> core/tx`
  - `signers -> core`
  - 未来若引入 `program_clients`，则允许其依赖 `rpc/interfaces/signers`
- 禁止：
  - `core` 依赖任何上层模块
  - `tx -> rpc`
  - `interfaces -> rpc`（除非明确拆出独立高层 client 模块）
  - `rpc` 反向依赖 `interfaces/signers`
- `compat` 可读取各层数据但不反向成为核心依赖

## 6. 测试架构

- L1：core 单元测试
- L2：tx 组件测试
- L3：rpc + mock transport
- L4：Devnet 集成测试（环境变量门控）
- L5：compat/oracle 对照

## 7. 非功能架构约束

- 可维护性：每个模块独立可测
- 可扩展性：新增接口能力不改动 core 契约
- 可观测性：错误上下文可追踪
- 可靠性：无网络环境下仍可完整执行离线测试集

## 8. 风险与控制

- 动态 JSON 解析边界遗漏：逐步引入 typed parse 子层。
- v0 与后续版本语义漂移：以 oracle 和 Rust 对照保障。
- 扩展模块过快导致耦合：强制依赖方向 + 审查规则。

## 9. 验收标准

- 架构文档覆盖当前模块与未来扩展模块职责。
- 依赖方向规则明确且可审查。
- 关键扩展点（transport/signers/interfaces）在设计上已预留。
- 与 `docs/00-roadmap.md` 的 Product Phase 1~4 路线以及 `docs/01-prd.md` 的 Phase 1 Milestones（M1~M3）一致。
