# Shared bats setup. Sandboxes $HOME and allows stubbing external commands.

setup_common() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  export STUB_BIN="$TEST_TMP/stubbin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"
  # Unset so tests do not depend on the developer's XDG configuration.
  unset XDG_CONFIG_HOME
  export STUB_LOG="$TEST_TMP/stub.log"
  : > "$STUB_LOG"
  DOTFILES_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DOTFILES_ROOT
}

teardown_common() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
}

# stub_command <name> [exit_code] [stdout]
# Creates a fake executable that logs its invocation to $STUB_LOG.
stub_command() {
  local name=$1 code=${2:-0} out=${3:-}
  cat > "$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
echo "$name \$*" >> "$STUB_LOG"
if [ -n '$out' ]; then printf '%s\n' '$out'; fi
exit $code
EOF
  chmod +x "$STUB_BIN/$name"
}

# stub_called <substring> — true if any stub invocation line contains it
stub_called() {
  grep -qF -- "$1" "$STUB_LOG"
}
