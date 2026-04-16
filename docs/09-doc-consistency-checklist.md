# Doc Consistency Checklist

**Date**: 2026-04-16

## 1. 审查目标

对 `README.md` 与 `docs/00-08` 的命名、阶段划分、任务归属和测试规划做一致性审查，并将关键冲突收敛为一套统一约定。

## 2. 统一后的命名约定

- **Product Phase**：只表示顶层产品路线图阶段，统一为 `Phase 1 ~ Phase 4`
- **Milestone（M）**：只表示当前 `Product Phase 1` 的执行里程碑，统一为 `M1 ~ M3`
- **文档序号 `docs/01-08`**：只表示文档生命周期顺序，不等于 Product Phase 编号

## 3. 审查发现与处理结果

| ID | 问题 | 影响文件 | 处理结果 |
|---|---|---|---|
| C-01 | `Phase / Stage / Track / Milestone` 混用，产品阶段与文档阶段易混淆 | `README.md`, `docs/00`, `docs/01`, `docs/04`, `docs/05`, `docs/08` | 已统一为 `Product Phase + Milestone + 文档序号` 三层表达 |
| C-02 | `README` 使用 Track A-D，和路线图 Phase 表述不一致 | `README.md`, `docs/00` | 已改为 Product Phase 1~4 |
| C-03 | PRD 中 `M3/M4/M5` 与路线图中的后续 phase 含义冲突 | `docs/01` | 已将未来能力改为引用 `docs/00-roadmap.md`，PRD 仅保留 Phase 1 的 `M1~M3` |
| C-04 | 任务拆解把 interfaces/signers 当作 `M4/M5`，与顶层路线图不一致 | `docs/04` | 已改为 Product Phase 2/3 backlog，当前承诺仅保留 Phase 1 / M1-M3 |
| C-05 | 测试规格未覆盖路线图中的 Product Phase 2（扩展 RPC/Websocket/Nonce） | `docs/05` | 已拆分为 L6（Phase 2）和 L7（Phase 3） |
| C-06 | 演进文档使用 Stage A-D，和 roadmap 不同 | `docs/08` | 已改为 Product Phase 1~4 |
| C-07 | `interfaces` 默认可依赖 `rpc`，边界容易膨胀 | `docs/02` | 已收紧：默认只依赖 `core/tx`，联网 helper 需拆独立模块 |
| C-08 | 审查报告对外状态表述容易超出当前已实现范围 | `docs/07` | 已限制为只能宣称 Product Phase 1 / M1-M3 |

## 4. 仍需持续关注的事项

- [ ] Phase 1 收口项尚未全部实现：oracle 扩充、typed parse 收紧、Devnet E2E、benchmark 基线
- [ ] Product Phase 2 仍需单独补充更细的技术规格（尤其是 Websocket 生命周期与 Nonce 工作流）
- [ ] Product Phase 3 进入前，需持续维护 `docs/03d-cabi-spec.md`，把 C ABI 边界 / 所有权 / 错误模型从模板推进到可执行规格
- [ ] 目标用户仍偏宽；虽已新增 `docs/16-consumer-profiles-and-security-notes.md`，但如进入 C ABI 或硬件钱包场景，仍需进一步收敛目标用户，并补更明确的 NFR 与安全约束

## 5. 本次审查后的建议维护动作

1. 所有 roadmap 变更先改 `docs/00-roadmap.md`
2. 所有当前执行节点变更同步改 `docs/01`, `docs/04`, `docs/05`, `docs/06`, `docs/07`
3. 所有 phase 命名变更必须回写 `README.md`
4. 进入 Product Phase 2 / 3 前，先补对应子规格文件，再开实现任务
5. 能力状态发生变化时，同步更新 `docs/10-coverage-matrix.md`
6. Phase 1 收口信号发生变化时，同步更新 `docs/11-15` 对应文档
