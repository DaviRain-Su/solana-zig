# Phase 3a - Interfaces Spec

> 本文是 `docs/03-technical-spec.md` 的子规格，主要承接 Product Phase 2-3 的接口层能力。
>
> 本文聚焦：**指令构造、数据布局、账户约束、错误语义**。不承载 RPC 网络访问职责。

## 1. Scope

当前计划覆盖：
- `system`
- `compute-budget`
- `token`
- `token-2022`
- `memo`
- `stake`
- ATA（Associated Token Account）辅助构造

其中：
- `compute-budget` 可在 Product Phase 2 提前落地
- 其余接口能力主要位于 Product Phase 3

## 2. Design Boundary

interfaces 层默认：
- 依赖 `core/tx`
- 不直接依赖 `rpc`
- 不承担联网 helper 责任
- 不隐藏账户排列与 signer/writable 语义

若未来需要“联网查询 + 指令构造”的高层 helper，必须拆到独立 `program_clients/*` 或等价模块。

## 3. Common API Shape

所有接口模块应尽量采用统一风格：

```zig
pub const Params = struct { ... };
pub fn buildXxxInstruction(allocator: std.mem.Allocator, params: Params) !tx.Instruction
pub fn programId() core.Pubkey
```

对于需要多条指令组合的 helper，可采用：

```zig
pub fn buildXxxInstructions(allocator: std.mem.Allocator, params: Params) ![]tx.Instruction
```

## 4. Common Validation Rules

- 账户数量、顺序、signer/writable 语义必须显式可审查
- 指令 data 字节布局必须可回溯到 Rust 对标接口 crate
- 禁止 silent fallback（例如缺失可选账户时自动降级为另一条指令）
- 参数非法时返回明确错误，而非构造“尽量能跑”的指令

## 5. Module Decomposition

### 5.1 system
- 首批目标：`transfer`, `create_account`, `assign`, `advance_nonce_account`
- 锁定归属：Durable Nonce 的指令构造归入 `system` 模块；若需要查询 + 组装 + 签名协同，则在更高层 helper 中组合
- 必须定义：
  - program id
  - instruction discriminant
  - 账户顺序
  - data layout

### 5.2 compute-budget
- 首批目标：
  - `set_compute_unit_limit`
  - `set_compute_unit_price`
- 需支持和普通交易指令组合

### 5.3 token / token-2022
- 首批目标：
  - mint / transfer / approve / burn
  - ATA create helper
- token-2022 需单独标注扩展字段与兼容边界

### 5.4 memo
- 目标：memo 指令构造
- 要求：支持空 signer 与带 signer 两种账户组合场景

### 5.5 stake
- 首批目标：`create_stake_account`, `delegate`, `deactivate`, `withdraw`
- 重点：多账户顺序与授权角色区分

### 5.6 ata (Associated Token Account)
- 首批目标：`findAssociatedTokenAddress` + `createAssociatedTokenAccountInstruction`
- 重点：deterministic ATA derivation via `findProgramAddress` with seeds `[owner, token_program_id, mint]`
- 返回：`Instruction` builder，可直接嵌入交易

## 6. Error Model

建议在 `src/solana/errors.zig` 扩充或按模块细分，但对外至少应可表达：
- `InvalidInstructionParams`
- `InvalidAccountLayout`
- `UnsupportedExtension`
- `MissingRequiredAuthority`
- `IntegerOverflow`

## 7. Test Mapping Requirements

至少覆盖：
- Happy：与 Rust 参考字节布局一致
- Boundary：账户顺序、可选账户、省略字段、零值/边界值
- Error：非法参数、缺失 authority、错误扩展组合

映射到 `docs/05-test-spec.md`：
- `I-FACE-001`
- `I-FACE-002`
- `I-FACE-003`
- `I-FACE-004`

## 8. First Implementation Order

1. `compute-budget`
2. `system`
3. `token` + ATA
4. `token-2022`
5. `memo`
6. `stake`

## 9. Open Questions

- ATA helper 是否应只返回 instruction，还是允许返回“可能需要的前置账户集合”？
- token-2022 扩展能力是否按扩展点拆子模块？
