# Phase 2 - Architecture

## Module Graph

```
core  →  tx  →  rpc
              ↗
compat（仅测试路径，不进入生产依赖）
```

## 模块职责

| 模块 | 路径 | 职责 |
|------|------|------|
| **core** | `src/solana/core/` | 密码学原语与编码：Pubkey、Signature、Keypair、Hash、base58、shortvec |
| **tx** | `src/solana/tx/` | 交易构建与序列化：Instruction、AccountMeta、Message（legacy + v0）、VersionedTransaction |
| **rpc** | `src/solana/rpc/` | JSON-RPC 客户端：HttpTransport + RpcClient（5 个高频方法）+ 类型化响应 |
| **compat** | `src/solana/compat/` | 测试兼容性工具：oracle 向量加载器 + bincode little-endian 辅助 |

## 公共 API 入口

`src/root.zig` 统一导出所有模块：

```zig
pub const solana = @import("solana/mod.zig");
pub const core = solana.core;
pub const tx = solana.tx;
pub const rpc = solana.rpc;
pub const compat = solana.compat;
```

## 依赖策略

**零外部依赖**。`build.zig.zon` 的 `dependencies` 为空，全部使用 Zig 标准库：
- 密码学：`std.crypto.sign.Ed25519`
- 哈希：`std.crypto.hash.sha2.Sha256`
- HTTP：`std.http.Client`
- JSON：`std.json`

这降低了供应链风险，简化了交叉编译，但也意味着需要自行实现 base58 等编码。

## 内存管理策略

- 所有需要动态分配的函数通过参数接收 `std.mem.Allocator`，由调用方控制生命周期
- `*Alloc()` 后缀表示返回分配的内存，调用方需 `defer allocator.free(...)` 释放
- 固定大小的类型（Pubkey/Signature/Hash）使用栈分配，无需 allocator
- Message/Transaction 提供 `deinit()` 方法管理内部动态数组

## Error Strategy

- **编解码/签名/交易错误**：使用 Zig 统一错误集（error union），编译期可穷举
- **RPC 错误**：`RpcResult(T)` tagged union 区分 `ok` 和 `rpc_error`，保留完整 `code/message/data_json`
- **HTTP 传输错误**：`RpcTransport` 错误类型处理网络层失败

## 最低 Zig 版本

`0.16.0`（见 `build.zig.zon` 中 `minimum_zig_version`）

## Feature Flags（尚未实现）

规划中：
- `full`（默认）
- `rpc`
- `devnet-integration-tests`
