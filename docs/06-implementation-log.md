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

## 2026-04-16 第十次增量记录（public API / ALT 语义 / oracle v2）

### 输入
- 新一轮 review 指出：`Message.DecodeResult` 对外公开类型不可用、v0 lookup 未按 writable/readonly 语义编译、`deserialize` 未校验编译后索引越界。
- oracle 生成脚本仍会产出坏 JSON，且与 `docs/12` 的 `v2` 结构方向不一致；Devnet 包装脚本也会把完整 RPC URL 落盘。

### 输出
- `src/solana/tx/message.zig` 引入 `Self` 别名修复 `Message.DecodeResult` 的公开 API 形态，并新增通过包导出的可用性测试。
- `Message.compileV0` 改为先聚合账户角色，再按 lookup 权限兼容性决定是否走 ALT；writable 账户不再被 readonly lookup 错误降级。
- `Message.deserialize` 现会校验 compiled instruction 的 `program_id_index/account_indexes` 是否落在静态+动态账户空间内。
- `scripts/oracle/Cargo.toml` 补齐 `[[bin]]`，`generate_vectors.rs` 改为可执行、输出合法 JSON，并写入 `v2` core 向量结构。
- `src/solana/compat/oracle_vector.zig` 与 `testdata/oracle_vectors.json` 同步升级到 `v2` core schema。
- `scripts/devnet/phase1_acceptance.sh` 现在对 `SOLANA_RPC_URL` 做脱敏后再写日志。
- `docs/03`、`docs/12` 同步回写了 lookup 权限与 oracle `v2` 当前状态。

### 风险
- oracle 生成链路虽然已从坏 JSON 修到可执行 + `v2` core schema，但 keypair/message/transaction 向量仍未补齐，closeout 仍不能据此宣称完成。
- 真正的 Devnet E2E harness 仍未落地；当前仅修复了日志脱敏问题。

### 验证
- 计划执行：`zig build test`、`bash -n scripts/devnet/phase1_acceptance.sh`、`cargo run --manifest-path scripts/oracle/Cargo.toml --release`。

## 2026-04-16 第十一次增量记录（结果模板 / C ABI / ADR / 总索引）

### 输入
- 需要按优先级继续完善文档：先补 Phase 1 的真实结果模板，再补 Phase 3 的 C ABI 子规格、ADR 模板、文档总索引，以及用户/安全约束收敛说明。

### 输出
- 新增 `docs/13a-benchmark-baseline-results.md`，作为 benchmark 第一版真实结果模板。
- 新增 `docs/14a-devnet-e2e-run-log.md`，作为 Devnet 包装式验收 / 真实 harness 结果模板。
- 新增 `docs/03d-cabi-spec.md`，沉淀 C ABI 的导出边界、所有权模型、错误码与版本化策略。
- 新增 `docs/adr/README.md` 与 `docs/adr/ADR-template.md`，使 ADR 机制从规则变成可执行模板。
- 新增 `docs/README.md`，为当前多层文档体系提供统一索引。
- 新增 `docs/16-consumer-profiles-and-security-notes.md`，收敛主用户、未来用户与安全/所有权约束。
- `README.md`、`docs/00`、`docs/03`、`docs/08`、`docs/09`、`docs/10`、`docs/13`、`docs/14`、`docs/15` 同步接入这些新文档的引用与维护关系。

### 风险
- 新增的是模板与边界文档，并不等于已经产出真实 benchmark / Devnet 运行结果；后续仍需把模板真正填起来。
- C ABI 规格已建立，但在进入 Phase 3 前仍需持续收紧为可执行接口清单。

### 验证
- 文档链进一步完整：`README -> docs/README -> 03/03d -> 13/13a -> 14/14a -> 16 -> adr/*`。

## 2026-04-16 第十三次增量记录（状态降温 / 主用户收敛 / closeout ownership）

### 输入
- 最新一轮文档 review 认为：`docs/00` 的 Phase 1 状态表述仍偏乐观、`docs/01` 与 `docs/16` 的用户范围仍可再收敛、`AccountInfo` 的 Phase 1 最小 typed 子集在主规格中不够可执行、`T4-16` 的 closeout ownership 仍偏窄。

### 输出
- `docs/00-roadmap.md` 将 Phase 1 状态降温为“进入 closeout”，并明确“实现主体已具备，但仍有收口 blocker”。
- `docs/01-prd.md` 在保留长期目标用户的同时，新增“Product Phase 1 当前主用户”小节，明确当前主对象是 Zig host/client 开发者。
- `docs/03-technical-spec.md` 与 `docs/03c-rpc-extended-spec.md` 明确 `AccountInfo` 的 Phase 1 最小 typed 子集：`lamports`、`owner`、`executable`、`rentEpoch`；`data` 与更复杂扩展字段可继续保留为 `OwnedJson`。
- `docs/04-task-breakdown.md` 扩大 `T4-16` 验收标准，把 `docs/10/11/13a/14a/15` 与 benchmark / Devnet evidence / execution matrix 的同步关系纳入 closeout ownership。
- `README.md` 将 oracle 生成器表述从“skeleton”更新为“`v2` core generator 已可用，但 keypair/message/transaction 向量仍待补齐”。
- `docs/10-coverage-matrix.md` 将 commit 锚点字段更新为更明确的 `Last synced docs commit`。

### 风险
- 以上调整让 closeout gate 与任务 ownership 更可执行，但并不意味着这些收口 blocker 已被实现解决；当前只是把要求写得更精确。

### 验证
- 文档在“状态表述 / 当前主用户 / typed parse 最小粒度 / closeout ownership”四个维度进一步对齐。

## 2026-04-16 第十四次增量记录（quickstart ownership 与 coverage anchor 同步）

### 输入
- 最新一轮 review 指出：`docs/17-quickstart-and-api-examples.md` 中的 transaction 示例错误地同时 `defer msg.deinit()` 又把 `msg` 传给 `VersionedTransaction.initUnsigned(...)`，会误导读者产生 double-free。

## 2026-04-16 第十五次增量记录（P2 Batch A residual docs backfill）

### 输入
- `#17/#18` 双任务并审后，记录到两条 non-blocking residual：
  1. `#18` 的 `docs/06` 与 `docs/10` 回写缺口。
  2. `G-P2-02` 放行口径需在文档里固化，避免“success/failure evidence”解释漂移。

### 输出
- 补齐 `docs/10-coverage-matrix.md`：
  - `sendTransaction` 状态从 `partial -> done`，备注明确 `send + confirm` live 证据来自 `docs/14a` Run 4/5（`#17`）。
  - Phase 2 的“扩展 RPC methods”从 `planned -> partial`，备注明确 Batch A 三方法已完成（`#18`）。
  - `Last synced docs commit` 更新为 `1f8856d`。
- 在本日志固化 `G-P2-02` 解释口径：
  - 本批按 **success live evidence + 代码失败分支覆盖** 放行；
  - send/confirm 路径的 failure evidence 留档作为后续批次持续增强项，不阻塞本批关门。

### 风险
- 若后续批次不持续补充 send/confirm failure evidence 的留档，`G-P2-02` 的“强证据面”仍会偏向成功路径。

