#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

@test "log_step writes a step marker to stderr" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; log_step 'doing a thing' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"doing a thing"* ]]
  [[ "$output" == *"▶"* ]]
}

@test "log_warn records the message in WARNINGS" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; log_warn 'careful'; printf '%s\n' \"\${WARNINGS[@]}\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"careful"* ]]
}

@test "run executes the command when DRY_RUN is unset" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; run touch '$TEST_TMP/made'; [ -f '$TEST_TMP/made' ]"
  [ "$status" -eq 0 ]
}

@test "run does not execute the command when DRY_RUN=1" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; DRY_RUN=1 run touch '$TEST_TMP/nope'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TMP/nope" ]
}

@test "run under DRY_RUN reports what it would have done" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; DRY_RUN=1 run touch /some/path 2>&1"
  [[ "$output" == *"touch /some/path"* ]]
}
