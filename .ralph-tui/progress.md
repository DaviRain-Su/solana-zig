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
- For live Devnet RPCs that mutate state and can be faucet-limited, prefer a typed end-to-end assertion that captures the returned signature, polls the affected account for a before/after state delta, and explicitly treats rate-limit RPC errors as a logged skip path instead of a hard failure.
- For live Devnet acceptance that needs a non-ephemeral on-chain artifact (for example an ALT account), prefer a discovery helper that scans recent blocks via raw JSON-RPC and reuses the discovered key in the typed client assertion; this avoids hardcoding addresses that may disappear while still validating the real parser.
- For token-account live acceptance, prefer discovering a sample token account via raw helper RPCs (for example `getTokenLargestAccounts`), then decode the canonical SPL Token account layout through the typed `getAccountInfo` path to derive a reusable owner/mint fixture before asserting higher-level typed RPC filters.

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

## 2026-04-16 - US-006
- Verified `requestAirdrop` was already implemented in `RpcClient`, then added the missing payload-capture regression test and a dedicated Devnet E2E that uses the typed RPC method, records the returned signature, and polls `getBalance` until the recipient balance increases.
- Files changed:
  - `src/solana/rpc/client.zig`
  - `src/e2e/devnet_e2e.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - Live faucet-backed RPC acceptance is more robust when it proves a concrete account-state delta (`before_balance -> after_balance`) instead of only checking that the RPC returned success.
  - Gotchas encountered
    - Zig 0.16 in this repo does not expose `std.crypto.random`, so a dedicated deterministic seed is the safer choice for stable Devnet E2E accounts unless a different randomness source is wired explicitly.
---

## 2026-04-16 - US-007
- Implemented typed `getAddressLookupTable` account parsing so successful responses now return an `AddressLookupTableAccount` shape (`key` + `state` with `addresses`), added explicit mock coverage for the `null`/not-found case, and added a gated Devnet E2E that discovers a recent ALT from live blocks before validating typed parsing against the RPC method.
- Files changed:
  - `src/solana/rpc/types.zig`
  - `src/solana/rpc/client.zig`
  - `src/e2e/devnet_e2e.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `getAddressLookupTable` fits the repo best when the outer RPC response keeps Solana context metadata, but the nullable payload itself is promoted into an SDK-shaped account object (`key` + `state`) rather than exposing the raw wire layout directly.
    - For live ALT verification, scanning recent `getBlock` results for `message.addressTableLookups[*].accountKey` is a practical way to discover a currently active table without hardcoding a brittle Devnet fixture.
  - Gotchas encountered
    - Zig rejects function parameters that shadow a top-level declaration in the same file, so local JSON helper argument names in `devnet_e2e.zig` must avoid `root` because that file already imports `const root = @import("solana_zig");`.
---

## 2026-04-16 - US-008
- Implemented `getTokenAccountsByOwnerWithOptions` with typed `programId` / `mint` filters, configurable `encoding` + `commitment`, and reshaped results so each item now exposes `pubkey` plus nested `account_info` while preserving decoded account data and raw account JSON.
- Added mock coverage for the programId happy path payload, mint-filter empty-list handling, RPC error preservation, and malformed responses; added a gated Devnet E2E that discovers a wrapped-SOL holder via `getTokenLargestAccounts`, decodes the owner from the token account bytes, and validates both filter modes against live RPC.
- Files changed:
  - `src/solana/rpc/types.zig`
  - `src/solana/rpc/client.zig`
  - `src/e2e/devnet_e2e.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `getTokenAccountsByOwner` fits the repo’s extended-RPC pattern best with a `WithOptions` variant whose required filter is a small tagged union, keeping the legacy convenience wrapper for the common `programId` case while still making payload assertions deterministic.
    - Live token-account validation is most robust when a raw discovery helper finds a current token account first and the typed `getAccountInfo` parser is then reused to decode the canonical `[mint|owner|...]` account layout for downstream assertions.
  - Gotchas encountered
    - Declaring a `Pubkey.fromBase58(...)` constant at file scope triggered Zig comptime branch-quota errors in the E2E target, so the wrapped-SOL mint had to stay as a string constant and be parsed at runtime inside the test.
---