### 验证
- `docs/10` 与 `docs/14a` / `docs/15` 的状态引用一致。
- `#17/#18` 的 gate 解释已在实现日志中留痕，便于 Phase 2 第一批汇总复核。
- 同时 `docs/10-coverage-matrix.md` 的 commit 锚点已落后于最近一次文档新增提交。

### 输出
- `docs/17-quickstart-and-api-examples.md` 删除 `defer msg.deinit()`，并明确注释：`msg` 在 `initUnsigned(...)` 时所有权转移给 `tx`。
- `docs/10-coverage-matrix.md` 的 `Last synced docs commit` 同步刷新到最近一次文档基线。

### 风险
- `docs/10` 的 commit 锚点本质上是文档审阅快照，后续每次文档提交后都仍需继续刷新，否则容易再次过期。

### 验证
- quickstart 示例的所有权语义已与 `src/solana/tx/transaction.zig` 当前实现一致。

## 2026-04-16 第十六次增量记录（收口文档补齐：L4 / Test Mapping / ALT 权限）

### 输入
- 针对最新文档 review，仍有 3 处需要补齐：`docs/02` 的 L4 口径未降级、`docs/03` 的测试映射章节落后于当前代码、`docs/15` 未把 ALT 权限正确性单列为 closeout blocker。

### 输出
- `docs/02-architecture.md` 将 L4 从“Devnet 集成测试”改为“Devnet acceptance harness / 外部集成验证”，并明确当前不是 in-tree E2E 测试层。
- `docs/03-technical-spec.md` 重写 Test Mapping：纳入现有的 mock transport 测试、parser hardening、`Message.DecodeResult` 导出可用性，以及当前 oracle `v2 core` 子集覆盖。

## 2026-04-16 第十七次增量记录（C2: v0/ALT 与 VersionedTransaction 失败路径补强）

### 输入
- `#8 C2` 要求补齐 `v0/ALT` 与 `VersionedTransaction` 的失败路径证据，且测试命名需可被 closeout gate 检索。

### 输出
- `src/solana/tx/message.zig` 新增 3 个失败路径测试（统一前缀 `v0_alt_*`）：
  - `v0_alt_deserialize_rejects_unsupported_version_byte`
  - `v0_alt_deserialize_rejects_lookup_truncation`
  - `v0_alt_deserialize_rejects_compiled_index_outside_lookup_space`
- `src/solana/tx/transaction.zig` 新增 3 个失败路径测试（统一前缀 `versioned_deserialize_*`）：
  - `versioned_deserialize_rejects_truncated_signature_bytes`
  - `versioned_deserialize_rejects_unsupported_message_version`
  - `versioned_deserialize_rejects_trailing_bytes`

### 风险
- 当前仓库存在与本任务无关的 RPC 编译中断（`src/solana/rpc/client.zig` 中未声明符号），导致 `zig build test` 全量验证暂不可得。

### 验证
- 已执行：`zig build test`（被 RPC 非相关错误阻塞，见风险项）。
- 该批改动未引入新的运行时依赖，目标是补齐 closeout gate 的失败路径证据。
- `docs/15-phase1-execution-matrix.md` 明确补入 ALT 权限正确性要求：writable 账户不能被 readonly lookup 错配，并将其提升为显式 high-priority blocker。

## 2026-04-16 第十八次增量记录（C3: oracle Phase 1 最低集合补齐）

### 输入
- `#9 C3` 目标是把 `testdata/oracle_vectors.json` 从 `v2 core` 子集扩到 `docs/12` 定义的 Phase 1 最低集合，并让 Zig 侧对 keypair/message/transaction 做实际消费断言。
- `#12` gate 额外要求两点：固定命名键（`kp_sig_*` / `msg_*` / `tx_*`）与“生成器输出 -> Zig 消费断言”一一对应表。

### 输出
- `scripts/oracle/generate_vectors.rs` 扩充为完整 Phase 1 oracle 生成器，新增：
  - `keypair`: `kp_sig_seed_01`, `kp_sig_seed_02`
  - `message`: `msg_legacy_simple`, `msg_legacy_multi_ix`, `msg_v0_basic_alt`, `msg_v0_multi_lookup`
  - `transaction`: `tx_legacy_signed`, `tx_v0_signed`
- `testdata/oracle_vectors.json` 现已包含 `core + keypair + message + transaction` 四组最小集合。
- `src/solana/compat/oracle_vector.zig` 新增 Zig 侧消费断言：
  - 固定 seed -> pubkey/signature
  - legacy / v0 message compile -> serialize
  - legacy / v0 transaction sign -> verify -> serialize

### Generator -> Zig 消费断言映射

| 生成器输出 | Zig 断言 | docs/11 gate |
|---|---|---|
| `core.pubkey_*`, `core.hash_nonzero`, `core.shortvec.*` | `expectPubkeyCase` / `expectShortvecCase` / hash bytes compare | `G-CLOSE-02` 基础兼容样本 |
| `keypair.kp_sig_seed_01`, `kp_sig_seed_02` | `expectKeypairSignatureCase`（seed -> pubkey -> sign -> verify） | `G-CLOSE-02` Keypair sign -> Signature |
| `message.msg_legacy_simple`, `msg_legacy_multi_ix` | `expectMessageCase`（compileLegacy -> serialize） | `G-CLOSE-02` legacy message serialize |
| `message.msg_v0_basic_alt`, `msg_v0_multi_lookup` | `expectMessageCase`（compileV0/ALT -> serialize） | `G-CLOSE-02` v0 message serialize（含 ALT） |
| `transaction.tx_legacy_signed` | `expectTransactionCase`（legacy tx sign/verify/serialize） | `G-CLOSE-02` versioned transaction serialize |
| `transaction.tx_v0_signed` | `expectTransactionCase`（v0 tx sign/verify/serialize） | `G-CLOSE-02` versioned transaction serialize |

### 风险
- 当前 oracle 生成器依赖 Rust `solana-sdk = 4.0.1` 的稳定 API；后续若升级 Rust 基线，需要重新生成并审查 JSON diff。
- `#10` 的 Devnet live 证据仍是外部阻塞，与本任务无关；`#9` 只解决 oracle gate。

### 验证
- `cargo run --manifest-path scripts/oracle/Cargo.toml --release`
- `zig build test`

### 风险
- 文档已补齐到与当前实现更一致，但这不等于 v0 / ALT 已完全收口；这里强调的是“收口信号更准确”，不是“实现已完成”。

### 验证
- 文档之间的 L4 / wrapper / harness 口径已进一步对齐：`README -> docs/02 -> docs/05 -> docs/14 -> docs/15`。

## 2026-04-16 第十九次增量记录（C5/C6: Closeout 文档统一与 Gate Review）

### 输入
- `#7/#8/#9/#10` 已完成，需要按 `docs/11` 执行一次 Phase 1 closeout gate review，并统一回写 `docs/06/07/10/14a/15`。

### 输出
- `docs/10-coverage-matrix.md` 已同步最新收口基线（对齐 `#7/#8/#9/#10`），修正旧的 typed/oracle/E2E 过时描述。
- `docs/07-review-report.md` 新增 `Closeout Checkpoint (2026-04-16)`，给出 G-CLOSE-01..06 快照与证据引用。
- `docs/14a-devnet-e2e-run-log.md` 已包含 Run 2（public devnet）与 Run 3（local surfnet）live 证据。
- `docs/15-phase1-execution-matrix.md` 已更新 Devnet E2E 为 `closeable`，并回写 oracle 与 typed parse 的进展。

