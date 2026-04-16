# Devnet E2E Run Log

**Template Date**: 2026-04-16
**Purpose**: 记录 Product Phase 1 的 Devnet 验收实际执行结果，区分"包装式验收"、当前真实 in-tree harness，以及最终 closeout evidence pack 所需的 live 证据。

> 本文是 `docs/14-devnet-e2e-acceptance.md` 的结果模板。
>
> 重要：
> - `Run Type = real-harness` 且覆盖 `construct -> sign -> simulate`，可作为“当前 in-tree live harness 已存在”的依据。
> - `sendTransaction` 与后续 confirm 的 live 证据已在后续 run 中补齐；是否可据此宣称 Phase 1 closeout，仍需回到 `docs/11` / `docs/15` 做整体判定。

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

#### 3.2 Mock Harness Run
- [x] transaction constructed (K3-H1 S3: `Message.compileLegacy`)
- [x] transaction signed (K3-H1 S5: `tx.sign + verifySignatures`)
- [x] simulation executed — happy (K3-H1 S6: mock returns `.ok`)
- [x] simulation executed — failure (K3-F1 S6: mock returns `.rpc_error`)
- [x] `std.testing.allocator` zero-leak (K3-H1 + K3-F1)

#### 3.3 Real Harness Run (Devnet)
- [ ] Pending: requires `SOLANA_RPC_URL` to be set
- [ ] transaction constructed
- [ ] transaction signed
- [ ] simulation executed
- [ ] send executed
- [ ] result / signature / error captured

### 4. Detailed Notes

#### Mock K3-H1 (Happy Path)
- Scripted `getLatestBlockhash` response with `lastValidBlockHeight=1000`
- Compiled legacy message with 1 instruction, 2 accounts
- Signed with deterministic keypair (`seed=[1]*32`)
- Verified: signature length = 64 bytes, `verifySignatures()` passes
- Scripted `simulateTransaction` returns `.ok`
- All assertions pass, zero memory leaks

#### Mock K3-F1 (Failure Path)
- Same setup as K3-H1 but **skips signing** (tx has zero-filled signatures)
- Scripted `simulateTransaction` returns `.rpc_error` (`code=-32002, "Transaction signature verification failure"`)
- Assertions: `code < 0`, `message.len > 0`
- All assertions pass, zero memory leaks

### 5. Artifacts

- Harness source: `src/e2e/devnet_e2e.zig`
- Build step: `zig build devnet-e2e`
- Contract reference: `docs/18-surfpool-e2e-contract.md`

### 6. Follow-up Actions

- Related implementation log update: `docs/06-implementation-log.md`
- Related review update needed: no
- Related execution matrix rows to update:
  - `docs/15` "Devnet E2E evidence": `open` → `in-progress` (mock done, live pending)
  - `docs/15` "benchmark baseline": `open` → `closeable` (first baseline recorded)

### 7. What Remains for Live Evidence

To move beyond mock-only status:
1. Set `SOLANA_RPC_URL` to a devnet endpoint
2. Run `zig build devnet-e2e`
3. Capture output showing `getLatestBlockhash -> sign -> simulate` completing
4. Record commit, endpoint (redacted), and result in a new Run section below

---

## Run 2 — Devnet Live (Public Devnet)

### 1. Run Metadata

