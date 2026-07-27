#!/usr/bin/env bash
# Agent skills.
#
# ~/.claude/skills holds symlinks into ~/.agents/skills, a shared tree used by
# several agent CLIs. All 61 skills come from GitHub upstreams and none are
# locally authored, but no skill-manager CLI is guaranteed on the target host,
# so the 820K tree is vendored and copied rather than re-fetched.

step_skills() {
  # The skills tree is 61 copied directories plus the links into Claude Code, so
  # it follows the data root rather than always landing on $HOME's volume.
  local agents_dir="${DOTFILES_DATA_ROOT:+$DOTFILES_DATA_ROOT/agents}"
  local rc=0 name target linkdir count
  agents_dir="${agents_dir:-$HOME/.agents}"
  local claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "copy 61 skills into $agents_dir and link 59 into $claude_dir/skills"
    return 0
  fi

  mkdir -p "$agents_dir/skills"
  # Copy the contents, not the directory, so re-runs refresh in place rather
  # than nesting skills/skills.
  cp -R "$DOTFILES_ROOT/agents/skills/." "$agents_dir/skills/" \
    || { log_fail "could not copy skills tree"; return 1; }
  cp "$DOTFILES_ROOT/agents/.skill-lock.json" "$agents_dir/.skill-lock.json" \
    || { log_fail "could not copy .skill-lock.json"; return 1; }
  count="$(find "$agents_dir/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
  log_ok "installed $count skills into $agents_dir/skills"

  linkdir="$claude_dir/skills"
  mkdir -p "$linkdir"
  while read -r name; do
    [ -n "$name" ] || continue
    target="$agents_dir/skills/$name"
    if [ ! -d "$target" ]; then
      log_warn "skill in manifest but not vendored: $name"
      rc=2
      continue
    fi
    ln -sfn "$target" "$linkdir/$name" || { log_warn "could not link skill $name"; rc=2; }
  done < "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt"

  # Count the manifest, not the directory: unrelated entries live here too
  # (OMC keeps an .omc state directory under ~/.claude/skills).
  count="$(grep -c '[^[:space:]]' "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt")"
  log_ok "linked $count skills into $linkdir"
  return $rc
}