### Gate Review 结论（按 `docs/11`）
- G-CLOSE-01 Test Gate: pass
- G-CLOSE-02 Oracle Gate: pass
- G-CLOSE-03 RPC Gate: pass（以 `#7` typed parse 收敛与边界覆盖为准）
- G-CLOSE-04 v0/Tx Gate: pass（以 `#8` 失败路径补齐与泄漏修复为准）
- G-CLOSE-05 Devnet Gate: **in-progress**
  - 已有 `construct -> sign -> simulate` 的 live 证据（devnet + surfnet）
  - `send` 证据仍未纳入当前 harness contract
- G-CLOSE-06 Documentation Gate: in-progress（文档已大体同步，但最终例外项归档仍需锁定）

### 风险
- 若直接宣称“Phase 1 fully closed out”，会与 `docs/11` 对 Devnet Gate 的 `construct -> sign -> simulate -> send` 要求冲突。
- `docs/15` 仍存在 `open/in-progress/closeable` 条目，最终需在 gate review 中明确“继续收敛”或“记录为 Phase 1 例外项”。

### 验证
- `zig build test`
- `cargo run --manifest-path scripts/oracle/Cargo.toml --release`
- `SOLANA_RPC_URL=https://api.devnet.solana.com zig build devnet-e2e`
- `SOLANA_RPC_URL=http://127.0.0.1:8899 zig build devnet-e2e`

## 2026-04-16 第二十次增量记录（文档复核吸收：E2E 口径与 typed RPC 同步）

### 输入
- 复核发现主规格与 closeout 文档未完全跟上最近这波 E2E / typed parse 演进：
  - `docs/14/14a/15/11/README` 对 real harness / wrapper / send gap 的口径不完全一致
  - `docs/03` / `docs/03c` / `docs/18` 仍残留 `OwnedJson` 时代的 RPC 签名描述

### 输出
- `docs/14-devnet-e2e-acceptance.md` 改为明确区分：
  - wrapper 留档路径
  - 当前 in-tree live harness（到 `simulate`）
  - 尚未收口的 `sendTransaction` live 证据
- `docs/14a-devnet-e2e-run-log.md` 回写 Run 2 / Run 3 的真实含义：可支撑 `construct -> sign -> simulate` live 证据，但**不能**单独宣称完整 `send` 闭环已完成。
- `docs/15-phase1-execution-matrix.md` 将 `Devnet E2E evidence` 从过度乐观表述拉回 `in-progress`，与 `sendTransaction` 行状态重新对齐。
- `docs/11-phase1-closeout-checklist.md`、`README.md`、`docs/01`、`docs/05`、`docs/17` 同步更新主叙事，避免继续把仓库状态写成“只有 wrapper、没有 real harness”。
- `docs/03-technical-spec.md`、`docs/03c-rpc-extended-spec.md`、`docs/18-surfpool-e2e-contract.md` 回写当前 public API：
  - `getAccountInfo -> RpcResult(AccountInfo)`
  - `simulateTransaction -> RpcResult(SimulateTransactionResult)`
  - 并明确 `raw_json/err_json` 作为原始语义旁路

### 风险
- 文档已改为更保守且更贴近当前实现，但这不代表 `sendTransaction` closeout blocker 已消失。
- `packages/client` 仍是最小 shim；与当前 Zig typed RPC API 并非完全 parity，需要后续单独收敛。

### 验证
- 文档交叉核对：`README -> docs/01 -> docs/03 -> docs/11 -> docs/14 -> docs/15 -> docs/18`

## 2026-04-16 第二十一次增量记录（Phase 1 Closeout Declaration）

### Closeout Declaration

- Commit: `609f173`（Devnet live 证据） + `6fa3029`（oracle 收口） + `f546b03`（v0/tx 失败路径收口） + `892cfd8`（RPC typed parse 收口）
- Test gate: pass
- Oracle gate: pass
- Benchmark baseline: recorded（`docs/13a`）
- Devnet E2E: pass-with-exception（`construct -> sign -> simulate` 已有 devnet/surfnet live；`send/confirm` 见例外项）
- Remaining exceptions:
  - `sendTransaction` live send/confirm（`docs/18` scope-exception，转入 Phase 2）
  - 扩展 typed parse / ALT 高复杂语义 / core 边界样本扩充（见 `docs/08` 与 `docs/15`）
- Review reference: `docs/07-review-report.md`

### 说明

- 本次 closeout 采用 “with documented exceptions” 口径，例外项已在 `docs/08` 与 `docs/15` 固化。

## 2026-04-16 第二十二次增量记录（#21: P2 Batch A residual docs backfill）

### 输入
- `#17/#18` 已放行为 Done，但跨线复核给出两条 non-blocking residual：
  1. `G-P2-02` 放行解释需要文档固化（success live + failure 分支覆盖）
  2. `#18` 的 docs gate 需要补齐在 `docs/06` / `docs/10` 的显式留痕

### 输出
- 在 `docs/19-phase2-planning.md` 的 `G-P2-02` 下新增 Batch 1 放行解释：
  - 允许以“1 条稳定 live success（send + confirm）+ 失败分支覆盖证据”作为本批放行依据
  - 并要求在实施日志与执行矩阵中留痕
- 在本文件新增本条记录，作为 `#21` 的 residual 收口证据。
- `docs/10-coverage-matrix.md` 已对齐 `1f8856d` 基线，包含：
  - `sendTransaction` 已标 `done`（Run 4/5）
  - Product Phase 2 扩展 RPC 为 `partial`（Batch A 三方法完成）

### 风险
- 该解释仅用于 Batch 1 放行，不应被误用为长期降低 `G-P2-02` 标准；
- 后续批次若具备稳定环境，应优先补充 live failure 证据。

### 验证
- 文档一致性核对：`docs/06` ↔ `docs/10` ↔ `docs/19`

## 2026-04-16 第二十三次增量记录（#17 P2-2: send + confirm failure evidence 补齐）

### 输入
- @codex_5_4 跨线复核指出 `G-P2-02` 要求"至少 1 成功 + 1 失败证据留档"，当前只有成功证据。
- 需要补齐 send/confirm 失败路径的测试与留档。

### 输出
- `src/e2e/devnet_e2e.zig` 新增两个 mock 失败测试：
  - `P2-2 mock: send failure path` — sendTransaction 返回 `rpc_error`（code=-32002, AccountNotFound），断言 code < 0 且 message 非空。
  - `P2-2 mock: confirm failure path` — getSignatureStatuses 返回 confirmed 但带 `InstructionError`，断言 err_json 非空。
- `src/solana/rpc/client.zig` 新增 `getSignatureStatuses` typed parse 方法 + 3 个 mock 测试。
- `src/solana/rpc/types.zig` 新增 `SignatureStatus` 类型。
- `docs/14a` Run 5 已包含成功 confirm 证据；失败路径由 mock 测试覆盖（无需 live 失败证据）。
- `docs/10` 新增 `getSignatureStatuses` 条目。

### 证据
- Live 成功：sig `3pkLWVQ...e6xn`, confirmationStatus `confirmed`, slot `413542952`
- Mock 失败：send rpc_error + confirm-with-error 均通过断言

