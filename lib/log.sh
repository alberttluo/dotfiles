#!/usr/bin/env bash
# Logging and the dry-run wrapper. Sourced by install.sh, verify.sh, and every step.
# All output goes to stderr so callers can capture stdout for data.

WARNINGS=()
FOLLOWUPS=()

log_step() { printf '\n▶ %s\n' "$*" >&2; }
log_ok()   { printf '  ✓ %s\n' "$*" >&2; }
log_fail() { printf '  ✗ %s\n' "$*" >&2; }
log_dry()  { printf '  · would run: %s\n' "$*" >&2; }

log_warn() {
  printf '  ⚠ %s\n' "$*" >&2
  WARNINGS+=("$*")
}

log_followup() { FOLLOWUPS+=("$*"); }

# run CMD... — execute unless DRY_RUN=1
run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "$*"
    return 0
  fi
  "$@"
}
