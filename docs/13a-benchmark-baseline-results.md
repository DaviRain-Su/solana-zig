# Benchmark Baseline Results

**Template Date**: 2026-04-16
**Purpose**: 记录 Product Phase 1 的第一版 benchmark 实际结果，并为后续回归对比提供固定格式。

> 本文是 `docs/13-benchmark-baseline-spec.md` 的结果模板，不替代 benchmark 规范本身。
>
> 使用方式：每次形成一版可比较结果时，复制本模板中的"Run Record"节并补充真实数据。

---

## Run 1 — Phase 1 Baseline (First Real Record)

### 1. Run Record

- Run ID: `2026-04-16/a771c6d/small`
- Commit: `a771c6d`
- Date: `2026-04-16`
- Operator: `@CC (automated benchmark harness)`
- Host / CPU: Apple Silicon (arm64)
- OS: Darwin 25.3.0
- Zig Version: `0.16.0`
- Target Triple: `aarch64-macos` (native)
- Optimize Mode: `ReleaseFast`
- Notes: 10,000 iterations per op, 100 warmup iterations. Using `page_allocator` (not arena). Timing via `mach_absolute_time`.

### 2. Input Profiles Used

| Profile | Description | Notes |
|---|---|---|
| `small` | 32-byte pubkey for base58; value 12345 for shortvec | Fixed byte patterns (0x0A×32) |
| `small` | 1 instruction, 2 accounts, 8-byte payload | Legacy message compile+serialize |
| `phase1-realistic` | 1 instruction, 3 accounts (1 via ALT), 8-byte payload | v0 message with AddressLookupTable |

### 3. Result Table

| op | profile | iterations | total time | avg/op | notes |
|---|---|---:|---:|---:|---|
| base58 encode | `small` | 10,000 | 59,495 µs | 5,949 ns | 32-byte input → ~44 char output |
| base58 decode | `small` | 10,000 | 48,849 µs | 4,884 ns | ~44 char input → 32 bytes |
| shortvec encode | `small` | 10,000 | 17,333 µs | 1,733 ns | value=12345, alloc-based |
| shortvec decode | `small` | 10,000 | 6 µs | <1 ns | value=12345, no-alloc (inline) |
| legacy msg compile+serialize | `small` | 10,000 | 157,178 µs | 15,717 ns | 1 ix, 2 accounts |
| legacy msg deserialize | `small` | 10,000 | 66,106 µs | 6,610 ns | from serialized bytes |
| v0 msg compile+serialize | `phase1-realistic` | 10,000 | 210,683 µs | 21,068 ns | 1 ix, 3 accounts, 1 ALT |
| v0 msg deserialize | `phase1-realistic` | 10,000 | 121,978 µs | 12,197 ns | from serialized bytes |
| tx compile+sign+serialize | `small` | 10,000 | 580,725 µs | 58,072 ns | legacy, 1 signer (Ed25519) |
| tx deserialize | `small` | 10,000 | 83,199 µs | 8,319 ns | from serialized bytes |
| ed25519 sign | `small` | 10,000 | 356,365 µs | 35,636 ns | message bytes ~100 bytes |
| ed25519 verify | `small` | 10,000 | 405,812 µs | 40,581 ns | message bytes ~100 bytes |

### 4. Artifacts

- Raw results file: N/A (stdout capture above)
- Supporting harness: `src/benchmark.zig` (build via `zig build bench`)
- Related implementation log entry: `docs/06-implementation-log.md` (pending update)

### 5. Comparison Notes

- Compared against previous run: none (first baseline)
- Significant regression detected: N/A
- Observations:
  - Ed25519 sign (~36 µs) and verify (~41 µs) dominate tx pipeline cost
  - base58 encode/decode ~5-6 µs per pubkey (acceptable for client use)
  - shortvec decode is essentially free (no alloc, inline parse)
  - v0 message compile ~33% slower than legacy due to ALT processing

### 6. Phase 3 Extension Hook

当进入 Product Phase 3 的"vs Rust SDK"性能对比阶段时，可在本文基础上追加：
- Rust baseline 环境
- Rust command / harness
- 方法一致性说明
- 差异解释

---

## Run 2 — Phase 3 Batch 4 (Signers + C ABI Baseline)

### 1. Run Record

- Run ID: `2026-04-17/bce967d/small`
- Commit: `bce967d`
- Date: `2026-04-17`
- Operator: `@codex_5_3`
- Host / CPU: Apple Silicon (arm64)
- OS: Darwin 25.3.0
- Zig Version: `0.16.0`
- Target Triple: `aarch64-macos` (native)
- Optimize Mode: `ReleaseFast`
- Notes: 基于 Batch 4 canonical 输入，扩展 signers / C ABI 两项基线。

### 2. Result Table

| op | profile | iterations | total time | avg/op | throughput | notes |
|---|---|---:|---:|---:|---:|---|
| signer_in_memory_sign | `small` | 10,000 | 362,831 us | 36,283 ns | 27,561 ops/s | 对应 `BENCH|signer_in_memory_sign|small|10000|362831|36283|27561` |
| cabi_pubkey_to_base58 | `small` | 10,000 | 12,138 us | 1,213 ns | 823,858 ops/s | 对应 `BENCH|cabi_pubkey_to_base58|small|10000|12138|1213|823858` |

### 3. Canonical

