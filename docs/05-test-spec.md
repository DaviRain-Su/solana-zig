# Phase 5 - Test Spec

## 1. 测试目标

- 验证 Phase 3 的字节契约、接口契约、错误契约。
- 覆盖当前 M1-M3 范围，并为 M4-M5 全量扩展预留测试框架。
- 确保离线测试可作为主门禁，在线测试作为增量验证。

## 2. 测试层级

- L1：core 单元测试
- L2：tx 组件测试
- L3：rpc + mock transport
- L4：Devnet 集成测试（环境变量门控）
- L5：compat/oracle 对照测试
- L6（Phase 2+）：interfaces/signers 集成测试

## 3. 环境与执行

- 默认：`zig build test`
- Devnet 测试启用：`SOLANA_RPC_URL` 存在
- 无 `SOLANA_RPC_URL`：L4 全部 skip，不影响离线门禁
- 所有涉及动态分配的测试必须使用 `std.testing.allocator` 并通过泄漏检测

## 4. 当前范围测试矩阵（M1-M3）

### 4.1 core/base58
- Happy: roundtrip
- Boundary: 空输入、长输入、前导零
- Error: 非法字符

### 4.2 core/shortvec
- Happy: `0/1/127/128/255/16384/1_000_000`
- Boundary: 单字节/双字节边界
- Error: 截断、移位溢出

### 4.3 key types
- Happy: pubkey/signature roundtrip，keypair sign+verify
- Boundary: 固定长度刚好满足
- Error: 固定长度不满足

### 4.4 message/transaction
- Happy: legacy/v0 编译与编解码互逆
- Boundary: 账户排序、权限 OR 合并
- Error: invalid version / invalid message / duplicate lookup / too many accounts / missing signer / signature mismatch / invalid transaction tail

### 4.5 rpc
- Happy: 5 个高频方法
- Boundary: number_string 数字字段解析
- Error: transport error / parse error / invalid response / rpc_error 保真

### 4.6 compat
- Happy: oracle vectors 对照通过

## 5. 全量实现测试扩展（M4-M5）

### 5.1 interfaces（Phase 2+）
- I-FACE-001: system interface 指令字节对齐
- I-FACE-002: token interface 指令参数与账户布局对齐
- I-FACE-003: token-2022 扩展字段边界
- I-FACE-004: 组合交易（system + token）可签名并模拟

### 5.2 signers（Phase 3+）
- I-SIGN-001: in-memory signer 与当前 keypair 行为一致
- I-SIGN-002: 外部 signer adapter 错误语义透传
- I-SIGN-003: signer 切换对交易序列化无副作用

## 6. Gate 定义

- G1：L1+L2+L5 全绿（必需）
- G2：L3 全绿（必需）
- G3：L4 在配置环境时全绿（建议）
- G4：新增公共 API 必须带 Happy + Error 用例
- G5（Phase 2+）：L6 核心用例通过后方可宣称“接口/签名后端能力可用”
- G6：所有使用动态分配的用例无内存泄漏（`std.testing.allocator`）

## 7. 产物要求

- 每次测试扩展同步更新 `docs/06-implementation-log.md`。
- 发现的高风险缺口同步写入 `docs/07-review-report.md`。
- 兼容矩阵变化同步写入 `docs/08-evolution.md`。
