#!/usr/bin/env bats

load helper

# `run !` below is only honoured as a negation from bats 1.5.0 on; older
# releases would treat the assertion as vacuously true.
bats_require_minimum_version 1.5.0

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
  export XDG_CONFIG_HOME="$HOME/.config"
  export CM_SRC_DIR="$TEST_TMP/src/context-manager"
  export CM_REPO_URL="file:///dev/null/fake-remote"
  # Pin the kernel. The step is a no-op on macOS, so without this every
  # Linux-path test below silently passes without exercising anything when the
  # suite runs on a Mac. The macOS test overrides this stub with its own.
  stub_command uname 0 "Linux"
  # cargo must look present, or the step returns early before the source stage.
  stub_command cargo 0
  # The step reports on the service; keep it deterministic and offline.
  stub_command systemctl 1
}
teardown() { teardown_common; }

cm_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
    export CM_SRC_DIR='$CM_SRC_DIR' CM_REPO_URL='$CM_REPO_URL'
    source '$DOTFILES_ROOT/install/80-context-manager.sh'
    $1
  "
}

config_dest() { printf '%s/context-manager/config.toml' "$XDG_CONFIG_HOME"; }

# A stub `git` whose `clone` materialises a checkout carrying a fake
# deploy/install.sh, so the orchestration is exercised without a real build.
stub_git_clone() {
  local deploy_exit=${1:-0}
  cat > "$STUB_BIN/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$STUB_LOG"
if [ "\$1" = "clone" ]; then
  dest="\${@: -1}"
  mkdir -p "\$dest/.git" "\$dest/deploy"
  cat > "\$dest/deploy/install.sh" <<'INNER'
#!/usr/bin/env bash
echo "deploy-ran" >> "$TEST_TMP/deploy.log"
exit $deploy_exit
INNER
fi
exit 0
EOF
  chmod +x "$STUB_BIN/git"
}

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
  stub_git_clone
  run cm_step "step_context_manager"
  [ -f "$(config_dest)" ]
  cmp -s "$DOTFILES_ROOT/config/context-manager/config.toml" "$(config_dest)"
}

@test "step leaves a hand-tuned config untouched and warns about drift" {
  stub_git_clone
  mkdir -p "$XDG_CONFIG_HOME/context-manager"
  printf 'threshold = 0.99\n' > "$(config_dest)"
  run cm_step "step_context_manager"
  # Local tuning must survive — this file is per-host.
  [ "$(cat "$(config_dest)")" = "threshold = 0.99" ]
  [[ "$output" == *"differs from the tracked copy"* ]]
}

@test "step clones the repo and runs its deploy installer" {
  stub_git_clone
  run cm_step "step_context_manager"
  stub_called "git clone"
  [ -f "$TEST_TMP/deploy.log" ]
  [[ "$output" == *"built and deployed"* ]]
}

@test "step seeds the config BEFORE building, so the upstream default cannot win" {
  # The fake deploy script would write a dry_run=true config if none existed;
  # assert ours is already in place by the time it runs.
  cat > "$STUB_BIN/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$STUB_LOG"
if [ "\$1" = "clone" ]; then
  dest="\${@: -1}"; mkdir -p "\$dest/.git" "\$dest/deploy"
  cat > "\$dest/deploy/install.sh" <<'INNER'
#!/usr/bin/env bash
grep -q 'threshold' "$(config_dest)" && echo "config-present-first" >> "$TEST_TMP/order.log"
INNER
fi
exit 0
EOF
  chmod +x "$STUB_BIN/git"
  run cm_step "step_context_manager"
  [ -f "$TEST_TMP/order.log" ]
}

@test "step updates an existing checkout with --ff-only instead of cloning" {
  mkdir -p "$CM_SRC_DIR/.git" "$CM_SRC_DIR/deploy"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CM_SRC_DIR/deploy/install.sh"
  stub_command git 0
  run cm_step "step_context_manager"
  stub_called "pull --ff-only"
  run ! stub_called "git clone"
}

@test "step warns but still builds when the checkout cannot fast-forward" {
  mkdir -p "$CM_SRC_DIR/.git" "$CM_SRC_DIR/deploy"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CM_SRC_DIR/deploy/install.sh"
  stub_command git 1
  run cm_step "step_context_manager"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not fast-forward"* ]]
  [[ "$output" == *"built and deployed"* ]]
}

@test "step reports a missing toolchain as a followup, not a hard failure" {
  # No cargo anywhere: remove the stub and hide any real rustup install.
  rm -f "$STUB_BIN/cargo"
  run bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME' CM_SRC_DIR='$CM_SRC_DIR'
    export PATH='$STUB_BIN:/usr/bin:/bin'
    export HOME='$TEST_TMP/nohome'; mkdir -p \"\$HOME\"
    source '$DOTFILES_ROOT/install/80-context-manager.sh'
    step_context_manager
  "
  [ "$status" -eq 2 ]
  [[ "$output" == *"cargo not found"* ]]
}

@test "step fails clearly when the clone has no deploy installer" {
  cat > "$STUB_BIN/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$STUB_LOG"
if [ "\$1" = "clone" ]; then mkdir -p "\${@: -1}/.git"; fi
exit 0
EOF
  chmod +x "$STUB_BIN/git"
  run cm_step "step_context_manager"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no deploy/install.sh"* ]]
}

@test "step surfaces a failing deploy installer" {
  stub_git_clone 1
  run cm_step "step_context_manager"
  [ "$status" -eq 2 ]
  [[ "$output" == *"deploy/install.sh failed"* ]]
}

@test "step under DRY_RUN writes nothing and never builds" {
  stub_git_clone
  run cm_step "DRY_RUN=1 step_context_manager"
  [ "$status" -eq 0 ]
  [ ! -f "$(config_dest)" ]
  [ ! -f "$TEST_TMP/deploy.log" ]
  [[ "$output" == *"would run"* ]]
}

@test "step is a clean no-op on macOS" {
  cat > "$STUB_BIN/uname" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-s" ] && { echo Darwin; exit 0; }
echo x86_64
EOF
  chmod +x "$STUB_BIN/uname"
  run cm_step "step_context_manager"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Linux-only"* ]]
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

@test "the Brewfile provides the build prerequisites" {
  grep -q '^brew "rust"' "$DOTFILES_ROOT/Brewfile"
  grep -q '^brew "jq"' "$DOTFILES_ROOT/Brewfile"
}

@test "the cm-hook wiring the daemon depends on is present in settings.json" {
  run jq -e '
    ([.hooks.SessionStart[]?.hooks[]?.command] | any(test("cm-hook"))) and
    ([.hooks.SessionEnd[]?.hooks[]?.command]   | any(test("cm-hook")))
  ' "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -eq 0 ]
}
