# Technical Notes — solana-zig

## Build Commands
- `zig build test` — run unit tests (baseline 193/193)
- `zig build e2e` — end-to-end tests
- `zig build devnet-e2e` — devnet e2e
- `zig build nonce-e2e` — durable nonce e2e

## Zig 0.16.0 Compatibility Fixes Applied
- `std.time.sleep` / `std.Thread.sleep` removed → use `std.posix.nanosleep`
- `std.json.stringifyAlloc` unavailable → manual JSON stringification
- `error.EndOfStream` not in `std.Io` reader error set → `error.ReadFailed`
- `build.zig` requires `.link_libc = true` on root module (for `std.c.socket` and `std.c.clock_gettime`)

## Smoke Endpoints
- Public devnet: `SOLANA_RPC_URL=https://api.devnet.solana.com`
- Local live: `SURFPOOL_RPC_URL=http://127.0.0.1:8899`
