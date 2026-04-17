# ADR-0002 - Phase 4 Core Types 共享策略（off-chain ↔ on-chain）

- Status: `proposed`
- Date: `2026-04-17`
- Deciders: @kimi, @codex_5_4 (reviewer)
- Related Docs: `docs/40-phase4-planning.md`, `docs/41-phase4-release-readiness.md`
- Related Code: `src/solana/core/`, `src/solana/cabi/`

## 1. Context

Phase 4 要求 `solana-zig` 同时支持 off-chain SDK（native host target）与 on-chain program（`bpfel-freestanding` / SBF target）。这带来一个架构问题：**核心类型（Pubkey、Hash、Signature 等）是否可以在两条路线之间共享？**

当前约束：
- off-chain SDK 使用完整 `std`（含 allocator、I/O、C ABI 导出）。
- on-chain program 运行在 `freestanding` 环境，不能依赖 OS I/O、动态内存分配器（除非自带 bump allocator），且必须严格控制二进制体积。
- zignocchio 作为 Phase 4 主参考路径，其 `Pubkey` 定义为裸 `[32]u8`，而 `solana-zig` 当前定义为带方法的 `struct { bytes: [32]u8 }`。

## 2. Decision

**采用 Option A（分层共享）：**
- `src/solana/core/{pubkey,hash,signature}.zig` **可直接通过 `@import` 共享**到 on-chain target。
- `Keypair` 与任何需要 OS 随机数生成器的功能 **不共享**，on-chain 侧由调用方传入 `Pubkey`/`Signature`。
- Base58 编解码层目前可共享，但后续若发现 `.rodata` 体积问题，可再拆出 `no_base58` 编译开关。
- 共享前必须执行一次 `freestanding` 依赖扫描，确保 core 目录下没有隐式 `std` I/O / allocator / fmt 调用。

生效范围：Phase 4 Batch 0 起生效；共享入口统一为 `@import("solana").core.Pubkey` 等。

## 3. Evidence

### 3.1 布局一致性验证
Native target 下 `@sizeOf` / `@alignOf` 实测结果：

| Type | `@sizeOf` | `@alignOf` | 说明 |
|------|-----------|------------|------|
| `Pubkey` | 32 | 1 | 32 字节定长数组，无填充 |
| `Hash` | 32 | 1 | 32 字节定长数组，无填充 |
| `Signature` | 64 | 1 | 64 字节定长数组，无填充 |

与 zignocchio 的裸类型定义（`Pubkey = [32]u8`，`Signature = [64]u8`）在 ABI 层面完全兼容。

### 3.2 `bpfel-freestanding` 编译扫描
使用 Zig 0.16.0 对 core 类型文件执行 `build-obj` 扫描：

```bash
zig build-obj -target bpfel-freestanding src/solana/core/hash.zig
zig build-obj -target bpfel-freestanding src/solana/core/signature.zig
zig build-obj -target bpfel-freestanding src/solana/core/pubkey.zig
```

**结果：全部通过（exit 0，无编译错误）。**

### 3.3 `std` 依赖边界
对 `src/solana/core/{pubkey,hash,signature}.zig` 进行 freestanding 可用性审查：

| 类型 | 已验证可用 | 依赖说明 |
|------|------------|----------|
| `Pubkey` | ✅ | 使用 `std.mem.eql`、`std.crypto.hash.sha2.Sha256`、`std.crypto.ecc.Edwards25519`，均为纯计算库，freestanding 兼容 |
| `Hash` | ✅ | 使用 `std.crypto.hash.sha2.Sha256`，纯计算，freestanding 兼容 |
| `Signature` | ✅ | 使用 `std.crypto.sign.Ed25519`，纯计算，freestanding 兼容 |
| `Keypair` | ❌ | 使用 `std.crypto.sign.Ed25519.KeyPair.generate()`，依赖 OS randomness，**不共享** |

## 4. Alternatives Considered

### Option A - 分层 `@import` 共享（选中）
- **描述**：保留现有 `src/solana/core/` 目录结构，确认其无 OS 依赖后直接供 on-chain 复用。
- **优点**：
  - 单一源码（Single Source of Truth），避免 off-chain / on-chain 类型定义分叉。
  - `Pubkey`/`Hash`/`Signature` 当前已是纯字节数组 struct，方法均为纯计算，天然 freestanding 友好。
  - 不引入额外仓库或包管理复杂度。
- **缺点**：
  - 未来若有人在 `pubkey.zig` 中加入 `std.fmt` 或日志调用，会意外破坏 SBF 编译。
  - 需要 CI 增加 `freestanding` 编译门控来防止回归。

### Option B - 独立 on-chain types 包
- **描述**：新建 `src/solana/sbf_types/` 或独立 package，只放最精简的裸类型定义。
- **优点**：
  - 绝对隔离，on-chain 类型不会被 off-chain 特性污染。
  - 与 zignocchio 的极简风格对齐。
- **缺点**：
  - 重复定义 `Pubkey`/`Hash`/`Signature`，转换开销和心智负担增加。
  - 若后续类型格式升级（如新增辅助方法），需要双轨同步。

### Option C - 直接复用 zignocchio 类型
- **描述**：on-chain 侧直接依赖 zignocchio 的 `sdk/types.zig`，off-chain 侧保持现有实现。
- **优点**：
  - 与 zignocchio 生态 100% 兼容。
- **缺点**：
  - zignocchio 的 `Pubkey` 是裸 `[32]u8`，没有 `eql()`、`fromBase58()` 等方法；功能差距大，不适合 off-chain SDK 使用。
  - 强制两套类型体系并存，用户体验差。

## 5. Consequences

### 对代码的影响
- `src/solana/core/` 目录增加 `freestanding` CI 编译检查（target `bpfel-freestanding`）。
- `Keypair` 明确留在 off-chain 层；on-chain entrypoint 只接收 `Pubkey` / `Signature` / `Hash`。
- 若发现 `base58.zig` 在 SBF 下体积过大或触发 linker 限制，后续可补 `no_base58` 编译选项。

### 对文档的影响
- `docs/40-phase4-planning.md` 的 core-types 共享章节已更新为 Option A。
- 需在 `docs/06-implementation-log.md` 中记录共享决策及扫描结果。

### 对测试的影响
- core 目录现有单元测试（`zig test src/solana/core/*.zig`）在 native target 继续运行。
- 新增 SBF compile-only 测试：验证 `src/solana/core/` 在 `bpfel-freestanding` 下可编译通过。

### 对迁移/兼容性的影响
- 无破坏性变更；`Pubkey`/`Hash`/`Signature` 的内存布局（32/32/64 字节定长数组）与 zignocchio 裸类型在 ABI 层面兼容。
- C ABI 层（`include/solana_zig.h`）的 struct 定义保持不变。

## 6. Rollback / Revisit Trigger

在以下任一信号出现时，需重新审查本决策：
1. `bpfel-freestanding` 编译扫描发现 core 类型存在不可移除的 `std` OS/allocator 依赖。
2. `sbpf-linker` 报告 `.rodata.cst32` 或 base58 lookup table 导致 ELF 超限。
3. zignocchio 或 Solana 官方发布新的标准类型库，且功能覆盖度超过当前 core 层。

## 7. Follow-up Actions

- [x] 执行 `freestanding` 依赖扫描（`zig build -Dtarget=bpfel-freestanding` 针对 core 目录）
- [ ] 在 CI 中增加 SBF compile-only gate
- [ ] 在 `docs/06-implementation-log.md` 记录落地情况
