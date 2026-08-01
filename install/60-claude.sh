#!/usr/bin/env bash
# Claude Code CLI and configuration.
#
# Plugins are not packaged: Claude Code installs them itself from the
# extraKnownMarketplaces entries in settings.json on first launch. hud/ IS
# packaged, because OMC's setup flow only creates it after first launch, which
# would leave statusLine pointing at a missing script on a fresh machine.
#
# CLAUDE.md is split: this repo tracks only the author's own instructions
# (CLAUDE-user.md), and oh-my-claudecode generates the rest into CLAUDE.md.
# See install_claude_md for why.

# Newest cached oh-my-claudecode plugin, or empty when Claude Code has not
# installed it yet — it does that on first launch from settings.json, which on a
# fresh machine is after this step runs. Any valid root will do: OMC's own script
# re-resolves the newest cache version itself.
omc_plugin_root() {
  local base="$1/plugins/cache/omc/oh-my-claudecode" dir version
  [ -d "$base" ] || return 0
  while read -r version; do
    if [ -f "$base/$version/scripts/setup-claude-md.sh" ]; then
      printf '%s' "$base/$version"
      return 0
    fi
  done < <(for dir in "$base"/*/; do
             [ -d "$dir" ] && basename "$dir"
           done | sort -Vr)
}

# CLAUDE.md is owned by OMC and must be a regular file: its setup coordinator
# refuses to write through a symlink, so linking this repo's copy here made
# `/oh-my-claudecode:setup` fail on every OMC release and left the managed block
# to be merged by hand. Instead OMC regenerates its own block in place and
# preserves everything below it — and the only thing below it is an import of
# CLAUDE-user.md, which IS linked, because nothing but the author writes to it.
install_claude_md() {
  local config_dir=$1 main="$1/CLAUDE.md" plugin_root

  unlink_if_symlink "$main"

  if [ -e "$main" ] && grep -q '^@CLAUDE-user\.md$' "$main" 2>/dev/null; then
    log_ok "$main already imports CLAUDE-user.md"
  elif [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "add @CLAUDE-user.md import to $main"
  else
    # Appended rather than written: on a re-run CLAUDE.md also holds OMC's
    # generated block, and rewriting the file would discard it.
    printf '@CLAUDE-user.md\n' >> "$main" \
      || { log_fail "could not write $main"; return 1; }
    log_ok "added @CLAUDE-user.md import to $main"
  fi

  plugin_root="$(omc_plugin_root "$config_dir")"
  if [ -z "$plugin_root" ]; then
    log_warn "oh-my-claudecode is not installed yet — run /oh-my-claudecode:setup after first launch to add its CLAUDE.md block"
    return 0
  fi

  if ! run bash "$plugin_root/scripts/setup-claude-md.sh" global; then
    log_warn "oh-my-claudecode CLAUDE.md update failed — run /oh-my-claudecode:setup manually"
    return 0
  fi
  [ "${DRY_RUN:-0}" = "1" ] || log_ok "refreshed the oh-my-claudecode block in $main"
}

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
  # CLAUDE-user.md is author-edited only, so linking is correct: edits in the repo
  # take effect immediately and nothing writes to it behind your back. OMC only
  # ever touches CLAUDE.md and CLAUDE-omc.md.
  backup_and_link "$DOTFILES_ROOT/claude/CLAUDE-user.md" "$config_dir/CLAUDE-user.md" || return 1
  # COPIED, not linked. The HUD writes per-session cache into hud/cache/, so a
  # symlink would make the repo the write target for runtime state.
  backup_and_copy "$DOTFILES_ROOT/claude/hud"           "$config_dir/hud"           || return 1

  install_claude_md "$config_dir" || return 1

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
