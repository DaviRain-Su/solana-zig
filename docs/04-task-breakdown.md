# Phase 4 - Task Breakdown

## 1. 执行约束

- 所有任务默认 `Commit`（生产代码）。
- 单任务目标时长：`<= 4h`。
- 每个任务必须有可审计产物（代码/测试/文档）。
- 每完成 3 个任务执行一次熵检查（禁止 silent fallback / 重复分叉）。

## 2. 里程碑与阶段

- M1：核心稳定（core + tx 离线兼容）
- M2：RPC 可用（高频方法 + mock 覆盖）
- M3：可展示（Devnet E2E + 文档收口）
- M4：接口扩展（system/token/token-2022/...）
- M5：签名后端扩展（可插拔 key management）

## 3. 当前迭代任务（M1-M3）

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

## 4. 后续全量任务（M4-M5）

### 4.1 接口能力（M4）

| ID | 预估 | 依赖 | 验收标准 |
|---|---:|---|---|
| T4-17 | 4h | M3 | 新建 `interfaces/system` 模块 |
| T4-18 | 4h | T4-17 | system transfer/create 指令构造与测试 |
| T4-19 | 4h | M3 | 新建 `interfaces/token` 模块 |
| T4-20 | 4h | T4-19 | token mint/transfer/ATA 基础路径 |
| T4-21 | 4h | T4-20 | token-2022 基础扩展路径 |
| T4-22 | 3h | T4-17,T4-21 | 接口能力兼容矩阵初版 |

### 4.2 签名后端（M5）

| ID | 预估 | 依赖 | 验收标准 |
|---|---:|---|---|
| T4-23 | 4h | M4 | `signers` 抽象接口定义 |
| T4-24 | 3h | T4-23 | in-memory signer 实现 |
| T4-25 | 4h | T4-23 | 外部 signer adapter（mock/KMS stub） |
| T4-26 | 3h | T4-24,T4-25 | tx 流程接入 signer 抽象 |
| T4-27 | 3h | T4-26 | signer 集成测试与错误语义测试 |

## 5. 执行顺序

1. `T4-01 -> T4-16`（M1-M3）
2. `T4-17 -> T4-22`（M4）
3. `T4-23 -> T4-27`（M5）

## 6. DoD（每任务）

- 功能代码完成且可构建。
- 至少 1 个 Happy + 1 个 Error 测试（文档任务除外）。
- `zig build test` 全量通过。
- 若接口变化，必须同步 `docs/03/05/README`。
- 在 `docs/06-implementation-log.md` 记录输入/输出/风险/验证。

## 7. 风险与回滚

- v0 与 Rust 语义偏差：以增量提交隔离并快速回滚。
- RPC 解析不稳定：先收紧 typed parse 子集再扩展。
- Devnet 波动：E2E 仅 opt-in，不阻塞离线门禁。