- isolated worktree: `/tmp/solana-zig-p3d81-2c8eca2`
- commit: `bce967d`
- `git status --short`: clean
- `zig build test --summary all`: `208/208 tests passed`

### 4. Verdict Input Mapping

- Batch 4 benchmark 扩展输入：已满足 `G-P3D-04`。
- strict exception model 输入：仍存在 `partial_exception` + `accepted exception path`。
- 当前结论：Batch 4 维持 `final: 有条件发布`，不可升级到 `可发布`。

---

## Run 3 — Phase 3 Batch 5 (Rust Baseline Comparison)

### 1. Run Record

- Run ID: `2026-04-17/p3e87-rust-baseline/small`
- Commit: `b71a899`（harness source；`9f903e5` 为 reviewer package docs sync）
- Date: `2026-04-17`
- Operator: `@codex_5_3`
- Host / CPU: Apple Silicon (arm64)
- OS: Darwin 25.3.0
- Zig Version: `0.16.0`
- Rust Version: `rustc 1.89.0`
- Target Triple: `aarch64-macos` (native)
- Optimize Mode: `ReleaseFast` (Zig) / `--release` (Rust)
- Notes: Rust benchmark harness located at `scripts/oracle/rust_benchmark.rs`, 10,000 iterations.

### 2. Result Table (Rust)

| op | profile | iterations | total time | avg/op | throughput | notes |
|---|---|---:|---:|---:|---:|---|
| rust_signer_sign | `small` | 10,000 | 108,370 us | 10,837 ns | 92,276 ops/s | `BENCH\|rust_signer_sign\|small\|10000\|108370\|10837\|92276` |
| rust_pubkey_to_base58 | `small` | 10,000 | 833 us | 83 ns | 12,004,801 ops/s | `BENCH\|rust_pubkey_to_base58\|small\|10000\|833\|83\|12004801` |

### 3. Zig vs Rust Delta (same host, same iteration scale)

| op | Zig avg/op | Rust avg/op | Delta |
|---|---:|---:|---:|
| signer sign | 36,283 ns (`Run 2`) | 10,837 ns | Zig ~3.35x slower |
| pubkey->base58 | 1,213 ns (`Run 2`, C ABI path) | 83 ns | Zig ~14.61x slower |

### 4. Batch 5 Verdict Input Mapping

- `#87 / G-P3E-04` 的 Rust baseline 输入已补齐；
- 与 `#84` strict exception 输入合并后，当前 aggregate 输入仍为：
  - `requestAirdrop = partial_exception`
  - `getAddressLookupTable = accepted_exception_path`
- 因仍存在 open exceptions，Batch 5 / Phase 3 aggregate 暂不满足升级到 `可发布` 的条件。

---

## Run 4 — encodeToBuf Zero-Allocation Optimization

### 1. Run Record

- Run ID: `2026-04-17/encodeToBuf-opt/small`
- Commit: current HEAD
- Date: `2026-04-17`
- Operator: `@Kimi`
- Host / CPU: Apple Silicon (arm64)
- OS: Darwin 25.3.0
- Zig Version: `0.16.0`
- Target Triple: `aarch64-macos` (native)
- Optimize Mode: `ReleaseFast`
- Notes: 添加 `base58.encodeToBuf` 栈缓冲区版本，消除 `toBase58Alloc` 的堆分配开销。

### 2. Result Table (Selected)

| op | profile | iterations | total time | avg/op | throughput | notes |
|---|---|---:|---:|---:|---:|---|
| pubkey_base58_encode | `small` | 10,000 | 49,872 µs | 4,987 ns | 200,513 ops/s | `toBase58Alloc` (heap allocation, generic algorithm) |
| pubkey_to_base58_buf | `small` | 10,000 | 500 µs | **50 ns** | **20,000,000 ops/s** | `toBase58Buf` (zero-allocation + five8 fast path for 32B) |
| pubkey_to_base58_fast | `small` | 10,000 | 500 µs | **50 ns** | **20,000,000 ops/s** | Direct `base58_fast.encode32` call |
| cabi_pubkey_to_base58 | `small` | 10,000 | 526 µs | **52 ns** | **19,011,406 ops/s** | C ABI wrapper (now also routes 32B through `base58_fast`) |

### 3. Delta Summary

| comparison | Zig | Rust bs58 | Delta |
|---|---:|---:|---:|
| Native fast path | 50 ns | ~83 ns | **Zig ~1.66x faster** |
| C ABI path | 52 ns | ~83 ns | **Zig ~1.60x faster** |
| vs old alloc path | 4,987 ns | — | **~100x faster** |

### 4. Observations

- 通过引入 five8/firedancer 查表算法（`base58_fast.zig`），32-byte pubkey→base58 从 ~5.0 µs 骤降至 **~50 ns**，不仅超越了之前的零分配路径，也**显著超越了同机 Rust `bs58` 的 ~83 ns**。
- 核心优化点：预计算 `ENC_TABLE` 将逐位大数除法（O(N²)）替换为查表+乘加累加（O(N)）；C ABI 层也复用了该 fast path，仅多一次极小的 `dupe` 复制。
- 当前瓶颈已不再是 base58 编码本身，而是可能的：**(a) 64-byte signature 的 decode 路径尚未优化；(b) Ed25519 签名/验证仍使用纯 Zig 实现，与 Rust 的 SIMD/ASM 库仍有 ~3x 差距**。
