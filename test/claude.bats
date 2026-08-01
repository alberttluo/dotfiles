#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

claude_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/60-claude.sh'
    $1
  "
}

@test "packaged settings.json is valid JSON" {
  run jq -e . "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "packaged settings.json points hooks at the XDG plugin path" {
  grep -q 'config/tmux/plugins/tmux-agent-indicator' "$DOTFILES_ROOT/claude/settings.json"
  ! grep -q '\.tmux/plugins/tmux-agent-indicator' "$DOTFILES_ROOT/claude/settings.json"
}

# A path baked in from the machine the settings were captured on fails on every
# other machine, and does it once per session with no obvious cause.
@test "packaged settings.json hardcodes no home directory" {
  ! grep -qE '"/(home|Users)/' "$DOTFILES_ROOT/claude/settings.json"
}

# context-manager is Linux-only, so on macOS these hooks fire against a binary
# that is never installed. They must no-op instead of erroring every session.
@test "the cm-hook hooks tolerate a missing binary" {
  local cmd
  cmd="$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$DOTFILES_ROOT/claude/settings.json")"
  run env -u PORTABLE_PREFIX HOME="$TEST_TMP/nowhere" sh -c "$cmd"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the cm-hook hooks run the binary when it is installed" {
  local cmd
  cmd="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$DOTFILES_ROOT/claude/settings.json")"
  mkdir -p "$TEST_TMP/prefix/bin"
  printf '#!/usr/bin/env bash\necho ran-cm-hook\n' > "$TEST_TMP/prefix/bin/cm-hook"
  chmod +x "$TEST_TMP/prefix/bin/cm-hook"
  run env PORTABLE_PREFIX="$TEST_TMP/prefix" sh -c "$cmd"
  [ "$status" -eq 0 ]
  [ "$output" = "ran-cm-hook" ]
}

@test "packaged settings.json omits the skip-permissions bypass" {
  run jq -e 'has("skipDangerousModePermissionPrompt")' "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -ne 0 ]
}

@test "packaged settings.json keeps the model, statusline, and plugin set" {
  run jq -e '.model and .statusLine and .enabledPlugins' "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "no credentials or session state is packaged" {
  [ ! -e "$DOTFILES_ROOT/claude/.credentials.json" ]
  [ ! -e "$DOTFILES_ROOT/claude/history.jsonl" ]
  [ ! -e "$DOTFILES_ROOT/claude/projects" ]
  [ ! -e "$DOTFILES_ROOT/claude/hud/cache" ]
}

@test "the omc template has no absolute node path" {
  grep -q '@@NODE_BINARY@@' "$DOTFILES_ROOT/claude/.omc-config.json.template"
  ! grep -q '/home/alluo/.nvm' "$DOTFILES_ROOT/claude/.omc-config.json.template"
}

# setupCompleted stays: it is what makes OMC skip its wizard on a fresh machine.
# setupVersion does not, because the step rewrites this file on every run and a
# tracked version string would reinstate a stale one after each OMC release.
@test "the omc template pins no oh-my-claudecode version" {
  run jq -e 'has("setupVersion")' "$DOTFILES_ROOT/claude/.omc-config.json.template"
  [ "$status" -ne 0 ]
  run jq -e '.setupCompleted' "$DOTFILES_ROOT/claude/.omc-config.json.template"
  [ "$status" -eq 0 ]
}

@test "step_claude links CLAUDE-user.md but COPIES settings.json" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  run claude_step "step_claude"
  [ -L "$HOME/.claude/CLAUDE-user.md" ]
  [ -f "$HOME/.claude/settings.json" ]
  [ ! -L "$HOME/.claude/settings.json" ]
}

@test "step_claude leaves CLAUDE.md a real file importing CLAUDE-user.md" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  run claude_step "step_claude"
  [ -f "$HOME/.claude/CLAUDE.md" ]
  [ ! -L "$HOME/.claude/CLAUDE.md" ]
  grep -q '^@CLAUDE-user\.md$' "$HOME/.claude/CLAUDE.md"
}

@test "an install that previously linked CLAUDE.md is migrated, not written through" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  mkdir -p "$HOME/.claude"
  printf 'tracked content\n' > "$TEST_TMP/repo-claude-md"
  ln -s "$TEST_TMP/repo-claude-md" "$HOME/.claude/CLAUDE.md"
  run claude_step "step_claude"
  [ ! -L "$HOME/.claude/CLAUDE.md" ]
  # the old link target must not have been appended to through the link
  run grep -c '@CLAUDE-user\.md' "$TEST_TMP/repo-claude-md"
  [ "$output" = "0" ]
}

@test "install_claude_md does not duplicate the import on re-run" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  run claude_step "step_claude"
  run claude_step "step_claude"
  run grep -c '^@CLAUDE-user\.md$' "$HOME/.claude/CLAUDE.md"
  [ "$output" = "1" ]
}

@test "install_claude_md preserves an existing OMC block when adding the import" {
  mkdir -p "$HOME/.claude"
  printf '<!-- OMC:START -->\n# managed\n<!-- OMC:END -->\n' > "$HOME/.claude/CLAUDE.md"
  run claude_step "install_claude_md '$HOME/.claude'"
  grep -q '<!-- OMC:START -->' "$HOME/.claude/CLAUDE.md"
  grep -q '^@CLAUDE-user\.md$' "$HOME/.claude/CLAUDE.md"
}

