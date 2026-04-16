# Surfpool Local E2E Contract (Phase 1)

> `#4 K3` 交付产物：surfpool（本地 RPC / test-validator）E2E 可执行契约模板。  
> 目标：为 `#3 K2`（`@zignocchio/client`）提供行为基线，并为 `#10 C4`（Devnet E2E）提供同构复用模板。
>
> 注：当前 Zig 主库的 RPC public API 已前进到 typed `AccountInfo` / `SimulateTransactionResult`。本文对 wrapper 的要求也以“保留 typed 语义 + 原始 JSON 旁路”为准，不再把 `simulateTransaction` 视为纯 `OwnedJson` 黑盒。

---

## 1. 通用前置（Global Preconditions）

| 项 | 内容 |
|---|---|
| **本地 RPC 端点** | 通过 `SURFPOOL_RPC_URL` 显式提供；推荐本地端点为 `http://127.0.0.1:8899`。 |
| **测试门控** | 未设置 `SURFPOOL_RPC_URL` 时，E2E 测试自动 `return`（skip），不报错、不阻塞 CI；**不存在隐式默认端点回退执行**。 |
| **Allocator** | 全程使用 `std.testing.allocator`，零泄漏为强制断言。 |
| **固定 Seed** | 所有 keypair 使用 `fromSeed([_]u8{1} ** 32)`，确保输入绝对固定。 |
| **时间约束** | 单次 case 执行 ≤ 5 秒；超时视为环境异常。 |

---

## 2. Case K3-H1 — Signed Local Flow（Protocol-Level Happy Path）

### 2.1 Preconditions

1. 本地 RPC 进程已启动且可响应（`getHealth` 或等效心跳通过）。
2. `SURFPOOL_RPC_URL` 已设置为该本地端点。
3. 不依赖任何预存账户余额、airdrop 或 program 部署状态。
4. 因不假设 program 已部署，S6 的“happy”定义是 **RPC / client 路径成功返回可检查的 simulation 结果**，而不是链上程序执行结果必然 `err == null`。

### 2.2 Fixed Inputs

| 名称 | 类型 | 值 |
|---|---|---|
| `endpoint` | `[]const u8` | `try std.process.getEnvVarOwned(allocator, "SURFPOOL_RPC_URL")` |
| `payer_seed` | `[32]u8` | `[_]u8{1} ** 32` |
| `program_id` | `Pubkey` | `Pubkey.init([_]u8{0x06} ** 32)` |
| `receiver` | `Pubkey` | `Pubkey.init([_]u8{0x07} ** 32)` |
| `ix_data` | `[]const u8` | `&[_]u8{0x01, 0x02, 0x03}` |

### 2.3 Steps

| # | 动作 | API |
|---|---|---|
| S1 | 初始化 RPC client | `var client = try RpcClient.init(allocator, .default, endpoint); defer client.deinit();` |
| S2 | 获取最新 blockhash | `const bh = try client.getLatestBlockhash();` |
| S3 | 构造 legacy message | `var msg = try Message.compileLegacy(allocator, payer.pubkey(), &ixs, bh.ok.blockhash);` |
| S4 | 构造 unsigned tx | `var tx = try VersionedTransaction.initUnsigned(allocator, msg); defer tx.deinit();` |
| S5 | 签名并验签 | `try tx.sign(&[_]Keypair{payer}); try tx.verifySignatures();` |
| S6 | 模拟交易 | `const sim = try client.simulateTransaction(tx);` |

### 2.4 Expected Output & Assertions

| 步骤 | 预期返回 | 断言 |
|---|---|---|
| S2 | `.ok` variant | `A-H1: try std.testing.expect(bh == .ok);` |
| S2 | `blockhash` 有效 | `A-H2: try std.testing.expect(bh.ok.last_valid_block_height > 0);` |
| S3-S5 | 无 error | `A-H3: 无 Zig error union 返回` |
| S5 | 签名长度固定 64 bytes | `A-H3a: try std.testing.expectEqual(@as(usize, 64), tx.signatures[0].bytes.len);` |
| S5 | 验签通过 | `A-H3b: try tx.verifySignatures();`（已在步骤中执行，断言为不抛错） |
| S2 | blockhash 非空（可 base58 编码） | `A-H3c: blockhash.toBase58Alloc 成功且结果长度 > 0` |
| S6 | `.ok` variant | `A-H4: try std.testing.expect(sim == .ok);` |
| S6 | simulation 结果保留 typed + raw 语义 | `A-H5: 可检查 sim.ok.logs / sim.ok.units_consumed，并通过 sim.ok.err_json / sim.ok.raw_json 保留错误与原始响应语义` |

