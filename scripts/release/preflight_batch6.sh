#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${1:-artifacts/release}"
mkdir -p "$OUT_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
COMMIT_SHA="$(git rev-parse --short HEAD)"
REPORT_PATH="$OUT_DIR/batch6-preflight-${TIMESTAMP}-${COMMIT_SHA}.md"

ALLOW_BATCH6_EXCEPTION="${ALLOW_BATCH6_EXCEPTION:-false}"

run_and_capture() {
  local cmd="$1"
  local log="$2"

  set +e
  bash -lc "$cmd" >"$log" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "PASS"
  else
    echo "FAIL"
  fi
}

TEST_LOG="$OUT_DIR/batch6-test-${TIMESTAMP}-${COMMIT_SHA}.log"
DEVNET_LOG="$OUT_DIR/batch6-smoke-devnet-${TIMESTAMP}-${COMMIT_SHA}.log"
LOCAL_LOG="$OUT_DIR/batch6-smoke-local-${TIMESTAMP}-${COMMIT_SHA}.log"

TEST_STATUS="$(run_and_capture "zig build test --summary all" "$TEST_LOG")"

if [[ -n "${SOLANA_RPC_URL:-}" ]]; then
  DEVNET_STATUS="$(run_and_capture "zig build devnet-e2e --summary all" "$DEVNET_LOG")"
else
  DEVNET_STATUS="MISSING"
  : >"$DEVNET_LOG"
fi

if [[ -n "${SURFPOOL_RPC_URL:-}" ]]; then
  LOCAL_STATUS="$(run_and_capture "zig build e2e --summary all" "$LOCAL_LOG")"
else
  LOCAL_STATUS="MISSING"
  : >"$LOCAL_LOG"
fi

DOCS_STATUS="PASS"
for f in \
  docs/06-implementation-log.md \
  docs/10-coverage-matrix.md \
  docs/14a-devnet-e2e-run-log.md \
  docs/15-phase1-execution-matrix.md \
  docs/27-batch6-release-readiness.md; do
  if [[ ! -f "$f" ]]; then
    DOCS_STATUS="FAIL"
    break
  fi
done

EXCEPTION_REQUIRED="false"
if [[ "$DEVNET_STATUS" != "PASS" || "$LOCAL_STATUS" != "PASS" ]]; then
  EXCEPTION_REQUIRED="true"
fi

VERDICT="不可发布"
if [[ "$TEST_STATUS" == "PASS" && "$DOCS_STATUS" == "PASS" ]]; then
  if [[ "$EXCEPTION_REQUIRED" == "false" ]]; then
    VERDICT="可发布"
  elif [[ "$ALLOW_BATCH6_EXCEPTION" == "true" ]]; then
    VERDICT="有条件发布"
  else
    VERDICT="不可发布"
  fi
fi

cat >"$REPORT_PATH" <<EOF
# Batch 6 Preflight Report

- timestamp: $TIMESTAMP
- commit: $COMMIT_SHA
- allow_batch6_exception: $ALLOW_BATCH6_EXCEPTION

## Results

- build/test: $TEST_STATUS
- smoke(public devnet): $DEVNET_STATUS
- smoke(local-live): $LOCAL_STATUS
- docs consistency files: $DOCS_STATUS
- exception_required: $EXCEPTION_REQUIRED
- verdict: $VERDICT

## Artifacts

- test_log: $TEST_LOG
- devnet_smoke_log: $DEVNET_LOG
- local_smoke_log: $LOCAL_LOG

## Notes

- 若 \`exception_required=true\`，必须在 \`docs/15\` 登记 Batch 6 exception（原因 + 收敛阶段）。
- 仅当无未收敛 exception 时，verdict 才允许为 \`可发布\`。
EOF

echo "report saved to: $REPORT_PATH"
echo "verdict: $VERDICT"
