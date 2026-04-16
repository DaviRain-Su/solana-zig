# Product Phase 2 Batch 2 Planning

**Date**: 2026-04-16  
**Status**: Planning draft（`#26 P2-6`）  
**Owner**: `#26`  
**Depends on**: `docs/00-roadmap.md`, `docs/03c-rpc-extended-spec.md`, `docs/03a-interfaces-spec.md`, `docs/19-phase2-planning.md`

> 本文用于冻结 Product Phase 2 第二批范围、DoD、执行顺序与 gate。  
> 在本文过审前，`#27/#28/#29/#30` 仅允许调研与草案准备，不进入实现提交。

## 1. 背景与目标

Phase 2 第一批已完成：
- `send + confirm` live 证据闭环
- RPC Batch A（`getTransaction/getSignaturesForAddress/getSlot`）收口
- Websocket 最小可用（lifecycle/reconnect/malformed）收口

第二批目标是把 Phase 2 路线从“可用”推进到“可组合工作流”：
1. 扩展 RPC Batch B（生产常用只读/测试辅助方法）
2. Durable Nonce 最小可用流程
3. Priority Fees / ComputeBudget 指令构建
4. 第二批 docs/gate 持续留痕并最终收口

## 2. In Scope（冻结版）

### 2.1 `#27 P2-7` — 扩展 RPC Batch B

固定方法集合（本批仅这 4 个）：
1. `getEpochInfo`
2. `getMinimumBalanceForRentExemption`
3. `requestAirdrop`
4. `getAddressLookupTable`

每个方法必须具备：
- typed parse（最小稳定子集 + 必要 raw 旁路）
- `happy` 用例
- `rpc_error` 用例
- `malformed/invalid response` 用例

### 2.2 `#28 P2-8` — Durable Nonce 最小可用

最小交付：
- nonce account 查询（依赖 RPC typed parse 能力）
- Nonce Advance 指令构建（代码归属固定：`interfaces/system`）
- 一个最小流程测试：`query nonce -> build advance ix -> compile/sign`（mock 或 local live 可复现）

### 2.3 `#29 P2-9` — Priority Fees / ComputeBudget

最小交付：
- ComputeBudget 指令 builder（代码归属固定：`interfaces/compute_budget`；至少 `setComputeUnitLimit`、`setComputeUnitPrice`）
- 参数合法性校验（边界值、非法值）
- 指令序列化用例（可与 Rust 参考字节做对照）

### 2.4 `#30 P2-10` — docs/gate 收口

第二批执行过程中的持续回写：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/15-phase1-execution-matrix.md`（继续承载 Phase 2 tracking 条目）

## 3. Out of Scope（Batch 2 非目标）

本批不做：
1. `getTokenAccountsByOwner`（延后到 Phase 2 后续批次）
2. Websocket 新能力扩展（本批只消费第一批已收口能力，不再扩大 websocket 范围）
3. 完整 interfaces 扩展（token/token-2022/memo/stake）
4. signers/C ABI（Phase 3）

## 4. 执行顺序与依赖

### 4.1 串并行规则

1. `#26` 通过前：`#27/#28/#29/#30` 冻结提交
2. `#26` 通过后：
   - `#27` 与 `#29` 可并行
   - `#28` 可与 `#27` 并行，但若依赖 `requestAirdrop` typed 行为，优先消费 `#27` 的稳定接口
   - `#30` 全程跟随并实时回写

### 4.2 推荐顺序

1. `#27`（先稳住 Batch B typed parse 基线）
2. `#29`（ComputeBudget builder 并行落地）
3. `#28`（Nonce workflow 组装，复用前两线能力）
4. `#30`（过程性回写 + 末尾总对账）

## 5. Gate / DoD

## G-P2B-01 Test Gate

- canonical 三件套（所有提审线统一）：
  - clean `git status`
  - commit hash
  - 单次全量 `zig build test` 原始结果
- 无新增编译 blocker
- 无新增 leak / 死锁信号

## G-P2B-02 RPC Batch B Gate（#27）

- 4 个方法全部完成 typed parse
- 每方法至少 `happy + rpc_error + malformed` 三类覆盖
- integration-evidence（Batch 2 固定例外口径）：
  - `requestAirdrop`：至少 1 条可复现 live 证据（优先 `public devnet`，次选 `local validator/surfnet`）
  - `getEpochInfo/getMinimumBalanceForRentExemption/getAddressLookupTable`：本批允许 `mock + local-live` 作为 integration-evidence 替代（不强制 `public devnet`）
  - 以上例外必须在 `docs/15` 显式登记 `Batch 2 exception`（含原因与后续收敛阶段）

## G-P2B-03 Nonce Gate（#28）

- nonce 查询可返回稳定结构
- advance 指令构建参数与账户约束可验证
- 至少 1 条流程测试可复现（query -> build -> compile/sign）

## G-P2B-04 ComputeBudget Gate（#29）

- `setComputeUnitLimit` / `setComputeUnitPrice` builder 可用
- 参数边界校验完备
- 指令序列化有对照证据（测试留档）

## G-P2B-05 Docs Gate（#30）

每条任务提审必须同步回写：
- `docs/06-implementation-log.md`
- `docs/10-coverage-matrix.md`
- `docs/15-phase1-execution-matrix.md`（Phase 2 tracking）

> 若涉及 live 证据，再额外回写 `docs/14a-devnet-e2e-run-log.md`。

## 6. 任务归属建议（冻结版）

1. `#27`：@codex_5_3（RPC Batch B）
2. `#28`：@kimi（Durable Nonce workflow）
3. `#29`：@CC（ComputeBudget builders）
4. `#30`：@codex_5_4（docs/gate 对账）

## 7. 放行条件

`#27/#28/#29/#30` 进入正式实现提交前，需满足：
1. 本文完成 review 并确认冻结
2. 各任务线程显式引用本文 DoD
3. owner 冲突清理完成，避免同文件并发写冲突
