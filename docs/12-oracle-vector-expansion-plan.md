# Oracle Vector Expansion Plan

**Date**: 2026-04-16

> 本文定义 Product Phase 1 收口所需的最小 oracle 向量集合、文件结构演进方向和维护流程。

## 1. Goal

把 `testdata/oracle_vectors.json` 维护为可支撑以下声明的最小证据集，并在此基础上继续扩样本：
- 核心固定长度类型兼容
- 签名行为兼容
- legacy / v0 message 字节兼容
- versioned transaction 字节兼容

> 当前状态：**Phase 1 最低集合已满足**；本文后续更侧重“如何继续扩样本与维护流程”，而不是继续把最低集本身视为 blocker。

## 2. Current Status / Remaining Gap

当前内置向量文件已升级到 `v2` 结构，且 **Phase 1 最低集合已覆盖到**：
- core：`pubkey_*` / `hash_nonzero` / `shortvec_*`
- keypair/signature：固定 seed 签名样本
- message：legacy / v0 最低集合
- transaction：legacy / v0 signed 最低集合

因此：
- **已满足** PRD 中的最低 oracle 指标
- 当前剩余 gap 不再是“最低集合缺失”，而是：
  - 更多边界样本
  - 更多多消息/多 lookup 组合
  - 后续 Rust 基线升级后的 diff 审查与再生成

## 3. Minimum Vector Set for Phase 1

### 3.1 Core
- `pubkey_zero`
- `pubkey_nonzero`
- `pubkey_leading_zero_bytes`
- `hash_nonzero`
- `shortvec_0`
- `shortvec_127`
- `shortvec_128`
- `shortvec_300`
- `shortvec_16384`

### 3.2 Keypair / Signature
- `keypair_seed_32b_case_01`
- `keypair_seed_32b_case_02`
- `signature_for_message_case_01`
- `signature_for_message_case_02`

### 3.3 Message
- `legacy_message_case_simple`
- `legacy_message_case_multi_instruction`
- `v0_message_case_basic_alt`
- `v0_message_case_multiple_lookups`

### 3.4 Transaction
- `versioned_tx_legacy_case_signed`
- `versioned_tx_v0_case_signed`

## 4. Suggested JSON Layout (v2)

建议演进到按能力分组，而不是继续平铺字段：

```json
{
  "core": { ... },
  "keypair": { ... },
  "message": { ... },
  "transaction": { ... }
}
```

推荐字段类型：
- 固定字节：hex
- 可打印地址/签名：base58
- 二进制 blob：hex
- seed：hex
- 说明字段：`notes`

## 5. Generation Workflow

1. 在 `scripts/oracle/generate_vectors.rs` 中固定 Rust crate 版本
2. 用固定 seed / 固定输入生成输出
3. 把结果写入新的 JSON 结构（当前已切到 `v2`；后续继续扩充字段）
4. 在 Zig 侧新增解析与断言
5. 每次 Rust 基线升级时重新生成并做 diff 审查

## 6. Validation Rules

- 所有 seed、message 输入必须固定且可复现
- 向量命名必须稳定，避免“同义不同名”
- 向量必须同时服务于：
  - 代码断言
  - 文档追踪
  - 版本升级 diff

## 7. Task Mapping

| 向量类目 | 对应任务 |
|---|---|
| base58 / shortvec | `T4-02`, `T4-03` |
| pubkey / signature / hash | `T4-04` |
| keypair sign/verify | `T4-05` |
| v0 message | `T4-06`, `T4-07` |
| versioned transaction | `T4-08`, `T4-09` |

## 8. Acceptance Criteria

- 向量文件结构文档化
- Zig 测试可消费上述最小集合
- 至少覆盖 1 组 legacy tx 和 1 组 v0 tx
- 向量增量变更能通过 git diff 清晰审查

### 8.1 Phase 1 Gate Status Snapshot

- Phase 1 最低集合：**已满足**
- 当前后续工作：**非阻塞扩样本与维护流程持续化**

## 9. Open Decisions

- 是否保留旧平铺格式兼容读取，还是直接升级为 v2 结构
- message / transaction blob 是全部存 hex，还是同时存“结构字段 + blob”双份表示
- 是否把 oracle 元信息（Rust crate 版本、生成时间、生成器 commit）写入文件头