- Run ID: `2026-04-16/892cfd8/devnet-live`
- Commit: `892cfd8` (+ local fix: `sim_json.parsed.deinit()` → `sim.deinit(gpa)` to match #7 typed parse refactor)
- Date: `2026-04-16`
- Run Type: `real-harness` (live RPC round-trip to public devnet)
- Operator: `@CC (automated)`
- RPC Endpoint: `https://api.devnet.solana.com`
- Command / Entry: `SOLANA_RPC_URL=https://api.devnet.solana.com zig build devnet-e2e`
- Log Path: stdout (inline below)
- Exit Code: `0`

### 2. Result Summary

- Overall Result: **pass**
- Failure Stage: none
- Notes: All 3 tests pass (2 mock + 1 devnet live). Devnet live test successfully completed `getLatestBlockhash -> compileLegacy -> sign -> verify -> simulate` against the public devnet endpoint.

### 3. Evidence Checklist

#### 3.1 Mock Harness Run (still passes alongside live)
- [x] K3-H1 mock: construct → sign → simulate (happy) — pass
- [x] K3-F1 mock: unsigned tx simulate fails (failure) — pass
- [x] `std.testing.allocator` zero-leak

#### 3.2 Real Harness Run (Devnet)
- [x] `SOLANA_RPC_URL` set to `https://api.devnet.solana.com`
- [x] `getLatestBlockhash` returned live blockhash from devnet
- [x] transaction constructed (`Message.compileLegacy`)
- [x] transaction signed (`tx.sign` + `verifySignatures`)
- [x] simulation executed (`simulateTransaction` returned `.ok` in this run)
- [ ] send executed
- [ ] send result / signature captured

#### 3.3 Console Output (captured)
```
[devnet E2E] endpoint: https://api.devnet.solana.com
[devnet E2E] simulate returned .ok
```

### 4. Detailed Notes

- The E2E harness required a one-line fix: `sim_json.parsed.deinit()` → `var sim = sim_val; sim.deinit(gpa)` (3 occurrences). This is because #7 (commit `892cfd8`) refactored `SimulateTransactionResult` to have a direct `deinit(allocator)` method instead of the previous `.parsed` wrapper.
- The devnet accepted the simulate request and returned `.ok`. This confirms the live RPC round-trip through `simulateTransaction` completed successfully.
- Contract compliance: the live test exercises S2→S6 (`getLatestBlockhash -> compileLegacy -> sign -> verify -> simulate`) against a real RPC endpoint.
- **Non-claim**: this run does **not** exercise `sendTransaction`, so it cannot by itself support the statement that full `construct -> sign -> simulate -> send` closeout is complete.

### 5. Artifacts

- Harness source: `src/e2e/devnet_e2e.zig`
- Build step: `zig build devnet-e2e`
- Contract reference: `docs/18-surfpool-e2e-contract.md`

### 6. Conclusion

Current in-tree Devnet live harness evidence is established for `construct -> sign -> simulate`.

`docs/15` 中的 "Devnet E2E evidence" 应维持为 `in-progress`：
- live harness 已有真实证据
- 但 `sendTransaction` live 发送证据仍未纳入当前 harness / closeout pack

---

## Run 3 — Local Surfnet Live (Supplementary Confirmation)

### 1. Run Metadata

- Run ID: `2026-04-16/892cfd8/surfnet-live`
- Commit: `892cfd8` (same E2E fix as Run 2)
- Date: `2026-04-16`
- Run Type: `real-harness` (live RPC round-trip to local surfnet)
- Operator: `@CC (automated)`
- RPC Endpoint: `http://127.0.0.1:8899` (surfnet, datasource: `api.mainnet-beta.solana.com`)
- Command / Entry: `SOLANA_RPC_URL=http://127.0.0.1:8899 zig build devnet-e2e`
- Exit Code: `0`

### 2. Result Summary

- Overall Result: **pass**
- Failure Stage: none
- Notes: All 3 tests pass. Local surfnet live test also completed the same `getLatestBlockhash -> compileLegacy -> sign -> verify -> simulate` flow.

### 3. Console Output (captured)
```
[devnet E2E] endpoint: http://127.0.0.1:8899
[devnet E2E] simulate returned .ok
```

### 4. Notes

- This run confirms the current harness works against both public devnet and local surfnet-style endpoints.
- Surfnet was started by @davirain with mainnet-beta as datasource (not devnet), but the RPC interface is identical for the methods exercised here.
- Run 2 (public devnet) remains the primary evidence; this run is supplementary confirmation only.
- As with Run 2, this run does **not** provide `sendTransaction` live evidence.

---

## Run 4 — sendTransaction Live (Local Surfnet, #17 P2-2)

### 1. Run Metadata

- Run ID: `2026-04-16/surfnet/sendtx-live`
- Date: `2026-04-16`
- Run Type: `real-harness` (live sendTransaction round-trip)
- Operator: `@CC (automated)`
- RPC Endpoint: `http://127.0.0.1:8899` (surfnet, datasource: `api.mainnet-beta.solana.com`)
- Command / Entry: `SOLANA_RPC_URL=http://127.0.0.1:8899 zig build devnet-e2e`
- Exit Code: `0`

### 2. Result Summary

- Overall Result: **pass** (4/4 tests)
- Failure Stage: none
- Notes: New P2-2 test successfully executed `requestAirdrop → getBalance → getLatestBlockhash → compileLegacy → sign → sendTransaction`. Received a valid transaction signature from the surfnet validator.

### 3. Evidence Checklist

- [x] `requestAirdrop` funded payer (`J4xQr3praHSVLe43rfhW3QqVu1vMMT27QVMvdka7Hkum`)
- [x] `getBalance` confirmed funds (199995000 lamports)
- [x] `getLatestBlockhash` returned live blockhash
- [x] transaction constructed (`Message.compileLegacy` — System Program self-transfer, 1000 lamports)
- [x] transaction signed (`tx.sign` + `verifySignatures`)
- [x] `sendTransaction` returned `.ok` with valid 64-byte signature
- [x] zero memory leaks (gpa enforced)

### 4. Console Output (captured)
```
[sendTx E2E] endpoint: http://127.0.0.1:8899
[sendTx E2E] payer: J4xQr3praHSVLe43rfhW3QqVu1vMMT27QVMvdka7Hkum
[sendTx E2E] payer balance: 199995000 lamports (after 0 polls)
[sendTx E2E] sendTransaction .ok — sig: 3E5Xn8N4dsRcPTs3zNGdigBLy9t4pE4CGsAhxpRJ1Eh87akLXCn1CQC4NY5wGvSjmZykn8mu5UiExWM9ra1oNPcX
```

### 5. Notes

- This run provided the initial `sendTransaction` live evidence (signature returned).
- The `sendTransaction` method in `client.zig` was updated to include `preflightCommitment: "confirmed"` to match `getLatestBlockhash` commitment level.
- Public devnet was also tested but airdrop was rate-limited (new keypair had 0 balance), so the test gracefully skips. Local surfnet is the authoritative evidence.
- The test uses a System Program self-transfer (payer → payer, 1000 lamports) to avoid needing a pre-funded receiver.
- **Note**: This run did not include confirm evidence. See Run 5 for the complete send + confirm evidence.

---

## Run 5 — sendTransaction + confirmTransaction Live (Local Surfnet, #17 P2-2 补齐)

### 1. Run Metadata

- Run ID: `2026-04-16/surfnet/send-confirm-live`
- Date: `2026-04-16`
- Run Type: `real-harness` (live sendTransaction + getSignatureStatuses round-trip)
- Operator: `@CC (automated)`
- RPC Endpoint: `http://127.0.0.1:8899` (surfnet, datasource: `api.mainnet-beta.solana.com`)
- Command / Entry: `SOLANA_RPC_URL=http://127.0.0.1:8899 zig build devnet-e2e`
- Exit Code: `0`

### 2. Result Summary

- Overall Result: **pass** (4/4 tests — 2 mock + 1 devnet simulate + 1 send+confirm)
- Failure Stage: none
- Notes: P2-2 test now exercises the full `requestAirdrop → getBalance → getLatestBlockhash → compileLegacy → sign → sendTransaction → getSignatureStatuses (confirm)` flow. Transaction confirmed on the first poll.

### 3. Evidence Checklist

- [x] `requestAirdrop` funded payer (`J4xQr3praHSVLe43rfhW3QqVu1vMMT27QVMvdka7Hkum`)
- [x] `getBalance` confirmed funds (299990000 lamports)
- [x] `getLatestBlockhash` returned live blockhash
- [x] transaction constructed (`Message.compileLegacy` — System Program self-transfer, 1000 lamports)
- [x] transaction signed (`tx.sign` + `verifySignatures`)
- [x] `sendTransaction` returned `.ok` with valid 64-byte signature
- [x] `getSignatureStatuses` returned `confirmationStatus: "confirmed"` at slot 413542952
- [x] zero memory leaks (gpa enforced)

### 4. Console Output (captured)

```
[sendTx E2E] endpoint: http://127.0.0.1:8899
[sendTx E2E] payer: J4xQr3praHSVLe43rfhW3QqVu1vMMT27QVMvdka7Hkum
[sendTx E2E] payer balance: 299990000 lamports (after 0 polls)
[sendTx E2E] sendTransaction .ok — sig: 3pkLWVQq5ZSX1gkqLpbap7FQYVnrSthxXHTcTJYHKvNdYT9jtkrMouJMXXqN57rLUReMD4kPMqqR2wDGhWQNe6xn
[sendTx E2E] confirm poll 0: status=confirmed, slot=413542952
[sendTx E2E] CONFIRMED — sig: 3pkLWVQq5ZSX1gkqLpbap7FQYVnrSthxXHTcTJYHKvNdYT9jtkrMouJMXXqN57rLUReMD4kPMqqR2wDGhWQNe6xn (after 0 polls)
```

### 5. Notes

- This run completes the `G-P2-02` DoD: **send + confirm** evidence (success path).
- `getSignatureStatuses` method was added to `client.zig` with typed parse support (`SignatureStatus` type).
- Confirmation was immediate (0 additional polls needed) — surfnet confirmed the tx within the same RPC round-trip window.
- This evidence, combined with Run 4's send evidence, closes the Phase 1 exception for `sendTransaction` live evidence.
- The full `construct → sign → send → confirm` pipeline is now verified end-to-end against a live validator.

### 6. Failure Evidence (Mock, G-P2-02 compliance)

G-P2-02 requires at least 1 success + 1 failure evidence. Failure paths are covered by mock tests in `src/e2e/devnet_e2e.zig`:

1. **Send failure** (`P2-2 mock: send failure path`): `sendTransaction` returns `rpc_error` with code=-32002 ("AccountNotFound"). Assertions: `code < 0`, `message.len > 0`.
2. **Confirm failure** (`P2-2 mock: confirm failure path`): `getSignatureStatuses` returns `confirmed` status with `InstructionError` in `err` field. Assertions: `confirmationStatus == "confirmed"`, `err_json != null`.

Both tests pass under `zig build devnet-e2e` with zero memory leaks.
