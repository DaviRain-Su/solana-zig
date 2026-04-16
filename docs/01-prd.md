# Phase 1 PRD — 链下客户端核心

> 本文档是 [solana-zig 顶层路线图](./00-roadmap.md) 的 Phase 1 子 PRD。

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

### 1.3 当前阶段目标（Phase 1）
先完成链下 host/client 可用闭环，优先保证行为兼容与字节兼容，为后续"全量实现"奠定稳定基础。

---

## 2. 用户与场景

### 2.1 目标用户
- Zig 客户端开发者（钱包、交易机器人、后端服务）。
- 从 Rust SDK 迁移到 Zig 的团队。
- 需要在 Zig 中复用 Solana 协议能力的基础设施团队。
- **嵌入式/系统级场景**：IoT 设备、硬件钱包等资源受限环境（Zig zero-overhead + 无 GC）。
- **C FFI 消费者**：其他语言通过 C ABI 调用 Solana 功能（Phase 3 导出）。
- **性能敏感场景**：MEV 搜索者、做市商等延迟敏感系统。

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
  - Devnet E2E（环境变量门控）

### 3.2 下一阶段扩展范围（Phase 2+）
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

---

## 4. 产品需求（Functional Requirements）

- FR-01：支持固定长度类型与地址/签名编解码。
- FR-02：支持 legacy/v0 message 编译与反序列化。
- FR-03：支持交易签名、验签、序列化、反序列化。
- FR-04：支持 5 个高频 RPC 方法并保留 RPC error 结构。
- FR-05：支持 transport 抽象注入，便于 mock 与测试。
- FR-06：支持 Devnet 端到端最小交易流程演示。

---

## 5. 非功能需求（Non-Functional Requirements）

- NFR-01（兼容性）：字节布局与 Rust SDK 基线行为一致（当前锁定 `solana-sdk 4.0.1`）。
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
- 配置 `SOLANA_RPC_URL` 时 Devnet E2E 能完成"构造->签名->模拟->发送"。
- `std.testing.allocator` 全量测试无内存泄漏。
- *(基线)* 序列化/反序列化吞吐量 benchmark 建立（不要求优于 Rust，但需记录数据供后续对比）。

### 6.2 全量实现指标（长期）
- 官方 Rust 客户端页面所列"客户端 + 组件 + 接口"能力达到可追踪覆盖矩阵。
- 每个覆盖项有对应 Zig 模块与测试映射。
- 版本升级时可通过兼容矩阵识别并回归差异。

---

## 7. 里程碑规划

- M1（当前）：核心链下闭环可用（core + tx + 高频 rpc）。
- M2：扩展 RPC 覆盖 + transport/mock 完整测试矩阵。
- M3：接口 crates 对应能力（system/token/token-2022 等）。
- M4：签名后端扩展与生产化治理（可插拔 key management）。
- M5：评估并推进链上语义子项目（独立生命周期，不与链下核心混做）。

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
