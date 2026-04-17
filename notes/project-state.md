# Project State — solana-zig

## Current Phase
Phase 3 Batch 4 closeout planning / repo-wide review (task #78 P3-16)

## Completed
- Phase 3 Batch 2: #69..#72 Done (193/193 tests PASS)
- Phase 2 Batch 3: #32, #34 Done; #33 transferred to @codex_5_3 / @codex_

## Active Tasks
- Phase 3 Batch 3 ✅ Closed as `有条件发布`
  - `#73` P3-11 scope freeze / DoD ✅ Done (`82da1b0`)
  - `#74` P3-12 token-2022 minimum builder ✅ Done (`da93cfb`)
  - `#75` P3-13 stake delegate minimum builder ✅ Done (`4d35e30`)
  - `#76` P3-14 exception convergence ✅ Done (`da93cfb`)
  - `#77` P3-15 docs/gate reconciliation ✅ Done (`e3a3794`)
- Phase 3 Batch 4 review-driven closeout (planning active)
  - `#78` P3-16 scope freeze / DoD / follow-up plan
  - P3-17: `MockExternalSigner` correctness closure
  - P3-18: stake create helper contract + negative-path closure
  - P3-19: C ABI reality alignment (header/core/tests/RPC story)
  - P3-20: top-level docs/status reconciliation

## Current Review Findings
- `MockExternalSigner.signMessage(...)` currently signs an empty string instead of the input message
- `buildCreateStakeAccountInstruction(...)` accepts `lamports` but currently only builds the initialize payload
- C ABI core/tx surfaces exist, but RPC export still uses dummy transport and needs explicit scope alignment
- Top-level docs previously overstated Phase 3 as fully complete; authority now centers on `docs/10`, `docs/36`, `docs/37`

## Baseline
- Freeze point: `e3a3794`
- Canonical baseline before Batch 4 implementation: current mainline + repo-wide review
- Zig version: 0.16.0
