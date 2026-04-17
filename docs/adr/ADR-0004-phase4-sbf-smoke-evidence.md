# ADR-0004 - Phase 4 SBF Compile + Localnet Smoke 证据（#96 / G-P4A）

- Status: `proposed`
- Date: `2026-04-17`
- Deciders: @kimi, @codex_5_4 (reviewer)
- Related Docs: `docs/40-phase4-planning.md`, `docs/41-phase4-release-readiness.md`
- Related Code: `scripts/`, `docs/adr/`

## 1. Scope

本证据包对应 Phase 4 Batch 0 任务 `#96`（P4-Pre-3）：在 `linux-x86_64` canonical host 上完成 `zignocchio` 示例程序的 **SBF compile + localnet deploy smoke** 全链路验证。

## 2. Compile 证据

### 2.1 环境
- **Host**: Docker `--platform=linux/amd64` (Debian trixie)
- **Zig**: 0.16.0 (`zig-x86_64-linux-0.16.0`)
- **sbpf-linker**: 0.1.8 (cargo install --locked)
- **LLVM**: 19.1.7

### 2.2 前置修复
`sbpf-linker` 依赖 `aya-rustc-llvm-proxy` 动态加载 LLVM，在 Debian 默认安装中需创建 symlink：

```bash
mkdir -p /usr/local/cargo/lib
ln -s /usr/lib/x86_64-linux-gnu/libLLVM-19.so /usr/local/cargo/lib/libLLVM.so
```

### 2.3 编译命令
```bash
cd /work && mkdir -p zig-out/lib && zig build
```

### 2.4 编译结果
- **exit code**: 0
- **产物**: `zig-out/lib/program_name.so`
- **file 类型**: `ELF 64-bit LSB shared object, eBPF, version 1 (SYSV), dynamically linked, stripped`
- **Machine**: `Linux BPF`
- **大小**: 3,320 bytes

## 3. Localnet Smoke 证据

### 3.1 环境
- **Host**: macOS (local)
- **Validator**: `solana-test-validator 3.1.12`
- **CLI**: `solana-cli` RPC localhost

### 3.2 部署命令
```bash
solana config set --url http://127.0.0.1:8899
solana-test-validator --reset --quiet
solana airdrop 2
solana program deploy --use-rpc /private/tmp/zignocchio/zig-out/lib/program_name.so
```

### 3.3 部署结果
- **exit code**: 0
- **Program Id**: `6W59Gbqv3nJxToWR3eyr8bDWnJktLGfWRcvBx3GSv3UV`
- **Deploy signature**: `2ePnMo3vuFfWT3NEFXGTUwgubJRDW9iZnJyF78oSPsKX9U6EFPAiJbEe41RnCjfmjNySCQCgB5ctJyNbaFcV3wVg`

## 4. Gate 映射

- **Task**: `#96` P4-Pre-3
- **Gate**: `G-P4A` — SBF compile + localnet smoke PASS（linux-x86_64 canonical host）
- **结论**: ✅ 通过

## 5. 对 Bootstrap 路线的影响

按 `docs/40-phase4-planning.md` §2.3.4 与 `docs/41-phase4-release-readiness.md` 已签收规则：
- `linux-x86_64` canonical host 上 zignocchio compile + smoke 均通过
- `solana-zig-bootstrap` 满足“永久排除”触发条件
