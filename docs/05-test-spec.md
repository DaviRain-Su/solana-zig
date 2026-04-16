# Phase 5 - Test Spec

## 1. 测试目标

- 验证 Phase 3 的字节契约、接口契约、错误契约。
- 确保 legacy 与 v0 消息/交易路径都可回归。
- 确保 RPC 在成功、业务错误、结构异常三类响应下行为确定。

## 2. 测试层级

- L1 单元测试（纯函数/小结构）：`core/*`
- L2 组件测试（编译与编解码）：`tx/*`
- L3 接口测试（RPC + mock transport）：`rpc/*`
- L4 集成测试（Devnet，环境变量门控）：`rpc + tx + core`
- L5 兼容测试（oracle vectors）：`compat/*`

## 3. 环境与执行

- 默认执行：`zig build test`
- Devnet 集成测试启用条件：存在 `SOLANA_RPC_URL`
- 无 `SOLANA_RPC_URL` 时：L4 全部 skip，不影响整体通过

## 4. 测试数据与夹具

- 固定向量文件：`testdata/oracle_vectors.json`
- deterministic seed：固定 32 字节数组（如 `[_]u8{n} ** 32`）
- mock RPC 响应：JSON 字符串 fixture（按方法分成功/失败/损坏）
- base58 非法字符集合：`0 O I l`

## 5. 核心用例矩阵（Happy / Boundary / Error）

### 5.1 `core/base58`

- Happy
- C-B58-001: 任意字节串 encode->decode roundtrip 相等
- C-B58-002: 含前导零字节输入 roundtrip 保持前导零
- Boundary
- C-B58-101: 空输入 `[]` 编解码
- C-B58-102: 长输入（>256 bytes）编码与反解码一致
- Error
- C-B58-201: 输入含非法字符，返回 `error.InvalidBase58`

### 5.2 `core/shortvec`

- Happy
- C-SV-001: 值 `0/1/127/128/255/16384/1_000_000` roundtrip
- Boundary
- C-SV-101: 单字节上界 `127`
- C-SV-102: 两字节起点 `128`
- Error
- C-SV-201: 截断输入 `[0x80]` -> `error.InvalidShortVec`
- C-SV-202: 移位溢出输入 -> `error.IntegerOverflow`

### 5.3 `core/Pubkey/Signature/Hash/Keypair`

- Happy
- C-KEY-001: `Pubkey.fromBase58/toBase58Alloc` roundtrip
- C-KEY-002: `Keypair.fromSeed + sign + verify` 成功
- Boundary
- C-KEY-101: `Pubkey.fromSlice` 长度 32 成功
- C-KEY-102: `Signature.fromSlice` 长度 64 成功
- Error
- C-KEY-201: `Pubkey.fromSlice` 长度 != 32 -> `error.InvalidLength`
- C-KEY-202: `Signature.fromSlice` 长度 != 64 -> `error.InvalidLength`

### 5.4 `tx/Message`（legacy + v0）

- Happy
- T-MSG-001: `compileLegacy -> serialize -> deserialize` 互逆
- T-MSG-002: 空 `instruction.data` 编译与反序列化成功
- T-MSG-003: `compileV0` 命中 lookup 后序列化/反序列化成功
- Boundary
- T-MSG-101: 账户按 4 类排序（签名/可写规则）正确
- T-MSG-102: 多 instruction 合并账户权限（OR 语义）正确
- Error
- T-MSG-201: v0 版本号非 0 -> `error.UnsupportedMessageVersion`
- T-MSG-202: 字节流越界/截断 -> `error.InvalidMessage`
- T-MSG-203: lookup key 冲突 -> `error.DuplicateLookupKey`
- T-MSG-204: 动态索引溢出 -> `error.TooManyAccounts`

### 5.5 `tx/VersionedTransaction`

- Happy
- T-TX-001: `initUnsigned -> sign -> serialize -> deserialize -> verifySignatures`
- T-TX-002: v0 message 交易签名与验签成功
- Boundary
- T-TX-101: `signatures.len == header.num_required_signatures`
- Error
- T-TX-201: 缺失 required signer -> `error.MissingRequiredSignature`
- T-TX-202: 签名数量不匹配 -> `error.SignatureCountMismatch`
- T-TX-203: 反序列化尾字节残留 -> `error.InvalidTransaction`

### 5.6 `rpc/RpcClient` + `rpc/HttpTransport`

- Happy
- R-RPC-001: `getLatestBlockhash` 成功解析 blockhash 与 lastValidBlockHeight
- R-RPC-002: `getBalance` 成功解析 lamports
- R-RPC-003: `getAccountInfo` 返回 `OwnedJson`
- R-RPC-004: `simulateTransaction` 正常返回 result
- R-RPC-005: `sendTransaction` 返回可解析 signature
- Boundary
- R-RPC-101: `number_string` 数字字段解析为 `u64`
- Error
- R-RPC-201: HTTP 非 200 -> `error.RpcTransport`
- R-RPC-202: 响应非 JSON object -> `error.InvalidRpcResponse`
- R-RPC-203: 缺失 `result` / 字段类型错误 -> `error.InvalidRpcResponse`
- R-RPC-204: JSON 解析失败 -> `error.RpcParse`
- R-RPC-205: 返回 `error` 字段 -> `RpcResult.rpc_error` 且 `code/message/data_json` 保真

### 5.7 `compat/oracle_vector`

- Happy
- O-ORC-001: `pubkey_base58` 与 `pubkey_hex` 对照一致
- O-ORC-002: `shortvec_300_hex` 与编码结果一致

## 6. Devnet 集成场景

- I-DVT-001: `getLatestBlockhash` 成功
- I-DVT-002: 构造并签名最小交易，`simulateTransaction` 成功
- I-DVT-003: `sendTransaction` 返回签名字符串，后续可查询状态
- I-DVT-004: 网络故障/限流时错误可读，不 panic

门控逻辑：
- 若 `SOLANA_RPC_URL` 缺失：标记 `skip`
- 若存在：执行全部 I-DVT-* 用例

## 7. 验收门槛（Gate）

- G1: L1+L2+L5 全绿（离线）
- G2: L3 全绿（mock RPC）
- G3: L4 在配置 `SOLANA_RPC_URL` 时全绿
- G4: 新增/修改公共接口必须带至少 1 个 Happy + 1 个 Error 用例

## 8. 产物要求

- 测试代码与实现同仓维护，随 PR 一起提交。
- `docs/06-implementation-log.md` 记录每批测试新增点与失败修复点。
- `docs/07-review-report.md` 记录测试覆盖缺口和残余风险。
