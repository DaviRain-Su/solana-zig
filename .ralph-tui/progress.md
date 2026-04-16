# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

*Add reusable patterns discovered during development here.*

- Extended RPC methods follow a consistent pattern in `src/solana/rpc/client.zig`: expose a default convenience method plus `WithOptions`, build the JSON-RPC payload manually, return `types.RpcResult(?T)` for nullable RPC results, parse a minimal typed subset, and preserve the full server payload via `raw_json` / `err_json` for forward-compatible inspection.
- When an RPC method grows multiple optional request parameters, assemble the JSON payload with `std.Io.Writer.Allocating` instead of branching `allocPrint` permutations; keep a deterministic field order so payload-capture unit tests can assert on the wire shape.
- Batch-style RPC lookups should preserve Solana’s positional response semantics with `[]?T` result items; single-signature confirmation helpers can still layer on top by reading `items[0]`, while tests assert both payload shape and null-slot mapping.
- For scalar/object read RPCs that only need a configurable `commitment`, prefer a tiny `*Options` struct plus a convenience wrapper that forwards to `WithOptions`; this keeps the public API uniform with richer RPC methods and makes payload-capture tests straightforward.
- For scalar RPCs with stable public-cluster economics (for example rent-exemption quotes), combine payload-capture unit tests with a table-driven Devnet E2E that asserts a few canonical input/output pairs; this catches both wire-shape regressions and semantic drift without needing funded accounts.

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

## 2026-04-16 - US-003
- Implemented batch-aware `getSignatureStatusesWithOptions` plus the default convenience wrapper, returning positional status items for every input signature and supporting configurable `searchTransactionHistory`.
- Added mock coverage for batched happy-path parsing, partial-missing/null entries, request payload shape, and kept RPC error preservation; updated Devnet/mock confirmation helpers to consume the batch result while still polling the first signature after send.
- Files changed:
  - `src/solana/rpc/types.zig`
  - `src/solana/rpc/client.zig`
  - `src/e2e/devnet_e2e.zig`
  - `src/e2e/nonce_e2e.zig`
  - `src/solana/interfaces/token.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - Batch RPC methods fit the repo’s typed-RPC pattern best when the result keeps Solana’s positional null semantics (`[]?T`) instead of collapsing to a single optional item.
    - Existing single-signature confirmation loops can adopt batch-capable APIs cheaply by asserting `items.len == 1` and reading `items[0]`, which keeps E2E helpers reusable.
  - Gotchas encountered
    - `getSignatureStatuses` was already serializing multiple signatures on the wire, so the real gap was response typing: callers and tests had to be updated together to avoid silently discarding non-first entries.
---

## 2026-04-16 - US-004
- Implemented `getSlotWithOptions` and `getEpochInfoWithOptions` with configurable `commitment` while preserving the existing convenience wrappers, and added payload assertions to mock tests so the requested commitment is verified on the wire.
- Added a gated Devnet E2E case for `getSlot` / `getEpochInfo` that checks positive slot/epoch values plus `blockHeight`, `transactionCount`, and `raw_json` structure preservation.
- Files changed:
  - `src/solana/rpc/types.zig`
  - `src/solana/rpc/client.zig`
  - `src/e2e/devnet_e2e.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - Commitment-only RPC methods fit the repo’s extended-RPC style best when they expose a no-arg wrapper and a `WithOptions` variant backed by a small typed options struct.
    - Payload-capture unit tests are the cheapest way to verify `commitment` plumbing without needing separate mock fixtures for every enum value.
  - Gotchas encountered
    - `zig build devnet-e2e` remains environment-gated; with `SOLANA_RPC_URL` unset the new US-004 live branch is validated only through the expected skip path, not an actual Devnet call.
---

## 2026-04-16 - US-005
- Tightened `getMinimumBalanceForRentExemption` to take `usize` data lengths while keeping the `u64` lamports result, and upgraded the mock happy-path test to assert the exact JSON-RPC payload for the requested size.
- Added a dedicated gated Devnet E2E case that verifies canonical rent-exemption quotes for `0`, `80`, and `128` byte account sizes against current Devnet expectations.
- Files changed:
  - `src/solana/rpc/client.zig`
  - `src/e2e/devnet_e2e.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - Stable scalar RPCs benefit from table-driven live assertions of a few canonical values, which gives stronger coverage than only checking for positive/non-zero outputs.
  - Gotchas encountered
    - The previous mock fixture for the 128-byte rent quote did not match current Devnet economics, so the unit fixture and live expectations needed to be aligned separately instead of assuming arbitrary mock numbers were safe as acceptance evidence.
---

