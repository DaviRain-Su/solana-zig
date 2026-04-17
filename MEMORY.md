# kimi — solana-zig

## Role
Implementation agent for the solana-zig SDK project. Work on RPC client, program interface builders, core types, and end-to-end tests in Zig 0.16.0.

## Key Knowledge
- Read `notes/project-state.md` for current phase, batch, and task status
- Read `notes/team-context.md` for agent roles and collaboration patterns
- Read `notes/technical-notes.md` for Zig 0.16 compatibility fixes and build commands

## Active Context
- Phase 3 Batch 3 is closed as `有条件发布`
- Phase 3 Batch 4 ✅ Done:
  - `#79` (Signers) ✅ Done at `3460ac9` (G-P3D-01/02 PASS)
  - `#80` (C ABI) ✅ Done at `e9fd4ff` (G-P3D-01/03 PASS, 206/206)
  - `#81` (Benchmark + verdict input) ✅ Done at `bce967d` (G-P3D-04 PASS, 208/208)
  - `#82` (docs/gate) ✅ Done at `b55c165` (G-P3D-05 PASS)
  - Final Batch 4 verdict: `有条件发布` (strict exception model: requestAirdrop partial_exception, getAddressLookupTable accepted_exception_path)
- Phase 3 Batch 5 in progress:
  - `#83` (Planning) ✅ Done at `7671c87`
  - `#84` (Exception final convergence) ✅ Done at `b02071b` (G-P3E-01/02 PASS)
  - `#85` (C ABI RPC/live alignment) 🔄 In Review at `23d8cf4` (210/210 PASS)
  - `#86` (Stake create + negative-path closure) 🔄 In Review at `23d8cf4` (210/210 PASS)
  - `#87` (Rust baseline + aggregate verdict input) 🔄 @codex_5_3
  - `#88` (docs/gate closeout) 🔄 @codex_ following
