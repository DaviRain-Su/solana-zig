# Phase 6 - Implementation Log

## 时间线

| 日期 | 里程碑 |
|------|--------|
| 2026-04-16 | Initial commit + Phase 1 全部完成（core/tx/rpc）|

## 已完成工作

1. **建立单仓多模块结构** — `src/solana/{core,tx,rpc,compat}` 四模块，`root.zig` 统一导出
2. **核心类型与编解码** — Pubkey/Signature/Keypair/Hash + base58 + shortvec
3. **Message/Transaction 编译与序列化** — Legacy + V0 消息，VersionedTransaction 签名/验证
4. **HTTP transport 与 5 个 RPC 方法** — getLatestBlockhash/getAccountInfo/getBalance/simulateTransaction/sendTransaction
5. **Oracle 向量与测试骨架** — Rust 生成脚本 + JSON 向量 + Zig 加载器

## 关键决策与原因

### base58 采用逐字节大数除法算法
Bitcoin 原始 base58 算法的直接移植。没有使用查表优化，因为 Pubkey/Signature 长度固定且较短（32-64 字节），逐字节方式足够高效，代码更易审计。

### HTTP transport 使用 `std.http.Client`
零外部依赖策略的直接结果。Zig 0.16 标准库 HTTP 客户端已支持 TLS，功能满足 JSON-RPC POST 需求。通过 `std.Io` 接口注入 I/O 上下文，保持可测试性。

### 签名使用 `std.crypto.sign.Ed25519`
Solana 使用 Ed25519 签名方案，Zig 标准库原生支持。Keypair 通过 `fromSeed()` 从 32 字节种子确定性生成，与 Rust SDK 的 `Keypair::from_bytes()` 行为一致。

### RPC 响应使用 `RpcResult(T)` tagged union
区分"RPC 调用成功但返回业务错误"与"HTTP 传输层失败"。保留完整 error 结构（code/message/data_json）而非扁平化，便于调用方精确处理不同错误类型。

### Message V0 序列化以 `0x80` 前缀区分
与 Rust SDK 保持一致：反序列化时先读首字节，`>= 0x80` 则为 versioned message（版本号 = byte & 0x7f），否则为 legacy message。

## Notes

- Phase 1 以"可验证的字节级兼容"为目标，优先确保编解码与 Rust SDK 4.0.1 行为完全一致
- RPC 方法覆盖率当前仅含最高频的 5 个，后续按需扩展
- Oracle 向量当前仅 2 个（all-zeros pubkey + shortvec(300)），需要在 Phase 2 补充更多
