# Docs Index

本目录按“路线 -> 规格 -> 执行 -> 治理 -> 结果模板”组织。

## 1. Product Roadmap / Scope

- `00-roadmap.md`：顶层产品路线图
- `01-prd.md`：Product Phase 1 PRD
- `02-architecture.md`：整体架构与依赖方向
- `03-technical-spec.md`：Phase 1 主技术规格

## 2. Future / Sub Specs

- `03a-interfaces-spec.md`：interfaces 子规格
- `03b-signers-spec.md`：signers 子规格
- `03c-rpc-extended-spec.md`：扩展 RPC / typed parse 子规格
- `03d-cabi-spec.md`：C ABI 子规格

## 3. Planning / Test / Execution

- `04-task-breakdown.md`：任务分解与 backlog
- `05-test-spec.md`：测试规格与 gate
- `10-coverage-matrix.md`：能力覆盖矩阵
- `11-phase1-closeout-checklist.md`：Phase 1 收口判定
- `15-phase1-execution-matrix.md`：Phase 1 执行矩阵

## 4. Evidence / Result Templates

- `12-oracle-vector-expansion-plan.md`：oracle 向量计划
- `13-benchmark-baseline-spec.md`：benchmark 规范
- `13a-benchmark-baseline-results.md`：benchmark 结果模板
- `14-devnet-e2e-acceptance.md`：Devnet 验收说明
- `14a-devnet-e2e-run-log.md`：Devnet 运行记录模板

## 5. Governance / Review

- `06-implementation-log.md`：实施日志
- `07-review-report.md`：审查报告
- `08-evolution.md`：演进治理与退出条件
- `09-doc-consistency-checklist.md`：文档一致性审查
- `adr/README.md`：ADR 索引与模板

## 6. User / Consumer Notes

- `16-consumer-profiles-and-security-notes.md`：目标用户、FFI / signer / 安全约束说明
- `17-quickstart-and-api-examples.md`：面向消费者的 Quickstart 与 API 最小示例
- `18-surfpool-e2e-contract.md`：K3 本地 E2E contract（AC-01~AC-07 单一真源）
- `19-phase2-planning.md`：Product Phase 2 第一批冻结记录（范围/DoD/依赖/放行条件）
- `20-phase2-batch2-planning.md`：Product Phase 2 第二批规划（RPC Batch B + Durable Nonce + ComputeBudget）
- `21-phase2-batch3-planning.md`：Product Phase 2 第三批规划（getTokenAccountsByOwner + WS re-stabilize/re-expose + Nonce/live 深化）
- `22-phase2-batch4-planning.md`：Product Phase 2 第四批规划（Token Accounts 深化 + WS production hardening + 发布前清单）
- `23-release-readiness-checklist.md`：发布前技术清单（provisional/final verdict 单一真源）
- `24-phase2-batch5-planning.md`：Product Phase 2 第五批规划（SPL Token 指令集深化 + WS 生产可观测性 + 发布自动化）
- `25-batch5-release-readiness.md`：Batch 5 专属发布前清单（不覆盖 Batch 4 final artifact）
- `26-phase2-batch6-planning.md`：Product Phase 2 第六批规划（SPL Token 交易流 + WS 可恢复性深化 + 发布流水线固化）
- `27-batch6-release-readiness.md`：Batch 6 专属发布前清单（不覆盖 Batch 5 final artifact）
- `28-phase2-closeout-readiness.md`：Phase 2 跨批次总收口专属产物（不覆盖 Batch 5/6 batch-level artifacts）
- `29-phase2-batch7-planning.md`：Product Phase 2 第七批规划（Batch B landing + smoke 收敛 + Phase 2 closeout artifact）
- `30-phase3-batch1-planning.md`：Product Phase 3 第一批规划（System/Token interfaces + exception 收敛）
- `31-phase3-batch1-release-readiness.md`：Phase 3 Batch 1 专属发布就绪清单（不覆盖 phase-level artifact）
- `32-phase3-batch2-planning.md`：Product Phase 3 第二批规划（ATA helper + token-2022/memo/stake + exception 收敛）
- `33-phase3-batch2-release-readiness.md`：Phase 3 Batch 2 专属发布就绪清单
- `34-phase3-batch3-planning.md`：Product Phase 3 第三批规划（token-2022 + stake delegate + exception 收敛与判定升级评估）
- `35-phase3-batch3-release-readiness.md`：Phase 3 Batch 3 专属发布就绪清单
- `36-phase3-batch4-planning.md`：Product Phase 3 第四批规划（signers 抽象 + C ABI 最小闭环 + benchmark 扩展 + verdict 升级评估）
- `37-phase3-batch4-release-readiness.md`：Phase 3 Batch 4 专属发布就绪清单
- `38-phase3-batch5-planning.md`：Product Phase 3 第五批规划（exception 最终收敛 + C ABI RPC/live 对齐 + stake create/negative-path + Rust 对比 + Phase 3 aggregate closeout）
- `39-phase3-batch5-release-readiness.md`：Phase 3 Batch 5 专属发布就绪清单（包含 Phase 3 aggregate verdict）
- `40-phase4-planning.md`：Phase 4 规划（链上程序支持 — Zig→SBF, scope / batch / gate / 决策项）
- `41-phase4-release-readiness.md`：Phase 4 发布就绪清单（gate 状态 / decision records / CU baseline / aggregate verdict）
