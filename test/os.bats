#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

@test "detect_os returns macos on Darwin" {
  stub_command uname 0 "Darwin"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; detect_os"
  [ "$status" -eq 0 ]
  [ "$output" = "macos" ]
}

@test "detect_os returns linux on Linux" {
  stub_command uname 0 "Linux"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; detect_os"
  [ "$status" -eq 0 ]
  [ "$output" = "linux" ]
}

@test "detect_os fails on an unsupported kernel" {
  stub_command uname 0 "FreeBSD"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; detect_os"
  [ "$status" -eq 1 ]
}

@test "brew_prefix prefers Apple Silicon path when present" {
  mkdir -p "$TEST_TMP/opt/homebrew/bin"
  printf '#!/bin/sh\n' > "$TEST_TMP/opt/homebrew/bin/brew"
  chmod +x "$TEST_TMP/opt/homebrew/bin/brew"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; BREW_CANDIDATE_ROOT='$TEST_TMP' brew_prefix"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/opt/homebrew" ]
}

@test "brew_prefix falls back to linuxbrew path" {
  mkdir -p "$TEST_TMP/home/linuxbrew/.linuxbrew/bin"
  printf '#!/bin/sh\n' > "$TEST_TMP/home/linuxbrew/.linuxbrew/bin/brew"
  chmod +x "$TEST_TMP/home/linuxbrew/.linuxbrew/bin/brew"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; BREW_CANDIDATE_ROOT='$TEST_TMP' brew_prefix"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/home/linuxbrew/.linuxbrew" ]
}

@test "brew_prefix fails when no brew exists" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; BREW_CANDIDATE_ROOT='$TEST_TMP/empty' brew_prefix"
  [ "$status" -eq 1 ]
}

@test "ensure_homebrew is a no-op when brew already resolves" {
  mkdir -p "$TEST_TMP/opt/homebrew/bin"
  printf '#!/bin/sh\n' > "$TEST_TMP/opt/homebrew/bin/brew"
  chmod +x "$TEST_TMP/opt/homebrew/bin/brew"
  stub_command curl 0
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; BREW_CANDIDATE_ROOT='$TEST_TMP' ensure_homebrew"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
}
