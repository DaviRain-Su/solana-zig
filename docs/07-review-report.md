# Phase 7 - Review Report

> 注：本文标题中的“Phase 7”是文档生命周期序号（审查报告），不是产品路线图阶段编号。

## 1. 审查范围

- 文档：`docs/00-06` 与最新 PRD / roadmap 一致性
- 代码：`core/tx/rpc/compat` 当前实现
- 测试：当前覆盖与 `docs/05-test-spec.md` 目标差距

## 2. 关键发现（按严重度）

### High

- H-01: Product Phase 2 / 3 范围（扩展 RPC、Websocket、interfaces、signers、C ABI）尚未进入实现阶段
- 影响：当前仅能宣称 Product Phase 1 / M1-M3 能力，不可对外宣称“全量实现”
- 状态：已在 `docs/04` 以 Phase 2 / Phase 3 backlog 形式重新对齐

### Medium

- M-01: RPC 解析仍以动态 JSON 为主，typed schema 收敛不足
- 影响：边界缺陷发现成本高，且易混淆 Phase 1 与 Phase 2 的边界
- 状态：当前 5 个高频方法的最小 typed schema 收敛仍是 Product Phase 1 收尾重点；更广泛 typed parse 扩展属于 Product Phase 2

- M-02: Devnet E2E 与未来 Websocket 测试依赖外部环境稳定性
- 影响：CI 波动风险
- 状态：已采用环境变量 / opt-in 门控策略

### Low

- L-01: oracle 向量集规模偏小
- 影响：兼容回归信号有限
- 状态：纳入 Product Phase 1 收口项

- L-02: 目标用户仍偏宽（嵌入式 / FFI / 高性能场景）
- 影响：未来 Phase 3 设计若不进一步收敛，容易提前承诺过多非当前能力
- 状态：建议在进入 Product Phase 3 前补一版用户与 ABI 边界收敛说明

## 3. 已解决项

- `RpcClient` 支持 transport 抽象注入，mock 测试路径已建立（happy path / rpc_error / transport error 三个注入式测试）
- v0 lookup 冲突语义与规格已统一
- `RpcResult/RpcErrorObject` 重复定义问题已清理
- README / roadmap / PRD / task / test / evolution 的命名体系已统一为 `Product Phase + Milestone + 文档序号` 三层表达

## 4. 残余风险评级

| 风险 | 等级 | 当前控制 |
|---|---|---|
| Rust 版本演进漂移 | 高 | 基线锁定 + 兼容矩阵 |
| RPC 动态解析误判 | 中 | mock 覆盖 + 后续 typed parse |
| Devnet / Websocket 外部不稳定 | 中 | opt-in 集成门控 |
| oracle 覆盖不足 | 低 | 向量扩展计划 |
| future scope 膨胀 | 低 | Product Phase 分阶段治理 |

## 5. 结论

- 当前阶段可判定为：`Product Phase 1 路线可执行并在推进中`。
- 当前对外表述应限定为：`Product Phase 1 / M1-M3`，即链下客户端核心与其收尾工作。
- Product Phase 2 / 3 方向清晰，但仍属于 backlog / 设计承诺，不能视为已落地能力。

## 6. 下一步审查门槛

- M3 完成后进行一次“Phase 1 Closeout Review”，确认是否可以结束 Product Phase 1。
- 进入 Product Phase 2 前进行一次“扩展 RPC / Websocket 设计审查”。
- 进入 Product Phase 3 前进行一次“interfaces / signers / C ABI 设计审查”。
