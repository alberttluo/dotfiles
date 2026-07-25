#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2317
#   SC2329/SC2317: the _* helpers are invoked indirectly, as command arguments to
#   check(), and the exit after `return` is the not-sourced fallback. Shellcheck
#   sees neither and reports them as dead code.
#
# Post-install assertions. Runnable standalone; exits 0 only if everything passes.
# Deliberately no `set -e`: every check must run so one failure cannot mask others.
set -uo pipefail

VERIFY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Skip re-sourcing when a caller (the test suite) already loaded the logging lib.
if [ -z "${WARNINGS+x}" ]; then
  # shellcheck source=lib/log.sh
  source "$VERIFY_ROOT/lib/log.sh"
fi

FAILURES=0

# Same resolution oh-my-tmux uses; hardcoding ~/.config would pass on precisely
# the machine where the packaged config is being ignored.
TMUX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
CM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/context-manager/config.toml"

# Cheap TOML sanity check: the daemon reads this file at startup and a syntax
# error there means no session management at all. No toml CLI is guaranteed, so
# assert the shape of the keys the daemon requires rather than full parsing.
_cm_config_parses() {
  [ -f "$CM_CONFIG" ] || return 1
  grep -qE '^threshold *= *[0-9.]+' "$CM_CONFIG" || return 1
  grep -qE '^dry_run *= *(true|false)' "$CM_CONFIG" || return 1
  grep -q '^\[model_windows\]' "$CM_CONFIG" || return 1
  # An unterminated array is the realistic hand-edit failure.
  grep -q '^]' "$CM_CONFIG"
}

_cm_hook_wired() {
  jq -e '
    ([.hooks.SessionStart[]?.hooks[]?.command] | any(test("cm-hook"))) and
    ([.hooks.SessionEnd[]?.hooks[]?.command]   | any(test("cm-hook")))
  ' "$HOME/.claude/settings.json" >/dev/null 2>&1
}

# check DESCRIPTION COMMAND... — never aborts, so one failure cannot mask others.
check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$desc"
  else
    printf '  ✗ %s\n' "$desc"
    FAILURES=$((FAILURES + 1))
  fi
}

# Asserts each manifest skill is a symlink to the shared tree. Counting directory
# entries instead would be both weaker and wrong: unrelated things live in
# ~/.claude/skills (OMC keeps an .omc state directory there).
_skills_linked() {
  local name target
  while read -r name; do
    [ -n "$name" ] || continue
    target="$(readlink "$HOME/.claude/skills/$name" 2>/dev/null)"
    [ "$target" = "$HOME/.agents/skills/$name" ] || return 1
    [ -d "$HOME/.claude/skills/$name" ] || return 1
  done < "$VERIFY_ROOT/agents/CLAUDE-SKILL-LINKS.txt"
  return 0
}

_font_count() {
  if [ "$(uname -s)" = "Darwin" ]; then
    [ "$(find "$HOME/Library/Fonts" -name 'JetBrainsMono*' 2>/dev/null | wc -l | tr -d ' ')" -ge 90 ]
  else
    [ "$(fc-list 2>/dev/null | grep -c JetBrainsMono)" -ge 90 ]
  fi
}

_tmux_parses() {
  local session="_verify_$$"
  tmux -f "$TMUX_DIR/tmux.conf" new-session -d -s "$session" \
    && tmux kill-session -t "$session"
}

# ~/.tmux.conf outranks the XDG path in oh-my-tmux's search order, and
# TMUX_CONF_LOCAL is derived as "$TMUX_CONF.local". If it exists, the packaged
# config is being ignored no matter how correct the XDG symlinks look.
_no_shadowing_tmux_conf() {
  [ ! -e "$HOME/.tmux.conf" ] && [ ! -L "$HOME/.tmux.conf" ]
}

# The config tmux will actually load must have its .local sibling present.
_tmux_conf_local_resolves() {
  local conf
  conf="$(for c in "$HOME/.tmux.conf" "$TMUX_DIR/tmux.conf" "$HOME/.config/tmux/tmux.conf"; do
    [ -f "$c" ] && printf '%s' "$c" && break
  done)"
  [ -n "$conf" ] && [ -e "$conf.local" ]
}

# Stock tmux values. If the status bar still shows these, oh-my-tmux loaded its
# variables but never applied its theme — the "default looking tmux" symptom,
# which _tmux_parses cannot detect because a syntax check does not theme anything.
TMUX_STOCK_STYLE="bg=green,fg=black"
TMUX_STOCK_LEFT="[#{session_name}]"

