#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

@test "verify.sh exits non-zero on a machine with nothing installed" {
  run bash "$DOTFILES_ROOT/verify.sh"
  [ "$status" -ne 0 ]
}

@test "verify.sh reports every check rather than stopping at the first failure" {
  run bash "$DOTFILES_ROOT/verify.sh"
  [ "$(printf '%s\n' "$output" | grep -c -E '✓|✗')" -gt 3 ]
}

@test "verify.sh names the specific thing that failed" {
  run bash "$DOTFILES_ROOT/verify.sh"
  [[ "$output" == *"zsh"* ]]
}

@test "check helper passes for a true command and fails for a false one" {
  run bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/verify.sh' --source-only
    check 'true thing' true
    check 'false thing' false
    printf 'failures=%s\n' \"\$FAILURES\"
  "
  [[ "$output" == *"failures=1"* ]]
}

@test "verify.sh counts the summary line as a failure report" {
  run bash "$DOTFILES_ROOT/verify.sh"
  [[ "$output" == *"check(s) failed"* ]]
}
