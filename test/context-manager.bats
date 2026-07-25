#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
  export XDG_CONFIG_HOME="$HOME/.config"
  # The step reports on the service; keep it deterministic and offline.
  stub_command systemctl 1
}
teardown() { teardown_common; }

cm_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
    source '$DOTFILES_ROOT/install/80-context-manager.sh'
    $1
  "
}

config_dest() { printf '%s/context-manager/config.toml' "$XDG_CONFIG_HOME"; }

@test "the tracked config is valid TOML and sets the documented keys" {
  local src="$DOTFILES_ROOT/config/context-manager/config.toml"
  [ -f "$src" ]
  grep -qE '^threshold = 0\.[0-9]+' "$src"
  grep -qE '^dry_run = (true|false)' "$src"
  grep -q '^ignore_cwds = \[' "$src"
  grep -q '^\[model_windows\]' "$src"
}

@test "the tracked config excludes the slow Windows mount" {
  grep -q '"/mnt/c/Users/Albert Luo"' "$DOTFILES_ROOT/config/context-manager/config.toml"
}

@test "step seeds the config when none exists" {
  run cm_step "step_context_manager"
  [ -f "$(config_dest)" ]
  cmp -s "$DOTFILES_ROOT/config/context-manager/config.toml" "$(config_dest)"
}

@test "step leaves a hand-tuned config untouched and warns about drift" {
  mkdir -p "$XDG_CONFIG_HOME/context-manager"
  printf 'threshold = 0.99\n' > "$(config_dest)"
  run cm_step "step_context_manager"
  # Local tuning must survive — this file is per-host.
  [ "$(cat "$(config_dest)")" = "threshold = 0.99" ]
  [[ "$output" == *"differs from the tracked copy"* ]]
}

@test "step is quiet when the live config already matches" {
  run cm_step "step_context_manager"
  run cm_step "step_context_manager"
  [ "$status" -eq 0 ]
  [[ "$output" == *"matches the tracked copy"* ]]
}

@test "step is idempotent" {
  run cm_step "step_context_manager"
  [ "$status" -eq 0 ]
  run cm_step "step_context_manager"
  [ "$status" -eq 0 ]
}

@test "step reports missing binaries as a followup, not a failure" {
  run cm_step "step_context_manager"
  [ "$status" -eq 0 ]
  [[ "$output" == *"binaries not installed"* ]]
}

@test "step under DRY_RUN writes nothing" {
  run cm_step "DRY_RUN=1 step_context_manager"
  [ "$status" -eq 0 ]
  [ ! -f "$(config_dest)" ]
}

@test "install.sh registers the step in order after 70-skills" {
  run bash -c "grep -n '70-skills:step_skills\|80-context-manager:step_context_manager' '$DOTFILES_ROOT/install.sh'"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"70-skills"* ]]
  [[ "${lines[1]}" == *"80-context-manager"* ]]
}

@test "install.sh --only accepts the new step id" {
  run bash "$DOTFILES_ROOT/install.sh" --dry-run --only 80-context-manager
  [ "$status" -eq 0 ]
  [[ "$output" != *"unknown step id"* ]]
}

@test "the cm-hook wiring the daemon depends on is present in settings.json" {
  run jq -e '
    (.hooks.SessionStart[]?.hooks[]? | select(.command | test("cm-hook"))) and
    (.hooks.SessionEnd[]?.hooks[]?   | select(.command | test("cm-hook")))
  ' "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -eq 0 ]
}
