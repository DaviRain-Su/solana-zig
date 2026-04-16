# Phase 6 - Implementation Log

## Completed
- 建立单仓多模块结构
- 实现核心类型与编解码
- 实现 Message/Transaction 编译与序列化
- 实现 HTTP transport 与核心 RPC 方法
- 增加 oracle 向量与测试骨架

## Notes
- 先以可验证功能为目标，后续再扩展 RPC 方法覆盖率

## 2026-04-16 增量记录

### 输入
- 完成 Phase 3 规格重写（字节契约、接口契约、错误模型、状态机、边界场景）。
- 完成 Phase 4 任务拆解（T4-01 ~ T4-16，<=4h，含依赖与 DoD）。
- 完成 Phase 5 测试规格（L1-L5 测试层级、门控与用例矩阵）。

### 输出
- `docs/03-technical-spec.md` 已升级为可执行规格。
- `docs/04-task-breakdown.md` 已升级为任务级执行清单。
- `docs/05-test-spec.md` 已升级为测试执行清单。

### 风险
- 当前 RPC 仍以动态 JSON 解析为主，typed schema 尚未收紧。
- v0 lookup 的正/逆向测试覆盖仍需在 T4-06/T4-07 落地。

### 下一步
- 进入 Phase 6 承诺型实现，按顺序执行：`T4-01 -> T4-05`（M1 核心稳定）。

## 2026-04-16 第二次增量记录

### 输入
- 根据审查意见完成“第三项”：为 `RpcClient` 引入可替换 transport 抽象（用于 mock）。
- 同步修复 v0 lookup 冲突语义与重复错误类型定义。

### 输出
- 新增 `src/solana/rpc/transport.zig`，提供 `Transport` 接口与默认 `HttpTransport` 适配器。
- `RpcClient` 新增 `initWithTransport(...)`，支持注入 fake transport。
- 新增 3 个 RPC 注入式测试（happy path / rpc_error / transport error）。
- `Message.compileV0` 调整为：静态 key 冲突时跳过注入；动态重复时报 `DuplicateLookupKey`。

### 验证
- `zig build test` 通过。

## 2026-04-16 第三次增量记录（文档对齐）

### 输入
- PRD 扩展为“当前可执行 + 全量实现路线”双轨描述。

### 输出
- `docs/02` 升级为可扩展架构文档（新增 interfaces/signers 分层）。
- `docs/04` 增补后续任务分解（全量实现后续任务）。
- `docs/05` 增补扩展阶段测试规划。
- `docs/07` 升级为结构化审查报告（含 severity 与残余风险）。
- `docs/08` 升级为演进治理文档（路线图 + ADR 规则 + 退出条件）。
- `docs/03` 增加全量实现的子规格拆分规则。

## 2026-04-16 第四次增量记录（命名与路线对齐）

### 输入
- 审查发现 `Phase / Stage / Track / Milestone` 在 README、路线图、PRD、任务与测试文档中混用，存在产品阶段与文档序号混淆。
- 后续 backlog 与顶层路线图在 phase 映射上存在不一致（尤其是 interfaces/signers/C ABI 与扩展 RPC/Websocket 的归属）。

### 输出
- 统一命名：`Product Phase` 仅用于 `docs/00-roadmap.md` 的产品路线图；`M1~M3` 仅用于当前 Product Phase 1 执行里程碑；`docs/01-08` 标题中的 `Phase` 明确为文档生命周期序号。
- `README.md` 改为与 Product Phase 1~4 一致的外部表述。
- `docs/01` 重写里程碑映射：当前 PRD 只承诺 Product Phase 1，后续能力改为引用顶层路线图。
- `docs/02` 收紧 `interfaces` 与 `rpc` 的边界，禁止默认耦合。
- `docs/04` 将当前承诺任务限制在 Product Phase 1 / M1-M3，并把后续内容改为 Product Phase 2/3 backlog。
- `docs/05` 将扩展测试拆成 Product Phase 2（RPC/Websocket/Nonce）与 Product Phase 3（interfaces/signers/C ABI）。
- `docs/07/08` 同步改为以 Product Phase 1~4 为主线表达审查与演进。
- 新增 `docs/09-doc-consistency-checklist.md`，沉淀本次审查发现与维护规则。

## 2026-04-16 第五次增量记录（覆盖矩阵与子规格落地）

### 输入
- 在命名统一后，仍缺少“能力状态全景图”和后续 Phase 2/3 的实体子规格文件。
- `docs/03` 已声明 `03a/03b/03c`，但此前尚无对应落地文件。

### 输出
- 新增 `docs/10-coverage-matrix.md`，将 Rust 参考能力、Zig 模块、当前状态、测试/文档映射统一到单一矩阵。
- 新增 `docs/03a-interfaces-spec.md`，沉淀 interfaces 层边界、模块顺序、错误模型与测试映射。
- 新增 `docs/03b-signers-spec.md`，沉淀 signer 抽象、后端适配、敏感数据与测试映射。
- 新增 `docs/03c-rpc-extended-spec.md`，沉淀扩展 RPC、Websocket、typed parse 与 Nonce 工作流约束。
- `README.md`、`docs/00`、`docs/03`、`docs/08` 同步加入对上述文档的引用与维护规则。

### 风险
- coverage matrix 目前仍基于当前代码与文档判断状态，后续实现推进时需要持续回写，避免再次过期。
- 子规格已能承接设计讨论，但仍属于“设计基线”，不是实现完成证明。

### 验证
- 文档引用链已补齐：`README -> 00 -> 03 -> 03a/03b/03c -> 10`。

### 风险
- 当前变更主要是治理与命名统一，不直接提升实现覆盖率。
- 如果后续 roadmap 再调整，仍需同步回写 `docs/01/04/05/08`。

### 验证
- 文档链路已按统一命名复核：`00 -> 01 -> 04 -> 05 -> 08 -> README`。
