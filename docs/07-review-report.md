# Phase 7 - Review Report

> 注：本文标题中的“Phase 7”是文档生命周期序号（审查报告），不是产品路线图阶段编号。

## 1. 审查范围

- 文档：`docs/00-06` 与最新 PRD / roadmap 一致性
- 代码：`core/tx/rpc/compat` 当前实现
- 测试：当前覆盖与 `docs/05-test-spec.md` 目标差距

## 2. 关键发现（按严重度）

### High

- H-01: Product Phase 2 / 3 范围（扩展 RPC、Websocket、interfaces、signers、C ABI）尚未形成完整可宣称能力面
- 影响：当前仅能宣称 Product Phase 1 / M1-M3 能力，不可对外宣称“全量实现”；即使已有部分 Phase 2 bootstrap / prototype，也不等于 Phase 2 已整体可用
- 状态：已在 `docs/04` / `docs/10` / `docs/19` 中区分“内部 prototype / partial”与“公开可承诺能力面”的边界；websocket 原型已撤出公开包面，待满足 zig-native-first / target portability 要求后再重新提审

### Medium

- M-01: RPC 解析仍以动态 JSON 为主，typed schema 收敛不足
- 影响：边界缺陷发现成本高，且易混淆 Phase 1 与 Phase 2 的边界
- 状态：当前 5 个高频方法的最小 typed schema 收敛仍是 Product Phase 1 收尾重点；更广泛 typed parse 扩展属于 Product Phase 2

- M-02: Devnet E2E 与未来 Websocket 测试依赖外部环境稳定性
- 影响：CI 波动风险
- 状态：已采用环境变量 / opt-in 门控策略

### Low

- L-01: oracle 最低集合已满足，但样本规模仍可继续扩充
- 影响：当前不再构成 Phase 1 gate blocker，但兼容回归信号仍可继续增强
- 状态：作为非阻塞扩样本与维护项持续推进

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
- Product Phase 2 / 3 方向清晰；其中已有部分 Phase 2 bootstrap（如扩展 RPC 第一批），websocket 线当前仅保留仓内 prototype / backlog 状态，且已撤出公开包面；在满足 zig-native-first / target portability 约束前，不能被写成“Phase 2 已完成”或“全量能力已落地”。

## 6. 下一步审查门槛

- M3 完成后进行一次“Phase 1 Closeout Review”，确认是否可以结束 Product Phase 1。
- 进入 Product Phase 2 前进行一次“扩展 RPC / Websocket 设计审查”。
- 进入 Product Phase 3 前进行一次“interfaces / signers / C ABI 设计审查”。

## 7. Closeout Checkpoint (2026-04-16)

本节用于对齐 `#7/#8/#9/#10` 收口结果，并作为 `docs/11` gate review 的输入摘要。

### 7.1 Gate 快照

| Gate | 状态 | 证据 |
|---|---|---|
| G-CLOSE-01 Test Gate | pass | `zig build test` 全量通过（含 `#7/#8/#9`） |
| G-CLOSE-02 Oracle Gate | pass | `#9` (`6fa3029`): `core + keypair + message + transaction` 向量 + Zig 消费断言 |
| G-CLOSE-03 RPC Gate | pass | `#7` (`892cfd8`): `getAccountInfo`/`simulateTransaction` typed 收敛 + happy/rpc_error/malformed 覆盖 |
| G-CLOSE-04 v0/Tx Gate | pass | `#8` (`d905ca2` + `f546b03`): v0/ALT 与 versioned tx 失败路径补齐，泄漏修复 |
| G-CLOSE-05 Devnet Gate | pass | `#10/#17`: 已有 `construct -> sign -> simulate` 与 `sendTransaction/confirm` 的 live 证据（见 `docs/14a` Run 2~5） |
| G-CLOSE-06 Documentation Gate | in-progress | 当前主要残项已收敛为：`docs/15` 中若干条目尚未完成最终 `closed / documented exception` 处置；其余 closeout 主线文档现以此为中心继续同步 |

### 7.2 当前结论

- Product Phase 1 的关键实现证据已明显收敛，Devnet live 路径也已补到 simulate/send/confirm。
- 结论：**当前仍不应宣称 Product Phase 1 已完成 closeout**；原因不再是 send 证据缺失，而是 `docs/15` 中仍有若干条目未完成最终 `closed / documented exception` 处置。
