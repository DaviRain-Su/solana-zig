# Phase 3 - Technical Spec

> 注：本文标题中的“Phase 3”是文档生命周期序号（技术规格文档），不是产品路线图中的 Product Phase 3。

## 1. Scope

本规格覆盖当前 `Phase 1` 的 Zig 实现边界：
- core: `base58/shortvec/Pubkey/Signature/Keypair/Hash`
- tx: `Instruction/Message(legacy+v0)/VersionedTransaction`
- rpc: `HttpTransport/RpcClient` 及 5 个高频方法
- compat: `oracle_vector` / `bincode_compat`

不覆盖：
- on-chain `no_std/SBF` 运行时语义
- 全量 JSON-RPC 方法映射
- Rust 宏生态等高级 API 对齐

---

## 2. Data Structures (字段、类型、字节)

### 2.1 Core 固定长度类型

| Type | Field | Zig Type | Byte Size | Constraint |
|---|---|---:|---:|---|
| `Pubkey` | `bytes` | `[32]u8` | 32 | 必须固定 32 字节 |
| `Signature` | `bytes` | `[64]u8` | 64 | 必须固定 64 字节 |
| `Hash` | `bytes` | `[32]u8` | 32 | 必须固定 32 字节 |

### 2.2 Shortvec

- 编码：7-bit continuation varint
- 每字节低 7 位是 payload；高位 `0x80` 表示后续仍有字节
- 输入截断时抛 `error.InvalidShortVec`
- 位移溢出时抛 `error.IntegerOverflow`

### 2.3 交易模型

| Type | Field | Zig Type | Notes |
|---|---|---|---|
| `AccountMeta` | `pubkey` | `Pubkey` | 账户键 |
|  | `is_signer` | `bool` | 是否签名 |
|  | `is_writable` | `bool` | 是否可写 |
| `Instruction` | `program_id` | `Pubkey` | 程序 id |
|  | `accounts` | `[]const AccountMeta` | 账户列表 |
|  | `data` | `[]const u8` | 指令数据，可空 |
| `MessageHeader` | `num_required_signatures` | `u8` | 交易需签名数 |
|  | `num_readonly_signed_accounts` | `u8` | 已签名只读数 |
|  | `num_readonly_unsigned_accounts` | `u8` | 未签名只读数 |
| `CompiledInstruction` | `program_id_index` | `u8` | program 索引 |
|  | `account_indexes` | `[]u8` | account 索引数组 |
|  | `data` | `[]u8` | 指令数据 |
| `CompiledAddressLookup` | `account_key` | `Pubkey` | ALT 账户 |
|  | `writable_indexes` | `[]u8` | 可写索引 |
|  | `readonly_indexes` | `[]u8` | 只读索引 |
| `Message` | `version` | `enum{legacy,v0}` | legacy / v0 |
|  | `header` | `MessageHeader` | 头部 |
|  | `account_keys` | `[]Pubkey` | 静态 key 列表 |
|  | `recent_blockhash` | `Hash` | 最近 blockhash |
|  | `instructions` | `[]CompiledInstruction` | 编译后指令 |
|  | `address_table_lookups` | `[]CompiledAddressLookup` | 仅 v0 有意义 |
| `VersionedTransaction` | `signatures` | `[]Signature` | 长度应等于 `num_required_signatures` |
|  | `message` | `Message` | 被签名消息 |

### 2.4 RPC 结构

| Type | Field | Zig Type | Notes |
|---|---|---|---|
| `RpcClient` | `endpoint` | `[]const u8` | RPC URL |
|  | `next_id` | `u64` | JSON-RPC id，自增，初始 1 |
| `LatestBlockhash` | `blockhash` | `Hash` | base58 转 32 bytes |
|  | `last_valid_block_height` | `u64` | 从 `result.value.lastValidBlockHeight` 解析 |
| `SendTransactionResult` | `signature` | `Signature` | base58 转 64 bytes |
| `RpcErrorObject` | `code` | `i64` | 原样透传 |
|  | `message` | `[]const u8` | 原样透传 |
|  | `data_json` | `?[]const u8` | `error.data` JSON stringify |

---

## 3. Public Interfaces (函数契约)

### 3.1 Core

