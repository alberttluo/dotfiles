#!/usr/bin/env bash
# Establish OS, required tooling, Homebrew, and the backup directory.

step_preflight() {
  local missing=0 cmd

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    log_fail "required command not found: curl (or wget)"
    missing=1
  fi
  if ! command -v git >/dev/null 2>&1; then
    log_fail "required command not found: git"
    missing=1
  fi
  [ "$missing" -eq 0 ] || return 1

  OS="$(detect_os)" || return 1
  ARCH="$(detect_arch)"
  export OS ARCH
  log_ok "detected $OS/$ARCH"

  # Homebrew on RHEL needs a compiler and file(1) for anything without a bottle.
  if [ "$OS" = "linux" ]; then
    for cmd in gcc file; do
      command -v "$cmd" >/dev/null 2>&1 || \
        log_warn "$cmd missing — some brew formulae may fail to build (dnf install $cmd)"
    done
  fi

  run mkdir -p "$BACKUP_DIR"
  log_ok "backups will go to $BACKUP_DIR"

  # Homebrew is an optimisation, not a prerequisite. Its prefix needs root to
  # create, so a locked-down host can never have it — and failing here would skip
  # every later step, including the ones that need no privileges at all.
  # 10-packages fills whatever gap this leaves with prebuilt downloads.
  if [ "${PORTABLE_ONLY:-0}" = "1" ]; then
    log_ok "--portable: skipping Homebrew"
    return 0
  fi
  ensure_homebrew || {
    log_warn "continuing without Homebrew — packages will come from prebuilt downloads"
    return 2
  }
}
