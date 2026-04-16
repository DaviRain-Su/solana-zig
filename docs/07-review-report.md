# Phase 7 - Review Report

> 注：本文标题中的“Phase 7”是文档生命周期序号（审查报告），不是产品路线图阶段编号。

## 1. 审查范围

- 文档：`docs/00-06` 与最新 PRD / roadmap 一致性
- 代码：`core/tx/rpc/compat/interfaces/signers/cabi` 当前实现
- 测试：当前覆盖（208 tests）与 `docs/05-test-spec.md` 目标差距

## 2. 关键发现（按严重度）

### High

- ~~H-01: Product Phase 2 / 3 范围（扩展 RPC、Websocket、interfaces、signers、C ABI）尚未形成完整可宣称能力面~~
- **已解决**：Phase 1/2/3 全部完成。16 个 RPC 方法、7 种 WebSocket 订阅、7 个 interface 模块、Signer 抽象、C ABI 导出均已落地。

### Medium

- ~~M-01: RPC 解析仍以动态 JSON 为主，typed schema 收敛不足~~
- **已解决**：16 个 RPC 方法全部 typed parse，保留 `raw_json` 旁路。
- ~~M-02: Devnet E2E 与未来 Websocket 测试依赖外部环境稳定性~~
- **已解决**：已采用环境变量 / opt-in 门控策略，mock 模式始终可用。

### Low

- L-01: oracle 最低集合已满足，但样本规模仍可继续扩充
- 影响：当前不再构成 gate blocker，但兼容回归信号仍可继续增强
- 状态：作为非阻塞扩样本与维护项持续推进

- L-02: 目标用户仍偏宽（嵌入式 / FFI / 高性能场景）
- 影响：Phase 3 已落地 C ABI / Signer，用户范围已自然收敛
- 状态：已在 `docs/16` 中收敛说明

## 3. 已解决项

- `RpcClient` 支持 transport 抽象注入，mock 测试路径已建立（happy path / rpc_error / transport error 三个注入式测试）
- v0 lookup 冲突语义与规格已统一
- `RpcResult/RpcErrorObject` 重复定义问题已清理
- README / roadmap / PRD / task / test / evolution 的命名体系已统一为 `Product Phase + Milestone + 文档序号` 三层表达

## 4. 残余风险评级

| 风险 | 等级 | 当前控制 |
|---|---|---|
| Rust 版本演进漂移 | 中 | 基线锁定 + 兼容矩阵 + oracle 回归 |
| RPC 动态解析误判 | 低 | 16 方法 typed parse + mock 覆盖 |
| Devnet / Websocket 外部不稳定 | 低 | opt-in 集成门控 + mock 始终可用 |
| oracle 覆盖不足 | 低 | 向量扩展计划（core + keypair + message + transaction） |
| future scope 膨胀 | 低 | Product Phase 分阶段治理（Phase 4 独立评估） |

## 5. 结论

- 当前阶段可判定为：**Product Phase 1/2/3 全部完成**。
- 当前对外表述应限定为：16 个 RPC 方法、7 种 WebSocket 订阅、7 个 interface 模块、Signer 抽象、C ABI 导出。
- Phase 4（链上程序支持）作为独立子项目评估，不与当前 client SDK 生命周期耦合。

## 6. 下一步审查门槛

- Phase 1/2/3 closeout 已完成，进入维护模式。
- Phase 4 进入前进行一次"链上程序支持设计审查"。
- 每次 Rust SDK 版本升级时执行 oracle 向量回归。

## 7. Closeout Checkpoint (2026-04-16) — Historical

> 本节为历史快照，记录 Phase 1 closeout 评审过程。Phase 1/2/3 现已全部完成。

### 7.1 Gate 快照

| Gate | 状态 | 证据 |
|---|---|---|
| G-CLOSE-01 Test Gate | pass | `zig build test` 全量通过（含 `#7/#8/#9`） |
| G-CLOSE-02 Oracle Gate | pass | `#9` (`6fa3029`): `core + keypair + message + transaction` 向量 + Zig 消费断言 |
| G-CLOSE-03 RPC Gate | pass | `#7` (`892cfd8`): `getAccountInfo`/`simulateTransaction` typed 收敛 + happy/rpc_error/malformed 覆盖 |
| G-CLOSE-04 v0/Tx Gate | pass | `#8` (`d905ca2` + `f546b03`): v0/ALT 与 versioned tx 失败路径补齐，泄漏修复 |
| G-CLOSE-05 Devnet Gate | pass | `#10/#17`: 已有 `construct -> sign -> simulate` 与 `sendTransaction/confirm` 的 live 证据（见 `docs/14a` Run 2~5） |
| G-CLOSE-06 Documentation Gate | pass | `docs/15` 已收口，Phase 1/2/3 文档同步完成 |

### 7.2 结论

- Phase 1/2/3 全部完成，208 tests pass，zero memory leaks。
- 所有 closeout gates 均已通过。
