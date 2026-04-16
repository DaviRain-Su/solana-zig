# Phase 7 - Review Report

> 注：本文标题中的“Phase 7”是文档生命周期序号（审查报告），不是产品路线图阶段编号。

## 1. 审查范围

- 文档：`docs/00-06` 与最新 PRD / roadmap 一致性
- 代码：`core/tx/rpc/compat/interfaces/signers/cabi` 当前实现
- 测试：当前覆盖（208 tests）与 `docs/05-test-spec.md` 目标差距

## 2. 关键发现（按严重度）

### High

- H-01: 顶层状态文档一度把 Phase 3 写成“已全部完成”，但代码与细粒度追踪文档仍显示 closeout 未完成。
  - 影响：对外状态口径不可信，容易把“主体能力已落地”误写成“验收闭环完成”。
  - 当前处理：本轮 review 已回写 `README.md`、`docs/00-roadmap.md`、`docs/10-coverage-matrix.md`、`docs/36/37`。

- H-02: `MockExternalSigner` 存在 correctness gap。
  - 证据：`src/solana/signers/mock_external.zig` 的 `signMessage(...)` 当前忽略输入消息并签名空字符串。
  - 影响：mock external signer 不能作为可靠的 transaction-level signing 证据。

- H-03: Stake create helper 的 API/实现契约不一致。
  - 证据：`buildCreateStakeAccountInstruction(...)` 接口接收 `lamports`，但当前实现仅序列化 `StakeInstruction.initialize` 路径。
  - 影响：API 名称和行为不一致，且会误导调用方与文档示例。

### Medium

- M-01: C ABI 已有可用 surface，但 RPC 仍是 scaffold 级别。
  - 证据：`src/solana/cabi/rpc.zig` 通过 dummy transport 初始化 `RpcClientHandle`。
  - 影响：当前不能把 C ABI RPC 写成“可直接发真实链请求的已完成能力”。

- M-02: C ABI header / core / tests 仍未完全对齐。
  - 证据：`include/solana_zig.h` 与 `src/solana/cabi/core.zig` 的能力面、测试命名与 roundtrip 语义仍有偏差。
  - 影响：会削弱 C ABI 首版的可审计性与后续版本化基线。

### Low

- L-01: oracle / benchmark / E2E 仍值得持续扩样本
  - 影响：当前不构成 blocker，但作为回归与版本升级保护网仍应继续维护

- L-02: 运营类状态文档（如 `MEMORY.md`、`notes/project-state.md`）容易滞后
  - 影响：对协作代理和后续维护者造成误导

## 3. 已解决项

- `RpcClient` 支持 transport 抽象注入，mock 测试路径已建立（happy path / rpc_error / transport error 三个注入式测试）
- v0 lookup 冲突语义与规格已统一
- `RpcResult/RpcErrorObject` 重复定义问题已清理
- README / roadmap / PRD / task / test / evolution 的命名体系已统一为 `Product Phase + Milestone + 文档序号` 三层表达

## 4. 残余风险评级

| 风险 | 等级 | 当前控制 |
|---|---|---|
| `MockExternalSigner` 误导 transaction-level 签名语义 | 高 | 已在 `docs/10` / `docs/36` 标为 Batch 4 首要修复项 |
| Stake create helper API/实现漂移 | 高 | 已在 `docs/10` / `docs/36` 标为 Batch 4 首要修复项 |
| C ABI RPC 被误认为真实可用 | 中 | `docs/cabi-guide.md` 已显式降级说明；后续由 Batch 4 决定是补真实 transport 还是缩 surface |
| Rust 版本演进漂移 | 中 | 基线锁定 + 兼容矩阵 + oracle 回归 |
| 运营/状态文档继续漂移 | 低 | 本轮已明确 `docs/10`、`docs/36`、`docs/37` 为当前权威跟踪文档 |

## 5. 结论

- 当前阶段可判定为：**Product Phase 1/2 已完成；Phase 3 主体能力已落地，但仍处于 Batch 4 closeout**。
- 当前对外表述应限定为：
  - 16 个 RPC 方法、7 种 WebSocket 订阅、7 个 interface 模块已实现
  - signer abstraction / C ABI / stake 已有主实现，但仍有 correctness 与 closeout 项待处理
- Phase 4（链上程序支持）仍作为独立子项目评估，不与当前 client SDK 生命周期耦合。

## 6. 下一步审查门槛

- 先完成 Phase 3 Batch 4 closeout：
  1. 修复 `MockExternalSigner` correctness gap；
  2. 对齐 stake create helper 契约并补负路径测试；
  3. 收紧 C ABI scope 与验证证据；
  4. 完成顶层状态文档与 planning/readiness artifact 对账。
- 之后再进入常规维护模式与 Phase 4 设计审查。

## 7. Closeout Checkpoint (2026-04-16) — Historical

> 本节为历史快照，记录 Phase 1 closeout 评审过程；不代表当前 Phase 3 已完成最终 closeout。

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

- Phase 1 closeout gates 已通过。
- 该历史结论不覆盖当前 Phase 3 Batch 4 closeout 状态。
