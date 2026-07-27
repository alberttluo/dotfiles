#!/usr/bin/env bats
#
# Relocating everything bulky off $HOME onto a second volume.

load helper

setup() {
  setup_common
  export ROOT="$TEST_TMP/ece/albertlu/dotfiles-data"
}
teardown() { teardown_common; }

dataroot() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/data-root.sh'
    $1
  "
}

@test "every relocation points inside the root" {
  run dataroot "data_root_exports '$ROOT'"
  [ "$status" -eq 0 ]
  # PORTABLE_PREFIX is the root itself — portable_install owns its bin/ — so the
  # match is on the root, not on a subdirectory of it.
  local var
  for var in XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME PORTABLE_PREFIX \
             CARGO_HOME RUSTUP_HOME ZSH NVM_DIR npm_config_cache \
             CLAUDE_CONFIG_DIR CM_SRC_DIR; do
    [[ "$output" == *"$var=\"$ROOT"* ]] || {
      echo "$var is not under the root:"; echo "$output"; return 1
    }
  done
}

# Config is what makes the shell able to find the root in the first place, so it
# has to stay where the shell already looks.
@test "XDG_CONFIG_HOME is left alone so config stays in HOME" {
  run dataroot "data_root_exports '$ROOT'"
  [[ "$output" != *"XDG_CONFIG_HOME"* ]]
}

@test "a trailing slash on the root does not produce doubled separators" {
  run dataroot "data_root_exports '$ROOT/'"
  [[ "$output" != *"//"* ]]
}

@test "the emitted file is POSIX sh, because .zshenv sources it" {
  dataroot "data_root_exports '$ROOT'" > "$TEST_TMP/env"
  run sh -n "$TEST_TMP/env"
  [ "$status" -eq 0 ]
}

@test "PATH keeps what was already on it" {
  run dataroot "PATH=/sentinel/bin; eval \"\$(data_root_exports '$ROOT')\"; printf '%s' \"\$PATH\""
  [[ "$output" == *"$ROOT/bin"* ]]
  [[ "$output" == *"$ROOT/cargo/bin"* ]]
  [[ "$output" == *"/sentinel/bin"* ]]
}

@test "apply_data_root exports into the running installer" {
  run dataroot "apply_data_root '$ROOT'; printf '%s|%s' \"\$PORTABLE_PREFIX\" \"\$CARGO_HOME\""
  [ "$output" = "$ROOT|$ROOT/cargo" ]
}

@test "ensure_data_root creates the root when it is absent" {
  run dataroot "ensure_data_root '$ROOT'"
  [ "$status" -eq 0 ]
  [ -d "$ROOT" ]
}

@test "ensure_data_root fails clearly when the root cannot be created" {
  run dataroot "ensure_data_root '/proc/nope/dotfiles-data' 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/proc/nope/dotfiles-data"* ]]
}

@test "ensure_data_root fails when the root exists but is not writable" {
  mkdir -p "$ROOT"
  chmod a-w "$ROOT"
  run dataroot "ensure_data_root '$ROOT' 2>&1"
  chmod u+w "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"writable"* ]]
}

@test "ensure_data_root under DRY_RUN creates nothing" {
  run dataroot "DRY_RUN=1 ensure_data_root '$ROOT'"
  [ "$status" -eq 0 ]
  [ ! -d "$ROOT" ]
}

@test "write_data_root_env writes a file the shell can source" {
  run dataroot "write_data_root_env '$ROOT' '$TEST_TMP/dotfiles-env'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/dotfiles-env" ]
  run bash -c "PATH=/sentinel/bin; . '$TEST_TMP/dotfiles-env'; printf '%s' \"\$ZSH\""
  [ "$output" = "$ROOT/oh-my-zsh" ]
}

@test "write_data_root_env is idempotent rather than appending" {
  dataroot "write_data_root_env '$ROOT' '$TEST_TMP/dotfiles-env'"
  dataroot "write_data_root_env '$ROOT' '$TEST_TMP/dotfiles-env'"
  run grep -c "DOTFILES_DATA_ROOT=" "$TEST_TMP/dotfiles-env"
  [ "$output" = "1" ]
}

@test "write_data_root_env under DRY_RUN writes nothing" {
  run dataroot "DRY_RUN=1 write_data_root_env '$ROOT' '$TEST_TMP/dotfiles-env'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TMP/dotfiles-env" ]
}
