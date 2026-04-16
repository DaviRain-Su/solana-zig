#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SOLANA_RPC_URL:-}" ]]; then
  echo "error: SOLANA_RPC_URL is required" >&2
  exit 1
fi

OUT_DIR="${1:-artifacts/devnet}"
mkdir -p "$OUT_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
COMMIT_SHA="$(git rev-parse --short HEAD)"
LOG_PATH="$OUT_DIR/phase1-devnet-${TIMESTAMP}-${COMMIT_SHA}.log"

{
  echo "[phase1-devnet-acceptance] start"
  echo "timestamp=$TIMESTAMP"
  echo "commit=$COMMIT_SHA"
  echo "rpc_url=${SOLANA_RPC_URL}"
  echo "command=zig build test"
  echo
  zig build test
  echo
  echo "[phase1-devnet-acceptance] pass"
} 2>&1 | tee "$LOG_PATH"

echo "log saved to: $LOG_PATH"
