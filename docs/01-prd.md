# Phase 1 PRD — 链下客户端核心

> 本文档是 [solana-zig 顶层路线图](./00-roadmap.md) 的 Product Phase 1 子 PRD。
>
> **命名说明**：本文标题中的“Phase 1”表示文档生命周期中的 PRD 阶段，同时本文内容对应产品路线图中的 `Product Phase 1`；后续出现的 `M1~M3` 仅表示当前 Product Phase 1 的执行里程碑。

## 1. 背景与目标

### 1.1 背景
Solana 官方 Rust 客户端生态已形成分层 crate 体系（客户端、组件、接口、签名后端等）。  
当前 Zig 生态缺少同等级别、可用于生产的 SDK 组合，导致：
- Zig 团队在 Solana 侧需要跨语言桥接，增加复杂度与维护成本。
- 协议升级、错误语义与字节布局对齐成本高。
- 无法在 Zig 体系内完成端到端"构造交易 -> 签名 -> 发送 -> 结果解析"闭环。

> **参考 crate 说明**：Solana SDK 自 v2.x 起进行了 crate 拆分重组。本项目锚定的 `4.0.1` 指拆分后的版本体系。实际参考的核心 crate 包括：
> - `solana-pubkey` / `solana-signature` / `solana-keypair` — 核心类型
> - `solana-transaction` / `solana-message` — 交易构建
> - `solana-rpc-client` — RPC 客户端
>
> 后续版本升级时需同步更新 oracle 向量生成脚本中的依赖版本。

### 1.2 总目标（最终态）
在 Zig 中构建一个对齐官方 Rust SDK 语义的 Solana SDK 体系，覆盖：
- 客户端能力（RPC + 交易构建与签名）
- 组件能力（消息、签名、序列化等基础类型）
- 接口能力（System/Token/ComputeBudget 等接口 crate 对应能力）
- 签名与密钥管理扩展（可插拔后端）

**停止条件**：当某能力可以通过现有底层模块（core/tx/rpc）在 userland 组合实现时，不强制纳入本仓库内建范围。例如 `spl-token-interface` 等应用层接口 crate，优先作为独立包扩展，而非全部内聚。

### 1.3 当前阶段目标（Phase 1）
先完成链下 host/client 可用闭环，优先保证行为兼容与字节兼容，为后续"全量实现"奠定稳定基础。

### 1.4 基线定义（Locked Baseline）

所有行为与字节布局对齐以下锁定的 Rust crate 版本。若官方后续升级导致语义变化，需在 `08-evolution.md` 中记录 ADR，并通过 oracle 回归验证。

| Zig 模块 | 对标 Rust Crate | 锁定版本 | 说明 |
|---|---|---|---|
| core (pubkey/signature/keypair/hash) | `solana-sdk` (umbrella) | **4.0.1** | 字节布局基准源 |
| core (shortvec) | `solana-short-vec` | **3.2.0** | `solana-sdk 4.0.1` 的依赖版本 |
| tx (message/transaction) | `solana-message` / `solana-transaction` | **4.0.0** | `solana-sdk 4.0.1` 的依赖版本 |
| tx (signer) | `solana-signer` / `solana-keypair` | **3.0.0** | `solana-sdk 4.0.1` 的依赖版本 |
| rpc | `solana-client` | **3.1.12** | 当前 `solana-client 4.0.0` 仍处于 beta，故锁定最新稳定版 |

**注意**：`solana-sdk 4.0.1` 内部聚合了大量 component crates。上表已拆出与 Phase 1 直接相关的子 crate 版本。链上语义（`solana-program` 中的 SBF/no_std 部分）当前 Out of Scope。

---

## 2. 用户与场景

### 2.1 目标用户
- Zig 客户端开发者（钱包、交易机器人、后端服务）。
- 从 Rust SDK 迁移到 Zig 的团队。
- 需要在 Zig 中复用 Solana 协议能力的基础设施团队。
- **嵌入式/系统级场景（长期目标）**：IoT 设备、硬件钱包等资源受限环境（Zig zero-overhead + 无 GC）。
- **C FFI 消费者（后续目标）**：其他语言通过 C ABI 调用 Solana 功能（Phase 3 导出）。
- **性能敏感场景（长期目标）**：MEV 搜索者、做市商等延迟敏感系统。

### 2.1.1 Product Phase 1 当前主用户
- 当前 Phase 1 的主用户以 **Zig host/client 开发者** 为主。
- 当前主闭环是：链下构造交易、签名交易、调用高频 RPC、验证字节与错误语义兼容性。
- C ABI、多语言消费、嵌入式/硬件钱包、极低延迟场景属于后续阶段扩展目标，不作为 Phase 1 的主优化对象。

### 2.2 核心场景
- 构造并签名交易（legacy/v0）。
- 通过 RPC 读取链状态并发送交易。
- 对齐 Rust SDK 字节布局与错误语义，减少跨语言偏差。

---

## 3. 范围定义

### 3.1 当前阶段 In Scope（必须交付）
- core：
  - `Pubkey/Signature/Keypair/Hash`
  - `base58/shortvec` 编解码
