# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

*Add reusable patterns discovered during development here.*

- Core fixed-size value types follow a shared wrapper pattern: expose `pub const LENGTH`, store bytes in a fixed array field, provide `init`/`fromSlice` plus `fromBase58`/`toBase58Alloc` helpers, and keep inline tests beside the type; shared base58 helpers surface `error.InvalidLength` and `error.InvalidBase58` consistently.
- When a fixed-size crypto wrapper needs an "unsigned" sentinel, expose it as a type-level helper like `zero()` and reuse that helper at call sites instead of repeating inline zero-byte struct literals.
- When wrapping Zig std crypto key material, expose public length constants and byte-oriented constructors around `std.crypto.sign.Ed25519` so 32-byte deterministic seeds and 64-byte secret-key recovery share one `Keypair` API without leaking stdlib internals to callers.
- For Solana wire-format varints, keep the public API ergonomic with `usize` inputs/results but enforce the protocol's strict `shortu16` rules at the codec boundary: 1-3 bytes only, `u16` maximum, canonical encodings only, and decode should report consumed bytes for cursor-based parsers.
- Transaction-facing plain data structs mirror Rust SDK layout by keeping field names and declaration order identical, while using `[]const` slices for borrowed account/data views instead of introducing extra wrappers.
- Versioned wire models can stay unified behind a `version` tag when the structural delta is small: `Message` shares one compile/serialize/deserialize pipeline for legacy and v0, with version-specific prefixes/lookup sections layered on top of common header/key/instruction handling.
- For ALT-backed messages, keep compile-time lookup tables (`AddressLookupTable`) separate from owned wire-format lookup records and expose a Rust-aligned public alias when the serialized shape already matches the SDK model.
- When required signer pubkeys live in `message.account_keys[0..num_required_signatures]`, transaction signing can stay caller-order-independent by matching each provided `Keypair.pubkey()` back to that prefix before filling signature slots.
- Oracle compatibility suites should embed the versioned JSON fixture with `@embedFile` and route each vector family through focused helper assertions (`expectPubkeyCase` / `expectMessageCase` / `expectTransactionCase`) so Rust parity coverage stays offline, deterministic, and easy to expand.
- RPC transport plumbing uses a tiny function-pointer vtable (`Transport.init(ctx, postJson, deinit)`) around `*anyopaque`, which keeps `RpcClient` production-ready with `std.http.Client` while letting tests inject lightweight scripted mocks without changing higher-level RPC parsing.

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

## 2026-04-16 - US-005
- What was implemented
  - Tightened `src/solana/core/shortvec.zig` to match `solana-short-vec 3.2.0` `shortu16` semantics: encoding now rejects values above `u16::MAX`, decoding accepts only canonical 1-3 byte encodings, rejects aliases and invalid third-byte continuations, and still reports consumed bytes for cursor-based message parsing.
  - Added boundary and invalid-case inline coverage for canonical encodings including `0`, `127`, `128`, `16383`, `16384`, and `65535`, plus alias, truncation, overflow, and over-limit encode failures.
- Files changed
  - `src/solana/core/shortvec.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - Solana's `shortvec` compatibility point is specifically Rust `shortu16`, so the repo can keep `usize` at the API edge while enforcing strict canonical `u16` framing inside the codec.
  - Gotchas encountered
    - A generic LEB128 decoder is too permissive for Solana: aliases like `[0x80, 0x00]` for zero and continued third bytes must be rejected even though they decode numerically.
---

## 2026-04-16 - US-006
- What was implemented
  - Verified `src/solana/tx/instruction.zig` already satisfies the story: `Instruction` exposes `program_id`, `accounts`, and `data`, while `AccountMeta` exposes `pubkey`, `is_signer`, and `is_writable`.
  - Confirmed the declaration order matches the Rust SDK model shape used for transaction instruction construction.
- Files changed
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - Transaction model leaf structs in `src/solana/tx` stay intentionally minimal and Rust-aligned, which lets higher-level builders and message compilation code consume them directly without adapter layers.
  - Gotchas encountered
    - This story's implementation was already present, so the work here was focused on source verification against the PRD/spec plus regression validation rather than adding new code.
---

## 2026-04-16 - US-007
- What was implemented
  - Verified `src/solana/tx/message.zig` already satisfies the story: `Message.compileLegacy` builds legacy messages from payer + instructions + blockhash, serialization/deserialization are implemented, and static account ordering follows signer-writable > signer-readonly > non-signer-writable > non-signer-readonly via `orderRoles`.
  - Confirmed Rust-byte-identical compatibility through the embedded oracle cases `msg_legacy_simple` and `msg_legacy_multi_ix` consumed by `src/solana/compat/oracle_vector.zig`.
- Files changed
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `src/solana/tx/message.zig` keeps legacy and v0 in one `Message` type, which avoids duplicated compile/codec logic while still matching version-specific wire rules.
  - Gotchas encountered
    - `tasks/prd.json` still marks `US-007` as incomplete, but the source and oracle coverage already satisfy the acceptance criteria, so this iteration was verification plus progress capture rather than new implementation.
---

## 2026-04-16 - US-008
- What was implemented
  - Verified the existing v0 message pipeline already supports `Message.compileV0`, ALT-aware static/dynamic account partitioning, v0 serialization with lookup sections, deserialization, and Rust oracle parity through `msg_v0_basic_alt` / `msg_v0_multi_lookup`.
  - Added a public `MessageAddressTableLookup` alias for Rust SDK naming parity and a focused v0 roundtrip test that asserts lookup indexes, dynamic instruction indexes, and deserialize fidelity.
- Files changed
  - `src/solana/tx/message.zig`
  - `src/solana/mod.zig`
  - `src/root.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - The existing `CompiledAddressLookup` wire shape already matches Rust's `MessageAddressTableLookup`, so API-compat closeout can be handled with a public alias instead of duplicating the struct.
  - Gotchas encountered
    - Positive v0 coverage needs to assert dynamic account indexes after compile/deserialization (`payer=0`, `program=1`, lookup accounts appended afterward), otherwise ALT lookup correctness is only indirectly covered by byte-oracle tests.
