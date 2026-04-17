# C ABI Usage Guide

> Scope: Product Phase 3 Batch 3 — C ABI export layer for `solana-zig`.

## Overview

The C ABI layer allows non-Zig languages to safely call a minimal subset of `solana-zig` capabilities:
- Core fixed-size types (`Pubkey`, `Signature`, `Hash`)
- Transaction building and serialization
- Minimal RPC client initialization

Current 2026-04-17 review status:
- `core` and `transaction` exports are usable as documented below
- `rpc` exports are in **scaffold** state: they validate handle lifecycle and error-code plumbing, but use a dummy transport. To make real RPC calls from C, extend the C ABI surface with a real HTTP transport binding.

## Header File

Include `include/solana_zig.h` in your C/C++ project.

```c
#include "solana_zig.h"
```

## Ownership Model

**Rule: Who allocates, provides the free function.**

All heap-allocated outputs from the ABI must be freed using the matching `solana_*_free` or `destroy` function. Do not call `free()` directly on Zig-allocated memory.

| Allocation source | Free function |
|---|---|
| `solana_pubkey_to_base58` | `solana_string_free` |
| `solana_signature_to_base58` | `solana_string_free` |
| `solana_hash_to_base58` | `solana_string_free` |
| `solana_transaction_serialize` | `solana_bytes_free` |
| `solana_instruction_create` | `solana_instruction_destroy` |
| `solana_message_compile_legacy` | `solana_message_destroy` |
| `solana_transaction_create_unsigned` (consumes `msg`) | `solana_transaction_destroy` |
| `solana_rpc_client_init` | `solana_rpc_client_deinit` |

## Error Codes

| Code | Name | Meaning |
|---|---|---|
| `0` | `SOLANA_OK` | Success |
| `1` | `SOLANA_ERR_INVALID_ARGUMENT` | Bad input (null pointer, wrong length, bad base58) |
| `2` | `SOLANA_ERR_INVALID_LENGTH` | Buffer length mismatch |
| `3` | `SOLANA_ERR_RPC_TRANSPORT` | Network / transport failure |
| `4` | `SOLANA_ERR_RPC_PARSE` | Could not parse RPC response |
| `5` | `SOLANA_ERR_BACKEND_FAILURE` | RPC returned an error object |
| `6` | `SOLANA_ERR_INTERNAL` | Unexpected internal failure |

## Examples

### Pubkey roundtrip

```c
#include "solana_zig.h"
#include <stdio.h>
#include <string.h>

int main(void) {
    uint8_t bytes[32] = {0};
    SolanaPubkey pk;
    if (solana_pubkey_from_bytes(bytes, 32, &pk) != SOLANA_OK) {
        return 1;
    }

    char *b58 = NULL;
    size_t len = 0;
    if (solana_pubkey_to_base58(&pk, &b58, &len) != SOLANA_OK) {
        return 1;
    }

    printf("pubkey base58: %.*s\n", (int)len, b58);
    solana_string_free(b58, len);
    return 0;
}
```

### Build and serialize a transaction

```c
#include "solana_zig.h"
#include <stdio.h>

int main(void) {
    SolanaPubkey program_id = { .bytes = {7} };
    SolanaPubkey payer = { .bytes = {6} };
    SolanaHash blockhash = { .bytes = {5} };
    SolanaAccountMeta accounts[1] = {
        { .pubkey = payer, .is_signer = 1, .is_writable = 1 },
    };

    SolanaInstruction *ix = NULL;
    uint8_t data[] = {0x01};
    if (solana_instruction_create(&program_id, accounts, 1, data, 1, &ix) != SOLANA_OK) {
        return 1;
    }

    SolanaInstruction *ixs[1] = { ix };
    SolanaMessage *msg = NULL;
    if (solana_message_compile_legacy(&payer, ixs, 1, &blockhash, &msg) != SOLANA_OK) {
        solana_instruction_destroy(&ix);
        return 1;
    }

    SolanaTransaction *tx = NULL;
    if (solana_transaction_create_unsigned(&msg, &tx) != SOLANA_OK) {
        solana_message_destroy(&msg);
        solana_instruction_destroy(&ix);
        return 1;
    }

    uint8_t *serialized = NULL;
    size_t serialized_len = 0;
    if (solana_transaction_serialize(tx, &serialized, &serialized_len) != SOLANA_OK) {
        solana_transaction_destroy(&tx);
        solana_instruction_destroy(&ix);
        return 1;
    }

    printf("serialized tx length: %zu\n", serialized_len);

    solana_bytes_free(serialized, serialized_len);
    solana_transaction_destroy(&tx);
    solana_instruction_destroy(&ix);
    return 0;
}
```

## Limitations

- The C ABI RPC client (`solana_rpc_client_init`) uses a **dummy transport** (scaffold state). Real HTTP transport from C requires extending the C ABI surface.
- `solana_hash_*` covers byte construction, base58 conversion, and equality (`solana_hash_equal`).
- `solana_zig_abi_version()` is exported as a C function (in addition to the `SOLANA_ZIG_ABI_VERSION` macro).
- Opaque handles (`SolanaRpcClientHandle`, `SolanaInstruction`, `SolanaMessage`, `SolanaTransaction`) hide internal Zig types. Do not cast them to your own structs.

## Versioning

- Current ABI version: `1`
- Macro: `SOLANA_ZIG_ABI_VERSION`
