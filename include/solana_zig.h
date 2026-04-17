#ifndef SOLANA_ZIG_H
#define SOLANA_ZIG_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SOLANA_ZIG_ABI_VERSION 1

int solana_zig_abi_version(void);

/* ===================== Error codes ===================== */
#define SOLANA_OK 0
#define SOLANA_ERR_INVALID_ARGUMENT 1
#define SOLANA_ERR_INVALID_LENGTH 2
#define SOLANA_ERR_RPC_TRANSPORT 3
#define SOLANA_ERR_RPC_PARSE 4
#define SOLANA_ERR_BACKEND_FAILURE 5
#define SOLANA_ERR_INTERNAL 6

/* ===================== Opaque handles ===================== */
typedef struct SolanaRpcClientHandle SolanaRpcClientHandle;
typedef struct SolanaInstruction SolanaInstruction;
typedef struct SolanaMessage SolanaMessage;
typedef struct SolanaTransaction SolanaTransaction;

/* ===================== Fixed-size types ===================== */
typedef struct SolanaPubkey {
    uint8_t bytes[32];
} SolanaPubkey;

typedef struct SolanaSignature {
    uint8_t bytes[64];
} SolanaSignature;

typedef struct SolanaHash {
    uint8_t bytes[32];
} SolanaHash;

/* ===================== Pubkey ===================== */
int solana_pubkey_from_bytes(const uint8_t *bytes, size_t len, SolanaPubkey *out);
int solana_pubkey_to_base58(const SolanaPubkey *pubkey, char **out_str, size_t *out_len);
int solana_pubkey_from_base58(const char *str, size_t len, SolanaPubkey *out);
int solana_pubkey_equal(const SolanaPubkey *a, const SolanaPubkey *b);

/* ===================== Signature ===================== */
int solana_signature_from_bytes(const uint8_t *bytes, size_t len, SolanaSignature *out);
int solana_signature_from_base58(const char *str, size_t len, SolanaSignature *out);
int solana_signature_to_base58(const SolanaSignature *sig, char **out_str, size_t *out_len);
int solana_signature_equal(const SolanaSignature *a, const SolanaSignature *b);

/* ===================== Hash ===================== */
int solana_hash_from_bytes(const uint8_t *bytes, size_t len, SolanaHash *out);
int solana_hash_from_base58(const char *str, size_t len, SolanaHash *out);
int solana_hash_to_base58(const SolanaHash *h, char **out_str, size_t *out_len);
int solana_hash_equal(const SolanaHash *a, const SolanaHash *b);

/* ===================== General free ===================== */
void solana_string_free(char *str, size_t len);
void solana_bytes_free(uint8_t *bytes, size_t len);

/* ===================== Instruction ===================== */

typedef struct SolanaAccountMeta {
    SolanaPubkey pubkey;
    int is_signer;
    int is_writable;
} SolanaAccountMeta;

int solana_instruction_create(
    const SolanaPubkey *program_id,
    const SolanaAccountMeta *accounts,
    size_t account_count,
    const uint8_t *data,
    size_t data_len,
    SolanaInstruction **out
);
void solana_instruction_destroy(SolanaInstruction **ix);

/* ===================== Message ===================== */
int solana_message_compile_legacy(
    const SolanaPubkey *payer,
    SolanaInstruction **const *instructions,
    size_t instruction_count,
    const SolanaHash *recent_blockhash,
    SolanaMessage **out
);
void solana_message_destroy(SolanaMessage **msg);

/* ===================== Transaction ===================== */
int solana_transaction_create_unsigned(SolanaMessage **msg, SolanaTransaction **out);
int solana_transaction_sign_with_keypair(SolanaTransaction *tx, const uint8_t *secret_key, size_t secret_key_len);
int solana_transaction_serialize(const SolanaTransaction *tx, uint8_t **out_bytes, size_t *out_len);
void solana_transaction_destroy(SolanaTransaction **tx);

/* ===================== RPC Client ===================== */
/* Current Batch 4 status: lifecycle scaffold only; transport is a dummy/stub and RPC calls are not live-ready from C yet. */
int solana_rpc_client_init(const char *endpoint, size_t endpoint_len, SolanaRpcClientHandle **out);
void solana_rpc_client_deinit(SolanaRpcClientHandle **handle);
int solana_rpc_client_get_latest_blockhash(SolanaRpcClientHandle *handle, SolanaHash *out_blockhash);
int solana_rpc_client_get_balance(SolanaRpcClientHandle *handle, const SolanaPubkey *pubkey, uint64_t *out_lamports);

#ifdef __cplusplus
}
#endif

#endif /* SOLANA_ZIG_H */
