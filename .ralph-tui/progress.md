# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

*Add reusable patterns discovered during development here.*

- Extended RPC methods follow a consistent pattern in `src/solana/rpc/client.zig`: expose a default convenience method plus `WithOptions`, build the JSON-RPC payload manually, return `types.RpcResult(?T)` for nullable RPC results, parse a minimal typed subset, and preserve the full server payload via `raw_json` / `err_json` for forward-compatible inspection.

---

## 2026-04-16 - US-001
- Verified `getTransaction` was already implemented end-to-end for the story scope: signature lookup, `slot` / `blockTime` / `meta` parsing, `commitment` + `maxSupportedTransactionVersion` options, mock coverage, and Devnet E2E coverage.
- Ran validation targets: `zig build test`, `zig build bench`, and `zig build devnet-e2e` (live Devnet branch skipped as designed because `SOLANA_RPC_URL` was not set).
- Files changed:
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `getTransaction` uses the repo’s reusable typed-RPC pattern: parse the stable high-value fields (`slot`, `blockTime`, `meta.fee`, `meta.err`, `meta.logMessages`) while keeping `raw_json` for the rest of the payload.
    - Devnet E2E coverage here follows a poll-until-available helper pattern (`waitForTransactionDetails`) after `sendTransaction` + confirmation, which is reusable for later eventually consistent RPC methods.
  - Gotchas encountered
    - `zig build devnet-e2e` intentionally passes with mock coverage even when live Devnet env vars are unset, so the skip output must be treated as expected rather than as a failure.
---

