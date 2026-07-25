#!/usr/bin/env bash
# Establish OS, required tooling, Homebrew, and the backup directory.

step_preflight() {
  local missing=0 cmd

  for cmd in curl git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_fail "required command not found: $cmd"
      missing=1
    fi
  done
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

  ensure_homebrew || return 1
}