### 验证
- `zig build test` ✅
- `zig build devnet-e2e` ✅（6 tests pass）
- G-P2-02 DoD: send ✓ + confirm ✓ + 成功证据 ✓ + 失败证据 ✓

## 2026-04-16 第二十四次增量记录（#24: websocket lifecycle / reconnect docs backfill）

### 输入
- `#22` 已清掉 `src/solana/rpc/ws_client.zig` 的 Zig 0.16 编译阻塞：
  - 移除无效 `std.time.sleep`
  - `MockWsServer` 改为 `port 0 + getPort()`，避免并行测试 `AddressInUse`
  - `std.Thread.spawn` 参数传递改为 Zig 0.16 兼容形式
  - `stop()` 改为 dummy connect 解除 `accept()` 阻塞，避免 worker thread panic
- `#23` 在只改测试区 + `MockWsServer` 钩子的边界内，补齐 websocket lifecycle / reconnect / failure-path 证据。

### 输出
- `ws_client.zig` 的 websocket 测试证据已形成 5 条稳定用例：
  - `ws_unsubscribe_ack_success`
  - `ws_reconnect_detect_disconnect_then_reconnect`
  - `ws_reconnect_resubscribe_after_reconnect`
  - `ws_reconnect_subscription_response_malformed`
  - `ws_reconnect_notify_path_with_server_close`
- `force_disconnect_after_notify` 与 `malformed_sub_reply` 两个 mock 开关已固定为本批 websocket 证据的主要触发器。
- `docs/10` 与 `docs/15` 已同步回写为：websocket 能力已获得正式测试证据，但主任务 `#20` 的 `WsRpcClient` 集成提审仍待完成，因此状态保持 `partial / in-progress`，不提前写成 `done`。

### 风险
- 当前已证明 websocket 生命周期 / reconnect / failure-path 的测试证据成立，但 `#20` 主任务仍在进行中；在 `WsRpcClient` 集成提审前，不应把 websocket 产品能力写成完全收口。
- 本轮 docs 回写采用“已验证的子任务证据 + 主任务仍在进行中”的口径；若 `#20` 后续改动 public surface，需要再次核对 `docs/10` / `docs/15`。

### 验证
- `zig build test` ✅（单次全量）
- 5 条 websocket 证据用例全部 PASS
- `G-P2-04`：subscribe/unsubscribe、disconnect detect、reconnect、resubscribe、malformed failure 均有证据
- `G-P2-05`：`docs/06` / `docs/10` / `docs/15` 已同步回写

## 2026-04-16 第二十五次增量记录（#27 P2-7: RPC Batch B 首个 checkpoint）

### 输入
- `#26` 已通过第二轮 review，`docs/20-phase2-batch2-planning.md` 已冻结；第二批实现线正式放行。
- `#27` 首个 checkpoint 已提交，范围固定为：
  - `getEpochInfo`
  - `getMinimumBalanceForRentExemption`
  - `requestAirdrop`
  - `getAddressLookupTable`

### 输出
- `src/solana/rpc/types.zig` 已补充 Batch B 结果类型骨架：
  - `EpochInfo`
  - `RequestAirdropResult`
  - `AddressLookupTableResult`
- `src/solana/rpc/client.zig` 已落地 4 个方法的 typed parse 代码。
- `src/solana/rpc/client.zig` 已补齐每方法的三类测试代码：
  - `happy`
  - `rpc_error`
  - `malformed/invalid response`
- `docs/10` / `docs/15` 已为 Batch B 打开实时跟踪条目，但当前只记到 `in-progress / pending verification`，不提前升档。

### 风险
- 当前仍是“代码已落地” checkpoint，尚未拿到 `#27` 的 canonical 三件套，不能据此宣称 `G-P2B-02` 已通过。
- `G-P2B-02` 的 integration-evidence 还需按 `docs/20` 分流：
  - `requestAirdrop` 必须给出 live 证据
  - 只读方法若走 `mock + local-live`，需在 `docs/15` 登记 `Batch 2 exception`

### 验证
- 本条仅记录代码落地 checkpoint；正式验证待 `#27` 提供：
  - clean `git status`
  - commit hash
  - 单次全量 `zig build test`
  - 以及 `G-P2B-02` 对应的 integration-evidence

### 收口更新（修正）
- `#27` 的代码实现存在于独立 commit `0070fa8`（工作区 `/tmp/solana-zig-p2b27-164030`），但**尚未合并到 `main` 分支**。
- 该 commit 包含 4 个方法的 typed parse + 三类测试：
  - `getEpochInfo`
  - `getMinimumBalanceForRentExemption`
  - `requestAirdrop`
  - `getAddressLookupTable`
- integration-evidence 在 `0070fa8` 中已形成：
  - `requestAirdrop`：local-live 成功（surfnet `127.0.0.1:8899`）
  - `getEpochInfo` / `getMinimumBalanceForRentExemption`：`public devnet + local-live` 成功
  - `getAddressLookupTable`：`public devnet` 与 `local-live` 均返回 `-32601 Method not found`
- **文档状态修正**：此前 `docs/10` / `docs/15` 过早将 `#27` 标记为 `closed/done`。由于代码未进入 `main`，该状态不成立。已回写为 `in-progress / branch-committed pending merge`。
- 按 `docs/20` 的 Batch 2 固定例外口径，`getAddressLookupTable` 仍登记为 `Batch 2 exception`。

### 验证补充
- `G-P2B-01`：canonical 三件套在 `0070fa8` 中 ✅，但需合并到 `main` 后才算主线通过。
- `G-P2B-02`：typed parse + method-level tests + integration/exception 模型在 `0070fa8` 中 ✅。
- `G-P2B-05`：待 `0070fa8` 合并后最终闭环。

## 2026-04-16 第二十六次增量记录（#29 P2-9: ComputeBudget builders 首个 checkpoint）

### 输入
- `#26` 已冻结通过，`#29` 按 `docs/20` §2.3 与 `docs/03a` §5.2 进入正式实现。
- `#29` 首个 checkpoint 已提交，当前落点已回到 `interfaces/compute_budget`，未出现文件归属漂移。

### 输出
- 新建 `src/solana/interfaces/compute_budget.zig`，已落地：
  - `programId()`
  - `buildSetComputeUnitLimitInstruction`
  - `buildSetComputeUnitPriceInstruction`
- `src/solana/mod.zig` / `src/root.zig` 已接通 `interfaces.compute_budget` 导出。
- 证据侧已拿到：
  - `programId` 常量断言
  - `setComputeUnitLimit` happy / zero / max u32 / Rust 参考字节
  - `setComputeUnitPrice` happy / zero / max u64 / Rust 参考字节
  - 单次全量 `zig build test` `RC=0`
- `docs/10` / `docs/15` 已为 ComputeBudget 打开实时跟踪条目，但当前仍记为 `in-progress / pending canonical`，等待 commit hash + clean status 补齐。

### 风险
- 当前证据已明显满足 `G-P2B-04` 主体要求，但 `G-P2B-01` 的 canonical 三件套还缺：
  - clean `git status`
  - commit hash
  - 原始测试结果留档
- 在三件套到位前，`#29` 不应提升为正式放行状态。

### 验证
- checkpoint 自报：
  - 全量 `zig build test` `RC=0`
  - 字节布局 / 边界 / Rust 参考对照均通过
