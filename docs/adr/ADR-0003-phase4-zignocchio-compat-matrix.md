# ADR-0003 - Phase 4 zignocchio 工具链兼容矩阵（D-01 + D-05）

- Status: `proposed`
- Date: `2026-04-17`
- Deciders: @kimi, @codex_5_4 (reviewer)
- Related Docs: `docs/40-phase4-planning.md`, `docs/41-phase4-release-readiness.md`
- Related Code: `src/solana/core/`, `src/solana/cabi/`

## 1. Context

Phase 4 工具链基线已切换为 `zignocchio`（标准 Zig BPF target `bpfel-freestanding` + `sbpf-linker`）。Batch 0 需要产出可审计的兼容矩阵，覆盖：
- D-01：Zig 版本兼容性、build API 差异、linker 限制
- D-05：Host 支持矩阵与 canonical scoring 主机判定

## 2. Zig 版本兼容性（D-01）

### 2.1 测试环境
- **Zig 0.16.0**（solana-zig 当前主版本）
- **Zig 0.15.2**（solana-zig-bootstrap 自带版本，作为对照）

### 2.2 评估结果

| 维度 | Zig 0.16.0 | Zig 0.15.2 |
|------|------------|------------|
| `solana-program-sdk-zig` native test | ✅ 10/10 PASS | ✅ 10/10 PASS |
| `bpfel-freestanding` 编译（bitcode 生成） | ✅ PASS | ✅ PASS |
| `sbpf-linker` 链接 | ⚠️ 依赖 LLVM lib 路径修复 | ⚠️ 依赖 LLVM lib 路径修复 |
| build.zig API | `b.addLibrary(.dynamic)` | `b.addSharedLibrary()` |

### 2.3 结论
- zignocchio 的 `bpfel-freestanding` 编译在 Zig 0.15.2 与 0.16.0 上均可正常生成 bitcode。
- `sbpf-linker` 的链接步骤与 Zig 版本无关（它消费 LLVM bitcode）。
- 建议 Phase 4 保持 Zig 0.16.0 主基线不变；如有需要，对 `solana-program-sdk-zig` 做 build API shim 兼容即可。

## 3. Host / Arch 支持矩阵（D-05）

### 3.1 测试方法
1. 安装 `sbpf-linker`（`cargo install sbpf-linker --locked`）
2. 修复 LLVM shared lib 路径（Debian/Ubuntu 默认路径与 `aya-rustc-llvm-proxy` 期望路径不一致）：
   ```bash
   mkdir -p /usr/local/cargo/lib
   ln -s /usr/lib/x86_64-linux-gnu/libLLVM-19.so /usr/local/cargo/lib/libLLVM.so
   # aarch64 对应路径：/usr/lib/aarch64-linux-gnu/libLLVM-19.so
   ```
3. 运行链接命令：
   ```bash
   sbpf-linker --cpu v2 --llvm-args=-bpf-stack-size=4096 \
     --export entrypoint -o output.so entrypoint.bc
   ```

### 3.2 实测结果

| Host / Arch | sbpf-linker | 修复方式 | 产物验证 | 计分状态 |
|-------------|-------------|----------|----------|----------|
| `linux-x86_64` | **PASS** | LLVM lib symlink | eBPF ELF (3,320 bytes, Machine=Linux BPF) | **canonical scoring** |
| `linux-aarch64` | **PASS** | LLVM lib symlink | eBPF ELF | usable, non-canonical |
| `darwin-aarch64` | **FAIL** | 无 | `_LLVMInitializeBPFTarget` panic | non-scoring / dev-only |

### 3.3 根因说明
- **Linux (x86_64/aarch64)**：崩溃原因是 `aya-rustc-llvm-proxy` 在默认 Debian 安装中找不到 `libLLVM.so`；创建 symlink 后链接成功。
- **macOS (aarch64)**：`_LLVMInitializeBPFTarget` 在运行时 panic，符号存在但初始化代码路径在 Darwin 上有平台级缺陷；当前无已知修复方式。

## 4. Linker 限制与已知风险

| 风险项 | 当前状态 | 缓解措施 |
|--------|----------|----------|
| `sbpf-linker` 需 LLVM lib symlink | 已知，已记录 | CI/文档中声明前置步骤 |
| `.rodata.cst32` / ELF 体积 | 未触发 | 持续监控，必要时拆 `no_base58` 开关 |
| `sbpf-linker` darwin 不支持 | 已知平台限制 | 开发期用 Linux 容器/CI 做 SBF 编译 |

## 5. Decision

1. **Canonical scoring host**：`linux-x86_64`（D-05 落盘）。
2. **Zig 版本基线**：保持 0.16.0，zignocchio bitcode 生成不受版本影响（D-01 落盘）。
3. **`darwin-aarch64`**：标记为 `sbpf-linker` 已知平台限制，仅用于 native dev / non-scoring（D-05 落盘）。
4. **Bootstrap 状态**：在 `#96` localnet smoke 通过前，仍保持 `controlled fallback candidate`；若 `linux-x86_64` compile + smoke 均 reviewer 签收，则按 `#99` 规则永久排除。

## 6. Evidence Commands

```bash
# Zig version
$ zig version
0.16.0

# sbpf-linker version
$ sbpf-linker --version
sbpf-linker 0.1.8

# Freestanding compile (Zig 0.16.0)
$ zig build-obj -target bpfel-freestanding src/solana/core/pubkey.zig
# exit 0

# Link (linux-x86_64, after LLVM symlink fix)
$ sbpf-linker --cpu v2 --llvm-args=-bpf-stack-size=4096 \
    --export entrypoint -o output.so entrypoint.bc
# exit 0, output.so: ELF 64-bit LSB shared object, eBPF, Machine: Linux BPF
```
