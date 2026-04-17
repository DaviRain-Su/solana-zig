# Consumer Profiles and Security Notes

**Date**: 2026-04-16

> 本文用于收敛“谁是当前主用户、谁是未来用户、哪些安全/所有权约束必须提前明确”。
>
> 它不替代 PRD，而是补充 PRD 中较宽的用户画像，避免未来阶段承诺过多但约束不足。

## 1. Primary Consumer Profiles

### 1.1 Current Primary Users (Product Phase 1)
- Zig host/client 开发者
- 需要在服务端或工具链中构造、签名、发送 Solana 交易的工程团队
- 重点关注：行为兼容、字节兼容、错误语义、测试可验证性

### 1.2 Current Users (Product Phase 3 — ✅ 已交付)
- 通过 C ABI 使用功能的非 Zig 语言调用者（C ABI 核心类型 + 交易构建已可用；RPC 导出为 scaffold 状态）
- 需要外部 signer / 托管 signer / mock signer 的集成方（Signer vtable + InMemorySigner + MockExternalSigner 已交付）
- 7 个 interface 模块消费者：system / token / token_2022 / compute_budget / memo / stake / ata
- 重点关注：所有权、句柄稳定性、错误码、secret boundary

### 1.3 Deferred / Non-primary Users
- 硬件钱包 / 安全芯片集成
- 极端低延迟 / 高频策略系统
- 嵌入式 / 受限环境

这些方向可以支持，但当前不是 Product Phase 1 的主优化目标，不应提前做过重承诺。

## 2. Security / Ownership Notes

### 2.1 Secret Material
- 若持有 seed / 私钥材料，应尽量缩短驻留时间
- 不应把“可导出私钥”当作所有 signer 的默认能力
- 若未来支持外部 signer，默认应假设 secret material 不在本地可见

### 2.2 Memory Ownership
- 对所有跨模块 / 跨语言返回值，必须明确谁负责释放
- 对 C ABI，必须采用稳定、可文档化的 ownership 规则
- 文档应避免使用模糊措辞如“调用者自行处理”，而不说明释放方式

### 2.3 Hidden Allocation / Hidden Fallback
- 不应在关键路径 silently fallback
- 若存在分配，API 应尽可能清楚地体现 allocator / ownership 模型
- 高风险路径（rpc parse / signer / ffi）要特别避免隐式行为

### 2.4 Error Transparency
- 错误不能被吞掉
- 外部后端错误要保留足够上下文
- JSON-RPC `error` 对象语义必须保真

## 3. NFR Suggestions for Future Phases

进入 Product Phase 3 前，建议把以下 NFR 明确化：
- C ABI 内存所有权
- signer secret boundary
- zeroization 策略
- thread-safety / reentrancy 边界
- buffer / string ABI 约定
- latency-sensitive path 的观测要求

## 4. Related Docs

- `docs/01-prd.md`
- `docs/03b-signers-spec.md`
- `docs/03d-cabi-spec.md`
- `docs/08-evolution.md`
- `docs/09-doc-consistency-checklist.md`
