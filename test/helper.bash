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

# sandbox_path — prints a PATH holding only $STUB_BIN plus the shell utilities the
# install scripts themselves call. /usr/bin carries real git, jq, zsh and tmux, so a
# test that expects one of those to be missing silently passes on the developer's
# machine unless the search path excludes it.
sandbox_path() {
  local util src
  SYS_BIN="$TEST_TMP/sysbin"
  export SYS_BIN
  mkdir -p "$SYS_BIN"
  for util in bash sh env printf mktemp mkdir rmdir rm mv cp ln chmod tar gzip xz cat sed grep uname dirname basename; do
    src="$(command -v "$util" 2>/dev/null)" || continue
    [ -n "$src" ] && ln -sf "$src" "$SYS_BIN/$util"
  done
  printf '%s' "$STUB_BIN:$SYS_BIN"
}

# stub_called <substring> — true if any stub invocation line contains it
stub_called() {
  grep -qF -- "$1" "$STUB_LOG"
}
