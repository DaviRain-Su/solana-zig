# Phase 4 Planning — 链上程序支持

**Date**: 2026-04-17  
**Status**: Draft (pending structural review)  
**Owner**: `#89`  
**Reviewer**: `@codex_5_4`  
**Baseline**: Phase 3 closeout `e913351`, 239/239 tests, verdict `有条件发布`

## 1. 背景

Phase 1-3 交付了完整的 off-chain 客户端 SDK（core types / transaction / RPC / 7 interface modules / signer abstraction / C ABI）。Phase 4 的目标是评估并实现 Zig 链上程序（on-chain program）支持，产出独立的 `solana-program-zig` 包。

根据 `docs/00-roadmap.md`，Phase 4 的前置条件是 **Zig 交叉编译到 SBF 目标的可行性验证**。

## 2. 可行性评估结论

### 2.1 Zig→SBF 工具链

- **结论：可行，已有成熟方案。**
- Solana 维护 LLVM fork（`llvm-project-solana`），包含 SBF 特定 patch。
- `joncinque/solana-zig-bootstrap` 基于 Solana LLVM fork 构建 patched Zig 编译器，支持 `sbf_target` / `sbfv2_target`。
- 预编译二进制已覆盖 x86_64/aarch64 Linux/macOS/Windows。
- 当前版本对齐 Zig 0.14.x + Solana LLVM v1.52。

### 2.2 已有生态

- `joncinque/solana-program-sdk-zig`（v0.17.1, Nov 2025, 活跃维护）：
  - Target 定义、Account 解析、PublicKey、logging、CPI helpers
  - `buildProgram()` linker helper
  - 集成测试跑在 Agave runtime（`solana-program-test`）
- `joncinque/borsh-zig`（v0.15.0）：纯 Zig Borsh 实现，SBF freestanding 兼容
- `joncinque/base58-zig`、`bincode-zig`：辅助库

### 2.3 约束条件

| 约束 | 说明 |
|------|------|
| no_std / freestanding | SBF 无 OS，Zig std 大部分不可用 |
| Heap | 32KB bump allocator（Solana 提供） |
| Stack | 4KB/frame, 64KB total depth |
| Compute Units | 默认 200K CU/instruction, 最大 1.4M |
| Entrypoint | `export fn entrypoint(_: [*]u8) callconv(.c) u64` |

### 2.4 风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| Zig 版本与 solana-zig-bootstrap 不同步 | 编译器不兼容 | 锁定 bootstrap 支持的 Zig 版本 |
| SBF 目标行为与 eBPF 有 delta | 运行时错误 | 用 solana-program-test 做 runtime 验证 |
| 上游 SDK 维护节奏不确定 | 依赖断裂 | 评估 fork vs vendor 策略 |
| 与 Phase 1-3 off-chain SDK 的类型复用 | 重复定义或循环依赖 | 提取共享 core types 到独立模块 |

## 3. Scope 定义

### 3.1 Phase 4 核心范围

| ID | 模块 | 说明 | 优先级 |
|----|------|------|--------|
| P4-M1 | 工具链集成 | solana-zig-bootstrap 集成 + build.zig SBF target | P0 |
| P4-M2 | Entrypoint 框架 | entrypoint 宏/函数 + account deserialization + instruction data 解析 | P0 |
| P4-M3 | 核心类型对齐 | PublicKey / Instruction / AccountMeta 与 off-chain SDK 共享或兼容 | P0 |
| P4-M4 | CPI (Cross-Program Invocation) | sol_invoke_signed 封装 + PDA 派生 | P0 |
| P4-M5 | Borsh 序列化 | Borsh 编解码，兼容 Anchor/Rust 程序 wire format | P1 |
| P4-M6 | System 指令 | CreateAccount / Transfer / Assign 的链上 CPI wrapper | P1 |
| P4-M7 | SPL Token 指令 | Transfer / MintTo / Approve 的链上 CPI wrapper | P2 |
| P4-M8 | 示例程序 | Counter / Escrow 等可部署示例 | P2 |