---

## 2026-04-16 - US-009
- What was implemented
  - Verified `VersionedTransaction` already supports unsigned construction, signing, signature verification, serialization, and deserialization on top of the shared legacy/v0 `Message` model.
  - Added focused transaction coverage for a legacy multi-signer flow with signer input order different from wire order, plus a successful v0 transaction sign/verify/serialize/deserialize roundtrip that re-checks ALT lookup indexes after parsing.
  - Revalidated Rust oracle parity for full signed transaction bytes through the existing embedded legacy and v0 transaction vectors.
- Files changed
  - `src/solana/tx/transaction.zig`
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - `VersionedTransaction.sign` is intentionally order-independent for caller-provided signers because it resolves each signer by pubkey against the required-signer prefix of `message.account_keys`.
  - Gotchas encountered
    - `VersionedTransaction.initUnsigned` takes ownership of the compiled `Message`, so follow-up tests and helpers must not `deinit` the message separately after constructing the transaction.
---

## 2026-04-16 - US-016
- What was implemented
  - Verified the oracle vector cross-reference suite was already complete for the story gate: embedded `testdata/oracle_vectors.json` fixtures cover non-zero pubkeys including leading-zero bytes, deterministic keypair signature vectors, legacy multi-instruction message serialization, v0 ALT-backed message serialization, and full signed transaction serialization.
  - Confirmed the Zig oracle tests in `src/solana/compat/oracle_vector.zig` exercise each vector family through compile/sign/serialize assertions against the embedded Rust SDK outputs, with no external service dependency.
- Files changed
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - The oracle suite groups fixture assertions by capability (`core`, `keypair`, `message`, `transaction`) and reuses shared compile helpers, which makes future vector expansion additive without changing test structure.
  - Gotchas encountered
    - `compileMessageCase` returns an owned `Message`, so transaction oracle assertions must transfer that ownership into `VersionedTransaction.initUnsigned` and avoid separately deinitializing the message on the success path.
---

## 2026-04-16 - US-010
- What was implemented
  - Verified the existing RPC transport layer already satisfies the story: `src/solana/rpc/transport.zig` defines a pluggable `Transport` interface for posting JSON-RPC payloads, `src/solana/rpc/http_transport.zig` provides the default `std.http.Client` implementation, and `RpcClient.initWithTransport` supports mock injection for tests.
  - Confirmed current request/response handling uses JSON-RPC 2.0 envelopes (`jsonrpc`, `id`, `method`, `params` / `result` / `error`) across the RPC client methods and injected-transport test coverage.
- Files changed
  - `.ralph-tui/progress.md`
- **Learnings:**
  - Patterns discovered
    - The RPC layer centralizes transport ownership in `RpcClient`, so callers choose between `init` (real HTTP) and `initWithTransport` (mock/scripted transport) without affecting typed response parsing.
  - Gotchas encountered
    - `tasks/prd.json` still marks `US-010` incomplete, but the transport abstraction, HTTP implementation, and injected mock coverage are already present in `src/solana/rpc/{transport,http_transport,client}.zig`, so this iteration was verification plus progress capture rather than new source edits.
---

