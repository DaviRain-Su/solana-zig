# Phase 4 Batch 1 Planning — Core Framework

**Date**: 2026-04-17  
**Status**: Draft (pending structural review)  
**Owner**: `#100`  
**Reviewer**: `@codex_5_4`  
**Baseline**: Batch 0 closed (`G-P4A PASS`), toolchain baseline = `zignocchio + sbpf-linker + surfpool`

## 1. 目标

Batch 1 目标是落地 on-chain 核心框架最小可用闭环，形成可持续迭代的独立包骨架，并解锁 `G-P4B`：

1. `entrypoint` 最小运行时框架
2. account deserialization 基础能力
3. instruction parse + dispatch 框架
4. 同仓独立包边界（D-04 owner 已拍板）

## 2. Scope Freeze

### 2.1 In Scope（Batch 1）

- `P4B-M1` package boundary：在当前仓内落地独立包（canonical 路径：`packages/solana-program-zig/`）
- `P4B-M2` build scaffold：独立包 `build.zig` + `bpfel-freestanding` 编译入口
- `P4B-M3` entrypoint：统一入口与最小 context（错误码、返回路径、日志边界）
- `P4B-M4` account deserialization：最小账户视图解析与边界校验
- `P4B-M5` instruction parse：指令 header/variant parse 与 dispatch 骨架
- `P4B-M6` hello-world/counter-minimal：用于 `G-P4B` smoke 的最小可调用程序

### 2.2 Out of Scope（Batch 1）

- CPI 深化（`invoke/invoke_signed` 细化）
- Borsh round-trip 完整对账（归 Batch 2）
- System/SPL wrappers（归 Batch 3）
- perf sidecar 新增结论（`#94` 已作为输入，不扩写）

### 2.3 Package Boundary Rules（机械约束）

1. canonical package path 固定为：`packages/solana-program-zig/`
2. 允许的 core type 共享仅限：`src/solana/core/{pubkey,hash,signature}.zig`（遵循 `D-02`）
3. `Keypair` 明确禁止进入 on-chain 包（不得 `@import`）
4. Batch 1 negative write-set（禁止改动）：
   - `src/solana/rpc/**`
   - `src/solana/cabi/**`
   - `src/e2e/**`
   - `include/solana_zig.h`
5. Batch 1 如需调整共享类型边界，必须先以 ADR supersede 更新 `D-02`

## 3. 固定边界（继承已签收决策）

1. canonical scoring host：`linux-x86_64`
2. smoke harness：`surfpool-first`（已由 `#97` supersede 签收）
3. `darwin-arm64`：dev-only / non-scoring
4. `solana-zig-bootstrap`：永久排除（不进入实施计分）
5. core types：按 `ADR-0002` Option A 分层 `@import` 共享，`Keypair` 不共享

## 4. Batch 1 任务拆分建议

| Task | 内容 | 建议 owner |
|------|------|------------|
| `#101` P4-07 | package boundary + build scaffold（独立包骨架 + bpf build entry） | `@kimi` |
| `#102` P4-08 | entrypoint runtime skeleton（入口/错误码/返回路径） | `@codex_5_3` |
| `#103` P4-09 | account deserialization（账户视图与边界校验） | `@codex_5_3` |
| `#104` P4-10 | instruction parse + dispatch + smoke demo | `@kimi` |
| `#105` P4-11 | Batch 1 docs/gate closeout（docs/06+10+15+41+43） | `@codex_` |

依赖关系：`#101 -> (#102/#103 并行) -> #104 -> #105`

## 5. Gate 定义（Batch 1）

| Gate | 验证内容 | 判定条件 |
|------|----------|----------|
| `G-P4B-01` | package boundary + compile | 独立包在 `linux-x86_64` 下可稳定编译，写集与 off-chain SDK 边界清晰 |
| `G-P4B-02` | entrypoint + account deserialization + instruction parse + smoke | `surfpool` 上完成 deploy + 最小调用 smoke（同一 canonical host 证据），并满足 deserialize 机械证据 |
| `G-P4B-03` | docs/gate 对账 | Batch 1 文档与证据链一致，状态/结论 reviewer-safe |

`G-P4B PASS` 条件：`G-P4B-01/02/03` 全通过。

## 6. DoD（Batch 1）

1. 独立包目录、构建入口、最小 API 边界可复用
2. entrypoint + account deserialize + instruction parse 可在 smoke 路径中被实际调用
3. deserialize 机械证据必须齐备：
   - 1 条正路径：合法账户视图解析成功
   - 2 条负路径：账户数据长度不足 + owner/account meta 不匹配
4. 所有证据可追溯到可审 commit/hash（clean canonical）
5. docs 不预写 PASS；仅在 reviewer 结论后固化 final 状态

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| package boundary 与现有 SDK 耦合过深 | 后续拆分困难 | 先固定目录边界与 import policy，再进实现 |
| parser 与账户模型过早绑定业务结构 | Batch 2/3 返工 | Batch 1 保持 generic parser + minimal variant |
| smoke 证据口径漂移 | gate 重复返工 | 严格使用 `linux-x86_64 + surfpool-first` 口径 |

## 8. 参考实现路径

实现时以 `zignocchio / solana-program-sdk-zig` 的 entrypoint 签名、AccountInfo 布局与 syscall 边界作为主参考，但证据与 gate 判定以本仓 Batch 1 交付为准。

## 9. Reviewer 请求

请基于本稿确认：
1. Scope/DoD 是否足以解锁 Batch 1 实现
2. `#101~#105` 拆分与依赖是否合理
3. `G-P4B-*` 判定条件是否机械且可审计
