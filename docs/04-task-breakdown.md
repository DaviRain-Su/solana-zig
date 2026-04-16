# Phase 4 - Task Breakdown

## 执行约束

- 所有任务定义为 `Commit`（生产代码），必须遵守 Phase 3 规格与 Phase 5 测试先行。
- 单任务目标时长：`<= 4h`。
- 每个任务完成后必须留下可审计产物（代码、测试、文档或日志）。
- 每连续完成 3 个任务，执行一次“代理熵检查”（禁止 silent fallback / 重复实现分叉）。

## 里程碑定义

- M1（核心稳定）：core + tx 字节兼容路径与离线测试可回归。
- M2（RPC 可用）：5 个高频 RPC 的稳定解析与错误保真。
- M3（可展示）：Devnet 端到端演示与文档闭环。

## 任务清单（决策已锁定）

| ID | Type | 预估 | 依赖 | 交付物 | 验收标准 |
|---|---|---:|---|---|---|
| T4-01 | Commit | 2h | 无 | `docs/03` 与 `docs/05` 对齐补注 | `03` 中接口和 `05` 用例映射一一对应，无 dangling API |
| T4-02 | Commit | 3h | T4-01 | `src/solana/core/base58.zig` 边界增强 | 新增最大长度/前导零/非法字符测试，`zig build test` 通过 |
| T4-03 | Commit | 2h | T4-01 | `src/solana/core/shortvec.zig` 溢出与截断覆盖 | 溢出、截断、边界值测试覆盖并通过 |
| T4-04 | Commit | 2h | T4-02 | `Pubkey/Signature/Hash` 长度与 roundtrip 强化 | 固定长度错误路径覆盖，oracle 对照仍通过 |
| T4-05 | Commit | 3h | T4-04 | `Keypair` 签名一致性测试扩展 | 多消息签名与验签路径稳定，无 flaky |
| T4-06 | Commit | 4h | T4-03,T4-04 | `Message.compileV0` 正向场景测试 | 包含 lookup 命中路径、序列化/反序列化互逆 |
| T4-07 | Commit | 4h | T4-06 | `Message.compileV0` 失败场景测试 | 覆盖 duplicate lookup key / overflow / invalid version |
| T4-08 | Commit | 3h | T4-06 | `VersionedTransaction` v0 交易签名路径 | v0 签名、序列化、反序列化、验签通过 |
| T4-09 | Commit | 3h | T4-08 | `VersionedTransaction` 失败路径补齐 | 缺失签名、尾字节残留、签名数量不匹配覆盖 |
| T4-10 | Commit | 4h | T4-01 | RPC 可替换 transport 抽象（用于 mock） | `RpcClient` 可在测试中注入 fake transport |
| T4-11 | Commit | 4h | T4-10 | RPC 单元测试：`getLatestBlockhash/getBalance` | 正常响应 + 错误响应 + 结构错误覆盖 |
| T4-12 | Commit | 4h | T4-10 | RPC 单元测试：`getAccountInfo/simulate/send` | 覆盖 base64 入参、rpc_error 保真、解析异常 |
| T4-13 | Commit | 3h | T4-11,T4-12 | `RpcErrorObject` 生命周期一致性 | 无内存泄露，错误对象释放规范化 |
| T4-14 | Commit | 4h | T4-08,T4-12 | Devnet E2E 测试脚手架 | 环境变量门控：无 `SOLANA_RPC_URL` 时自动跳过 |
| T4-15 | Commit | 3h | T4-14 | Devnet 演示样例（构造->签名->模拟->发送） | 示例可复现，失败信息可读 |
| T4-16 | Commit | 2h | T4-15 | 文档收口：README + 06/07/08 更新 | 覆盖能力矩阵、已知限制、下一步计划 |

## 执行顺序（必须按此顺序）

1. `T4-01 -> T4-05`（M1 核心稳定）
2. `T4-06 -> T4-09`（v0 与交易闭环）
3. `T4-10 -> T4-13`（M2 RPC 可用）
4. `T4-14 -> T4-16`（M3 可展示）

## 每任务完成定义（DoD）

- 对应功能代码已实现或重构完成。
- 至少新增 1 个 Happy Path + 1 个 Error Path 测试（纯文档任务除外）。
- `zig build test` 全量通过。
- 若任务涉及接口变化，`docs/03` 与 `README` 同步更新。
- 在 `docs/06-implementation-log.md` 追加任务记录（输入、输出、风险、结论）。

## 风险与回滚策略

- 风险：v0 lookup 行为与 Rust 语义存在细节偏差。  
  回滚：保留 legacy 路径稳定性，v0 改动以 feature gate 或增量提交隔离。
- 风险：RPC 响应动态解析导致边界遗漏。  
  回滚：先收紧 typed parse 最小子集，再逐步开放字段。
- 风险：Devnet 网络不稳定导致 CI 波动。  
  回滚：E2E 默认 opt-in，仅在环境变量存在时执行。
