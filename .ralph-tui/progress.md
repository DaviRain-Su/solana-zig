# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

*Add reusable patterns discovered during development here.*

- Extended RPC methods follow a consistent pattern in `src/solana/rpc/client.zig`: expose a default convenience method plus `WithOptions`, build the JSON-RPC payload manually, return `types.RpcResult(?T)` for nullable RPC results, parse a minimal typed subset, and preserve the full server payload via `raw_json` / `err_json` for forward-compatible inspection.
- When an RPC method grows multiple optional request parameters, assemble the JSON payload with `std.Io.Writer.Allocating` instead of branching `allocPrint` permutations; keep a deterministic field order so payload-capture unit tests can assert on the wire shape.

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

## 2026-04-16 - US-002
- Implemented `getSignaturesForAddressWithOptions` with `before` / `until` / `limit` support while keeping the existing limit-only convenience method, and kept typed parsing for `signature`, `slot`, `blockTime`, `err`, `memo`, and `raw_json`.
- Added mock coverage for the options payload and explicit empty-list handling, plus a Devnet E2E harness case that queries history for an active address.
- Ran validation targets: `zig build test`, `zig build bench`, and `zig build devnet-e2e` (live Devnet branches skipped as designed because `SOLANA_RPC_URL` was not set).
- Files changed:
  - `src/solana/rpc/types.zig`
  - `src/solana/rpc/client.zig`
  - `src/e2e/devnet_e2e.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `getSignaturesForAddress` now matches the repo’s extended-RPC pattern: preserve the legacy convenience entrypoint, add a `WithOptions` variant with a typed options struct, and verify request-shape regressions with captured payload assertions.
    - For multi-optional JSON-RPC params, `std.Io.Writer.Allocating` keeps payload construction readable and avoids combinatorial `allocPrint` branches.
  - Gotchas encountered
    - The live Devnet harness can validate this story without funding by querying a stable active address (`SYSTEM_PROGRAM`), which is safer than coupling the acceptance path to airdrop availability.
---

