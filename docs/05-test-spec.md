# Phase 5 - Test Spec

> 注：本文标题中的“Phase 5”是文档生命周期序号（测试规格文档），不是产品路线图阶段编号。
>
> 本文统一采用以下命名：`Product Phase` 表示产品路线图阶段，`M1~M3` 仅表示当前 Product Phase 1 的执行里程碑。

## 1. 测试目标

- 验证 `docs/03-technical-spec.md` 的字节契约、接口契约、错误契约。
- 覆盖当前 Product Phase 1 / M1-M3 范围，并为 Product Phase 2-3 预留测试框架。
- 确保离线测试可作为主门禁，在线测试作为增量验证。

## 2. 测试层级

- L1：core 单元测试
- L2：tx 组件测试
- L3：rpc + mock transport
- L4：Devnet acceptance harness / 外部集成验证（环境变量门控）
- L5：compat/oracle 对照测试
- L6：扩展 RPC / Websocket / Nonce 工作流测试（Product Phase 2）
- L7：interfaces / signers / C ABI 集成测试（Product Phase 3）

## 3. 环境与执行

- 默认：`zig build test`
- Devnet 验收路径启用：`SOLANA_RPC_URL` 存在
- 当前 L4 通过仓库内 `zig build devnet-e2e` live harness + acceptance wrapper 执行，不等同于 `zig build test` 主离线门禁层
- 无 `SOLANA_RPC_URL`：L4 不执行，不影响离线门禁
- 所有涉及动态分配的测试必须使用 `std.testing.allocator` 并通过泄漏检测

## 4. 当前范围测试矩阵（Product Phase 1 / M1-M3）

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

## 5. 后续扩展测试规划

### 5.1 Product Phase 2（扩展 RPC + 实时/交易增强）
- I-RPCX-001: `getTransaction(json baseline)` / `getSignaturesForAddress` mock + Devnet 对照（第一批已落地）
- I-RPCX-002: `getSlot` / `getEpochInfo` / `getMinimumBalanceForRentExemption` / `requestAirdrop` 覆盖（其中 `getSlot` 已在第一批落地）
- I-RPCX-003: `getAddressLookupTable` 与 ALT 管理语义覆盖
- I-RPCX-004: `getSignatureStatuses` happy / null / rpc_error / confirm-polling 覆盖（用于 `send -> confirm` 状态查询）
- I-WS-001: `accountSubscribe` / `logsSubscribe` / `signatureSubscribe` 的连接、断线、重连、取消订阅测试
- I-TXW-001: Durable Nonce 工作流与离线签名流程测试
- I-TXW-002: Priority Fees / Compute Budget 指令构造与组合交易测试

### 5.2 Product Phase 3（interfaces + signers + C ABI）
- I-FACE-001: system interface 指令字节对齐
- I-FACE-002: token interface 指令参数与账户布局对齐
- I-FACE-003: token-2022 扩展字段边界
- I-FACE-004: 组合交易（system + token）可签名并模拟
- I-SIGN-001: in-memory signer 与当前 keypair 行为一致
- I-SIGN-002: 外部 signer adapter 错误语义透传
- I-SIGN-003: signer 切换对交易序列化无副作用
- I-CABI-001: C ABI 所有权与释放约定测试
- I-CABI-002: 头文件与导出符号一致性检查
- I-PERF-001: Phase 3 性能对比报告中的 benchmark 方法、输入 profile 与复跑说明一致

## 6. Gate 定义

- G1：L1+L2+L5 全绿（必需）
- G2：L3 全绿（必需）
- G3：L4 在配置环境时通过（建议）；若当前仅执行包装脚本，需明确标注其不等同于完整 in-tree Devnet E2E
- G4：新增公共 API 必须带 Happy + Error 用例
- G5：Product Phase 2 宣称可用前，L6 核心用例必须通过
- G6：Product Phase 3 宣称可用前，L7 核心用例必须通过，且性能对比报告已形成可复跑记录
- G7：所有使用动态分配的用例无内存泄漏（`std.testing.allocator`）

## 7. 产物要求

- 每次测试扩展同步更新 `docs/06-implementation-log.md`。
- 发现的高风险缺口同步写入 `docs/07-review-report.md`。
- 兼容矩阵变化同步写入 `docs/08-evolution.md`。
- 能力状态变化同步回写 `docs/10-coverage-matrix.md`。
