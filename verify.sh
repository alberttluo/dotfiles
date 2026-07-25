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

# Allow the test suite to source the helpers without running the suite.
case "${1:-}" in
  --source-only) return 0 2>/dev/null || exit 0 ;;
esac

_link_count() {
  [ "$(find "$HOME/.claude/skills" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" -eq 59 ]
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
  tmux -f "$HOME/.config/tmux/tmux.conf" new-session -d -s "$session" \
    && tmux kill-session -t "$session"
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

_omc_node_ok() {
  local n
  n="$(jq -r '.nodeBinary' "$HOME/.claude/.omc-config.json" 2>/dev/null)"
  [ -n "$n" ] && [ "$n" != "null" ] && [ -x "$n" ]
}

printf '\n──────── shell ────────\n'
check "zsh is installed"                            command -v zsh
check "zsh starts an interactive shell cleanly"     zsh -ic 'exit'
check ".zshrc is a symlink"                         test -L "$HOME/.zshrc"
check ".zshrc.local exists"                         test -f "$HOME/.zshrc.local"

printf '\n──────── tmux ────────\n'
check "tmux is installed"                           command -v tmux
check ".config/tmux/tmux.conf resolves"             test -e "$HOME/.config/tmux/tmux.conf"
check "tmux.conf.local is linked"                   test -L "$HOME/.config/tmux/tmux.conf.local"
check "tmux config parses"                          _tmux_parses
check "tpm is installed (XDG path)"                 test -d "$HOME/.config/tmux/plugins/tpm"
check "tmux-agent-indicator is installed"           test -d "$HOME/.config/tmux/plugins/tmux-agent-indicator"
check "extrakto is installed"                       test -d "$HOME/.config/tmux/plugins/extrakto"

printf '\n──────── fonts ────────\n'
check "JetBrainsMono Nerd Font present"             _font_count

printf '\n──────── nvim ────────\n'
check "nvim is installed"                           command -v nvim
check ".config/nvim is linked"                      test -L "$HOME/.config/nvim"
check "nvim starts headless cleanly"                nvim --headless +qa

printf '\n──────── claude code ────────\n'
check "claude CLI is installed"                     command -v claude
check "settings.json is linked"                     test -L "$HOME/.claude/settings.json"
check "settings.json is valid JSON"                 jq -e . "$HOME/.claude/settings.json"
check "CLAUDE.md is linked"                         test -L "$HOME/.claude/CLAUDE.md"
check "hud script is executable"                    test -x "$HOME/.claude/hud/omc-hud-cache.sh"
check ".omc-config.json node path is valid"         _omc_node_ok
check "59 skills are linked"                        _link_count
check "pdf is not linked into Claude Code"          test '!' -e "$HOME/.claude/skills/pdf"
check "no machine state is linked"                  _no_state_linked

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf '✓ all checks passed\n'
  exit 0
fi
printf '✗ %s check(s) failed\n' "$FAILURES"
exit 1
