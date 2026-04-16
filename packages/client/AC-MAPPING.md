# AC-01~AC-07 Contract Mapping — @zignocchio/client v0.1.0

> Per docs/18 §8, this table maps each acceptance criterion to the TS implementation.

| AC | 约束 | TS 实现位置 | 测试覆盖 | 说明 |
|---|---|---|---|---|
| **AC-01** | client 支持 transport 注入 | `Connection` constructor overload + `Connection.initWithTransport()` | `connection.test.ts` "AC-01: transport injection" (2 tests) | Mock transport 通过 `Transport` interface 注入，与 Zig `initWithTransport` 等价 |
| **AC-02** | `getLatestBlockhash` 返回结构不变 | `Connection.getLatestBlockhash()` → `RpcResult<LatestBlockhash>` | `connection.test.ts` "AC-02: getLatestBlockhash typed response" | 字段名 `blockhash` + `last_valid_block_height` 与 Zig struct 一致 |
| **AC-03** | `simulateTransaction` 保留原始 JSON | `Connection.simulateTransaction()` → `RpcResult<OwnedJson>` | `connection.test.ts` "AC-03: simulateTransaction preserves raw JSON" (2 tests) | 返回 `OwnedJson { value, raw }` 保留完整 JSON，不强制收敛 |
| **AC-04** | `sign` + `verifySignatures` 独立可用 | `VersionedTransaction.sign(signers[])` + `.verifySignatures()` | `transaction.test.ts` "AC-04" (3 tests) | sign 接收 Keypair 数组，verifySignatures 独立调用返回 boolean |
| **AC-05** | `compileLegacy` 参数顺序不变 | `compileLegacy(payer, instructions, recentBlockhash)` | `transaction.test.ts` "AC-05" | 参数顺序 `(payer, instructions, blockhash)` 与 Zig `Message.compileLegacy(allocator, payer, ixs, bh)` 对齐（allocator 在 JS 中不需要） |
| **AC-06** | simulate payload 带 `sigVerify: true` | `Connection.simulateTransaction()` params 硬编码 `sigVerify: true` | `connection.test.ts` "AC-06: simulateTransaction payload carries sigVerify=true" | Mock transport 捕获请求体，JSON.parse 后断言 `params[1].sigVerify === true` |
| **AC-07** | endpoint 可配置 | `Connection(endpoint)` 构造器参数 | `connection.test.ts` "AC-07: endpoint is configurable" | 任意字符串均可，不写死任何默认端点 |

## Out-of-Scope (docs/18 §6)

以下能力 **不在** v0.1.0 实现范围内：

- Websocket / 订阅（Phase 2）
- Token Program / ATA / ComputeBudget（Phase 3）
- C ABI 导出（Phase 3）
- `sendTransaction` 真实上链确认 / 回执轮询（contract 只到 `simulateTransaction`）
- v0 message with Address Lookup Table（使用 legacy message）
- no_std / SBF 链上程序（Phase 4）

## File Inventory

| 文件 | 用途 |
|---|---|
| `src/types.ts` | 核心类型定义（RpcResult, LatestBlockhash, OwnedJson, Transport 等） |
| `src/connection.ts` | RPC client wrapper（AC-01, AC-02, AC-03, AC-06, AC-07） |
| `src/transaction.ts` | Keypair, compileLegacy, VersionedTransaction（AC-04, AC-05） |
| `src/pda.ts` | 最小 PDA helper（findProgramAddress, createProgramAddress） |
| `src/index.ts` | Barrel exports |
| `examples/k3-h1-happy.ts` | K3-H1 happy path 示例（aligned with docs/18 §2） |
| `__tests__/connection.test.ts` | Connection mock transport 测试（8 tests） |
| `__tests__/transaction.test.ts` | Transaction 签名/验签测试（9 tests） |
