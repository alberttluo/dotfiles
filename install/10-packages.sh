#!/usr/bin/env bash
# Install runtime dependencies from the Brewfile.

step_packages() {
  local brew_bin

  # PATH first: after a fresh bootstrap brew is not on PATH yet, so fall back to
  # the probed prefix. Checking PATH first also keeps the step stubbable in tests.
  if command -v brew >/dev/null 2>&1; then
    brew_bin="brew"
  else
    brew_bin="$(brew_prefix)/bin/brew"
    if [ ! -x "$brew_bin" ]; then
      log_fail "brew not found on PATH or at any known prefix"
      return 1
    fi
  fi

  run "$brew_bin" bundle --file="$DOTFILES_ROOT/Brewfile" \
    || { log_fail "brew bundle failed"; return 1; }
  log_ok "runtime packages installed"
}