- 正式验证待 `#29` 提交 canonical 三件套后收口

### 收口更新
- `#29` 已补齐 canonical 三件套：
  - commit `fffbc87`
  - `git status` clean（`#29` 相关 3 文件已提交，无遗留）
  - `zig build test --summary all`：`42/42 tests passed, EXIT=0`
- `G-P2B-04` 已满足：
  - `setComputeUnitLimit` / `setComputeUnitPrice` builder 可用
  - 参数边界校验完成
  - Rust 参考字节对照已留档
- `G-P2B-05` 本轮通过：`docs/06` / `docs/10` / `docs/15` 已同步从 checkpoint 骨架转为正式状态

## 2026-04-16 第二十七次增量记录（#28 P2-8: Durable Nonce workflow 收口）

### 输入
- `#26` 已冻结通过，`#28` 按 `docs/20` §2.2 与 `docs/03a` §5.1 进入正式实现。
- `#28` checkpoint 已提交，范围固定为：
  - `parseNonceAccountData`
  - `NonceState` typed parse
  - `buildAdvanceNonceAccountInstruction`
  - `query nonce -> build advance ix -> compile/sign` 最小流程测试

### 输出
- 新建 `src/solana/interfaces/system.zig`，已落地：
  - `programId()`
  - `buildAdvanceNonceAccountInstruction`
- `src/solana/mod.zig` / `src/root.zig` 已接通 `interfaces.system` 导出。
- `parseNonceAccountData` 已支持两种输入模式：
  - 直接 `State`（68 bytes）
  - `Versions` 包装（72 bytes）
- `NonceState` typed parse 已支持：
  - `uninitialized`
  - `initialized`（authority + blockhash）
- `AdvanceNonceAccount` builder 已验证：
  - discriminant `0x04`（u32 little-endian）
  - 账户顺序固定为 `nonce writable` / `recent_blockhashes sysvar readonly` / `authority signer`
- 最小流程测试已形成：
  - `query nonce account -> build advance ix -> compile/sign`
  - 包含 tx sign + serialize roundtrip

### 风险
- 当前 nonce 流程测试以 mock 账户路径完成端到端 `compile/sign` 验证，尚未要求 live nonce account。
- `recent_blockhashes sysvar` 目前仍按 Rust 4.0.1 参考实现保留为必需只读账户；若后续链语义变化，需要在下一阶段同步调整 builder 与文档依据。
- 目前未触发 Batch 2 exception：`#28` 已满足本批最小流程 gate，不需要额外例外登记。

### 验证
- canonical 三件套：
  - commit `5eca510`
  - `git status --short` 为空（commit 时刻 clean）
  - `zig build test` ✅
- 关键测试证据：
  - `parseNonceAccountData direct state initialized` — PASS
  - `parseNonceAccountData with Versions wrapper` — PASS
  - `parseNonceAccountData uninitialized` — PASS
  - `parseNonceAccountData rejects truncated` — PASS
  - `buildAdvanceNonceAccountInstruction byte layout and accounts` — PASS
  - `nonce workflow minimal compileLegacy` — PASS
  - `nonce workflow: query -> build advance ix -> compile and sign` — PASS
- gate 结论：
  - `G-P2B-03` ✅
  - `G-P2B-05` ✅（`docs/06` / `docs/10` / `docs/15` 已同步回写）

## 2026-04-16 第二十八次增量记录（#34 P2-14: Nonce live 深化）

### 输入
- 第三批 `#31` 已冻结通过，`#34` 按 `docs/21` §2.3 与 `G-P2C-04` 进入正式实现。
- `#34` checkpoint 已提交，目标固定为：
  - `query nonce -> build advance -> compile/sign -> send/confirm`
  - 形成稳定 live run-log
  - 若仅 `local-live` 可用，则登记 `Batch 3 exception`

### 输出
- 新建 `src/e2e/nonce_e2e.zig`，形成两类 E2E：
  - `P2-14 mock: query nonce -> build advance -> compile/sign -> send -> confirm`
  - `P2-14 live: create nonce -> query -> advance -> send -> confirm`
- `build.zig` 已新增 `nonce-e2e` build step。
- 基于 `#28` 的 `interfaces/system.zig`：
  - `parseNonceAccountData`
  - `buildAdvanceNonceAccountInstruction`
  已完成 live 路径复用验证。
- 本轮 local-live 证据已形成：
  - payer：`7XXPmL4qSHSpbivZnAGy1VN4J8svpdRuU3ohFQKfLmni`
  - nonce account：`tjAxCwK4gq6bp8r6kzEijq2Ht6nupuzf8q95d91zYoM`
  - create nonce tx：`3owqVDX7zNsDdNS32Q2wX9d1vUGUK2A3XWsg8uVssEPzFcjJAS4qa3Efxu7gBoGyf4ZQAiDfuKy8hjZBgRwo2Q7a`
  - advance nonce tx：`3pTHhtncebfRwRCXZ7xLiEDuztL8vi8CmweGRfNyMkCBgwVT4xsppCiTHo7mT1cc9keaC5fpQo6GiFbvqHzemfuU`

### 风险
- 当前 live 证据来自 `http://127.0.0.1:8899`，尚未形成 `public devnet` 对应 run。
- 因本批仅拿到 `local-live`，需要按 `docs/21` 的固定模型在 `docs/15` 登记 `Batch 3 exception`，并把后续收敛阶段写清。
- `recent_blockhashes sysvar` 仍沿用 Rust 4.0.1 参考语义；若链语义后续变化，需要同步调整 `interfaces/system` 与 live harness。

### 验证
- canonical 三件套：
  - commit `dd6bdff`
  - `git status` clean
  - `zig build test`：`47/47 passed`
- 附加 E2E：
  - `zig build nonce-e2e --summary all`：`2/2 passed`
- 关键 live 证据：
  - create nonce tx confirmed（poll 0）
  - advance nonce tx confirmed（poll 0）
  - nonce state `initialized`
  - authority 与 blockhash 均可从 live query 复现
- gate 结论（当前轮）：
  - `G-P2C-04` ✅
  - `G-P2C-05` 待本轮 `docs/14a` / `docs/15` 回写完成后正式闭环

## 2026-04-16 第二十九次增量记录（#32 P2-12: getTokenAccountsByOwner typed parse 收口）

### 输入
- 第三批 `#31` 已冻结通过，`#32` 按 `docs/21` §2.1 与 `G-P2C-02` 进入正式实现。
- `#32` 首个完整 checkpoint 已提交，范围固定为：
  - `getTokenAccountsByOwner(owner, program_id)` 方法实现
  - `TokenAccountInfo` / `TokenAccountsByOwnerResult` typed parse
  - `happy + rpc_error + malformed` 三类方法级测试
  - integration 证据（默认 `public devnet`）

### 输出
- `src/solana/rpc/client.zig` 已新增：
  - `getTokenAccountsByOwner(owner, program_id)`
  - 对应 JSON-RPC payload 与 typed parse 路径
- `src/solana/rpc/types.zig` 已新增：
  - `TokenAccountInfo`
  - `TokenAccountsByOwnerResult`
- 方法级测试已齐：
  - `rpc client getTokenAccountsByOwner typed parse happy path`
  - `rpc client getTokenAccountsByOwner preserves rpc error`
  - `rpc client getTokenAccountsByOwner returns InvalidRpcResponse on malformed success`
