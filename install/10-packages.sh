#!/usr/bin/env bash
# Install runtime dependencies.
#
# Homebrew first when it is usable, then prebuilt downloads for whatever is still
# missing. This step never returns 1: a machine without sudo cannot have Homebrew,
# and aborting here would skip every later step — including zsh, tmux, Neovim and
# Claude Code config, none of which need any privileges.

# tool:command-that-proves-it-is-installed
RUNTIME_TOOLS=(
  "zsh:zsh"
  "tmux:tmux"
  "git:git"
  "nvim:nvim"
  "node:node"
  "jq:jq"
  "rust:cargo"
)

# For anything that cannot be fetched, say how to get it rather than just failing.
_manual_hint() {
  case "$1" in
    git) printf 'preinstalled on most systems; otherwise dnf install git / xcode-select --install' ;;
    tmux) printf 'no static macOS build exists; brew install tmux, or build from source' ;;
    *) printf 'install it manually and re-run' ;;
  esac
}

step_packages() {
  local rc=0 brew_bin="" entry tool cmd

  if [ "${PORTABLE_ONLY:-0}" = "1" ]; then
    log_ok "--portable: skipping Homebrew, using prebuilt downloads only"
  elif command -v brew >/dev/null 2>&1; then
    brew_bin="brew"
  elif [ -x "$(brew_prefix 2>/dev/null)/bin/brew" ]; then
    brew_bin="$(brew_prefix)/bin/brew"
  fi

  if [ -n "$brew_bin" ]; then
    if run "$brew_bin" bundle --file="$DOTFILES_ROOT/Brewfile"; then
      log_ok "runtime packages installed via Homebrew"
    else
      log_warn "brew bundle failed — falling back to prebuilt downloads"
      rc=2
    fi
  elif [ "${PORTABLE_ONLY:-0}" != "1" ]; then
    log_warn "Homebrew unavailable — using prebuilt downloads instead"
    rc=2
  fi

  # Later steps run in this same process, so they inherit the prefix.
  PATH="$(portable_bin):$PATH"
  export PATH

  local missing=()
  for entry in "${RUNTIME_TOOLS[@]}"; do
    tool="${entry%%:*}"
    cmd="${entry##*:}"

    if command -v "$cmd" >/dev/null 2>&1; then
      continue
    fi

    if portable_supported "$tool"; then
      if portable_install "$tool"; then
        continue
      fi
      rc=2
    fi

    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$tool")
      log_warn "$tool unavailable — $(_manual_hint "$tool")"
      rc=2
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    log_followup "still missing: ${missing[*]} — steps needing them will be skipped"
  else
    log_ok "all runtime tools available"
  fi

  return $rc
}
