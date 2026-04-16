# Devnet E2E Run Log

**Template Date**: 2026-04-16
**Purpose**: 记录 Product Phase 1 的 Devnet 验收实际执行结果，区分“包装式验收”与“真实 E2E harness”。

> 本文是 `docs/14-devnet-e2e-acceptance.md` 的结果模板。
>
> 重要：只有 `Run Type = real-harness` 且留下 `construct -> sign -> simulate -> send` 证据时，才可用作“真实 Devnet E2E 已完成”的依据。

## 1. Run Metadata

- Run ID: `<yyyy-mm-dd>/<short-sha>/<wrapper|real-harness>`
- Commit: `<sha>`
- Date: `<yyyy-mm-dd hh:mm:ss tz>`
- Run Type: `<wrapper | real-harness>`
- Operator: `<name or machine>`
- RPC Endpoint: `<masked endpoint>`
- Command / Entry: `<script / test / harness>`
- Log Path: `<artifacts/devnet/...>`

## 2. Result Summary

- Overall Result: `<pass | fail | env-flaky>`
- Failure Stage: `<none | setup | offline-test | construct | sign | simulate | send | parse | env>`
- Notes: `<brief summary>`

## 3. Evidence Checklist

### 3.1 Wrapper Run
- [ ] `SOLANA_RPC_URL` present
- [ ] wrapper command executed
- [ ] log saved
- [ ] commit + time recorded

### 3.2 Real Harness Run
- [ ] transaction constructed
- [ ] transaction signed
- [ ] simulation executed
- [ ] send executed
- [ ] result / signature / error captured

## 4. Detailed Notes

### Environment
- `<fill>`

### Construct
- `<fill or N/A>`

### Sign
- `<fill or N/A>`

### Simulate
- `<fill or N/A>`

### Send
- `<fill or N/A>`

### Parse / Post-check
- `<fill or N/A>`

## 5. Follow-up Actions

- Related implementation log update: `docs/06-implementation-log.md` `<section>`
- Related review update needed: `<yes/no + docs/07 section>`
- Related execution matrix rows to update: `docs/15-phase1-execution-matrix.md` `<rows>`
