#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
  export SRC="$TEST_TMP/src"
  mkdir -p "$SRC"
  printf 'payload\n' > "$SRC/file"
}
teardown() { teardown_common; }

link_sh() {
  bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/link.sh'; $1"
}

@test "backup_and_link creates a symlink when destination is absent" {
  run link_sh "backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.file" ]
  [ "$(readlink -f "$HOME/.file")" = "$(readlink -f "$SRC/file")" ]
}

@test "backup_and_link creates missing parent directories" {
  run link_sh "backup_and_link '$SRC/file' '$HOME/.config/deep/nest/file'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/deep/nest/file" ]
}

@test "backup_and_link moves an existing regular file to the backup dir" {
  printf 'original\n' > "$HOME/.file"
  run link_sh "backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.file" ]
  [ "$(cat "$BACKUP_DIR/.file")" = "original" ]
}

@test "backup_and_link moves an existing directory to the backup dir" {
  mkdir -p "$HOME/.dir"
  printf 'inner\n' > "$HOME/.dir/inner"
  run link_sh "backup_and_link '$SRC' '$HOME/.dir'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.dir" ]
  [ "$(cat "$BACKUP_DIR/.dir/inner")" = "inner" ]
}

@test "backup_and_link is a no-op when the correct symlink already exists" {
  ln -s "$SRC/file" "$HOME/.file"
  run link_sh "backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.file" ]
  [ -z "$(ls -A "$BACKUP_DIR")" ]
}

@test "backup_and_link replaces a symlink pointing somewhere else" {
  printf 'other\n' > "$TEST_TMP/other"
  ln -s "$TEST_TMP/other" "$HOME/.file"
  run link_sh "backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ "$(readlink -f "$HOME/.file")" = "$(readlink -f "$SRC/file")" ]
}

@test "backup_and_link fails when the source does not exist" {
  run link_sh "backup_and_link '$TEST_TMP/absent' '$HOME/.file'"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.file" ]
}

@test "backup_and_link under DRY_RUN touches nothing" {
  run link_sh "DRY_RUN=1 backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.file" ]
}

@test "backup_and_link under DRY_RUN does not claim to have moved anything" {
  printf 'original\n' > "$HOME/.file"
  run link_sh "DRY_RUN=1 backup_and_link '$SRC/file' '$HOME/.file' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would move"* ]]
  # the original must still be in place, and nothing in the backup dir
  [ "$(cat "$HOME/.file")" = "original" ]
  [ -z "$(ls -A "$BACKUP_DIR")" ]
}

@test "backup_and_copy copies rather than links" {
  run link_sh "backup_and_copy '$SRC/file' '$HOME/.copied'"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.copied" ]
  [ ! -L "$HOME/.copied" ]
  [ "$(cat "$HOME/.copied")" = "payload" ]
}

@test "backup_and_copy overwrites an existing copy after backing it up" {
  printf 'stale\n' > "$HOME/.copied"
  run link_sh "backup_and_copy '$SRC/file' '$HOME/.copied'"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.copied")" = "payload" ]
  [ "$(cat "$BACKUP_DIR/.copied")" = "stale" ]
}