# Must run on the DEFAULT socket. oh-my-tmux derives TMUX_PROGRAM by running
# `tmux display -p` with no -S, so on a `-L <name>` socket it misdetects and aims
# its apply commands at the default server, leaving the probe server unthemed.
_tmux_themed() {
  local created=0 style left
  if ! tmux ls >/dev/null 2>&1; then
    tmux new-session -d -s _verify_theme >/dev/null 2>&1 || return 1
    created=1
  fi
  # The theme is applied asynchronously via run-shell; poll rather than guess.
  local waited=0
  while [ "$waited" -lt 10 ]; do
    style="$(tmux show -gv status-style 2>/dev/null)"
    if [ -n "$style" ] && [ "$style" != "$TMUX_STOCK_STYLE" ]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  left="$(tmux show -gv status-left 2>/dev/null)"
  if [ "$created" = 1 ]; then
    tmux kill-session -t _verify_theme >/dev/null 2>&1
  fi
  [ -n "$style" ] && [ "$style" != "$TMUX_STOCK_STYLE" ] && [ "$left" != "$TMUX_STOCK_LEFT" ]
}

_no_state_linked() {
  local p
  for p in .credentials.json history.jsonl projects session-env; do
    if [ -L "$HOME/.claude/$p" ]; then
      return 1
    fi
  done
  return 0
}

# Claude Code writes to settings.json, so it must not be a symlink into the repo.
_settings_is_copy() {
  [ -f "$HOME/.claude/settings.json" ] && [ ! -L "$HOME/.claude/settings.json" ]
}

_omc_node_ok() {
  local n
  n="$(jq -r '.nodeBinary' "$HOME/.claude/.omc-config.json" 2>/dev/null)"
  [ -n "$n" ] && [ "$n" != "null" ] && [ -x "$n" ]
}

# Allow the test suite to source the helpers without running the suite. This must
# come after every helper definition, or sourcing returns before they exist and
# tests silently pass on "command not found".
case "${1:-}" in
  --source-only) return 0 2>/dev/null || exit 0 ;;
esac

printf '\n──────── shell ────────\n'
check "zsh is installed"                            command -v zsh
check "zsh starts an interactive shell cleanly"     zsh -ic 'exit'
check ".zshrc is a symlink"                         test -L "$HOME/.zshrc"
check ".zshrc.local exists"                         test -f "$HOME/.zshrc.local"

printf '\n──────── tmux ────────\n'
check "tmux is installed"                           command -v tmux
check "tmux.conf resolves in the XDG config dir"    test -e "$TMUX_DIR/tmux.conf"
check "tmux.conf.local is linked"                   test -L "$TMUX_DIR/tmux.conf.local"
check "no shadowing ~/.tmux.conf"                  _no_shadowing_tmux_conf
check "the loaded tmux.conf has its .local sibling"  _tmux_conf_local_resolves
check "tmux config parses"                          _tmux_parses
check "oh-my-tmux theme actually applied"           _tmux_themed
check "tpm is installed (XDG path)"                 test -d "$TMUX_DIR/plugins/tpm"
check "tmux-agent-indicator is installed"           test -d "$TMUX_DIR/plugins/tmux-agent-indicator"
check "extrakto is installed"                       test -d "$TMUX_DIR/plugins/extrakto"

printf '\n──────── fonts ────────\n'
check "JetBrainsMono Nerd Font present"             _font_count

printf '\n──────── nvim ────────\n'
check "nvim is installed"                           command -v nvim
check ".config/nvim is linked"                      test -L "$HOME/.config/nvim"
check "nvim starts headless cleanly"                nvim --headless +qa

printf '\n──────── claude code ────────\n'
check "claude CLI is installed"                     command -v claude
check "settings.json is a copy, not a repo symlink"  _settings_is_copy
check "settings.json is valid JSON"                 jq -e . "$HOME/.claude/settings.json"
check "CLAUDE.md is linked"                         test -L "$HOME/.claude/CLAUDE.md"
check "hud script is executable"                    test -x "$HOME/.claude/hud/omc-hud-cache.sh"
check ".omc-config.json node path is valid"         _omc_node_ok
check "all 59 manifest skills are linked"           _skills_linked
check "pdf is not linked into Claude Code"          test '!' -e "$HOME/.claude/skills/pdf"
check "no machine state is linked"                  _no_state_linked

printf '\n──────── context-manager ────────\n'
check "config.toml exists"                          test -f "$CM_CONFIG"
check "config.toml parses as TOML"                  _cm_config_parses
check "cwd exclusions are configured"               grep -q '^ignore_cwds = \[' "$CM_CONFIG"
check "cm-hook is wired into settings.json"         _cm_hook_wired
# Reported, not required: the daemon is built from a separate repo, so a machine
# can be fully provisioned by this installer and still not run it.
if [ -x "$HOME/.local/bin/context-managerd" ]; then
  check "context-managerd is installed"             test -x "$HOME/.local/bin/context-managerd"
  check "cm-hook is installed"                      test -x "$HOME/.local/bin/cm-hook"
  check "the service is active"                     systemctl --user is-active --quiet context-manager
else
  printf '  · context-manager daemon not installed (optional) — skipped\n'
fi

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf '✓ all checks passed\n'
  exit 0
fi
printf '✗ %s check(s) failed\n' "$FAILURES"
exit 1