```zig
pub fn Pubkey.fromBase58(input: []const u8) !Pubkey
pub fn Pubkey.toBase58Alloc(self: Pubkey, allocator: std.mem.Allocator) ![]u8

pub fn Signature.fromBase58(input: []const u8) !Signature
pub fn Signature.toBase58Alloc(self: Signature, allocator: std.mem.Allocator) ![]u8
pub fn Signature.verify(self: Signature, msg: []const u8, pubkey: Pubkey) !void

pub fn Keypair.fromSeed(seed: [32]u8) !Keypair
pub fn Keypair.sign(self: Keypair, msg: []const u8) !Signature

pub fn shortvec.encodeAlloc(allocator: std.mem.Allocator, value: usize) ![]u8
pub fn shortvec.decode(input: []const u8) !DecodeResult
```

前置条件：
- `fromSlice` 类 API 输入长度必须精确匹配固定字节数
- `Keypair.fromSeed` 只接受 32 字节 seed

后置条件：
- `toBase58Alloc` 返回内容可被对应 `fromBase58` 还原
- `Keypair.sign` 返回可被 `Signature.verify` 验证

### 3.2 Message / Transaction

```zig
pub fn Message.compileLegacy(... ) !Message
pub fn Message.compileV0(..., lookup_tables: []const AddressLookupTable) !Message
pub fn Message.serialize(self: Message, allocator: std.mem.Allocator) ![]u8
pub fn Message.deserialize(allocator: std.mem.Allocator, bytes: []const u8) !Message.DecodeResult

pub fn VersionedTransaction.initUnsigned(allocator: std.mem.Allocator, message: Message) !VersionedTransaction
pub fn VersionedTransaction.sign(self: *VersionedTransaction, signers: []const Keypair) !void
pub fn VersionedTransaction.verifySignatures(self: VersionedTransaction) !void
pub fn VersionedTransaction.serialize(self: VersionedTransaction, allocator: std.mem.Allocator) ![]u8
pub fn VersionedTransaction.deserialize(allocator: std.mem.Allocator, bytes: []const u8) !VersionedTransaction
```

前置条件：
- `compileLegacy/compileV0` 必须传入 payer
- `sign` 时若某 required signer 未提供，返回 `error.MissingRequiredSignature`

后置条件：
- `serialize` 与 `deserialize` 互逆（在输入合法时）
- `verifySignatures` 按 `message.header.num_required_signatures` 校验签名

### 3.3 RPC

```zig
pub fn RpcClient.getLatestBlockhash(self: *RpcClient) !RpcResult(LatestBlockhash)
pub fn RpcClient.getAccountInfo(self: *RpcClient, pubkey: Pubkey) !RpcResult(OwnedJson)
pub fn RpcClient.getBalance(self: *RpcClient, pubkey: Pubkey) !RpcResult(u64)
pub fn RpcClient.simulateTransaction(self: *RpcClient, tx: VersionedTransaction) !RpcResult(OwnedJson)
pub fn RpcClient.sendTransaction(self: *RpcClient, tx: VersionedTransaction) !RpcResult(SendTransactionResult)
```

前置条件：
- `endpoint` 必须是可访问 URL
- `simulate/send` 输入交易必须可序列化

后置条件：
- 若响应含 `error` 字段，返回 `RpcResult.rpc_error`
- 非 200 HTTP 状态码映射为 `error.RpcTransport`
- JSON 结构不符合预期映射为 `error.InvalidRpcResponse`

### 3.3.1 Phase 1 `getAccountInfo` 最小 typed 子集

当前公开 API 仍允许 `getAccountInfo(...) !RpcResult(OwnedJson)`，以保留兼容与渐进收敛空间。
但在 Product Phase 1 closeout 时，`AccountInfo` 至少应能稳定抽取并校验以下最小 typed 子集：
- `lamports: u64`
- `owner: Pubkey`
- `executable: bool`
- `rentEpoch: u64`

当前阶段可继续保留为未完全 typed / 原样承载的内容：
- `data`
- 更复杂 encoding 变体
- 暂未稳定建模的扩展字段

这意味着：Phase 1 关注的是“高价值基础字段”的最小收敛，而不是把完整 `AccountInfo` 一次性 fully typed 化。

---

## 4. Binary Protocol Specs

### 4.1 Message serialization

#### Legacy

```
[header:3]
[shortvec account_keys_len]
[account_keys bytes = 32 * N]
[recent_blockhash:32]
[shortvec instructions_len]
  repeat:
  [program_id_index:1]
  [shortvec account_indexes_len]
  [account_indexes bytes]
  [shortvec data_len]
  [data bytes]
```

