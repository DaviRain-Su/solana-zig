# Phase 4 - Task Breakdown

> 注：本文标题中的“Phase 4”是文档生命周期序号（任务拆解文档），不是产品路线图阶段编号。
>
> 本文统一采用以下命名：`Product Phase` 表示产品路线图阶段，`M1~M3` 仅表示当前 Product Phase 1 的执行里程碑。

## 1. 执行约束

- 所有任务默认 `Commit`（生产代码）。
- 单任务目标时长：`<= 4h`。
- 每个任务必须有可审计产物（代码/测试/文档）。
- 每完成 3 个任务执行一次熵检查（禁止 silent fallback / 重复分叉）。

## 2. 当前 Product Phase 1 的 Milestones

- M1：核心稳定（core + tx 离线兼容）
- M2：RPC 可用（高频方法 + mock 覆盖）
- M3：Phase 1 收口（Devnet E2E + 文档收口 + oracle/benchmark 补齐）

## 3. 当前承诺任务（Product Phase 1 / M1-M3）

| ID | 预估 | 依赖 | 验收标准 |
|---|---:|---|---|
| T4-01 | 2h | 无 | `docs/03` 与 `docs/05` 用例映射无悬空项 |
| T4-02 | 3h | T4-01 | base58 边界增强，`zig build test` 通过 |
| T4-03 | 2h | T4-01 | shortvec 溢出/截断覆盖 |
| T4-04 | 2h | T4-02 | Pubkey/Signature/Hash 长度与 roundtrip 强化 |
| T4-05 | 3h | T4-04 | Keypair 多消息签名与验签稳定 |
| T4-06 | 4h | T4-03,T4-04 | v0 compile 正向场景覆盖 |
| T4-07 | 4h | T4-06 | v0 失败路径覆盖 |
| T4-08 | 3h | T4-06 | v0 交易签名/验签路径覆盖 |
| T4-09 | 3h | T4-08 | tx 边界与失败路径补齐 |
| T4-10 | 4h | T4-01 | transport 抽象可注入 mock |
| T4-11 | 4h | T4-10 | RPC happy + error + malformed 覆盖（部分方法） |
| T4-12 | 4h | T4-10 | RPC 其余方法与 base64 入参覆盖 |
| T4-13 | 3h | T4-11,T4-12 | RpcErrorObject 生命周期一致性 |
| T4-14 | 4h | T4-08,T4-12 | Devnet E2E 脚手架（ENV 门控） |
| T4-15 | 3h | T4-14 | 端到端示例可复现 |
| T4-16 | 2h | T4-15 | README + 06/07/08 收口 |

执行备注（v0 语义任务）：
- `T4-06/T4-07` 预留 `20%` buffer 用于 Rust oracle 行为对照与冲突语义调试。
- 若语义对照耗时超预期，允许拆分为两个独立 commit（正向路径 / 失败路径），但必须保持同一任务验收闭环。
- 若 Rust oracle 对照发现语义偏差，允许将 `T4-06` 拆分为 `T4-06a/T4-06b` 子任务后执行。

## 4. 后续 Product Phase Backlog（非当前承诺）

### 4.1 Product Phase 2 候选任务（扩展 RPC + 实时/交易增强）

| ID | 预估 | 依赖 | 验收标准 |
|---|---:|---|---|
| T4-17 | 4h | M3 | `getAddressLookupTable` + mock/test |
| T4-18 | 4h | T4-17 | `getTransaction(json baseline)` / `getSignaturesForAddress` / `getTokenAccountsByOwner` 首批覆盖 |
| T4-19 | 4h | T4-17 | `getSlot` / `getEpochInfo` / `getMinimumBalanceForRentExemption` / `requestAirdrop` 覆盖 |
| T4-20 | 4h | T4-18,T4-19 | Websocket 订阅骨架（connect / reconnect / unsubscribe） |
| T4-21 | 4h | T4-17 | Durable Nonce 查询 + `interfaces/system` 中的 Nonce Advance 指令构造 |
| T4-22 | 3h | T4-21 | Priority Fees / Compute Budget 指令构造与测试 |

### 4.2 Product Phase 3 候选任务（interfaces + signers + C ABI）

| ID | 预估 | 依赖 | 验收标准 |
|---|---:|---|---|
| T4-23 | 4h | T4-22 | 新建 `interfaces/system` 与基础测试 |
| T4-24 | 4h | T4-23 | `interfaces/token` + ATA 基础路径 |
| T4-25 | 4h | T4-24 | token-2022 / memo / stake 首批接口能力与覆盖矩阵初版 |
| T4-26 | 4h | T4-23 | `signers` 抽象接口 + in-memory / external adapter |
| T4-27 | 4h | T4-25,T4-26 | C ABI 导出层、头文件与所有权文档 |
| T4-28 | 3h | T4-27 | Phase 3 性能对比报告（vs Rust SDK）与复跑说明 |

## 5. 执行顺序

1. `T4-01 -> T4-16`（当前承诺：Product Phase 1 / M1-M3）
2. `T4-17 -> T4-22`（后续：Product Phase 2 backlog）
3. `T4-23 -> T4-28`（后续：Product Phase 3 backlog）

## 6. DoD（每任务）

- 功能代码完成且可构建。
- 至少 1 个 Happy + 1 个 Error 测试（文档任务除外）。
- `zig build test` 全量通过。
- 若接口变化，必须同步 `docs/03/05/10/README`。
- 在 `docs/06-implementation-log.md` 记录输入/输出/风险/验证。

## 7. 风险与回滚

- v0 与 Rust 语义偏差：以增量提交隔离并快速回滚。
- RPC 解析不稳定：先收紧 typed parse 子集再扩展。
- Websocket / Devnet 外部波动：在线能力全部 opt-in，不阻塞离线门禁。