---

## 3. Case K3-F1 — Failure Path

### 3.1 Preconditions

与 K3-H1 **完全相同**，唯一区别：S5 中 **不执行签名**。

### 3.2 Fixed Inputs

与 K3-H1 完全一致。

### 3.3 Steps

| # | 动作 | API |
|---|---|---|
| S1 | 初始化 RPC client | `var client = try RpcClient.init(allocator, .default, endpoint); defer client.deinit();` |
| S2 | 获取最新 blockhash | `const bh = try client.getLatestBlockhash();` |
| S3 | 构造 legacy message | `var msg = try Message.compileLegacy(allocator, payer.pubkey(), &ixs, bh.ok.blockhash);` |
| S4 | 构造 unsigned tx | `var tx = try VersionedTransaction.initUnsigned(allocator, msg); defer tx.deinit();` |
| S5 | **跳过签名** | — |
| S6 | 模拟交易 | `const sim = try client.simulateTransaction(tx);` |

> **失败点说明**：S6 因 `simulateTransaction` RPC payload 包含 `"sigVerify": true`，服务端在签名验证阶段拒绝全零签名，返回 RPC 层 error。

### 3.4 Expected Output & Assertions

| 步骤 | 预期返回 | 断言 |
|---|---|---|
| S6 | **首选**：`.rpc_error` variant | `A-F1: try std.testing.expect(sim == .rpc_error);` |
| S6 | **兜底**：若返回 `.ok`，则 `err_json != null` | `A-F1-fallback: switch (sim) { .ok => |v| { /* 断言 v.err_json != null */ }, .rpc_error => {} }` |
| S6 | `.rpc_error` 时 `code < 0` | `A-F2: try std.testing.expect(sim.rpc_error.code < 0);` |
| S6 | `.rpc_error` 时 `message` 非空 | `A-F3: try std.testing.expect(sim.rpc_error.message.len > 0);` |
| 全局 | 零泄漏 | `A-F4: std.testing.allocator 自动检测` |

---

## 4. Determinism Contract

| 规则 | 说明 |
|---|---|
| **D-01 端点隔离** | 仅访问 `SURFPOOL_RPC_URL` 显式指定的本地地址（推荐 `127.0.0.1`），不触及外部网络。 |
| **D-02 种子固定** | `Keypair.fromSeed([_]u8{1} ** 32)` 为唯一合法 payer seed；禁止随机生成。 |
| **D-03 无状态依赖** | 不读取链上账户余额、不依赖 program 部署、不要求 airdrop。 |
| **D-04 可跳过** | 当 `SURFPOOL_RPC_URL` 未设置时，测试立即 `return;`，行为等同于 `zig build test` 不执行本 case。 |
| **D-05 超时保护** | 任意 RPC 调用或序列化步骤超时 > 5 秒即视为环境失败，不视为产品缺陷。 |

---

## 5. API Contract Exports（`#3 K2` 硬约束）

以下字段/签名/行为必须在 `#3` 的 `@zignocchio/client` 实现中原样暴露或保留：

| 编号 | 约束 | 来源 | 影响面 |
|---|---|---|---|
| **C-01** | `RpcClient` 必须保留 `initWithTransport(allocator, endpoint, transport)`，支持 transport 注入。 | `client.zig` | mock / E2E /
| **C-02** | `getLatestBlockhash()` 返回 `RpcResult(LatestBlockhash)`，结构体字段名为 `blockhash` + `last_valid_block_height`。 | `rpc/types.zig` | wrapper 类型映射 |
| **C-03** | 高频 typed RPC 结果必须跟随当前 Zig public API：`getAccountInfo -> RpcResult(AccountInfo)`、`simulateTransaction -> RpcResult(SimulateTransactionResult)`；wrapper 至少保留关键 typed 字段与 `raw_json/err_json` 旁路，不能退化为丢语义的黑盒 JSON。 | `client.zig` / `rpc/types.zig` | error / result 包装 |
| **C-04** | `VersionedTransaction.sign(&[_]Keypair{...})` 接收 signer 切片；签名后 `verifySignatures()` 独立可用。 | `tx/transaction.zig` | TS API 签名 |
| **C-05** | `Message.compileLegacy(allocator, payer, instructions, recent_blockhash)` 参数顺序与类型固定。 | `tx/message.zig` | TS helper 映射 |
| **C-06** | `simulateTransaction` 发出的 RPC payload 必须固定携带 `"sigVerify": true`；否则 K3-F1 失效。 | `client.zig` | RPC 请求构造 |
| **C-07** | `#3` 的 connection/endpoint 配置必须是可注入字符串，不能写死 `https://api.devnet.solana.com`。 | E2E 需求 | 初始化 API |

