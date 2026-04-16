# Phase 3 - Technical Spec

## Byte Contracts
- `Pubkey`: 32 bytes
- `Signature`: 64 bytes (Ed25519)
- `Hash`: 32 bytes
- `shortvec`: 7-bit continuation varint

## Message Contracts
- Legacy: header + account_keys + recent_blockhash + instructions
- V0: legacy body + address table lookups

## Transaction Contracts
- signatures encoded as `shortvec(len) + 64*len`
- message bytes are signed payload

## RPC Contracts
- JSON-RPC 2.0 envelope
- 非 200 状态码视为 transport failure
- `error` 字段优先返回 rpc_error

## State Machine
`Draft -> CompiledMessage -> SignedTx -> SerializedTx -> Submitted`

## Defaults
- RPC commitment: `confirmed`
- send/simulate encoding: `base64`