#### V0

```
[version_prefix: 0x80]
[legacy body same as above]
[shortvec lookups_len]
  repeat:
  [lookup.account_key:32]
  [shortvec writable_indexes_len]
  [writable_indexes bytes]
  [shortvec readonly_indexes_len]
  [readonly_indexes bytes]
```

### 4.2 Transaction serialization

```
[shortvec signatures_len]
[signature bytes = 64 * N]
[message bytes]
```

签名 payload：
- 直接使用 `message.serialize(...)` 的完整字节序列

---

## 5. Compile / Ordering Algorithms

### 5.1 Account ordering rule

`Message.compile*` 采用固定分类顺序输出静态账户：
1. signer + writable
2. signer + readonly
3. nonsigner + writable
4. nonsigner + readonly

同一账户多次出现时合并：
- `is_signer = old OR new`
- `is_writable = old OR new`

### 5.2 v0 lookup 注入规则

- 仅 `!is_signer` 且与 lookup 权限语义兼容的账户可走 ALT：
  - `is_writable = true` 的账户只能使用 writable lookup entry
  - `is_writable = false` 的账户只能使用 readonly lookup entry
- 动态索引从 `account_keys.len` 开始递增
- 若 lookup key 与静态 key 冲突，跳过 lookup 注入（静态 key 优先）
- 若同一 pubkey 被多个 lookup 条目重复注入（动态域内重复），返回 `error.DuplicateLookupKey`
- 若动态索引超过 `u8` 上限，返回 `error.TooManyAccounts`

---

## 6. RPC Request/Response Contracts

### 6.1 Fixed request defaults

- `getLatestBlockhash`: `commitment=confirmed`
- `getAccountInfo`: `encoding=base64`
- `simulateTransaction`: `encoding=base64`, `sigVerify=true`
- `sendTransaction`: `encoding=base64`, `skipPreflight=false`

### 6.2 Transport

- method: POST
- headers:
  - `Content-Type: application/json`
  - `Accept: application/json`
- status 仅接受 `200 OK`

### 6.3 Parse strategy

- Root 必须是 JSON object
- 先检查 `error` 字段
- 再按方法读取 `result` 字段
- integer 字段支持 `integer` 与 `number_string` 两种表示

---

## 7. Error Model

核心错误集合定义于 `src/solana/errors.zig`：
- 编码解码：`InvalidBase58/InvalidLength/InvalidShortVec/IntegerOverflow`
- 消息交易：`MissingAccountKey/MissingProgramId/TooManyAccounts/DuplicateLookupKey/InvalidMessage/InvalidTransaction/SignatureCountMismatch/MissingRequiredSignature/UnsupportedMessageVersion`
- RPC 传输/解析：`RpcTransport/RpcParse/InvalidRpcResponse/RpcTimeout`

RPC 业务错误封装定义于 `src/solana/rpc/types.zig`：
- `RpcErrorObject { code, message, data_json }`
- `RpcResult(T)`：`ok: T` 或 `rpc_error: RpcErrorObject`
- 当 JSON-RPC 返回 `error` 字段时，必须走 `RpcResult.rpc_error`，不丢失 `code/message/data` 语义

---

## 8. State Machine

### 8.1 Transaction lifecycle

`Draft -> CompiledMessage -> UnsignedTx -> SignedTx -> SerializedTx -> Submitted`

状态转换：
- `Draft -> CompiledMessage`: `Message.compileLegacy` / `compileV0`
- `CompiledMessage -> UnsignedTx`: `VersionedTransaction.initUnsigned`
- `UnsignedTx -> SignedTx`: `VersionedTransaction.sign`
- `SignedTx -> SerializedTx`: `VersionedTransaction.serialize`
- `SerializedTx -> Submitted`: `RpcClient.sendTransaction`

失败回退：
- 任一阶段返回 error，状态保持在上一个稳定状态，不做隐式重试

---

## 9. Constants and Defaults

- `Pubkey.LENGTH = 32`
- `Signature.LENGTH = 64`
- `Hash.LENGTH = 32`
- `RpcClient.next_id` 初始值 `1`
- v0 message 前缀字节：`0x80`
- `VersionedTransaction` 空签名槽默认 `64` 个 `0x00`

---

## 10. Boundary & Failure Scenarios