### 3.2 明确排除

- off-chain SDK 功能增强（属 Phase 3 后续）
- Anchor 兼容 IDL 生成（过于复杂，不在 Phase 4 评估范围）
- 生产级部署工具链（Phase 4 聚焦核心能力验证）

### 3.3 Phase 3 遗留项处理

| 遗留项 | 处置 |
|--------|------|
| `requestAirdrop` partial_exception | 不纳入 Phase 4；保持 Phase 3 verdict `有条件发布` |
| `getAddressLookupTable` accepted_exception_path | 同上 |
| Perf calibration (native Zig vs Rust) | 作为 Phase 4 前置 sidecar 任务 (P4-Pre-1)，**不阻塞** Batch 1 解锁；结果作为 P4 verdict 输入 |
| #14 Package rename | 独立处理，不纳入 Phase 4 |
| #15 npm publish | SUSPENDED，不纳入 |

## 4. Build or Integrate 决策

**推荐方案：Evaluate → Selective Integrate → Extend**

1. **Evaluate**（Batch 0）：在当前 `solana-zig` 仓库内评估 `solana-zig-bootstrap` + `solana-program-sdk-zig` 的集成可行性（独立仓库在 Batch 1 前按 D-04 决策创建）
2. **Selective Integrate**：将验证通过的组件（target def, entrypoint, allocator）作为基础，不 fork 全量
3. **Extend**：在集成基础上实现 Phase 4 特有模块（CPI wrapper, Borsh, SPL interfaces）
4. **Core types 共享**：评估 off-chain SDK 的 `core/` 模块能否在 freestanding 模式下编译，避免重复定义

## 5. Batch 划分

### Batch 0 — 前置与可行性验证（P4-Pre）

| Task | 说明 |
|------|------|
| P4-Pre-1 | Perf calibration: native Zig vs native Rust benchmark（不经 C ABI）。**Sidecar**：不阻塞 G-P4A / Batch 1，结果作为 Phase 4 verdict 输入 |
| P4-Pre-2 | solana-zig-bootstrap 本地构建验证 + **Zig 版本兼容性探针**：在目标 Zig 版本下编译 `solana-program-sdk-zig` 最小示例，产出 compat matrix（可编译 / 需 patch / API break 列表） |
| P4-Pre-3 | 在当前 `solana-zig` 仓库内做 SBF target 最小验证（编译 + localnet 加载 smoke）。独立仓库 `solana-program-zig` 的创建推迟到 Batch 1 前（见 Decision D-04） |
| P4-Pre-4 | 测试基础设施拍板（`solana-test-validator` vs `solana-program-test`）并产出 ADR |
| P4-Pre-5 | Core types 共享决策：`@import` 共享 vs vendor split，产出 ADR。若选共享，附 `Pubkey/Hash/Signature` 布局一致性检查；若选拆分，附 freestanding 最小子模块边界 |

**Gate**: G-P4A — 三件套判定：
1. SBF target compile PASS（P4-Pre-2/3）
2. Localnet load/call smoke PASS（P4-Pre-3）
3. Decision records 固化：test harness ADR（P4-Pre-4）+ core types ADR（P4-Pre-5）+ Zig compat matrix（P4-Pre-2）

`P4-Pre-1`（perf calibration）为 **sidecar**，不阻塞 Batch 1 解锁，但结果须在 G-P4E 前落盘

### Batch 1 — 核心框架（P4-M1~M3）

| Task | 说明 |
|------|------|
| P4-B1-1 | build.zig SBF target 完整集成（debug/release） |
| P4-B1-2 | Entrypoint + account deserialization |
| P4-B1-3 | Core types 对齐（PublicKey/Instruction/AccountMeta） |
| P4-B1-4 | 最小可部署程序（hello-world on localnet） |

**Gate**: G-P4B — 可在 localnet 部署并调用最小程序

### Batch 2 — CPI 与序列化（P4-M4~M5）

