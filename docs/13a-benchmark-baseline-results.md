# Benchmark Baseline Results

**Template Date**: 2026-04-16
**Purpose**: 记录 Product Phase 1 的第一版 benchmark 实际结果，并为后续回归对比提供固定格式。

> 本文是 `docs/13-benchmark-baseline-spec.md` 的结果模板，不替代 benchmark 规范本身。
>
> 使用方式：每次形成一版可比较结果时，复制本模板中的“Run Record”节并补充真实数据。

## 1. Run Record

- Run ID: `<yyyy-mm-dd>/<short-sha>/<profile-name>`
- Commit: `<sha>`
- Date: `<yyyy-mm-dd hh:mm:ss tz>`
- Operator: `<name or local-machine-label>`
- Host / CPU: `<machine>`
- OS: `<os version>`
- Zig Version: `<zig version>`
- Target Triple: `<target>`
- Optimize Mode: `<Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>`
- Notes: `<special conditions / warmup / environment limits>`

## 2. Input Profiles Used

| Profile | Description | Notes |
|---|---|---|
| `small` | 单 instruction、少量账户 | `<fill>` |
| `medium` | 多 instruction、多账户 | `<fill>` |
| `phase1-realistic` | 接近当前 Phase 1 目标交易（建议含 v0 + ALT） | `<fill>` |

## 3. Result Table

| op | profile | iterations | total time | avg/op | notes |
|---|---|---:|---:|---:|---|
| base58 encode | `small` | `<n>` | `<time>` | `<time>` | `<fill>` |
| base58 decode | `small` | `<n>` | `<time>` | `<time>` | `<fill>` |
| shortvec encode | `small` | `<n>` | `<time>` | `<time>` | `<fill>` |
| shortvec decode | `small` | `<n>` | `<time>` | `<time>` | `<fill>` |
| legacy message serialize | `medium` | `<n>` | `<time>` | `<time>` | `<fill>` |
| legacy message deserialize | `medium` | `<n>` | `<time>` | `<time>` | `<fill>` |
| v0 message serialize | `phase1-realistic` | `<n>` | `<time>` | `<time>` | `<fill>` |
| v0 message deserialize | `phase1-realistic` | `<n>` | `<time>` | `<time>` | `<fill>` |
| tx serialize | `phase1-realistic` | `<n>` | `<time>` | `<time>` | `<fill>` |
| tx deserialize | `phase1-realistic` | `<n>` | `<time>` | `<time>` | `<fill>` |
| tx sign | `phase1-realistic` | `<n>` | `<time>` | `<time>` | `<fill>` |
| tx verify | `phase1-realistic` | `<n>` | `<time>` | `<time>` | `<fill>` |

## 4. Artifacts

- Raw results file: `<artifacts/benchmarks/... or N/A>`
- Supporting harness / command: `<command or script path>`
- Related implementation log entry: `docs/06-implementation-log.md` `<section>`

## 5. Comparison Notes

- Compared against previous run: `<run id or none>`
- Significant regression detected: `<yes/no>`
- If yes, review required in: `docs/07-review-report.md` `<section or TODO>`

## 6. Phase 3 Extension Hook

当进入 Product Phase 3 的“vs Rust SDK”性能对比阶段时，可在本文基础上追加：
- Rust baseline 环境
- Rust command / harness
- 方法一致性说明
- 差异解释
