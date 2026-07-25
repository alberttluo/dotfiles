#!/usr/bin/env bash
# OS/arch detection and Homebrew resolution.
#
# BREW_CANDIDATE_ROOT exists only so tests can point the probe at a sandbox.
# In real runs it is empty and the absolute paths below are used as-is.

detect_os() {
  case "$(uname -s)" in
    Darwin) printf 'macos\n' ;;
    Linux)  printf 'linux\n' ;;
    *)      log_fail "unsupported operating system: $(uname -s)"; return 1 ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) printf 'arm64\n' ;;
    *)             printf 'x86_64\n' ;;
  esac
}

# Probe order matters: Apple Silicon, Intel macOS, Linux.
brew_prefix() {
  local root="${BREW_CANDIDATE_ROOT:-}"
  local candidate
  for candidate in \
    "$root/opt/homebrew" \
    "$root/usr/local" \
    "$root/home/linuxbrew/.linuxbrew"
  do
    if [ -x "$candidate/bin/brew" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_homebrew() {
  if brew_prefix >/dev/null 2>&1; then
    log_ok "Homebrew present at $(brew_prefix)"
    return 0
  fi

  log_warn "Homebrew not found; bootstrapping"
  run /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || { log_fail "Homebrew bootstrap failed"; return 1; }

  if [ "${DRY_RUN:-0}" = "1" ]; then
    return 0
  fi

  brew_prefix >/dev/null 2>&1 || {
    log_fail "Homebrew installed but no prefix resolved"
    return 1
  }
  log_ok "Homebrew installed at $(brew_prefix)"
}