- public devnet integration 已形成最小可复现证据：
  - endpoint `https://api.devnet.solana.com`
  - runner 输出 `token_accounts=0`

### 风险
- 当前共享工作树上存在 `#33` websocket hang/deadlock，因此 `#32` 的 canonical 三件套不能直接依赖共享工作树。
- 本轮已通过**隔离干净 worktree**解耦验证 `#32`，因此 `#32` 不再被 `#33` 阻塞。
- 当前未触发 `Batch 3 exception`：`#32` 已拿到 `public devnet` integration 证据。

### 验证
- canonical 三件套（隔离 worktree）：
  - worktree `/tmp/solana-zig-p2c32-canonical`
  - commit `b99d7fc`
  - `git status --short` 为空（clean）
  - `zig build test --summary all`：`5/5 steps succeeded; 47/47 tests passed; EXIT 0`
- 方法级测试证据：
  - `happy` — PASS
  - `rpc_error` — PASS
  - `malformed` — PASS
- integration 证据：
  - `endpoint=https://api.devnet.solana.com token_accounts=0`
- gate 结论：
  - `G-P2C-01` ✅（通过隔离 worktree canonical 固化）
  - `G-P2C-02` ✅
  - `G-P2C-05` ✅（本轮 `docs/06` / `docs/10` / `docs/15` / `docs/14a` 已同步）

## 2026-04-16 第三十次增量记录（#33 P2-13: Websocket re-stabilize / re-expose 收口）

### 输入
- 第三批 `#31` 过审后，`#33` 作为最后一条未闭环实现线进入 websocket 稳态增强与公开导出恢复阶段。
- 当前目标按 `docs/21` 的 `G-P2C-03` 固定为：
  - backoff reconnect
  - resubscribe 幂等
  - duplicate notification 去重
  - connection flap / failure-path 收口
- `#35` 收口口径已固定：只有在 websocket 统一证据包到位后，才把 `docs/10` 的 websocket 能力从 pending/partial 转成正式状态。

### 输出
- `src/solana/rpc/ws_client.zig` 已在 `c57b189` 完成 websocket 基线恢复与稳态 hardening：
  - `WsRpcClient.reconnectWithBackoff(retries, base_delay_ms)`
  - 订阅注册与幂等复用（同 filter 不重复发新订阅）
  - reconnect 后自动 resubscribe
  - 相同通知 hash 的连续去重
- `MockWsServer` 已重新稳定化，清除了共享工作树此前的缺失/混合态与 mock hang 前置问题，使 websocket 测试重新回到可评审状态。
- `mod/root` 公开导出已重新接通，`#33` 达到 `re-expose` 条件。

### 风险
- 当前收口只覆盖 websocket 稳态恢复与公开导出恢复，不包含新的订阅类型扩展。
- dedup 采用“相同通知 hash 连续去重”的最小策略；若后续需要更强的跨连接/跨会话语义，应在后续批次单独冻结范围。
- 本轮不要求额外 live run-log，仍以 `G-P2C-03` 的测试证据与 canonical 三件套作为放行依据。

### 验证
- canonical 三件套：
  - commit `c57b189`
  - `git status` clean
  - `zig build test --summary all`：`62/62 tests passed`
- websocket 稳态测试证据：
  - `ws_backoff_reconnect_retry_budget` — PASS
  - `ws_resubscribe_idempotent_same_filter_returns_same_id` — PASS
  - `ws_dedup_skip_duplicate_notifications` — PASS
  - `ws_connection_flap_reconnect_with_backoff` — PASS
- gate 结论：
  - `G-P2C-01` ✅
  - `G-P2C-03` ✅
  - `G-P2C-05` ✅（本轮 `docs/06` / `docs/10` / `docs/15` 已同步，websocket 已达到 `re-expose` 条件）

## 2026-04-16 第三十一次增量记录（#38 P2-18: Websocket production hardening 收口）

### 输入
- 第四批 `#36` 已通过结构审并放行实现；`#38` 按 `docs/22` §2.2 与 `G-P2D-03` 进入 websocket production hardening。
- 本轮冻结目标固定为：
  - heartbeat（ping/pong）
  - deterministic backoff + 硬上限
  - reconnect 后 cleanup / state consistency
  - dedup cache 边界

### 输出
- `src/solana/rpc/ws_client.zig` 已在 `6d3c58c` 完成 production hardening：
  - 新增 `sendPing()` heartbeat 方法
  - 新增 `subscriptionCount()` 状态查询
  - `reconnectWithBackoff` 冻结硬上限：`MAX_RECONNECT_RETRIES=5`、`MAX_BACKOFF_MS=30_000`
  - dedup 从单 hash 升级为 ring buffer，`DEDUP_CACHE_SIZE=16`
  - 补齐 `isDuplicateNotification` / `recordNotificationHash` 内部方法
- websocket 生产硬化四类证据已全部到位：
  - `ws_production_heartbeat_ping_pong`
  - `ws_production_backoff_hard_limit`
  - `ws_production_cleanup_state_consistency`
  - `ws_production_dedup_cache_boundary`

### 风险
- 当前 hardening 仍限定在现有订阅能力之上，不扩新增订阅类型。
- backoff 采用 deterministic 模型而非 jitter；这符合 `docs/22` 冻结口径，但若后续需要更贴近生产环境的随机退避，应在后续批次重新冻结范围。
- dedup 当前采用固定 ring buffer 窗口，仅解决“无限增长”问题，不把它误写成跨连接/跨会话的全局去重语义。

### 验证
- canonical 三件套：
  - commit `6d3c58c`
  - websocket 写集已提交，`zig build test --summary all`：`69/69 tests passed`
- 关键 websocket hardening 测试：
  - `ws_production_heartbeat_ping_pong` — PASS
  - `ws_production_backoff_hard_limit` — PASS
  - `ws_production_cleanup_state_consistency` — PASS
  - `ws_production_dedup_cache_boundary` — PASS
- gate 结论：
  - `G-P2D-01` ✅
  - `G-P2D-03` ✅
  - `G-P2D-05` ✅

## 2026-04-16 第三十二次增量记录（#37 P2-17: Token Accounts 深化收口）

### 输入
- 第四批 `#36` 已通过结构审并放行实现；`#37` 按 `docs/22` §2.1 与 `G-P2D-02` 进入 Token Accounts 查询层收口。
- 本轮冻结目标固定为：
  - `getTokenAccountBalance` typed parse + 三类测试
  - `getTokenSupply` typed parse + 三类测试
  - `public devnet` integration 证据

### 输出
- `src/solana/rpc/types.zig` 已新增 `types.TokenAmount`。
- `src/solana/rpc/client.zig` 已在 `4b1f8e4` 完成：
  - `getTokenAccountBalance(token_account)`
  - `getTokenSupply(mint)`
  - 两个方法的 typed parse：`amount` / `decimals` / `uiAmountString` + `raw_json`
- 两个方法均已补齐三类测试：
  - `happy`
  - `rpc_error`
  - `malformed`

### 风险
- 当前查询层收口只覆盖最小 token amount 查询闭环，不进入完整 SPL Token interface。
- 本轮 canonical 采用隔离 worktree 固化，避免并行工作树噪音影响 `#37` 的放行判定。
- `public devnet` integration 已到位，因此本轮**不触发 Batch 4 exception**。