| Task | 说明 |
|------|------|
| P4-B2-1 | CPI invoke/invoke_signed 封装 |
| P4-B2-2 | PDA derivation (create_program_address / find_program_address) |
| P4-B2-3 | Borsh 集成（编解码 + 兼容性测试 vs Rust Borsh） |

**Gate**: G-P4C — CPI 跨程序调用 + Borsh round-trip 通过

### Batch 3 — 指令接口与示例（P4-M6~M8）

| Task | 说明 |
|------|------|
| P4-B3-1 | System program CPI wrappers |
| P4-B3-2 | SPL Token CPI wrappers |
| P4-B3-3 | Counter 示例程序（完整 deploy + test） |
| P4-B3-4 | Escrow 示例程序（多账户 + CPI） |

**Gate**: G-P4D — 示例程序部署 + 集成测试 PASS

### Batch 4 — 收口与发布（P4-Closeout）

| Task | 说明 |
|------|------|
| P4-B4-1 | 文档：README / API reference / 快速开始 |
| P4-B4-2 | CI pipeline（SBF build + localnet test） |
| P4-B4-3 | 与 off-chain SDK 集成验证（构建交易 → 签名 → 部署 → 调用 → 解析） |
| P4-B4-4 | Release readiness + aggregate verdict |

**Gate**: G-P4E — Phase 4 aggregate verdict

## 6. Gate 定义

| Gate | 验证内容 | 判定条件 |
|------|----------|----------|
| G-P4A | 可行性 | ① SBF target compile PASS ② localnet load/call smoke PASS ③ 三份 decision records 固化（test harness ADR + core types ADR + Zig compat matrix） |
| G-P4B | 核心框架 | hello-world 程序 localnet 部署+调用成功 + core types 对齐验证 |
| G-P4C | CPI + 序列化 | 跨程序调用成功 + Borsh round-trip Zig↔Rust 一致 + **CU baseline 输出**（每条关键 CPI 路径记录 CU 消耗） |
| G-P4D | 指令接口 | Counter + Escrow 程序 localnet 全流程通过 + **CU baseline 输出**（示例程序 CU 消耗记录 + 变更趋势） |
| G-P4E | 发布就绪 | CI green + docs complete + integration test PASS + perf calibration sidecar 落盘 |

## 7. 产出物

- 独立仓库 `solana-program-zig`（与 `solana-zig` 分离生命周期）
- 核心包：entrypoint / accounts / cpi / borsh / system / spl-token
- 示例程序：counter / escrow
- CI：SBF 编译 + localnet 集成测试
- 文档：快速开始 + API reference

## 8. 团队分工建议

| 角色 | 职责 |
|------|------|
| CC-Opus | Planning + gate coordination（延续 Phase 3 模式） |
| @codex_5_4 | Structural reviewer（planning → gate review） |
| @codex_ / @codex_5_3 | Implementation（Batch 0-3 实现线） |
| @kimi | Scope review + testing support |
| @CC | Routing + coordination support |

## 9. 决策项（带截止批次）

| ID | 决策项 | 截止 | 产出 |
|----|--------|------|------|
| D-01 | **Zig 版本锁定**：off-chain SDK Zig 版本是否与 solana-zig-bootstrap 兼容？缺口多大？ | Batch 0 (P4-Pre-2) | Zig compat matrix |
| D-02 | **Core types 共享策略**：`@import` 共享 vs vendor copy？ | Batch 0 (P4-Pre-5) | ADR (含布局一致性 / freestanding 验证) |
| D-03 | **测试基础设施**：`solana-test-validator` vs `solana-program-test` Rust harness？ | Batch 0 (P4-Pre-4) | ADR (含 Rust 工具链依赖评估) |
| D-04 | **独立仓库时机**：Batch 0 在当前仓做 feasibility，Batch 1 前完成分仓决策 | Batch 0→1 过渡 | 分仓 / 保留 monorepo 决策记录 |

所有 D-01~D-03 必须在 G-P4A 关闭前固化。D-04 须在 Batch 1 开工前拍板。
