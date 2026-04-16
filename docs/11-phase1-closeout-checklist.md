# Phase 1 Closeout Checklist

**Date**: 2026-04-16

> 本文用于定义：**什么时候可以对内/对外宣称 Product Phase 1 已完成收口**。
>
> 它不替代 PRD、任务分解和测试规格，而是把收口判定标准集中起来。

## 1. Closeout Definition

只有当以下四类条件同时满足时，才可宣称 `Product Phase 1 closed out`：

1. **兼容性**：核心离线能力与锁定 Rust 基线的字节/行为兼容证据完整
2. **测试性**：离线门禁稳定，全量关键 public API 有 Happy + Error 覆盖
3. **可展示性**：Devnet E2E 可复现，且流程证据可留档
4. **可追踪性**：coverage / execution / implementation log / review 文档已同步收口

## 2. Required Evidence Packs

### 2.1 Oracle Evidence
- 见：`docs/12-oracle-vector-expansion-plan.md`
- 必须至少包含：
  - 非零 pubkey（含前导零）
  - Keypair sign -> Signature（确定性 seed）
  - legacy message serialize
  - v0 message serialize（含 ALT）
  - versioned transaction serialize

### 2.2 Benchmark Evidence
- 见：`docs/13-benchmark-baseline-spec.md`
- 必须至少记录一版基线结果，不要求达成特定性能阈值，但必须可重复执行与比较

### 2.3 Devnet E2E Evidence
- 见：`docs/14-devnet-e2e-acceptance.md`
- 必须证明最小闭环可复现：
  - 构造
  - 签名
  - 模拟
  - 发送

### 2.4 Execution Evidence
- 见：`docs/15-phase1-execution-matrix.md`
- 所有 `partial` 项必须进入以下两种状态之一：
  - 变为 `done`
  - 被明确降级为“不阻塞 Phase 1 closeout 的已记录例外项”，且需在 `docs/07` 和 `docs/08` 说明原因

## 3. Mandatory Gates

### G-CLOSE-01: Test Gate
- `zig build test` 通过
- 无新增内存泄漏
- 核心路径无已知 blocker

### G-CLOSE-02: Oracle Gate
- `testdata/oracle_vectors.json` 已扩充到 Phase 1 最低集合
- 向量生成/维护流程在文档中可复现

### G-CLOSE-03: RPC Gate
- 当前 5 个高频方法均具备：
  - happy 覆盖
  - rpc_error 覆盖
  - malformed/invalid response 覆盖
- 至少 `LatestBlockhash` / `AccountInfo` 的 typed parse 收敛达到可接受水平

### G-CLOSE-04: v0 / Tx Gate
- v0 compile 正向/失败路径覆盖到位
- versioned transaction 的签名、验签、序列化、反序列化闭环稳定

### G-CLOSE-05: Devnet Gate
- 在配置 `SOLANA_RPC_URL` 时，Devnet E2E 流程可执行
- 产出留档日志、提交哈希、执行时间和结果摘要

### G-CLOSE-06: Documentation Gate
- `docs/06`, `docs/07`, `docs/08`, `docs/10`, `docs/15` 全部同步
- `README.md` 当前状态表述不超出已实现能力

## 4. Current Closeout Blockers (as of 2026-04-16)

- oracle 向量规模不足
- benchmark baseline 尚未形成固定记录模板
- Devnet E2E 尚缺统一验收说明与证据模板
- coverage matrix 中多个 `partial` 项尚未映射为明确收口动作

## 5. Recommended Closeout Order

1. 补 oracle 向量计划与最小集合
2. 补 v0 / tx / rpc partial 项测试覆盖
3. 补 benchmark 基线记录模板
4. 跑 Devnet E2E 验收并留档
5. 更新 execution matrix 与 review report
6. 执行一次 `Phase 1 Closeout Review`

## 6. Closeout Declaration Template

建议在完成收口时使用如下模板写入 `docs/06` 与 PR 描述：

```md
Phase 1 Closeout Declaration
- Commit: <sha>
- Test gate: pass
- Oracle gate: pass
- Benchmark baseline: recorded
- Devnet E2E: pass / gated pass
- Remaining exceptions: <none or list>
- Review reference: docs/07-review-report.md
```
