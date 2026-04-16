# Phase 8 - Evolution

> 全面重写路线图见 [00-roadmap.md](./00-roadmap.md)。本文档聚焦演进治理与能力扩展。
>
> 注：本文标题中的“Phase 8”是文档生命周期序号（演进治理文档），不是产品路线图阶段编号。

## 1. 演进目标

- 从“高频客户端可用”演进到“Rust 客户端生态能力可追踪覆盖”。
- 保持兼容矩阵可维护，支持版本升级与差异回归。
- 用统一命名约束产品阶段、执行里程碑和文档序号，避免路线图与任务体系漂移。

## 2. 命名与治理约定

- **Product Phase**：只用于顶层产品路线图，统一采用 `Phase 1 ~ Phase 4`。
- **Milestone（M）**：只用于当前 `Product Phase 1` 执行里程碑，统一采用 `M1 ~ M3`。
- **文档序号 `docs/01-08`**：表示文档生命周期顺序，不等于 Product Phase 编号。
- 对外状态汇报时，优先使用：`Product Phase X`；如处于 Phase 1 内部执行，再补充 `Mx`。

## 3. 版本与兼容治理

- 当前基线：`solana-sdk 4.0.1`（拆分后 crate 体系）
- 每次升级必须产出：
  - 差异清单（crate/行为/错误语义）
  - 回归测试结果
  - 迁移说明（破坏性变化）

## 4. 能力路线图（与 `docs/00-roadmap.md` 对齐）

### Product Phase 1（当前）
- core/tx/rpc 高频路径
- transport 可替换
- Phase 1 收口：oracle 扩充、typed parse 收紧、Devnet E2E、benchmark 基线
- 当前执行里程碑：`M1 -> M2 -> M3`

### Product Phase 2（下一阶段）
- 扩展 RPC 方法
- Websocket 订阅与生命周期管理
- Durable Nonce / Priority Fees / Compute Budget 工作流

### Product Phase 3（后续）
- interfaces 扩展：system/token/token-2022/memo/stake 等
- signers 可插拔后端
- C ABI 导出与多语言消费约定

### Product Phase 4（评估）
- 链上语义子项目（独立生命周期）
- SBF / no_std / entrypoint / 账户序列化可行性评估

## 5. 文档协同规则

- Product roadmap 范围变化：必须同步更新 `docs/01/04/05`。
- 当前 Milestone 调整：必须同步更新 `docs/04/06/07`。
- 风险变化：必须同步更新 `docs/07`（审查报告）。
- 兼容变化：必须同步更新 `docs/08`（本文件）。
- 若出现命名层级变化，必须先更新 `docs/00` 的命名约定，再回写其他文档。

## 6. ADR 与决策记录

- 需要 ADR 的变更类型：
  - 兼容策略变化
  - 公共接口破坏性变更
  - 底层序列化/签名语义变化
  - 模块依赖方向调整
  - Product Phase 边界变化

- ADR 最小字段：背景、决策、备选、影响、回滚。

## 7. 度量与退出条件

- Product Phase 1 退出条件：高频 RPC + tx 路线稳定，离线门禁持续通过，M3 收口项完成。
- Product Phase 2 退出条件：扩展 RPC / Websocket / Nonce 工作流形成可重复验证闭环。
- Product Phase 3 退出条件：主要 interfaces、至少两类 signer 后端、C ABI 核心路径可用。
- Product Phase 4 退出条件：形成独立 `solana-program-zig` 可行性结论与拆分方案。

## 8. 长期维护清单

- 定期更新 oracle 向量。
- 定期执行 Devnet / Websocket 回归。
- 对齐官方文档新增 crate/接口条目。
- 定期复核 backlog 与 roadmap 的 phase 映射是否仍一致。
