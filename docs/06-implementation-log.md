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

## 2026-04-16 第十二次增量记录（收口文档补齐：L4 / Test Mapping / ALT 权限）

### 输入
- 针对最新文档 review，仍有 3 处需要补齐：`docs/02` 的 L4 口径未降级、`docs/03` 的测试映射章节落后于当前代码、`docs/15` 未把 ALT 权限正确性单列为 closeout blocker。

### 输出
- `docs/02-architecture.md` 将 L4 从“Devnet 集成测试”改为“Devnet acceptance harness / 外部集成验证”，并明确当前不是 in-tree E2E 测试层。
- `docs/03-technical-spec.md` 重写 Test Mapping：纳入现有的 mock transport 测试、parser hardening、`Message.DecodeResult` 导出可用性，以及当前 oracle `v2 core` 子集覆盖。

## 2026-04-16 第十五次增量记录（C2: v0/ALT 与 VersionedTransaction 失败路径补强）

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

## 2026-04-16 第十六次增量记录（C3: oracle Phase 1 最低集合补齐）

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

## 2026-04-16 第十七次增量记录（C5/C6: Closeout 文档统一与 Gate Review）

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

## 2026-04-16 第十八次增量记录（文档复核吸收：E2E 口径与 typed RPC 同步）

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

## 2026-04-16 第十八次增量记录（Phase 1 Closeout Declaration）

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
