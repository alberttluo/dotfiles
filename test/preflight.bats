#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
}
teardown() { teardown_common; }

preflight() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    $1
  "
}

@test "step_preflight fails when no downloader is available" {
  run bash -c "
    PATH='$(sandbox_path)'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    step_preflight
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl"* ]]
}

@test "wget alone satisfies the downloader requirement" {
  stub_command uname 0 "Linux"
  stub_command wget 0
  stub_command git 0
  run bash -c "
    PATH='$(sandbox_path)'
    export BACKUP_DIR='$BACKUP_DIR' BREW_CANDIDATE_ROOT='$TEST_TMP/noroot'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    step_preflight 2>&1
  "
  [ "$status" -ne 1 ]
  [[ "$output" != *"required command not found"* ]]
}

@test "a machine with no usable Homebrew warns instead of aborting the install" {
  stub_command uname 0 "Linux"
  stub_command curl 0
  stub_command git 0
  run bash -c "
    PATH='$(sandbox_path)'
    export BACKUP_DIR='$BACKUP_DIR' BREW_CANDIDATE_ROOT='$TEST_TMP/noroot'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    step_preflight 2>&1
  "
  # 2 = warn-and-continue. Returning 1 here aborts every later step, including
  # zsh, tmux, Neovim and Claude config, none of which need privileges.
  [ "$status" -eq 2 ]
}

@test "--portable does not even attempt the Homebrew bootstrap" {
  stub_command uname 0 "Linux"
  stub_command curl 0
  stub_command git 0
  run bash -c "
    PATH='$(sandbox_path)'
    export BACKUP_DIR='$BACKUP_DIR' BREW_CANDIDATE_ROOT='$TEST_TMP/noroot' PORTABLE_ONLY=1
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    step_preflight >/dev/null 2>&1
  "
  [ "$status" -eq 0 ]
  ! stub_called "Homebrew/install"
}

@test "a data root is created and recorded for later shells" {
  stub_command uname 0 "Linux"
  stub_command curl 0
  stub_command git 0
  local root="$TEST_TMP/ece/albertlu/dotfiles-data"
  run bash -c "
    PATH='$(sandbox_path)'
    export BACKUP_DIR='$BACKUP_DIR' BREW_CANDIDATE_ROOT='$TEST_TMP/noroot'
    export DOTFILES_DATA_ROOT='$root' HOME='$HOME'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/lib/data-root.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    step_preflight 2>&1
  "
  [ "$status" -ne 1 ]
  [ -d "$root" ]
  # Without this file the next login shell looks in $HOME again and finds nothing.
  [ -f "$HOME/.dotfiles-env" ]
  grep -q "$root" "$HOME/.dotfiles-env"
}

@test "an unusable data root aborts before anything is installed into it" {
  stub_command uname 0 "Linux"
  stub_command curl 0
  stub_command git 0
  run bash -c "
    PATH='$(sandbox_path)'
    export BACKUP_DIR='$BACKUP_DIR' BREW_CANDIDATE_ROOT='$TEST_TMP/noroot'
    export DOTFILES_DATA_ROOT='/proc/nope/data' HOME='$HOME'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/lib/data-root.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    step_preflight 2>&1
  "
  [ "$status" -eq 1 ]
}

@test "step_preflight fails on an unsupported OS" {
  stub_command uname 0 "FreeBSD"
  run preflight "step_preflight"
  [ "$status" -eq 1 ]
}

@test "step_preflight creates the backup directory" {
  stub_command uname 0 "Linux"
  stub_command brew 0
  run preflight "BREW_CANDIDATE_ROOT='' step_preflight"
  [ -d "$BACKUP_DIR" ]
}

@test "step_preflight exports OS and ARCH" {
  stub_command uname 0 "Linux"
  run preflight "step_preflight >/dev/null 2>&1; echo \"os=\$OS arch=\$ARCH\""
  [[ "$output" == *"os=linux"* ]]
}
