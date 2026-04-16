# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

*Add reusable patterns discovered during development here.*

- Core fixed-size value types follow a shared wrapper pattern: expose `pub const LENGTH`, store bytes in a fixed array field, provide `init`/`fromSlice` plus `fromBase58`/`toBase58Alloc` helpers, and keep inline tests beside the type; shared base58 helpers surface `error.InvalidLength` and `error.InvalidBase58` consistently.
- When a fixed-size crypto wrapper needs an "unsigned" sentinel, expose it as a type-level helper like `zero()` and reuse that helper at call sites instead of repeating inline zero-byte struct literals.
- When wrapping Zig std crypto key material, expose public length constants and byte-oriented constructors around `std.crypto.sign.Ed25519` so 32-byte deterministic seeds and 64-byte secret-key recovery share one `Keypair` API without leaking stdlib internals to callers.

---

## 2026-04-16 - US-001
- What was implemented
  - Verified the existing `Pubkey` implementation already satisfies the story: 32-byte fixed layout, base58 decode/encode helpers, correct leading-zero handling through the shared base58 codec, clear invalid-input errors, and Rust-oracle pubkey vector coverage.
- Files changed
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `Pubkey`, `Hash`, and `Signature` use the same fixed-array wrapper API shape, with shared base58 behavior centralized in `src/solana/core/base58.zig`.
    - Oracle compatibility is validated from `testdata/oracle_vectors.json` through inline tests in `src/solana/compat/oracle_vector.zig`.
  - Gotchas encountered
    - Leading-zero correctness is covered at the codec layer, so the important verification point for fixed-size types is that `decodeFixed` preserves byte length and rejects non-32-byte results with `error.InvalidLength`.
---

## 2026-04-16 - US-002
- What was implemented
  - Added an explicit `Signature.zero()` helper for the unsigned all-zero default, expanded `Signature` inline coverage for base58 roundtrip plus invalid-input errors, and updated transaction unsigned-signature initialization to reuse the shared zero-value helper.
- Files changed
  - `src/solana/core/signature.zig`
  - `src/solana/tx/transaction.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `VersionedTransaction.initUnsigned` is the main consumer of the signature unsigned sentinel, so centralizing the zero constructor in `Signature` keeps transaction code aligned with the fixed-wrapper API pattern.
  - Gotchas encountered
    - Clear invalid-input behavior for base58-backed wrappers comes from testing both failure modes separately: malformed alphabet should return `error.InvalidBase58`, while well-formed base58 that decodes to the wrong byte length should return `error.InvalidLength`.
---

## 2026-04-16 - US-003
- What was implemented
  - Verified the existing `Hash` implementation already satisfies the story: it stores bytes as a fixed `[32]u8`, exposes raw-byte construction via `init` and `fromSlice`, and supports base58 encode/decode through `toBase58Alloc` and `fromBase58`.
- Files changed
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `Hash` follows the same fixed-size wrapper contract already established by `Pubkey`: `LENGTH`, fixed-array storage, raw-byte constructors, and shared base58 helpers are sufficient for blockhash-style value objects.
  - Gotchas encountered
    - The story PRD entry was still marked incomplete even though `src/solana/core/hash.zig` already matched the acceptance criteria, so this iteration focused on verification plus progress capture rather than new source edits.
---

## 2026-04-16 - US-004
- What was implemented
  - Extended `Keypair` with random generation via `std.crypto.sign.Ed25519.KeyPair.generate` and 64-byte secret-key recovery via `Ed25519.SecretKey.fromBytes` + `KeyPair.fromSecretKey`.
  - Added inline coverage for random sign/verify, 64-byte recovery roundtrip, and mismatched secret-key rejection; existing oracle vector coverage continues to assert deterministic seed signatures match the Rust SDK output.
- Files changed
  - `src/solana/core/keypair.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `Keypair` can stay ergonomic by exposing raw-length constants while delegating cryptographic validation to Zig stdlib helpers, which preserves compatibility with downstream transaction-signing APIs.
  - Gotchas encountered
    - Zig stdlib Ed25519 secret keys are 64-byte values composed of the 32-byte seed plus a cached 32-byte public key, so recovery should use `KeyPair.fromSecretKey` in order to reject mismatched embedded public keys instead of trusting raw bytes blindly.
---

