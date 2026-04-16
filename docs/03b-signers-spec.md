# Phase 3b - Signers Spec

> 本文是 `docs/03-technical-spec.md` 的子规格，承接 Product Phase 3 的 signer 抽象与后端扩展。

## 1. Scope

目标覆盖：
- in-memory signer
- 外部 signer adapter（mock / KMS / HSM stub）
- 与 `VersionedTransaction` 的接入契约
- 错误语义、生命周期、零敏感数据处理边界

## 2. Design Goals

- 保持与当前 `Keypair` 路径行为兼容
- 让 tx 构建与签名后端解耦
- 不强制要求所有 signer 能导出私钥材料
- 为远程签名、硬件签名和托管签名预留一致接口

## 3. Minimum Interface Shape

建议最小接口围绕“拿到 pubkey + 对 message bytes 签名”：

```zig
pub const Signer = struct {
    ctx: *anyopaque,
    get_pubkey_fn: *const fn (ctx: *anyopaque) anyerror!core.Pubkey,
    sign_message_fn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, msg: []const u8) anyerror!core.Signature,
    deinit_fn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
};
```

可选扩展：
- signer label / backend kind
- supports_deterministic_sign
- supports_pubkey_derivation

## 4. Integration Rules

- `VersionedTransaction.sign(...)` 的现有 `Keypair` 路径保留，作为便捷 API
- 后续新增显式 signer 抽象入口，例如：

```zig
pub fn signWithSigners(self: *VersionedTransaction, signers: []const signers.Signer) !void
```

- 交易签名匹配规则仍以 `message.header.num_required_signatures` 和 signer pubkey 对齐为准
- 若 required signer 缺失，必须返回 `error.MissingRequiredSignature`

## 5. Error Model

至少需要表达：
- `MissingRequiredSignature`
- `SignerUnavailable`
- `SignerBackendFailure`
- `SignerRejected`
- `UnsupportedSignerOperation`
- `SignatureCountMismatch`

外部后端错误建议保留底层 message/context，禁止吞错。

## 6. Sensitive Data Rules

- in-memory signer 若持有 seed / secret material，应尽量缩短生命周期
- 若后续 Zig 版本或标准库能力允许，优先采用显式 zeroization
- 外部 signer adapter 默认不假设本地可访问 secret material
- 文档必须明确：签名接口输入输出的所有权与释放责任

## 7. Test Mapping Requirements

映射到 `docs/05-test-spec.md`：
- `I-SIGN-001`: in-memory signer 与当前 keypair 行为一致
- `I-SIGN-002`: 外部 signer adapter 错误语义透传
- `I-SIGN-003`: signer 切换对交易序列化无副作用

至少覆盖：
- Happy：单 signer、多 signer、顺序无关匹配
- Boundary：重复 signer、缺失 signer、空 signer 集合
- Error：后端拒签、超时、adapter failure、pubkey 不匹配

## 8. First Implementation Order

1. 定义统一 signer 接口
2. 提供 in-memory signer 适配当前 `Keypair`
3. 提供 fake / mock external signer
4. 把 tx 签名流程接到 signer 抽象
5. 再评估 KMS/HSM stub 与异步边界

## 9. Open Questions

- 外部 signer 是否需要异步接口，还是先用同步阻塞适配？
- 是否允许一个 signer 返回多个 pubkey（HD / keyring 场景）？
- C ABI 暴露 signer 时，是否只允许 opaque handle 而不暴露 vtable 细节？
