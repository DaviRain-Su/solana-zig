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

## 2026-04-16 第六次增量记录（Phase 1 收口文档补强）

### 输入
- 需要继续补齐 Product Phase 1 的收口文档，尤其是 oracle 向量扩展计划、benchmark 基线规范、Devnet E2E 验收说明。
- 需要把 coverage matrix 进一步转化为更具执行性的 closeout 矩阵。

### 输出
- 新增 `docs/11-phase1-closeout-checklist.md`，定义 Phase 1 closeout 的统一判定门槛。
- 新增 `docs/12-oracle-vector-expansion-plan.md`，定义最小 oracle 向量集合、结构演进与生成流程。
- 新增 `docs/13-benchmark-baseline-spec.md`，定义 benchmark 基线范围、记录格式与 review 规则。
- 新增 `docs/14-devnet-e2e-acceptance.md`，定义 Devnet E2E 的验收目标、留档要求与执行说明。
- 新增 `docs/15-phase1-execution-matrix.md`，将 `partial` 能力项映射到 T4 任务、blocker、证据与 closeout 条件。
- 新增 `scripts/devnet/phase1_acceptance.sh` 作为当前 Devnet 验收包装脚本。
- `README.md`、`docs/00`、`docs/08`、`docs/09`、`docs/10` 同步接入新文档引用与维护规则。

### 风险
- 当前 Devnet 验收脚本仍是 Phase 1 包装层，后续若引入专门 E2E harness，需要继续升级脚本行为与文档说明。
- benchmark 规范已建立，但尚未落第一版真实结果。

### 验证
- 文档链已补齐：`README -> 00 -> 10 -> 11/12/13/14/15`。

## 2026-04-16 第七次增量记录（吸收文档 review 反馈）

### 输入
- 针对当前文档集收到 5 条高置信度 review 反馈：依赖策略口径、typed parse 的 phase 归属、Phase 3 性能对比报告闭环、Phase 2 任务先于设计锁定、README 收口范围表述。

### 输出
- `docs/00` 的依赖策略改为统一口径：优先 Zig std，默认不引入外部依赖；若确有必要，仅允许最小外部依赖并需 ADR。
- 明确 typed parse 分层：Phase 1 只要求当前 5 个高频 RPC 的最小 typed schema 收敛；更广泛 typed parse 扩展归入 Phase 2。
- `docs/03c` 锁定 `getTransaction` 第一版采用 `json` encoding 基线，并锁定 Durable Nonce 指令构造归属 `interfaces/system`。
- `docs/04/05/08/10/13` 补上 Phase 3 性能对比报告的任务、测试/证据和退出条件闭环。
- `README.md` 当前剩余工作补充 typed RPC parse 收紧。

### 风险
- 以上修订收紧了未来实现边界；若后续实现发现 `getTransaction(json)` 或 Nonce 归属需调整，应通过 ADR 明确变更。

### 验证
- 文档中的 phase/任务/退出条件已按 review 反馈重新对齐。

## 2026-04-16 第八次增量记录（文档收口小修）

### 输入
- 再次复核文档后，发现仍有几处适合进入实现收口前的小修：`docs/11` blocker 表述偏旧、`docs/09` 对 Phase 3 的待补文档表述过宽、`docs/14` 尚可更明确区分包装脚本与真实 E2E harness、`docs/15` 缺少证据落点列、`docs/10` 缺少 review 元数据。

### 输出
- `docs/09` 改为更准确地强调：Phase 3 仍缺 C ABI 边界 / 所有权 / 错误模型说明，以及目标用户与安全约束收敛。
- `docs/10` 新增 `Last reviewed`、`Docs baseline commit` 和“可能落后于未提交代码”的说明。
- `docs/11` 将 blocker 从“缺模板”收紧为“缺真实 benchmark 记录 / 缺真实 E2E harness / execution matrix 尚未收口”。
- `docs/14` 明确写出：包装脚本通过不等于真实 Devnet E2E 完成。
- `docs/15` 新增“证据落点”列，明确测试、artifact 与文档落点。

### 风险
- `docs/10` 当前基于最近一次文档同步基线维护；若工作区代码继续演进而未同步文档，矩阵仍可能再次过期。

### 验证
- 文档收口信号、证据落点和 wrapper/harness 边界表达已更贴近当前仓库真实状态。

## 2026-04-16 第九次增量记录（parser hardening 与 Devnet 文档降级对齐）

### 输入
- 收到代码 review：`Message.deserialize` 的错误清理可能释放未初始化内存，`VersionedTransaction.verifySignatures` 可被畸形 header 触发越界，RPC malformed success response 存在 parsed JSON 泄漏，`build.zig.zon` 未打包 `testdata/`。
- 同时发现 PRD / 测试规格 / Devnet 验收文档把当前包装脚本表述得过于接近“真实 Devnet E2E”。

### 输出
- `src/solana/tx/message.zig` 增加 header 一致性校验、静态账户上限保护，并把 instruction / lookup 反序列化改为按“已初始化元素”清理，避免错误路径 free 未初始化内存。
- `src/solana/tx/transaction.zig` 在 `initUnsigned/sign/verifySignatures` 中显式校验 message header，阻断畸形交易导致的越界访问。
- `src/solana/rpc/client.zig` 为 `getAccountInfo` 与 `simulateTransaction` 增加 `errdefer` 清理，并补充 malformed success response 测试。
- `build.zig.zon` 把 `testdata` 纳入 package paths，修复 `compat.oracle_vector` 的打包缺口。
- `docs/01`、`docs/05`、`docs/11`、`docs/14`、`docs/15` 与 `README.md` 同步改为：当前只有包装脚本 / 外部 harness 验收路径，不等同于真实 in-tree Devnet E2E。

### 风险
- Devnet 真正的 `construct -> sign -> simulate -> send` harness 仍未实现，Phase 1 closeout 不能把当前脚本误报为完整 E2E 证据。
- `getAccountInfo` / `simulateTransaction` 仍主要返回 `OwnedJson`，typed parse 收敛仍是后续收口项。

### 验证
- 新增 parser hardening / malformed response 回归测试。
- 计划执行：`zig build test` + package packaging smoke test。

### 风险
- 当前变更主要是治理与命名统一，不直接提升实现覆盖率。
- 如果后续 roadmap 再调整，仍需同步回写 `docs/01/04/05/08`。

### 验证
- 文档链路已按统一命名复核：`00 -> 01 -> 04 -> 05 -> 08 -> README`。