1. base58 输入含非法字符（如 `0/O/I/l`） -> `error.InvalidBase58`
2. `Pubkey.fromSlice` 长度非 32 -> `error.InvalidLength`
3. `Signature.fromSlice` 长度非 64 -> `error.InvalidLength`
4. shortvec 输入截断（如 `[0x80]`） -> `error.InvalidShortVec`
5. shortvec 移位溢出 -> `error.IntegerOverflow`
6. message 字节为空 -> `error.InvalidMessage`
7. message 版本字节高位且版本号非 0 -> `error.UnsupportedMessageVersion`
8. deserialize 时字段越界（含 compiled instruction 的 `program_id_index/account_indexes` 超出静态+动态账户空间） -> `error.InvalidMessage`
9. tx 反序列化后仍有尾字节 -> `error.InvalidTransaction`
10. required signer 未全部签名 -> `error.MissingRequiredSignature`
11. 签名数组长度与 header 不符 -> `error.SignatureCountMismatch`
12. v0 lookup key 与静态 key 冲突 -> 跳过注入，不报错
13. v0 lookup key 在动态域重复注入 -> `error.DuplicateLookupKey`
14. v0 动态索引超过 `u8` -> `error.TooManyAccounts`
15. RPC 返回非 200 -> `error.RpcTransport`
16. RPC 返回 JSON 非 object -> `error.InvalidRpcResponse`
17. RPC `result` 字段缺失或类型不符 -> `error.InvalidRpcResponse`

---

## 11. Test Mapping (实现与规格对应)

当前代码内已覆盖：
- base58 roundtrip + 非法字符
- shortvec roundtrip + invalid
- pubkey/signature 固定长度校验
- keypair sign/verify
- legacy message compile/serialize/deserialize
- 空 instruction data
- v0 lookup 语义的基础回归：
  - 静态 key 冲突时跳过 lookup
  - 动态域重复 lookup key 报错
  - writable 账户不会被 readonly lookup 错配降级
- message 反序列化硬化：
  - header/account key 一致性校验
  - 截断输入清理路径
  - compiled instruction 索引越界校验
- tx sign/serialize/deserialize/verify
- 缺失签名失败
- RpcClient mock transport 测试：
  - happy path
  - rpc_error 保真
  - transport error
  - `getAccountInfo` / `simulateTransaction` malformed success response 清理
- 导出 API 可用性：`Message.DecodeResult` 可经包导出被外部引用
- oracle vector 对照（当前为 v2 core 子集：pubkey/hash/shortvec）

后续必须补齐（下一阶段 04/05 执行）：
- 更完整的 v0 / ALT oracle 与失败路径覆盖（尤其是多 lookup / versioned tx 场景）
- RPC 其余高频方法的 malformed/typed parse 收口与更系统的错误路径覆盖
- 真正的 Devnet acceptance harness / E2E 证据链（当前仍只有 wrapper / 外部 harness 路径）

---

## 12. Implementation Decisions Locked

- 行为兼容优先于 API 命名兼容
- 单仓多模块，不拆多包
- 链下 host/client 优先
- oracle 通过 `testdata/oracle_vectors.json` 固化
- RPC 首期仅高频方法，不追求全量覆盖

---

## 13. Full Implementation Spec Decomposition（后续）

为对齐新版 PRD 的“全量实现”目标，后续技术规格按子模块继续拆分：

- `03a-interfaces-spec.md`：system/token/token-2022/compute-budget/memo 接口层字节契约与 API 契约（主要对应 Product Phase 2-3，其中 compute-budget 可在 Phase 2 提前落地）
- `03b-signers-spec.md`：signer 抽象、后端适配、错误语义与生命周期契约（对应 Product Phase 3）
- `03c-rpc-extended-spec.md`：高频以外 RPC 方法扩展，以及 Phase 1 最小 typed schema 之后的 typed parse 扩展策略与兼容策略（主要对应 Product Phase 2）
- `03d-cabi-spec.md`：C ABI 导出边界、所有权模型、错误码与稳定性契约（对应 Product Phase 3）

当前已建立的子规格文件：
- `docs/03a-interfaces-spec.md`
- `docs/03b-signers-spec.md`
- `docs/03c-rpc-extended-spec.md`
- `docs/03d-cabi-spec.md`

要求：
- 每个子规格必须包含：数据结构、接口、边界条件、错误模型、测试映射。
- 子规格不可与本文件冲突；若冲突，以最新 ADR 决策为准并回写本文件。
- 若子规格进入实现阶段，必须同步更新 `docs/04/05/10`。
