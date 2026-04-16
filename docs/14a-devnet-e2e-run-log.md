# Devnet E2E Run Log

**Template Date**: 2026-04-16
**Purpose**: 记录 Product Phase 1 的 Devnet 验收实际执行结果，区分"包装式验收"与"真实 E2E harness"。

> 本文是 `docs/14-devnet-e2e-acceptance.md` 的结果模板。
>
> 重要：只有 `Run Type = real-harness` 且留下 `construct -> sign -> simulate -> send` 证据时，才可用作"真实 Devnet E2E 已完成"的依据。

---

## Run 1 — Mock E2E (Offline Harness)

### 1. Run Metadata

- Run ID: `2026-04-16/a771c6d/mock-harness`
- Commit: `a771c6d`
- Date: `2026-04-16`
- Run Type: `mock-harness` (offline, scripted RPC responses)
- Operator: `@CC (automated)`
- RPC Endpoint: `http://mock.test` (not a real endpoint)
- Command / Entry: `zig build devnet-e2e`
- Log Path: stdout (inline below)

### 2. Result Summary

- Overall Result: **pass**
- Failure Stage: none
- Notes: Both K3-H1 (happy path) and K3-F1 (failure path) mock tests pass. Devnet live test correctly skips when `SOLANA_RPC_URL` not set.

### 3. Evidence Checklist

#### 3.1 Wrapper Run
N/A (this is a mock harness run, not the wrapper script)

#### 3.2 Mock Harness Run (aligned with docs/18 contract)
- [x] transaction constructed (K3-H1 S3: `Message.compileLegacy`)
- [x] transaction signed (K3-H1 S5: `tx.sign + verifySignatures`)
- [x] simulation executed — happy (K3-H1 S6: mock returns `.ok` with `err: null`)
- [x] simulation executed — failure (K3-F1 S6: mock returns `.rpc_error` with `code < 0`)
- [x] `std.testing.allocator` zero-leak (K3-H1 + K3-F1)

#### 3.3 Real Harness Run (Devnet)
- [ ] Pending: requires `SOLANA_RPC_URL` to be set
- [ ] transaction constructed
- [ ] transaction signed
- [ ] simulation executed
- [ ] send executed (not in current contract scope — contract stops at simulate)
- [ ] result / signature / error captured

### 4. Detailed Notes

#### Mock K3-H1 (Happy Path)
- Scripted `getLatestBlockhash` response with `lastValidBlockHeight=1000`
- Compiled legacy message with 1 instruction, 2 accounts
- Signed with deterministic keypair (`seed=[1]*32`)
- Verified: signature length = 64 bytes, `verifySignatures()` passes
- Scripted `simulateTransaction` returns `.ok` with `err: null`
- All assertions pass, zero memory leaks

#### Mock K3-F1 (Failure Path)
- Same setup as K3-H1 but **skips signing** (tx has zero-filled signatures)
- Scripted `simulateTransaction` returns `.rpc_error` (`code=-32002, "Transaction signature verification failure"`)
- Assertions: `code < 0`, `message.len > 0`
- All assertions pass, zero memory leaks

#### Devnet Live Path
- Gated by `SOLANA_RPC_URL` env var
- When not set: prints `[skip]` and returns (D-04 contract compliance)
- When set: executes full `getLatestBlockhash → compileLegacy → sign → verify → simulate` flow
- Devnet may reject dummy tx (acceptable — evidence is that the RPC round-trip completes)

### 5. Artifacts

- Harness source: `src/e2e/devnet_e2e.zig`
- Build step: `zig build devnet-e2e`
- Contract reference: `docs/18-surfpool-e2e-contract.md`

### 6. Follow-up Actions

- Related implementation log update: `docs/06-implementation-log.md` (pending)
- Related review update needed: no
- Related execution matrix rows to update:
  - `docs/15` "Devnet E2E evidence": `open` → `in-progress` (mock done, devnet pending)
  - `docs/15` "benchmark baseline": `open` → `closeable` (first baseline recorded)

### 7. What Remains for Full Devnet Evidence

To move "Devnet E2E evidence" from `in-progress` to `closeable`:
1. Set `SOLANA_RPC_URL` to a devnet endpoint
2. Run `zig build devnet-e2e`
3. Capture output showing `getLatestBlockhash → sign → simulate` completing
4. Record commit, endpoint (redacted), and result in a new Run section below

---

## Run 2 — Devnet Live (Pending)

*(To be filled when `SOLANA_RPC_URL` is available)*
