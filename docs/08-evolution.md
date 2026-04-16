# Phase 8 - Evolution

## Compatibility Tracking
- **当前基线**：`solana-sdk 4.0.1`
- 未来版本升级时对比 crate 拆分与消息/交易语义变化
- 使用 oracle 向量回归验证兼容性（`scripts/oracle/generate_vectors.rs` 更新依赖版本后重新生成）

## Next Steps（按优先级排序）

### P1: 补齐测试覆盖
- 扩充 oracle 向量：非零 pubkey、Keypair 签名、Message 序列化、Transaction 完整 roundtrip
- 补齐 Devnet E2E 自动化流程（CI 中条件运行）
- 利用 `std.testing.allocator` 系统性检测内存泄漏

### P2: 扩展 RPC 方法
- 按使用频率逐步增加：`getTransaction`、`getSignaturesForAddress`、`getTokenAccountsByOwner` 等
- 为高频响应增加 typed schema（见 07-review-report Gaps）

### P3: 评估链上语义子项目
- **评估标准**：是否有 Zig 生态的链上程序开发需求（SBF target、no_std 约束）
- **预期产出**：独立 `solana-program-zig` 包，与本项目（链下客户端）分离生命周期
- **前置条件**：Zig 交叉编译到 SBF 的可行性验证