---

## 6. Out-of-Scope（不承诺）

以下能力**不在**本 contract 覆盖范围内，且 `#3` 的实现也不得借本 contract 提前承诺：

- **Websocket / 订阅**（Phase 2）
- **Token Program / ATA / ComputeBudget 等上层接口抽象**（Phase 3）
- **C ABI 导出**（Phase 3）
- **`sendTransaction` 的真实上链确认 / 回执轮询**（本 contract 只到 `simulateTransaction`）
- **v0 message with Address Lookup Table**（本 contract 使用 legacy message，保持最小路径）
- **no_std / SBF 链上程序**（Phase 4）

---

## 7. `docs/11` Phase 1 Closeout Gate 映射

| 本 contract 断言/步骤 | 对应 `docs/11` Gate | 说明 |
|---|---|---|
| K3-H1 S2-S6 + K3-F1 S6 | **G-CLOSE-03** RPC Gate（局部支撑） | 补齐 `simulateTransaction` 的本地 happy/rpc_error/err 语义检查；不替代完整 closeout 证据 |
| K3-H1 S3-S5 构造/签名/验签 | **G-CLOSE-04** Tx 侧证据（局部支撑） | 仅覆盖 transaction 构造/签名/验签路径；**不能替代** `docs/11` 中对 v0 compile 证据的要求 |
| K3-H1 + K3-F1 使用 `std.testing.allocator` | **G-CLOSE-01** Test Gate | 强制零泄漏检测 |
| 本地构造→签名→模拟模板 | **不直接满足 G-CLOSE-05** | 本 contract 只是 Devnet E2E 的本地同构模板；真正的 Devnet Gate 仍以 `SOLANA_RPC_URL` 条件下的 Devnet evidence 为准 |
| 固定 seed 的 keypair 签名 | **G-CLOSE-02** Oracle Gate（局部支撑） | `fromSeed` + `sign` + `verify` 与 oracle 向量中的确定性签名要求一致，但不能替代完整 oracle 集 |

---

## 8. `#3` 实现最小验收清单（可测试项）

将 C-01~C-07 翻译为 `#3 K2` review 时的逐项验收标准：

| 编号 | 验收项 | 测试方式 |
|---|---|---|
| **AC-01** | client 支持 transport 注入 | 提供 `initWithTransport` 等价方法；mock transport 单测通过 |
| **AC-02** | `getLatestBlockhash` 返回结构不变 | 调用后读取 `.ok.blockhash` 与 `.ok.last_valid_block_height` 成功 |
| **AC-03** | 高频 typed RPC 结果不丢语义 | `simulateTransaction` 至少暴露等价的 `err/logs/units_consumed/raw_json` 语义；若提供 `getAccountInfo`，至少暴露 `lamports/owner/executable/rent_epoch` + 原始旁路 |
| **AC-04** | `sign` + `verifySignatures` 独立可用 | 签名切片输入 + 签名后 `verifySignatures()` 不抛错 |
| **AC-05** | `compileLegacy` 参数顺序不变 | 传入 `(allocator, payer, instructions, recent_blockhash)` 成功 |
| **AC-06** | simulate payload 带 `sigVerify: true` | mock transport 捕获请求体，正则/assert 包含 `"sigVerify":true` |
| **AC-07** | endpoint 可配置 | 实例化 client 时传入任意字符串（包括 `http://127.0.0.1:8899`）成功 |

---

## 9. 建议的文件落点

- **Contract 文档**：`docs/18-surfpool-e2e-contract.md`（本文档）
- **测试实现**：`src/e2e/surfpool.zig`
- **build.zig 注册**：新增 `zig build e2e` step，依赖 `SURFPOOL_RPC_URL` 门控

---

## 10. 变更历史

| 日期 | 版本 | 说明 |
|---|---|---|
| 2026-04-16 | v1.0 | 按可执行模板格式输出，供 `#3` / `#10` 直接引用 |
