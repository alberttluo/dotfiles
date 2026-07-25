#!/usr/bin/env bash
# Entrypoint. Ordering and dispatch only — all real work lives in install/.
set -euo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT

# shellcheck source=lib/log.sh
source "$DOTFILES_ROOT/lib/log.sh"
# shellcheck source=lib/os.sh
source "$DOTFILES_ROOT/lib/os.sh"
# shellcheck source=lib/link.sh
source "$DOTFILES_ROOT/lib/link.sh"

DRY_RUN=0
SKIP_FONTS=0
ONLY=""

# id:function, in execution order.
STEP_IDS=(
  "00-preflight:step_preflight"
  "10-packages:step_packages"
  "20-fonts:step_fonts"
  "30-zsh:step_zsh"
  "40-tmux:step_tmux"
  "50-nvim:step_nvim"
  "60-claude:step_claude"
  "70-skills:step_skills"
)

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --dry-run       Print what would happen without touching the filesystem
  --only <id>     Run a single step (e.g. --only 40-tmux)
  --skip-fonts    Skip font installation
  --help          Show this message

Steps run in order: 00-preflight 10-packages 20-fonts 30-zsh 40-tmux 50-nvim
                    60-claude 70-skills
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-fonts) SKIP_FONTS=1 ;;
    --only)       ONLY="${2:-}"; shift ;;
    --help|-h)    usage; exit 0 ;;
    *)            printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
export DRY_RUN

if [ -n "$ONLY" ]; then
  _known=0
  for pair in "${STEP_IDS[@]}"; do
    if [ "${pair%%:*}" = "$ONLY" ]; then
      _known=1
    fi
  done
  if [ "$_known" -eq 0 ]; then
    log_fail "unknown step id: $ONLY"
    exit 2
  fi
fi

BACKUP_DIR="$HOME/.dotfiles-backup/$(date -u +%Y-%m-%dT%H-%M-%SZ)"
export BACKUP_DIR

# Source whichever step files exist; missing ones are simply not run.
for f in "$DOTFILES_ROOT"/install/*.sh; do
  [ -e "$f" ] || continue
  # shellcheck source=/dev/null
  source "$f"
done

FAILED=""
RAN=()

for pair in "${STEP_IDS[@]}"; do
  id="${pair%%:*}"
  fn="${pair##*:}"

  if [ -n "$ONLY" ] && [ "$ONLY" != "$id" ]; then
    continue
  fi
  if [ "$id" = "20-fonts" ] && [ "$SKIP_FONTS" -eq 1 ]; then
    log_step "$id (skipped: --skip-fonts)"
    continue
  fi
  if ! declare -F "$fn" >/dev/null 2>&1; then
    continue
  fi

  log_step "$id"
  set +e
  "$fn"
  rc=$?
  set -e

  case "$rc" in
    0) RAN+=("$id") ;;
    2) RAN+=("$id (with warnings)") ;;
    *) FAILED="$id"; break ;;
  esac
done

printf '\n──────── summary ────────\n' >&2
for r in "${RAN[@]:-}"; do
  if [ -n "$r" ]; then
    printf '  completed: %s\n' "$r" >&2
  fi
done

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  printf '\n  warnings:\n' >&2
  for w in "${WARNINGS[@]}"; do printf '    ⚠ %s\n' "$w" >&2; done
fi

if [ -n "$FAILED" ]; then
  printf '\n  ✗ failed at step: %s\n' "$FAILED" >&2
  exit 1
fi

cat >&2 <<EOF

  next steps (not automatable):
    1. run 'claude' and log in — credentials are never packaged
    2. fill in ~/.zshrc.local with this machine's paths, licenses, and aliases
    3. if chsh was skipped, change your login shell manually (see warnings above)

  backups, if any, are in: $BACKUP_DIR
EOF
