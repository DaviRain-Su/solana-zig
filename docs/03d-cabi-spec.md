# Phase 3d - C ABI Spec

> 本文是 `docs/03-technical-spec.md` 的子规格，承接 Product Phase 3 的 C ABI 导出层设计。
>
> 本文聚焦：**导出边界、所有权模型、错误码、句柄策略、ABI 稳定性约束**。

## 1. Scope

Product Phase 3 的 C ABI 首批目标覆盖：
- 核心固定长度类型相关导出
- 交易构建与序列化的最小导出能力
- RPC 客户端最小导出能力
- 错误码与所有权约定

暂不承诺：
- 一次性暴露全部内部 Zig 类型
- 直接暴露内部 vtable / allocator 细节
- 在首版 ABI 中稳定支持所有 future modules

## 2. Design Goals

- 让非 Zig 语言能够安全调用最小 Solana 能力
- 避免把 Zig 内部实现细节直接泄漏到 ABI 层
- 明确所有权与释放责任，避免双重释放或悬挂引用
- 为后续版本演进保留向后兼容空间

## 3. ABI Surface Strategy

建议优先导出以下三类内容：

### 3.1 Value Types
- 固定长度字节类型（如 pubkey/hash/signature）
- 适合按值传递或通过 caller-provided buffer 输出

### 3.2 Opaque Handles
- `RpcClientHandle`
- `TransactionHandle`
- 未来如有 signer / context，也优先用 opaque handle

### 3.3 Heap-returning Functions
- 仅在确有必要时返回动态分配结果
- 必须提供对等的 `free` / `destroy` API

## 4. Ownership Model

推荐采用单一规则：
- **谁分配，谁提供释放函数**
- C 调用者不直接使用 Zig allocator
- 所有堆对象必须通过 ABI 层提供的显式释放函数释放

示例：
```c
solana_string_t out = solana_pubkey_to_base58(...);
solana_string_free(out);
```

## 5. Error Model

建议首版采用稳定整数错误码：
- `SOLANA_OK = 0`
- `SOLANA_ERR_INVALID_ARGUMENT`
- `SOLANA_ERR_INVALID_LENGTH`
- `SOLANA_ERR_RPC_TRANSPORT`
- `SOLANA_ERR_RPC_PARSE`
- `SOLANA_ERR_BACKEND_FAILURE`
- `SOLANA_ERR_INTERNAL`

可选增强：
- thread-local last error message
- caller-provided error buffer

但首版必须保证：
- 错误码稳定
- 基本分类清晰
- 不把 Zig error union 直接暴露到 ABI

## 6. String / Buffer Conventions

建议统一采用：
- `ptr + len` 表示只读输入
- `ptr + len + capacity` 表示 caller-owned 可写输出缓冲
- 对于 ABI 自分配输出，返回 `{ptr,len}` 结构并提供释放函数

禁止：
- 假定输入字符串以 `\0` 结尾且无长度参数
- 把 Zig slice 直接映射为 ABI 类型而不加包装

## 7. Versioning and Stability

至少需要：
- `solana_zig_abi_version()`
- 头文件中显式 ABI version 宏
- 若发生破坏性变更，必须 bump ABI version 并写 ADR

## 8. Header Strategy

- 首版头文件建议集中在 `solana_zig.h`
- 内部 helper / 宏尽量少
- 对 opaque handle 只暴露前置声明，不暴露内部结构

## 9. Signer and Security Boundary

- C ABI 首版不强制暴露 signer vtable 细节
- 若要暴露 signer，优先 opaque handle + function table wrapper
- 若涉及 secret material，必须额外记录 zeroization / lifetime 规则

## 10. Test Mapping Requirements

映射到 `docs/05-test-spec.md`：
- `I-CABI-001`: C ABI 所有权与释放约定测试
- `I-CABI-002`: 头文件与导出符号一致性检查

至少覆盖：
- Happy：创建 / 调用 / 销毁闭环
- Boundary：空 buffer、小 buffer、null pointer 处理
- Error：非法参数、释放顺序错误、句柄失效

## 11. Open Questions

- 首版 C ABI 是否需要同时暴露 transaction builder 与 rpc，还是先只暴露 value + rpc？
- last error message 采用 TLS、全局静态缓冲，还是 caller-provided buffer？
- Phase 3 首版是否需要为外部 signer 预留 ABI hook？