### 验证
- canonical 三件套（隔离 worktree）：
  - worktree `/tmp/solana-zig-b4-37-RjLwUE`
  - commit `4b1f8e4`
  - `git status --short` 为空（clean）
  - `zig build test --summary all`：`69/69 tests passed`
- 定向单元测试：
  - `zig build test -- --test-filter "getTokenAccountBalance|getTokenSupply"` — PASS
- public devnet integration：
  - endpoint `https://api.devnet.solana.com`
  - `getTokenLargestAccounts(So111...)` 取得样本账户 `35akt5uJn73ZN9FkGgBKpRwbW5scoqV7M1N59cwb4TKV`
  - `getTokenAccountBalance(35akt...)` 返回 `amount=11109337918819635, decimals=9, uiAmountString=11109337.918819635`
  - `getTokenSupply(So111...)` 返回 `amount=0, decimals=9, uiAmountString=0`
- gate 结论：
  - `G-P2D-01` ✅
  - `G-P2D-02` ✅
  - `G-P2D-05` ✅

## 2026-04-16 第三十三次增量记录（#39 P2-19: Release readiness 收口）

### 输入
- 第四批 `#36` 已通过结构审并放行实现；`#39` 按 `docs/22` §2.3 与 `G-P2D-04` 进入发布前技术清单与 release verdict 收口。
- 本轮固定目标为：
  - 测试结果
  - 内存检查
  - 文档一致性
  - 发布判定

### 输出
- 新增 `docs/23-release-readiness-checklist.md`，并已从 provisional 收为 final：
  - 测试结果：`72/72 tests passed`
  - 内存检查：`std.testing.allocator` 零泄漏
  - 文档一致性：`docs/06/10/14a/15` 已与 Batch 4 实现状态同步
  - 发布判定：`final: 可发布`
- `docs/14a` 已补 Run 9，作为 Batch 4 public devnet smoke 证据。
- Batch 4 当前无未收敛 exception：`#37` / `#38` 均为无 exception。

### 风险
- 当前 release verdict 基于现有 Batch 4 范围，不外推到 Phase 3/发布凭证相关项（`#15` 仍独立阻塞，不属于当前产品 gate）。
- public devnet smoke 本轮出现 `sendTransaction` skip（airdrop rate-limited），但发送/确认链路已有 Run 4/5 历史 live 证据，因此不构成新的 release blocker。
- local-live smoke 本轮未重复跑 surfnet，而是复用 Run 4/5/6 历史证据。

### 验证
- release readiness checklist：
  - `docs/23-release-readiness-checklist.md`
  - status: `Final`
  - verdict: `final: 可发布`
- 测试 / smoke 证据：
  - `zig build test --summary all`：`72/72 tests passed`
  - `SOLANA_RPC_URL=https://api.devnet.solana.com zig build devnet-e2e`：`6/6 pass`
  - local-live 历史证据：`docs/14a` Run 4/5/6
- gate 结论：
  - `G-P2D-01` ✅
  - `G-P2D-04` ✅
  - `G-P2D-05` ✅

## 2026-04-16 第三十四次增量记录（#45 P2-23: Websocket 生产可观测性收口）

### 输入
- 第五批 `#43` 已通过结构审并放行实现；`#45` 按 `docs/24` §2.2 与 `G-P2E-03` 进入 websocket 生产可观测性收口。
- 本轮冻结目标固定为：
  - 冻结 `snapshot()` schema
  - 证明 reconnect / dedup / subscription state 的可观测计数
  - 保持 deterministic backoff 模型不变

### 输出
- `src/solana/rpc/ws_client.zig` 已在 `e7f8987` 完成 websocket observability：
  - 新增 `WsStats` 冻结 schema：
    - `reconnect_attempts_total`
    - `active_subscriptions`
    - `dedup_dropped_total`
    - `last_error_code`
    - `last_error_message`
    - `last_reconnect_unix_ms`
  - 新增 `snapshot()` 方法返回 `WsStats`
  - 在 `reconnect` / `reconnectWithBackoff` / `readNotification` 路径补齐 observability instrumentation
- 可观测性五类证据已全部到位：
  - `ws_observability_snapshot_initial_state`
  - `ws_observability_counters_after_subscribe`
  - `ws_observability_reconnect_counter_increments`
  - `ws_observability_dedup_dropped_counter`
  - `ws_observability_backoff_error_state`

### 风险
- 当前 observability 仅覆盖冻结字段，不把它误写成完整生产 metrics/export subsystem。
- `last_error_message` 仍采用最近一次错误的截断字符串缓冲；本轮只冻结“存在与可诊断”，不冻结跨版本稳定错误文本。
- 本轮**不触发 Batch 5 exception**；证据完全由代码侧 canonical 与可复现测试收口。

### 验证
- canonical 三件套：
  - commit `e7f8987`
  - websocket 写集已提交
  - `zig build test --summary all`：`82/82 tests passed`
- 关键 observability 测试：
  - `ws_observability_snapshot_initial_state` — PASS
  - `ws_observability_counters_after_subscribe` — PASS
  - `ws_observability_reconnect_counter_increments` — PASS
  - `ws_observability_dedup_dropped_counter` — PASS
  - `ws_observability_backoff_error_state` — PASS
- gate 结论：
  - `G-P2E-01` ✅
  - `G-P2E-03` ✅
  - `G-P2E-05` ✅

## 2026-04-16 第三十五次增量记录（#46 P2-24: 发布前自动化收口）

### 输入
- 第五批 `#43` 已通过结构审并放行实现；`#46` 按 `docs/24` §2.3 与 `G-P2E-04` 进入发布前自动化收口。
- 本轮冻结目标固定为：
  - 新增独立 preflight 入口脚本
  - 生成标准报告产物
  - 将 Batch 5 release verdict 输入对齐到 `docs/25`

### 输出
- 新增 `scripts/release/preflight_batch5.sh`，统一收集：
  - build/test
  - smoke（public devnet / local-live）
  - docs consistency
  - verdict input
- `docs/25-batch5-release-readiness.md` 已对齐 Batch 5 preflight 自动化路径与输出格式：
  - 脚本路径：`scripts/release/preflight_batch5.sh`
  - 报告产物：`artifacts/release/batch5-preflight-<timestamp>-<commit>.md`
  - logs：`artifacts/release/batch5-*.log`
- 支持 `ALLOW_BATCH5_EXCEPTION=true` 走 `有条件发布` 路径，用于 smoke 缺失时的标准化报告输出。

### 风险
- 当前可复现样例运行未提供 `SOLANA_RPC_URL` 与 `SURFPOOL_RPC_URL`，因此 smoke 两侧均为 `MISSING`。
- 这意味着本轮 **触发 Batch 5 exception**；脚本与报告链路已经成立，但 Batch 5 最终 release verdict 仍不能提前升为 `可发布`。
- 本轮收口的是自动化入口与标准报告能力，不把“缺 smoke 的 conditional verdict”误写成 Batch 5 的 final release verdict。

### 验证
- canonical 三件套（隔离 worktree）：
  - worktree `/tmp/solana-zig-b5-46-e7f8987`
  - commit `3e34225`
  - `git status --short` 为空（clean）
  - `zig build test --summary all`：`82/82 tests passed`
