# Phase 7 - Review Report

## Review Focus
- 字节布局与短向量编码一致性
- 签名流程（消息字节）一致性
- RPC error 保真（code/message/data_json）
- 文档与代码一致性

## Findings & Fixes

### 1. 重复定义：`RpcResult` / `RpcErrorObject`
- **问题**：`src/solana/errors.zig` 与 `src/solana/rpc/types.zig` 同时定义了 `RpcResult` 和 `RpcErrorObject`，易导致维护混淆。
- **修复**：已删除 `errors.zig` 中的重复定义，统一由 `rpc/types.zig` 维护（因其包含 `deinit` 生命周期方法）。

### 2. 未使用错误标签
- **问题**：`errors.zig` 中存在 `InvalidCharacter`、`MissingPayer`、`MissingRecentBlockhash` 三个未被任何代码路径引用的错误标签。
- **修复**：已删除上述死代码，保持错误集合精简。

### 3. `client.zig` 中冗余变量
- **问题**：`callAndParse` 内使用 `_ = root_obj;` 压制未使用变量警告，逻辑不够直观。
- **修复**：改为显式 `if (parsed.value != .object) { parsed.deinit(); return error.InvalidRpcResponse; }`，并在非对象时正确释放内存。

### 4. Feature Flags 文档未标注实现状态
- **问题**：`docs/02-architecture.md` 列出 `full/rpc/devnet-integration-tests` 但未说明尚未落地。
- **修复**：已追加 `(planned, not yet implemented)` 标注。

### 5. 错误模型文档与代码位置不一致
- **问题**：技术规格声称所有错误（含 RPC 业务错误）统一在 `errors.zig`，但 RPC 业务类型实际在 `rpc/types.zig`。
- **修复**：已在 `docs/03-technical-spec.md` 第 7 节拆分说明：核心错误在 `errors.zig`，RPC 业务封装在 `rpc/types.zig`。

## Remaining Gaps
- 当前 RPC 返回解析偏动态，后续可增加更严格 typed schema。
- V0 lookup 输入模型为 `index+pubkey`，仍可进一步对齐 Rust 生态抽象。
- `docs/04-task-breakdown.md` 与 `docs/05-test-spec.md` 中规划的 v0 / RPC mock / Devnet E2E 测试尚未实现，属于按计划排期的后续任务（T4-06 ~ T4-16）。