- tx：
  - `Instruction/AccountMeta`
  - `Message`（legacy + v0）
  - `VersionedTransaction`（sign/verify/serialize/deserialize）
- rpc：
  - `getLatestBlockhash`
  - `getAccountInfo`
  - `getBalance`
  - `simulateTransaction`
  - `sendTransaction`
- 测试与兼容：
  - oracle 向量对照
  - Devnet acceptance path（环境变量门控；当前已有仓库内 `zig build devnet-e2e` live harness 覆盖到 `construct -> sign -> simulate`，并保留 wrapper 留档路径；`send` 仍单独跟踪）

### 3.2 后续 Product Phase 扩展范围
对照官方页面 crate 家族逐步扩展：
- 客户端 crates：`solana-client` 相关更多 RPC 能力。
- 组件 crates：`solana-message/solana-transaction/solana-signature/solana-short-vec/...` 对应能力补齐。
- 接口 crates：`solana-system-interface`、`spl-token-interface`、`spl-token-2022-interface` 等。
- 签名后端：参考 `solana-keychain` 的可插拔后端思路。

### 3.3 当前阶段 Out of Scope（暂不承诺）
- 链上程序运行时语义（no_std/SBF）完整实现 → 见路线图 Phase 4。
- 一次性覆盖全部低频 RPC → 见路线图 Phase 2。
- Token Program / Associated Token Account 等上层抽象 → 见路线图 Phase 3。
- Websocket 订阅 → 见路线图 Phase 2。
- C ABI 导出 → 见路线图 Phase 3。
- 与 Rust API 命名 1:1 完全一致（当前以行为兼容优先）。

### 3.4 已知差异与约束

由于 Zig 与 Rust 语言特性不同，以下差异是结构性而非实现缺陷，需在设计和评审中默认接受：

| 差异项 | Rust 端表现 | Zig 端策略 |
|---|---|---|
| **宏系统** | `declare_id!`、`account!` 等过程宏大量存在 | Zig 无宏系统，改用编译期函数（`comptime`）或显式代码生成替代 |
| **异步模型** | `solana-client` 基于 `tokio` 异步运行时 | 当前使用 `std.http.Client` 阻塞 I/O；如需异步，后续在 Zig 事件循环层封装，不侵入 SDK 核心 |
| **泛型/特征** | `Signer` trait、`Pubkey` 上的泛型方法 | 用函数指针、接口结构（类似 vtable）或显式类型参数替代 |
| **序列化 crate** | `bincode` 作为外部依赖处理字节布局 | 当前为手写 serializer（`compat/bincode_compat.zig`）；未来如需更复杂 schema，再评估是否引入 Zig 等价实现 |
| **错误处理** | `thiserror` 派生 + `Result<T, E>` | 直接使用 Zig error union，不模拟 Rust 的 `Error` trait 层次 |

---

## 4. 产品需求（Functional Requirements）

- FR-01：支持固定长度类型与地址/签名编解码。
- FR-02：支持 legacy/v0 message 编译与反序列化。
- FR-03：支持交易签名、验签、序列化、反序列化。
- FR-04：支持 5 个高频 RPC 方法并保留 RPC error 结构。
- FR-05：支持 transport 抽象注入，便于 mock 与测试。
- FR-06：支持以仓库内 live harness + acceptance wrapper 形式演示 Devnet 最小交易流程；当前 live harness 覆盖到 `construct -> sign -> simulate`，并为后续 `sendTransaction` 收口预留接口。

---

## 5. 非功能需求（Non-Functional Requirements）

- NFR-01（兼容性）：字节布局与 Rust SDK 基线行为一致（锁定 `solana-sdk 4.0.1` + `solana-client 3.1.12`，见第 1.4 节基线定义）。
- NFR-02（可测试性）：每个公共接口至少 Happy + Error 两类测试。
- NFR-03（可维护性）：模块边界清晰（`core -> tx -> rpc`），禁止反向依赖。
- NFR-04（可扩展性）：RPC transport、签名后端可插拔。
- NFR-05（可观测性）：错误不 silent fallback，保留原始上下文。

---

## 6. 成功指标（Success Metrics）

### 6.1 Phase 1 指标
- 离线兼容测试全部通过（核心类型/消息/交易）。
- oracle 向量对照全部通过，**最低覆盖**：
  - 非零 pubkey（含前导零场景）
  - Keypair sign -> Signature（确定性种子）
  - Legacy message serialize（多 instruction）
  - V0 message serialize（含 ALT）
  - 完整 Transaction serialize（签名 + message）
- `zig build test` 持续通过。
- Phase 1 每个公共接口至少覆盖 1 个 Happy Path + 1 个 Error Path 测试。
- 配置 `SOLANA_RPC_URL` 时，可通过仓库内 `zig build devnet-e2e` 留档当前 Devnet live harness 路径，并可辅以 acceptance wrapper 留档元数据；完整“构造->签名->模拟->发送”闭环仍属于 Phase 1 收口目标，其中 `sendTransaction` 证据尚未补齐。
- `std.testing.allocator` 全量测试无内存泄漏。
- *(基线)* 序列化/反序列化吞吐量 benchmark 建立（不要求优于 Rust，但需记录数据供后续对比）。

