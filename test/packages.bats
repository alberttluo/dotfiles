#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export PORTABLE_PREFIX="$TEST_TMP/prefix"
  export OS=linux ARCH=x86_64
  # Without this, brew_prefix resolves the developer's real Homebrew and any test
  # that omits a brew stub runs a genuine `brew bundle` against the repo Brewfile.
  export BREW_CANDIDATE_ROOT="$TEST_TMP/noroot"
  # Several tests narrow PATH to include /usr/bin, where a REAL curl lives. Without
  # these stubs those tests perform genuine multi-megabyte downloads, which is how
  # this suite first hung. No test may ever reach the network.
  stub_command curl 22
  stub_command wget 1
}
teardown() { teardown_common; }

packages() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/lib/portable.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' PORTABLE_PREFIX='$PORTABLE_PREFIX' OS=linux ARCH=x86_64
    source '$DOTFILES_ROOT/install/10-packages.sh'
    $1
  "
}

# Pretend every runtime tool is already installed, so gap-filling is a no-op.
stub_all_tools_present() {
  local t
  for t in zsh tmux git nvim node jq cargo; do stub_command "$t" 0; done
}

@test "step_packages invokes brew bundle with the repo Brewfile" {
  stub_command brew 0
  stub_all_tools_present
  run packages "step_packages"
  [ "$status" -eq 0 ]
  stub_called "bundle"
  stub_called "$DOTFILES_ROOT/Brewfile"
}

@test "a failing brew bundle warns and continues instead of aborting the install" {
  stub_command brew 1
  stub_all_tools_present
  run packages "step_packages"
  # 2 = warn-and-continue. A hard failure here would abort every later step,
  # including the ones that need no privileges at all.
  [ "$status" -eq 2 ]
}

@test "missing brew is not fatal — the portable path takes over" {
  stub_all_tools_present
  run packages "PATH='$(sandbox_path)' step_packages"
  [ "$status" -ne 1 ]
}

@test "step_packages under DRY_RUN does not call brew" {
  stub_command brew 0
  stub_all_tools_present
  run packages "DRY_RUN=1 step_packages"
  [ "$status" -eq 0 ]
  ! stub_called "bundle"
}

@test "--portable skips brew entirely even when it is available" {
  stub_command brew 0
  stub_all_tools_present
  run packages "PORTABLE_ONLY=1 step_packages"
  ! stub_called "bundle"
}

@test "a tool missing after brew is fetched as a prebuilt binary" {
  stub_command brew 0
  # everything present except jq
  for t in zsh tmux git nvim node cargo; do stub_command "$t" 0; done
  cat > "$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$STUB_LOG"
dest=""; while [ \$# -gt 0 ]; do [ "\$1" = "-o" ] && dest="\$2"; shift; done
printf '#!/bin/sh\nexit 0\n' > "\$dest"
EOF
  chmod +x "$STUB_BIN/curl"
  run packages "PATH='$(sandbox_path)' step_packages"
  stub_called "jqlang/jq"
  [ -x "$PORTABLE_PREFIX/bin/jq" ]
}

@test "a tool with no prebuilt download is reported, not silently skipped" {
  stub_command brew 0
  # git is deliberately not fetchable; hide it so the gap is real
  for t in zsh tmux nvim node jq cargo; do stub_command "$t" 0; done
  run packages "PATH='$(sandbox_path)' step_packages 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git"* ]]
}

@test "the portable bin dir is put on PATH for later steps" {
  stub_command brew 0
  stub_all_tools_present
  run packages "step_packages >/dev/null 2>&1; printf '%s' \"\$PATH\""
  [[ "$output" == *"$PORTABLE_PREFIX/bin"* ]]
}

@test "Brewfile lists every runtime dependency" {
  for pkg in zsh tmux git neovim node jq; do
    grep -q "brew \"$pkg\"" "$DOTFILES_ROOT/Brewfile"
  done
}

@test "Brewfile does not list dev-only tools" {
  ! grep -q "bats-core" "$DOTFILES_ROOT/Brewfile"
  ! grep -q "shellcheck" "$DOTFILES_ROOT/Brewfile"
}
