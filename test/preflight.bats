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

@test "step_preflight fails when curl is unavailable" {
  # A PATH containing only the stub dir hides curl and git.
  run bash -c "
    PATH='$STUB_BIN'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    step_preflight
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl"* ]]
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
