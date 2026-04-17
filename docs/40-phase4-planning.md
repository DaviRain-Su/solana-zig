# Phase 4 Planning — 链上程序支持

**Date**: 2026-04-17  
**Status**: Draft (pending structural review)  
**Owner**: `#89` / delta `#99`  
**Reviewer**: `@codex_5_4`  
**Baseline**: Phase 3 closeout `e913351`, 239/239 tests, verdict `有条件发布`

## 1. 背景

Phase 1-3 已交付完整 off-chain SDK。Phase 4 目标是落地 Zig on-chain program 支持，并形成独立交付线 `solana-program-zig`。

本轮 `#99` 为 planning delta：根据 owner 指令，Phase 4 工具链基线切换为 `zignocchio` 路线，不再以 `solana-zig-bootstrap` 作为实施候选。

## 2. 工具链基线（更新）

### 2.1 结论

- 采用 `Solana-ZH/zignocchio` 路线作为 Phase 4 主工具链基线。
- 技术形态：`standard Zig BPF target` + `sbpf-linker`。
- 不使用 custom patched Zig compiler 路线作为本批实施候选。

### 2.2 可行性验证对象

Batch 0 的 `#95/#96` 仅对 `zignocchio` 路线计分，至少覆盖：

1. Zig 版本兼容性（含 build API 差异与 shim 需求）
2. SBF 编译可达性（compile 成功）
3. localnet smoke 可达性（load/call 成功）
4. linker/目标平台约束（含 `.rodata`/SPL 相关限制）

### 2.3 Host Matrix 与计分策略（本次必须写死）

1. 必须在 Batch 0 给出 `zignocchio/sbpf-linker` 在 `darwin-arm64` 的支持结论：`支持 / 不支持 / 条件支持`。\n
2. 若 `darwin-arm64` 不可用，允许采用 `linux-x86_64` 作为 `G-P4A` canonical 计分主机；`darwin-arm64` 仅作 native/dev 校验。\n
3. `solana-zig-bootstrap` 默认保持“已排除对照方案”；仅当触发机械条件时降级为 fallback candidate：\n
   - `linux-x86_64` 上 `zignocchio` 路线 compile 与 smoke 均失败，且失败可复现；\n
   - 已完成最小复现与根因记录（命令、环境、错误栈）；\n
   - reviewer 在 ADR 中签署 fallback 触发。\n

### 2.4 风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| Zig 版本与 `zignocchio` 路线不兼容 | 编译或链接失败 | 产出 compat matrix + build shim 决策 |
| sbpf-linker 在特定 host（如 darwin-arm64）不可用 | Batch 0 阻塞或平台割裂 | 固化 host tier（linux canonical / macOS dev-only）并记录限制 |
| on-chain/runtime 语义偏差 | 运行时错误 | `#96` 执行 localnet smoke + 最小可调用验证 |
| core types 共享策略不稳定 | 类型重复或接口漂移 | `#98` 固化 ADR + 布局一致性检查 |

## 3. Scope 定义

### 3.1 Phase 4 核心范围

| ID | 模块 | 说明 | 优先级 |
|----|------|------|--------|
| P4-M1 | 工具链集成 | `zignocchio` + `sbpf-linker` + SBF target | P0 |
| P4-M2 | Entrypoint 框架 | entrypoint + account deserialization + instruction parse | P0 |
| P4-M3 | 核心类型对齐 | PublicKey/Instruction/AccountMeta 对齐策略 | P0 |
| P4-M4 | CPI | invoke/invoke_signed + PDA | P0 |
| P4-M5 | Borsh | Zig↔Rust wire-format 一致性 | P1 |
| P4-M6 | System CPI wrappers | create/transfer/assign | P1 |
| P4-M7 | SPL Token CPI wrappers | transfer/mint/approve | P2 |
| P4-M8 | 示例程序 | counter/escrow | P2 |

### 3.2 明确排除

- Phase 3 两条 open exceptions 的关闭工作不并入 Phase 4 实现 scope；
- off-chain SDK 功能增强不并入本批；
- Anchor IDL 生成不并入本批。

### 3.3 Phase 3 遗留项处置

| 遗留项 | 处置 |
|--------|------|
| `requestAirdrop = partial_exception` | 保留 Phase 3 strict 结论，不在 Phase 4 重定义 |
| `getAddressLookupTable = accepted_exception_path` | 同上 |
| Perf calibration（native-vs-native / cabi-vs-cabi） | `#94` sidecar，不阻塞 `G-P4A`，但在 `G-P4E` 前必须落盘 |

## 4. 执行路线

`Reference zignocchio -> Integrate minimal runtime pieces -> Extend`

1. Batch 0 先锁工具链可行性与决策记录；
2. Batch 1 起再进入框架实现；
3. Batch 0->1 过渡时完成“独立仓库 vs monorepo”决策。

## 5. Batch 划分（Batch 0）

| Task | 说明 |
|------|------|
| `#94` P4-Pre-1 | Perf calibration sidecar（不阻塞 `G-P4A`） |
| `#95` P4-Pre-2 | `zignocchio` 工具链验证 + Zig compat matrix（含 host support tier） |
| `#96` P4-Pre-3 | 基于 `zignocchio` 的 SBF compile + localnet smoke |
| `#97` P4-Pre-4 | Test harness ADR（validator vs program-test）+ fallback 边界与 host policy 记录 |
| `#98` P4-Pre-5 | Core types 共享 ADR（@import vs vendor） |

## 6. Gate 定义

| Gate | 验证内容 | 判定条件 |
|------|----------|----------|
| `G-P4A` | Batch 0 可行性 | ① `#95/#96` 的 `zignocchio` 路线 compile + smoke PASS（canonical host = linux-x86_64） ② decision records 落盘（`#97/#98` + `#95` compat matrix 含 host tier） |
| `G-P4B` | 核心框架 | hello-world localnet deploy/call PASS |
| `G-P4C` | CPI + Borsh | CPI 成功 + Borsh round-trip + CU baseline 输出 |
| `G-P4D` | 指令接口 | System/SPL + 示例程序 PASS + CU baseline 输出 |
| `G-P4E` | 收口发布 | CI green + docs complete + integration PASS + `#94` sidecar 落盘 |

## 7. 决策项（带截止批次）

| ID | 决策项 | 截止 | 产出 |
|----|--------|------|------|
| D-01 | Zig 版本锁定（`zignocchio` 路线兼容性 + shim 需求） | Batch 0 (`#95`) | compat matrix + shim decision |
| D-02 | Core types 共享策略（@import vs vendor） | Batch 0 (`#98`) | ADR + 布局一致性/边界验证 |
| D-03 | Test harness 决策（validator vs program-test） | Batch 0 (`#97`) | ADR + CI 影响评估 |
| D-04 | 独立仓库时机（Batch 0 feasibility 后拍板） | Batch 0->1 过渡 | 决策记录 |
| D-05 | Host support matrix（linux canonical / darwin tier）与 fallback 触发规则 | Batch 0 (`#95/#97`) | host tier 结论 + fallback gate rule |

D-01~D-03、D-05 必须在 `G-P4A` 前关闭；D-04 在 Batch 1 开工前关闭。

## 8. 对旧路线的说明

`solana-zig-bootstrap` 路线在本批视为“已排除方案”，仅用于背景对照，不作为 `#95/#96` 计分对象。
