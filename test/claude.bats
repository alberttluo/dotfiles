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

@test "step_claude links CLAUDE.md but COPIES settings.json" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  run claude_step "step_claude"
  [ -L "$HOME/.claude/CLAUDE.md" ]
  [ -f "$HOME/.claude/settings.json" ]
  [ ! -L "$HOME/.claude/settings.json" ]
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
