# Benchmark Baseline Spec

**Date**: 2026-04-16

> 本文定义 Product Phase 1 收口所需的最小 benchmark 基线，不要求“快过 Rust”，但要求**可重复、可比较、可留档**。

## 1. Goal

建立第一版性能基线，回答三个问题：
1. 当前主要序列化/反序列化路径大概在什么量级
2. 后续优化是否真的带来收益
3. 是否有明显退化需要进入 review

## 2. Scope

Phase 1 最低 benchmark 集合建议覆盖：
- base58 encode / decode
- shortvec encode / decode
- legacy message serialize / deserialize
- v0 message serialize / deserialize
- versioned transaction serialize / deserialize
- transaction sign / verify

## 3. Benchmark Input Sets

输入集应分为：
- `small`
- `medium`
- `phase1-realistic`

示例：
- small：单 instruction，少量账户
- medium：多 instruction，多账户
- realistic：接近真实 Phase 1 目标交易（含 v0 + ALT）

## 4. Output Metrics

至少记录：
- operation name
- input profile
- iterations
- total time
- avg/op
- target triple
- optimize mode
- Zig version
- commit sha
- execution date

## 5. Record Format

推荐以 markdown 表格或 json 双份留档：

```md
| op | profile | iterations | avg/op | notes |
|---|---|---:|---:|---|
```

如果后续建立脚本化 benchmark，可把原始数据落到：
- `artifacts/benchmarks/*.json`
- 汇总写入 `docs/13` 的结果节或独立结果文件

## 6. Execution Guidance

- 首次只需建立一组稳定基线
- 每次大改序列化或签名路径后再更新
- 若设备或 optimize mode 不同，必须明确标注，不可混比

## 7. Review Rule

当前阶段 benchmark 主要用于观察，不作为硬性 fail gate。
但以下情况应触发 review：
- 同 profile 退化超过显著阈值（建议先用 15% 作为人工审查线）
- 新增大量分配或明显放大尾延迟
- serialize/deserialize 行为变化与 oracle 差异一起出现

## 8. Suggested Landing Plan

1. 先手工定义输入 profile
2. 建最小 benchmark harness
3. 在本地记录第一版基线
4. 将结果摘要写入 `docs/06` 或单独 benchmark 结果文件
5. 后续再考虑自动化

## 9. Task Mapping

| Benchmark 项 | 关联任务 |
|---|---|
| base58 / shortvec | `T4-02`, `T4-03` |
| legacy/v0 message | `T4-06`, `T4-07` |
| tx serialize/sign/verify | `T4-08`, `T4-09` |
| Phase 1 closeout baseline | `T4-16` |

## 10. Acceptance Criteria

- 至少一版 benchmark 基线已记录
- 至少覆盖 message / tx 主路径
- 记录中包含 commit、环境、optimize mode
- 结果可被后续版本复跑对比
