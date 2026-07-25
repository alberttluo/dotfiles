#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

skills_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/70-skills.sh'
    $1
  "
}

@test "all 61 skills are vendored" {
  [ "$(ls "$DOTFILES_ROOT/agents/skills" | wc -l)" -eq 61 ]
}

@test "the lock file covers every vendored skill" {
  run bash -c "
    jq -r '.skills | keys[]' '$DOTFILES_ROOT/agents/.skill-lock.json' | sort > '$TEST_TMP/lock'
    ls '$DOTFILES_ROOT/agents/skills' | sort > '$TEST_TMP/dirs'
    diff '$TEST_TMP/lock' '$TEST_TMP/dirs'
  "
  [ "$status" -eq 0 ]
}

@test "the link manifest names 59 skills" {
  [ "$(wc -l < "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt")" -eq 59 ]
}

@test "the link manifest excludes pdf and find-skills" {
  ! grep -qx 'pdf' "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt"
  ! grep -qx 'find-skills' "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt"
}

@test "every name in the manifest exists in the vendored tree" {
  while read -r name; do
    [ -d "$DOTFILES_ROOT/agents/skills/$name" ] || {
      echo "missing: $name"; return 1
    }
  done < "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt"
}

@test "every vendored skill has a SKILL.md" {
  local d
  for d in "$DOTFILES_ROOT"/agents/skills/*/; do
    [ -f "$d/SKILL.md" ] || { echo "no SKILL.md in $d"; return 1; }
  done
}

@test "step_skills copies the tree and lock file into ~/.agents" {
  run skills_step "step_skills"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.agents/.skill-lock.json" ]
  [ -d "$HOME/.agents/skills/caveman" ]
}

@test "step_skills creates the symlink farm in ~/.claude/skills" {
  run skills_step "step_skills"
  [ -L "$HOME/.claude/skills/caveman" ]
  [ -d "$HOME/.claude/skills/caveman" ]
  [ "$(ls "$HOME/.claude/skills" | wc -l)" -eq 59 ]
}

@test "step_skills does not link pdf or find-skills into Claude Code" {
  run skills_step "step_skills"
  [ ! -e "$HOME/.claude/skills/pdf" ]
  [ ! -e "$HOME/.claude/skills/find-skills" ]
  [ -d "$HOME/.agents/skills/pdf" ]
}

@test "step_skills is idempotent" {
  run skills_step "step_skills"
  [ "$status" -eq 0 ]
  run skills_step "step_skills"
  [ "$status" -eq 0 ]
  [ "$(ls "$HOME/.claude/skills" | wc -l)" -eq 59 ]
}

@test "step_skills does not nest skills/skills on a second run" {
  run skills_step "step_skills"
  run skills_step "step_skills"
  [ ! -d "$HOME/.agents/skills/skills" ]
}

@test "step_skills under DRY_RUN creates nothing" {
  run skills_step "DRY_RUN=1 step_skills"
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.agents/skills" ]
}
