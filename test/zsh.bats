#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

zsh_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/30-zsh.sh'
    $1
  "
}

@test "shared .zshrc contains no machine-specific paths" {
  ! grep -qE '/mnt/c|Vivado|XILINX|QUESTA|MGLS|SALT_LICENSE|Zscaler|nvim-linux-x86_64' \
    "$DOTFILES_ROOT/home/.zshrc"
}

@test "shared .zshrc does not hardcode a Homebrew prefix" {
  ! grep -q '/home/linuxbrew/.linuxbrew/bin/brew shellenv' "$DOTFILES_ROOT/home/.zshrc"
}

@test "shared .zshrc sources .zshrc.local guarded" {
  grep -q 'zshrc.local' "$DOTFILES_ROOT/home/.zshrc"
  grep -qE '\[ -f "\$HOME/\.zshrc\.local" \]' "$DOTFILES_ROOT/home/.zshrc"
}

@test "shared .zshrc loads nvm exactly once" {
  [ "$(grep -c 'nvm.sh' "$DOTFILES_ROOT/home/.zshrc")" -eq 1 ]
}

@test ".zshenv guards the cargo env" {
  grep -qE '\[ -f "\$\{CARGO_HOME:-\$HOME/\.cargo\}/env" \]' "$DOTFILES_ROOT/home/.zshenv"
}

@test "the example per-host file carries the EDA config" {
  for needle in Vivado QUESTA_HOME XILINXD_LICENSE_FILE NODE_EXTRA_CA_CERTS ssh-agent; do
    grep -q "$needle" "$DOTFILES_ROOT/home/.zshrc.local.example"
  done
}

@test "the example per-host file carries the skip-permissions alias" {
  grep -q 'dangerously-skip-permissions' "$DOTFILES_ROOT/home/.zshrc.local.example"
}

@test "the shared .zshrc does NOT carry the skip-permissions alias" {
  ! grep -q 'dangerously-skip-permissions' "$DOTFILES_ROOT/home/.zshrc"
}

@test ".zshrc parses cleanly under zsh with no EDA tooling present" {
  if ! command -v zsh >/dev/null 2>&1; then skip "zsh not installed"; fi
  run zsh -n "$DOTFILES_ROOT/home/.zshrc"
  [ "$status" -eq 0 ]
}

@test "step_zsh links .zshrc and .zshenv into HOME" {
  mkdir -p "$HOME/.oh-my-zsh"
  stub_command chsh 0
  stub_command sudo 1
  run zsh_step "OS=linux step_zsh"
  [ -L "$HOME/.zshrc" ]
  [ -L "$HOME/.zshenv" ]
}

@test "step_zsh seeds .zshrc.local when absent" {
  mkdir -p "$HOME/.oh-my-zsh"
  stub_command chsh 0
  stub_command sudo 1
  run zsh_step "OS=linux step_zsh"
  [ -f "$HOME/.zshrc.local" ]
  [ ! -L "$HOME/.zshrc.local" ]
}

@test "step_zsh does not clobber an existing .zshrc.local" {
  mkdir -p "$HOME/.oh-my-zsh"
  printf 'MY OWN CONFIG\n' > "$HOME/.zshrc.local"
  stub_command chsh 0
  stub_command sudo 1
  run zsh_step "OS=linux step_zsh"
  [ "$(cat "$HOME/.zshrc.local")" = "MY OWN CONFIG" ]
}

@test "step_zsh warns but does not fail when chsh fails" {
  mkdir -p "$HOME/.oh-my-zsh"
  stub_command chsh 1
  stub_command sudo 1
  # SHELL must differ from the resolved zsh, or the step correctly short-circuits
  # before chsh. Pinned so the test does not depend on the developer's own shell.
  run zsh_step "SHELL=/bin/bash OS=linux step_zsh"
  [ "$status" -eq 2 ]
}

@test "step_zsh is a no-op on the login shell when SHELL already matches" {
  mkdir -p "$HOME/.oh-my-zsh"
  stub_command chsh 1
  stub_command sudo 1
  zsh_path="$(command -v zsh)"
  run zsh_step "SHELL='$zsh_path' OS=linux step_zsh"
  [ "$status" -eq 0 ]
  ! stub_called "chsh"
}

@test 'oh-my-zsh is installed where \$ZSH points, not always under HOME' {
  export ZSH="$TEST_TMP/ece/oh-my-zsh"
  mkdir -p "$ZSH"
  stub_command chsh 0
  stub_command zsh 0
  run zsh_step "ZSH='$ZSH' step_zsh 2>&1"
  # An existing tree at $ZSH counts as installed; the installer must not be run
  # and nothing may be created under HOME instead.
  [[ "$output" == *"already present"* ]]
  [ ! -d "$HOME/.oh-my-zsh" ]
}

@test ".zshrc defers to an already-exported ZSH" {
  grep -qE '\$\{ZSH:=|\$\{ZSH:-' "$DOTFILES_ROOT/home/.zshrc"
}

@test ".zshrc puts the portable prefix on PATH rather than a fixed ~/.local" {
  grep -q 'PORTABLE_PREFIX' "$DOTFILES_ROOT/home/.zshrc"
}

@test ".zshenv sources the generated data-root file before anything needs it" {
  grep -q 'dotfiles-env' "$DOTFILES_ROOT/home/.zshenv"
}

@test ".zshenv finds cargo through CARGO_HOME" {
  grep -q 'CARGO_HOME' "$DOTFILES_ROOT/home/.zshenv"
}