### 6.2 全量实现指标（长期）
- 官方 Rust 客户端页面所列"客户端 + 组件 + 接口"能力达到可追踪覆盖矩阵。
- 每个覆盖项有对应 Zig 模块与测试映射。
- 版本升级时可通过兼容矩阵识别并回归差异。

---

## 7. 路线与里程碑规划

### 7.1 Product Phase 对齐

- Phase 1（当前，本文范围）：链下客户端核心（`core + tx + 高频 rpc`）及其测试/兼容收尾。
- Phase 2（见 `docs/00-roadmap.md`）：扩展 RPC、Websocket 订阅、Nonce 工作流、Compute Budget / Priority Fees。
- Phase 3（见 `docs/00-roadmap.md`）：interfaces、signers 与 C ABI。
- Phase 4（见 `docs/00-roadmap.md`）：链上程序支持评估，并作为独立子项目推进。

### 7.2 当前 Product Phase 1 执行 Milestones

- M1：核心离线兼容（core + tx 基础能力稳定）。
- M2：RPC/mock 可用（高频方法、transport 抽象、错误路径覆盖）。
- M3：Phase 1 收口（Devnet acceptance path / E2E、文档收口、oracle 扩充、benchmark 基线）。

---

## 8. 风险与缓解

- 风险 R1：Rust 版本演进导致行为变化。  
  缓解：锁基线版本 + 维护兼容矩阵 + oracle 回归。

- 风险 R2：动态 JSON 解析导致边界遗漏。  
  缓解：逐步收紧 typed schema + mock 响应全路径测试。

- 风险 R3：v0/lookup 语义偏差。  
  缓解：以 Rust 行为为 oracle，补齐正反向测试。

- 风险 R4：Devnet 不稳定引发 CI 波动。  
  缓解：集成测试门控（opt-in），离线测试做强约束。

- 风险 R5：Oracle 向量覆盖不足导致隐蔽兼容性问题。  
  缓解：Phase 1 完成前补齐上述最低向量集。

---

## 9. 约束与默认决策

- 兼容策略：行为兼容优先于 API 命名兼容。
- 工程组织：单仓多模块。
- 运行域：先链下 host/client，链上语义后置为独立子项目。
- 依赖策略：优先 Zig std，必要时引入最小外部依赖。

---

## 10. PRD 变更规则（为后续"全量实现"预留）

- 本文档允许持续增量修改，但必须遵守：
  - 任何"范围新增"必须同步更新 `03/04/05`。
  - 任何"兼容策略变化"必须在 `08-evolution.md` 记 ADR。
  - 任何"接口变化"必须附测试用例映射编号。
- 每次修订需在 PR 描述中标明：
  - 新增/删减范围
  - 对现有实现影响
  - 回滚策略

---

## 11. 参考

- Solana 官方 Rust 客户端文档（中文）：
  - https://solana.com/zh/docs/clients/official/rust
- 基线源码仓库：
  - `anza-xyz/solana-sdk` (v4.0.1): https://github.com/anza-xyz/solana-sdk/tree/v4.0.1
  - `anza-xyz/agave` (solana-client v3.1.12): https://github.com/anza-xyz/agave/tree/v3.1.12/client
- 基线 API 文档：
  - `solana-sdk` 4.0.1: https://docs.rs/solana-sdk/4.0.1
  - `solana-client` 3.1.12: https://docs.rs/solana-client/3.1.12
- Zig 版本约束依据：
  - Zig 0.16.0 Release Notes: https://ziglang.org/download/0.16.0/release-notes.html

### 11.1 官方 Reference Repositories（按当前官方页面）

- 客户端与核心组件：
  - https://github.com/anza-xyz/solana-sdk/tree/master/sdk
  - https://github.com/anza-xyz/agave/tree/master/client
  - https://github.com/anza-xyz/solana-sdk/tree/master/commitment-config
- 程序与程序交互（Pinocchio）：
  - https://github.com/anza-xyz/pinocchio
  - https://github.com/anza-xyz/pinocchio/tree/main/programs/system
  - https://github.com/anza-xyz/pinocchio/tree/main/programs/token
  - https://github.com/anza-xyz/pinocchio/tree/main/programs/token-2022
  - https://github.com/anza-xyz/pinocchio/tree/main/programs/associated-token-account
  - https://github.com/anza-xyz/pinocchio/tree/main/programs/memo
- 接口 crates：
  - https://github.com/anza-xyz/solana-sdk/tree/master/system-interface
  - https://github.com/anza-xyz/solana-sdk/tree/master/compute-budget-interface
  - https://github.com/solana-program/token/tree/main/interface
  - https://github.com/solana-program/token-2022/tree/main/interface
  - https://github.com/solana-program/associated-token-account/tree/main/interface
  - https://github.com/solana-program/memo/tree/main/interface
  - https://github.com/solana-program/token-metadata/tree/main/interface
  - https://github.com/solana-program/token-group/tree/main/interface
- 签名与密钥管理：
  - https://github.com/solana-foundation/solana-keychain
