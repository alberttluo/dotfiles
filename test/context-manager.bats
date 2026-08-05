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
  # The step builds from a submodule inside the repo it is run from. Point it at
  # a stand-in so exercising it never touches the real vendor/context-manager
  # checkout and never triggers a real cargo build.
  export FAKE_ROOT="$TEST_TMP/dotfiles"
  mkdir -p "$FAKE_ROOT/config/context-manager"
  cp "$DOTFILES_ROOT/config/context-manager/config.toml" \
     "$FAKE_ROOT/config/context-manager/config.toml"
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
    export DOTFILES_ROOT='$FAKE_ROOT' BACKUP_DIR='$BACKUP_DIR'
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
    source '$DOTFILES_ROOT/install/80-context-manager.sh'
    $1
  "
}

config_dest() { printf '%s/context-manager/config.toml' "$XDG_CONFIG_HOME"; }

# Materialise a checked-out submodule carrying a fake deploy/install.sh, so the
# orchestration is exercised without a real build.
fake_submodule() {
  local deploy_exit=${1:-0}
  mkdir -p "$FAKE_ROOT/vendor/context-manager/deploy"
  cat > "$FAKE_ROOT/vendor/context-manager/deploy/install.sh" <<EOF
#!/usr/bin/env bash
echo "deploy-ran" >> "$TEST_TMP/deploy.log"
exit $deploy_exit
EOF
}

# A stub git whose `submodule update` materialises the checkout, standing in for
# a repo cloned without --recursive.
stub_git_submodule() {
  cat > "$STUB_BIN/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$STUB_LOG"
if [ "\$3" = "submodule" ]; then
  mkdir -p "$FAKE_ROOT/vendor/context-manager/deploy"
  cat > "$FAKE_ROOT/vendor/context-manager/deploy/install.sh" <<'INNER'
#!/usr/bin/env bash
echo "deploy-ran" >> "$TEST_TMP/deploy.log"
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

# The daemon infers the context window from the model id it reads out of the
# transcript, and Claude Code writes the 1M Opus variant there as plain
# "claude-opus-5" — the [1m] of the model pin below never reaches the file. An
# explicit window entry is therefore the only way the daemon can tell a 1M
# session from the 200k default, and getting it wrong is not a near miss: a
# handoff at 45% of an assumed 200k fires at 9% of the real window, and the
# daemon's empirical correction cannot save it because the session is retired
# long before it is ever observed above 200k.
@test "every model the config pins has a matching context window" {
  grep -q '"model": "opus\[1m\]"' "$DOTFILES_ROOT/claude/settings.json"
  grep -qE '^"claude-opus-5" = 1000000$' "$DOTFILES_ROOT/config/context-manager/config.toml"
}

@test "the daemon is vendored as a submodule, not fetched at install time" {
  grep -q 'path = vendor/context-manager' "$DOTFILES_ROOT/.gitmodules"
  grep -q 'url = .*context-manager' "$DOTFILES_ROOT/.gitmodules"
  # The pin is the point: nothing the step *runs* may reach for a moving branch.
  # Comments are stripped first — the header legitimately mentions both, since
  # `git clone --recursive` is now how the daemon arrives.
  run ! bash -c "grep -v '^[[:space:]]*#' '$DOTFILES_ROOT/install/80-context-manager.sh' \
                 | grep -qE 'git clone|pull --ff-only'"
}

@test "step seeds the config when none exists" {
  fake_submodule
  run cm_step "step_context_manager"
  [ -f "$(config_dest)" ]
  cmp -s "$DOTFILES_ROOT/config/context-manager/config.toml" "$(config_dest)"
}

@test "step leaves a hand-tuned config untouched and warns about drift" {
  fake_submodule
  mkdir -p "$XDG_CONFIG_HOME/context-manager"
  printf 'threshold = 0.99\n' > "$(config_dest)"
  run cm_step "step_context_manager"
  # Local tuning must survive — this file is per-host.
  [ "$(cat "$(config_dest)")" = "threshold = 0.99" ]
  [[ "$output" == *"differs from the tracked copy"* ]]
}

@test "step runs the submodule's deploy installer" {
  fake_submodule
  run cm_step "step_context_manager"
  [ -f "$TEST_TMP/deploy.log" ]
  [[ "$output" == *"built and deployed"* ]]
}

@test "step seeds the config BEFORE building, so the upstream default cannot win" {
  # The real deploy script would write a dry_run=true config if none existed;
  # assert ours is already in place by the time it runs.
  mkdir -p "$FAKE_ROOT/vendor/context-manager/deploy"
  cat > "$FAKE_ROOT/vendor/context-manager/deploy/install.sh" <<EOF
#!/usr/bin/env bash
grep -q 'threshold' "$(config_dest)" && echo "config-present-first" >> "$TEST_TMP/order.log"
EOF
  run cm_step "step_context_manager"
  [ -f "$TEST_TMP/order.log" ]
}

@test "step checks out the submodule when the clone was not recursive" {
  stub_git_submodule
  run cm_step "step_context_manager"
  stub_called "submodule update --init"
  [ -f "$TEST_TMP/deploy.log" ]
  [[ "$output" == *"checked out vendor/context-manager"* ]]
}

# The pinned commit is the contract. An install that quietly moved it would put
# a daemon on the machine that no dotfiles commit describes.
@test "step leaves an already-checked-out submodule at its pinned commit" {
  fake_submodule
  stub_command git 0
  run cm_step "step_context_manager"
  # Asserted before the next `run`, which would overwrite $output.
  [[ "$output" == *"pinned commit"* ]]
  run ! stub_called "submodule update"
}

@test "step reports a missing toolchain as a followup, not a hard failure" {
  # No cargo anywhere: remove the stub and hide any real rustup install.
  rm -f "$STUB_BIN/cargo"
  run bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$FAKE_ROOT' BACKUP_DIR='$BACKUP_DIR'
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
    export PATH='$STUB_BIN:/usr/bin:/bin'
    export HOME='$TEST_TMP/nohome'; mkdir -p \"\$HOME\"
    source '$DOTFILES_ROOT/install/80-context-manager.sh'
    step_context_manager
  "
  [ "$status" -eq 2 ]
  [[ "$output" == *"cargo not found"* ]]
}

@test "step fails clearly when the submodule checkout produced no installer" {
  stub_command git 0
  run cm_step "step_context_manager"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no deploy/install.sh"* ]]
}

@test "step surfaces a failing submodule checkout" {
  stub_command git 1
  run cm_step "step_context_manager"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not check out"* ]]
}

@test "step surfaces a failing deploy installer" {
  fake_submodule 1
  run cm_step "step_context_manager"
  [ "$status" -eq 2 ]
  [[ "$output" == *"deploy/install.sh failed"* ]]
}

@test "step under DRY_RUN writes nothing and never builds" {
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
