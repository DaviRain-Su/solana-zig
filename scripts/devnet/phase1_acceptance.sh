#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SOLANA_RPC_URL:-}" ]]; then
  echo "error: SOLANA_RPC_URL is required" >&2
  exit 1
fi

redact_rpc_url() {
  python3 - "$1" <<'PY'
from urllib.parse import urlsplit, urlunsplit
import sys

raw = sys.argv[1]
parts = urlsplit(raw)
host = parts.hostname or ""

if parts.port is not None:
    host = f"{host}:{parts.port}"

if parts.username or parts.password:
    netloc = f"***:***@{host}"
else:
    netloc = host

path = parts.path or ""
print(urlunsplit((parts.scheme, netloc, path, "", "")))
PY
}

OUT_DIR="${1:-artifacts/devnet}"
mkdir -p "$OUT_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
COMMIT_SHA="$(git rev-parse --short HEAD)"
LOG_PATH="$OUT_DIR/phase1-devnet-${TIMESTAMP}-${COMMIT_SHA}.log"
REDACTED_RPC_URL="$(redact_rpc_url "${SOLANA_RPC_URL}")"

{
  echo "[phase1-devnet-acceptance] start"
  echo "mode=wrapper-only"
  echo "timestamp=$TIMESTAMP"
  echo "commit=$COMMIT_SHA"
  echo "rpc_url=${REDACTED_RPC_URL}"
  echo "command=zig build test"
  echo "note=this wrapper does not execute a true in-tree devnet construct/sign/simulate/send flow"
  echo
  zig build test
  echo
  echo "[phase1-devnet-acceptance] pass"
} 2>&1 | tee "$LOG_PATH"

echo "log saved to: $LOG_PATH"
