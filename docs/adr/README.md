# ADR Index

Architecture Decision Records（ADR）用于记录会影响文档、实现或阶段边界的重要决策。

## 1. When to Write an ADR

当出现以下变化时，建议新增 ADR：
- 兼容策略变化
- 公共接口破坏性变更
- typed parse / encoding / ABI 这种影响较大的设计锁定
- 模块依赖方向调整
- Product Phase 边界变化
- 外部依赖策略变化

## 2. File Naming

建议命名：
- `ADR-0001-short-title.md`
- `ADR-0002-short-title.md`

## 3. Template

- 模板文件：`docs/adr/ADR-template.md`

## 4. Initial Candidate ADRs

根据当前文档，以下决策已经足够重要，后续如需调整应转为 ADR：
- `getTransaction` 第一版采用 `json` baseline
- Phase 1 / Phase 2 typed parse 分层
- Durable Nonce 指令构造归属 `interfaces/system`
- 外部依赖策略：优先 Zig std，例外需最小化并记录
- Phase 3 C ABI 的所有权模型与错误码策略
