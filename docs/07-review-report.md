# Phase 7 - Review Report

## Review Focus
- 字节布局与短向量编码一致性
- 签名流程（消息字节 → Ed25519 签名）一致性
- RPC error 保真（code/message/data_json）

## 验证结果

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Pubkey 32B base58 roundtrip | ✅ | oracle 向量验证通过 |
| Signature 64B 签名/验证 | ✅ | Keypair sign + verify roundtrip |
| shortvec 编解码 | ✅ | oracle 向量 + 边界值测试 |
| Legacy message 序列化 | ✅ | compile + serialize + deserialize roundtrip |
| V0 message 0x80 前缀 | ✅ | 序列化/反序列化正确处理版本标识 |
| Transaction 签名覆盖完整 message bytes | ✅ | sign + verify + serialize roundtrip |
| RPC error 结构保真 | ✅ | code/message/data_json 完整保留 |

## Gaps

### P1: RPC 返回解析偏动态
- **现状**：`client.zig` 中 `getAccountInfo` 等方法通过 `std.json` 动态解析 `result` 字段
- **风险**：类型不匹配时只在运行时才能发现
- **建议**：后续为高频响应增加编译期 typed schema，至少覆盖 `LatestBlockhash` 和 `AccountInfo`

### P2: V0 AddressLookupTable 输入模型
- **现状**：`LookupEntry` 为 `{ index: u8, pubkey: Pubkey }` 简单对
- **Rust SDK 对比**：Rust 使用 `AddressLookupTableAccount` 包含完整账户数据
- **建议**：当前模型满足序列化需求，扩展 RPC 方法（如 `getAddressLookupTable`）时再对齐

### P3: 内存安全
- **现状**：所有动态分配通过 allocator 参数传入，`deinit()` 方法覆盖 Message/Transaction
- **待验证**：尚未进行系统性 leak 检测（可利用 `std.testing.allocator` 的泄漏检测能力）
