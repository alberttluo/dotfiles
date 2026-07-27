#!/usr/bin/env bash
# Claude Code CLI and configuration.
#
# Plugins are not packaged: Claude Code installs them itself from the
# extraKnownMarketplaces entries in settings.json on first launch. hud/ IS
# packaged, because OMC's setup flow only creates it after first launch, which
# would leave statusLine pointing at a missing script on a fresh machine.

step_claude() {
  local rc=0 node_bin
  # Claude Code's own variable, already the convention in claude/hud/lib/config-dir.sh.
  # Transcripts under projects/ grow without bound, so this is one of the larger
  # things a --data-root install needs to move off $HOME.
  local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

  if command -v claude >/dev/null 2>&1; then
    log_ok "Claude Code already installed"
  elif ! run npm install -g @anthropic-ai/claude-code; then
    log_warn "Claude Code install failed — install it manually"
    rc=2
  else
    log_ok "installed Claude Code"
  fi

  run mkdir -p "$config_dir"
  # COPIED, not linked. Claude Code writes to settings.json at runtime (theme,
  # model, skipDangerousModePermissionPrompt, plugin state), so a symlink lets the
  # application mutate tracked config — which silently re-added a per-host
  # permission bypass to this repo once already.
  backup_and_copy "$DOTFILES_ROOT/claude/settings.json" "$config_dir/settings.json" || return 1
  # CLAUDE.md is author-edited only, so linking is correct: edits in the repo take
  # effect immediately and nothing writes to it behind your back.
  backup_and_link "$DOTFILES_ROOT/claude/CLAUDE.md"     "$config_dir/CLAUDE.md"     || return 1
  # COPIED, not linked. The HUD writes per-session cache into hud/cache/, so a
  # symlink would make the repo the write target for runtime state.
  backup_and_copy "$DOTFILES_ROOT/claude/hud"           "$config_dir/hud"           || return 1

  node_bin="$(command -v node || true)"
  if [ -z "$node_bin" ]; then
    log_fail "node not found — cannot render .omc-config.json"
    return 1
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "render .omc-config.json with nodeBinary=$node_bin"
  else
    sed "s#@@NODE_BINARY@@#$node_bin#" \
      "$DOTFILES_ROOT/claude/.omc-config.json.template" \
      > "$config_dir/.omc-config.json" \
      || { log_fail "could not render .omc-config.json"; return 1; }
    log_ok "rendered .omc-config.json (node: $node_bin)"
  fi

  # Per-host, so seeded rather than linked.
  if [ -f "$config_dir/settings.local.json" ]; then
    log_ok "$config_dir/settings.local.json already exists — left untouched"
  else
    run cp "$DOTFILES_ROOT/claude/settings.local.json.example" \
           "$config_dir/settings.local.json"
    log_ok "seeded $config_dir/settings.local.json"
  fi

  log_followup "run 'claude' and log in — credentials are never packaged"
  return $rc
}