- preflight 样例运行：
  - command：`ALLOW_BATCH5_EXCEPTION=true scripts/release/preflight_batch5.sh /tmp/batch5-preflight-3e34225`
  - report：`/tmp/batch5-preflight-3e34225/batch5-preflight-20260416-194418-3e34225.md`
  - result：
    - `build/test`: `PASS`
    - `smoke(public devnet)`: `MISSING`
    - `smoke(local-live)`: `MISSING`
    - `docs consistency`: `PASS`
    - `exception_required`: `true`
    - `verdict`: `有条件发布`
- gate 结论：
  - `G-P2E-01` ✅
  - `G-P2E-04` ✅
  - `G-P2E-05` ✅

## 2026-04-16 第三十六次增量记录（#44 P2-22: SPL Token 指令集深化收口）

### 输入
- 第五批 `#43` 已通过结构审并放行实现；`#44` 按 `docs/24` §2.1 与 `G-P2E-02` 进入 SPL Token builders 收口。
- 本轮冻结目标固定为：
  - `transferChecked` builder
  - `closeAccount` builder
  - boundary + compile/sign 证据

### 输出
- 新增 `src/solana/interfaces/token.zig`，在 `d6ab74d` 完成：
  - `programId()` → `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`
  - `buildTransferCheckedInstruction(...)`
  - `buildCloseAccountInstruction(...)`
- `src/solana/mod.zig` 已接通 `interfaces.token` 导出。
- `src/root.zig` 已新增 `token interface compiles` compile surface 引用。

### 风险
- 本轮 builder 收口仅覆盖单 signer 最小 compile/sign 闭环，不扩多 signer / multisig 变体。
- 证据以字节布局、账户顺序与 signed legacy transaction compile/sign 为主，不把它误写成链上执行已完成。
- 本轮**不触发 Batch 5 exception**；`docs/24` 对 `P2-22` 的 exception 规则只在“仅 compile/sign 且缺少稳定链上执行需要降级”为前提，但当前本批对 `G-P2E-02` 的要求就是 builder + boundary + compile/sign，证据已完整满足冻结 gate。

### 验证
- canonical 三件套（隔离 worktree）：
  - worktree `/tmp/solana-zig-b5-44-sOZuSU`
  - commit `d6ab74d`
  - `git status --short` 为空（clean）
  - `zig build test --summary all`：`91/91 tests passed`
- 关键 token builder 测试：
  - `programId returns Tokenkeg...` — PASS
  - `transferChecked byte layout and account metas` — PASS
  - `transferChecked boundary: zero amount zero decimals` — PASS
  - `transferChecked boundary: max amount max decimals` — PASS
  - `closeAccount byte layout and account metas` — PASS
  - `token builders compile into signed legacy transaction` — PASS
- gate 结论：
  - `G-P2E-01` ✅
  - `G-P2E-02` ✅
  - `G-P2E-05` ✅

## 2026-04-16 第三十七次增量记录（#51 P2-28: Websocket 可恢复性深化收口）

### 输入
- 第六批 `#48` 已通过结构审并放行实现；`#51` 按 `docs/26` §2.2 与 `G-P2F-03` 进入 websocket recoverability 收口。
- 本轮冻结目标固定为：
  - reconnect storm / backoff 稳定性
  - recovery 后状态一致性
  - 断线/恢复消息边界

### 输出
- `src/solana/rpc/ws_client.zig` 已在 `a49ec19` 完成 recoverability 增强：
  - `MockWsServer.startMulti(allocator, max_connections)`，支持多连接 reconnect storm 场景
  - 3 条 `G-P2F-03` 机械验收测试，全部通过 `snapshot()/WsStats` 字段证明
- 关键 recoverability 证据已全部到位：
  - `ws_recoverability_reconnect_storm_stability`
  - `ws_recoverability_recovery_state_consistency`
  - `ws_recoverability_message_boundary_counters`

### 风险
- 当前 recoverability 收口只覆盖冻结的最小证据组，不把它误写成完整生产 QoS / delivery guarantee。
- 消息边界模型允许 disconnect 窗口内 drop，但要求 `dedup_dropped_total` 与 reconnect 相关字段可观测、单调不减。
- 本轮**不触发 Batch 6 exception**；证据完全由 canonical 三件套 + `snapshot()/WsStats` 机械测试收口。

### 验证
- canonical 三件套：
  - commit `a49ec19`
  - `ws_client.zig` 为唯一写集文件，已提交
  - `zig build test --summary all`：`94/94 tests passed`
- recoverability 测试：
  - `ws_recoverability_reconnect_storm_stability` — PASS
  - `ws_recoverability_recovery_state_consistency` — PASS
  - `ws_recoverability_message_boundary_counters` — PASS
- gate 结论：
  - `G-P2F-01` ✅
  - `G-P2F-03` ✅
  - `G-P2F-05` ✅

## 2026-04-16 第三十八次增量记录（#52 P2-29: 发布流水线固化收口）

### 输入
- 第六批 `#48` 已通过结构审并放行实现；`#52` 按 `docs/26` §2.3 与 `G-P2F-04` 进入 Batch 6 preflight / release pipeline 收口。
- 本轮冻结目标固定为：
  - 固定 Batch 6 preflight 主入口
  - 固定 report / log 产物规范
  - 形成可复现 exception-path 样例

### 输出
- 新增 `scripts/release/preflight_batch6.sh`，固定 Batch 6 preflight 主入口。
- `docs/27-batch6-release-readiness.md` 已对齐 Batch 6 preflight 路径与输出格式：
  - script path：`scripts/release/preflight_batch6.sh`
  - report：`artifacts/release/batch6-preflight-<timestamp>-<commit>.md`
  - logs：`artifacts/release/batch6-*.log`
- 当前已形成 `ALLOW_BATCH6_EXCEPTION=true` 的标准报告样例，可在 smoke 缺失时稳定生成 `有条件发布` 输入。

### 风险
- 当前样例运行未提供 Batch 6 所需双侧 smoke，因此：
  - `public devnet` smoke = `MISSING`
  - `local-live` smoke = `MISSING`
- 这意味着本轮 **触发 Batch 6 exception**；收口的是 preflight 主入口与报告规范，不等于 Batch 6 final release verdict 已可升级为 `可发布`。
- `docs/27` 当前只应保持 `provisional: 有条件发布`，直到后续 smoke 收敛完成。

### 验证
- canonical 三件套（隔离 worktree）：
  - worktree `/tmp/solana-zig-b6-52-d60cc1c`
  - commit `93bb638`
  - `git status --short` 为空（clean）
  - `zig build test --summary all`：`91/91 tests passed`
- preflight 样例运行：
  - command：`ALLOW_BATCH6_EXCEPTION=true scripts/release/preflight_batch6.sh /tmp/batch6-preflight-93bb638`
  - report：`/tmp/batch6-preflight-93bb638/batch6-preflight-20260416-200221-93bb638.md`
  - result：
    - `build/test`: `PASS`
    - `smoke(public devnet)`: `MISSING`
    - `smoke(local-live)`: `MISSING`
    - `exception_required`: `true`
    - `verdict`: `有条件发布`
- gate 结论：
  - `G-P2F-01` ✅
  - `G-P2F-04` ✅
  - `G-P2F-05` ✅
