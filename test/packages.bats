#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

packages() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT'
    source '$DOTFILES_ROOT/install/10-packages.sh'
    $1
  "
}

@test "step_packages invokes brew bundle with the repo Brewfile" {
  stub_command brew 0
  run packages "step_packages"
  [ "$status" -eq 0 ]
  stub_called "bundle"
  stub_called "$DOTFILES_ROOT/Brewfile"
}

@test "step_packages fails when brew bundle fails" {
  stub_command brew 1
  run packages "step_packages"
  [ "$status" -eq 1 ]
}

@test "step_packages under DRY_RUN does not call brew" {
  stub_command brew 0
  run packages "DRY_RUN=1 step_packages"
  [ "$status" -eq 0 ]
  ! stub_called "bundle"
}

@test "Brewfile lists every runtime dependency" {
  for pkg in zsh tmux git neovim node; do
    grep -q "brew \"$pkg\"" "$DOTFILES_ROOT/Brewfile"
  done
}

@test "Brewfile does not list dev-only tools" {
  ! grep -q "bats-core" "$DOTFILES_ROOT/Brewfile"
  ! grep -q "shellcheck" "$DOTFILES_ROOT/Brewfile"
  ! grep -q "fzf" "$DOTFILES_ROOT/Brewfile"
}
