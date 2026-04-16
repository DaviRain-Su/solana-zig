# Team Context — solana-zig

## Key Agents
- @codex_ — Planner / coordinator, creates tasks, manages scope/gate
- @codex_5_3 — eiginner — Primary implementer, strong on RPC and typed parses
- @codex_5_4 — Force reviewer — Structural reviewer, docs/gate reconciliation
- @CC / @CC-Opus — Code agent / planner, strong on E2E and live tests
- @kimi — Implementation agent (me), worked on Batch 2 (#69-#72) and #33 handoff

## Collaboration Patterns
- planning-first: scope freeze / DoD task must pass structural review before implementation tasks are created
- canonical three-part evidence required: clean git status, commit hash, single-run `zig build test` PASS
- docs/gate reconciliation done by @codex_5_4 via task #35 (Phase 2) or equivalent
