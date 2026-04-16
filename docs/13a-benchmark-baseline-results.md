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