@test "install_claude_md under DRY_RUN writes nothing and claims nothing" {
  mkdir -p "$HOME/.claude/plugins/cache/omc/oh-my-claudecode/4.15.7/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' \
    > "$HOME/.claude/plugins/cache/omc/oh-my-claudecode/4.15.7/scripts/setup-claude-md.sh"
  chmod +x "$HOME/.claude/plugins/cache/omc/oh-my-claudecode/4.15.7/scripts/setup-claude-md.sh"
  run claude_step "DRY_RUN=1 install_claude_md '$HOME/.claude'"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/CLAUDE.md" ]
  [[ "$output" == *"would run"* ]]
  [[ "$output" != *"refreshed"* ]]
}

@test "install_claude_md warns rather than failing when OMC is not installed yet" {
  mkdir -p "$HOME/.claude"
  run claude_step "install_claude_md '$HOME/.claude'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not installed yet"* ]]
}

@test "install_claude_md runs the OMC setup script when the plugin is cached" {
  local cache="$HOME/.claude/plugins/cache/omc/oh-my-claudecode"
  mkdir -p "$HOME/.claude" "$cache/4.9.0/scripts" "$cache/4.15.7/scripts"
  for v in 4.9.0 4.15.7; do
    cat > "$cache/$v/scripts/setup-claude-md.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$v" > "\$HOME/.omc-setup-ran"
EOF
    chmod +x "$cache/$v/scripts/setup-claude-md.sh"
  done
  run claude_step "install_claude_md '$HOME/.claude'"
  [ "$status" -eq 0 ]
  # newest cached version wins, not lexicographic order
  [ "$(cat "$HOME/.omc-setup-ran")" = "4.15.7" ]
}

@test "Claude Code writing to settings.json cannot modify the repo" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  run claude_step "step_claude"
  # simulate what Claude Code does when the user accepts dangerous mode
  python3 - "$HOME/.claude/settings.json" <<'PY2'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d["skipDangerousModePermissionPrompt"]=True
json.dump(d,open(p,"w"),indent=2)
PY2
  run jq -e 'has("skipDangerousModePermissionPrompt")' "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  # the repo copy must be untouched
  run jq -e 'has("skipDangerousModePermissionPrompt")' "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -ne 0 ]
}

@test "step_claude COPIES hud so runtime cache cannot reach the repo" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  run claude_step "step_claude"
  [ -d "$HOME/.claude/hud" ]
  [ ! -L "$HOME/.claude/hud" ]
  [ -x "$HOME/.claude/hud/omc-hud-cache.sh" ]
  [ -f "$HOME/.claude/hud/lib/config-dir.sh" ]
}

@test "writing to the installed hud cache does not touch the repo" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  run claude_step "step_claude"
  # simulate what the HUD does at runtime
  mkdir -p "$HOME/.claude/hud/cache"
  printf 'session state\n' > "$HOME/.claude/hud/cache/statusline.test.txt"
  [ ! -e "$DOTFILES_ROOT/claude/hud/cache/statusline.test.txt" ]
}

@test "step_claude renders the node path into .omc-config.json" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  run claude_step "step_claude"
  [ -f "$HOME/.claude/.omc-config.json" ]
  ! grep -q '@@NODE_BINARY@@' "$HOME/.claude/.omc-config.json"
  run jq -e '.nodeBinary' "$HOME/.claude/.omc-config.json"
  [ "$status" -eq 0 ]
}

@test "step_claude seeds settings.local.json without clobbering it" {
  stub_command claude 0 "1.0.0"
  mkdir -p "$HOME/.claude"
  printf '{"mine":true}\n' > "$HOME/.claude/settings.local.json"
  run claude_step "step_claude"
  run jq -e '.mine' "$HOME/.claude/settings.local.json"
  [ "$status" -eq 0 ]
}

# The two tests below must exercise the "claude not installed" branch. This
# machine has the real CLI on PATH, so PATH is narrowed to the stub dir plus the
# system directories, which excludes both claude and node.
claude_step_without_cli() {
  bash -c "
    PATH='$STUB_BIN:/usr/bin:/bin'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/60-claude.sh'
    $1
  "
}

@test "step_claude installs the CLI when absent" {
  stub_command npm 0
  stub_command node 0 "/stub/node"
  run claude_step_without_cli "step_claude"
  stub_called "@anthropic-ai/claude-code"
}

@test "step_claude warns rather than failing when the CLI install fails" {
  stub_command npm 1
  stub_command node 0 "/stub/node"
  run claude_step_without_cli "step_claude"
  [ "$status" -eq 2 ]
}

@test "Claude config follows CLAUDE_CONFIG_DIR onto another volume" {
  export CLAUDE_CONFIG_DIR="$TEST_TMP/ece/claude"
  stub_command claude 0
  stub_command node 0
  run claude_step "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' step_claude 2>&1"
  [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
  [ -L "$CLAUDE_CONFIG_DIR/CLAUDE-user.md" ]
  [ -f "$CLAUDE_CONFIG_DIR/CLAUDE.md" ]
  [ ! -d "$HOME/.claude" ]
}
